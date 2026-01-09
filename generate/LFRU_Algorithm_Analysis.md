# LFRU (Least Frequently and Recently Used) 算法详细分析

## 概述

LFRU 是一种混合缓存替换算法，结合了**频率**（Frequency）和**最近性**（Recency）两个维度来管理锁缓存。相比传统 LRU 只关注最后访问时间，LFRU 能更好地识别和保护常用的锁，同时避免被扫描操作污染缓存。

**参考论文**：https://arxiv.org/abs/1702.04078（Scan-resistant Caching Policies）

---

## 核心概念

### 1. 两层锁列表结构

LFRU 将缓存中的锁分为两个列表：

```
┌─────────────────────────────────┐
│   特权列表 (Privileged List)     │  ← 高价值锁（常使用）
│  ns_unused_priv_list             │
│  ns_nr_priv 计数                 │
└─────────────────────────────────┘
           ↓
    [被驱逐时]
           ↓
┌─────────────────────────────────┐
│   普通列表 (Normal List)          │  ← 低价值锁（使用少）
│  ns_unused_normal_list           │
│  ns_nr_unused - ns_nr_priv       │
└─────────────────────────────────┘
```

#### 列表特点：

| 特征 | 特权列表 | 普通列表 |
|------|---------|--------|
| 访问频率 | 高 | 低 |
| 驱逐优先级 | 低 | 高 |
| 晋升机制 | 一旦晋升，不再降级（直到驱逐）| 可通过访问晋升 |
| 降级机制 | 当列表过度膨胀时批量降级 | 在普通列表内部使用LRU |

### 2. 访问评分（Access Score）

每个锁有一个 8 位的访问评分：`l_lru_score`

```c
struct ldlm_lock {
    u8 l_lru_score;  // 范围: 0-254 (254 是上限)
    enum lru_list_type l_lru_type;  // LRU_NORMAL_LIST 或 LRU_PRIV
};
```

**评分如何增加**：
- 每当锁被插入 LRU 列表时，评分递增 1
- 上限是 254（`LDLM_LFRU_PRIV_THRESH_CAP`）以防整数溢出

**评分的含义**：
- 评分高 = 这把锁最近被频繁访问
- 评分低 = 这把锁长期未被使用

### 3. 晋升阈值（Privilege Threshold）

```c
__u8 ns_lfru_priv_score_threshold;  // 动态的晋升阈值
```

**关键规则**：
```
if (lock->l_lru_score > ns_lfru_priv_score_threshold ||
    lock->l_lru_score == LDLM_LFRU_PRIV_THRESH_CAP)
{
    // 锁被晋升到特权列表
}
```

**初始值**：1 (`LDLM_LFRU_MIN_PRIV_THRESH`)

---

## 算法工作流程

### Phase 1: 添加锁 (`ldlm_lfru_add_lock`)

当锁第一次进入缓存或再次被使用时调用：

```
┌─────────────────────────────────────┐
│  Step 1: 增加未使用锁计数            │
│  ns->ns_nr_unused++                 │
└─────────────────────────────────────┘
           ↓
┌─────────────────────────────────────┐
│  Step 2: 提高锁的访问评分            │
│  lock->l_lru_score = min(score+1, 254) │
└─────────────────────────────────────┘
           ↓
┌─────────────────────────────────────┐
│  Step 3: 评估是否晋升                 │
│  if (score > threshold OR score==254) │
│      → 晋升到特权列表                 │
│  else                                │
│      → 添加到普通列表                 │
└─────────────────────────────────────┘
           ↓
┌─────────────────────────────────────┐
│  Step 4: 调整晋升阈值                 │
│  (仅当新晋升的锁时)                   │
└─────────────────────────────────────┘
```

**代码对应**：

```c
static void ldlm_lfru_add_lock(struct ldlm_namespace *ns,
                               struct ldlm_lock *lock)
{
    bool was_priv = lock->l_lru_type == LRU_PRIV;
    bool new_priv = false;

    // Step 1: 增加计数
    ns->ns_nr_unused++;
    
    // Step 2: 提高评分
    lock->l_lru_score = min_t(int, lock->l_lru_score + 1,
                              LDLM_LFRU_PRIV_THRESH_CAP);
    
    // Step 3: 判断是否晋升
    new_priv = !was_priv &&
               (lock->l_lru_score > ns->ns_lfru_priv_score_threshold ||
                lock->l_lru_score == LDLM_LFRU_PRIV_THRESH_CAP);
    
    // Step 4: 添加到对应列表
    if (was_priv || new_priv) {
        list_add_tail(&lock->l_lru, &ns->ns_unused_priv_list);
        ns->ns_nr_priv++;
        lock->l_lru_type = LRU_PRIV;
    } else {
        list_add_tail(&lock->l_lru, &ns->ns_unused_normal_list);
        lock->l_lru_type = LRU_NORMAL_LIST;
    }
    
    // Step 5: 仅当新晋升时才调整阈值
    if (!was_priv)
        ldlm_check_and_adjust_lfru_thresh(ns, lock->l_lru_score);
}
```

---

### Phase 2: 动态阈值调整 (`ldlm_check_and_adjust_lfru_thresh`)

这是LFRU的关键创新！阈值会根据访问模式自适应地调整。

#### 工作原理：

```
条件1: 遇到更高评分的锁
  if (score > threshold OR score == CAP)
    ├─ 立即更新阈值 = score
    └─ 重置时间窗口计数器

条件2: 访问次数达到时间窗口大小
  当 access_window_cnt == check_window_size
    ├─ 更新阈值 = 这个窗口内的最大评分
    └─ 重置所有计数器

条件3: 访问次数达到窗口大小的一半
  当 access_window_cnt == check_window_size / 2
    └─ 对最大频率做衰减处理 (乘以 3/4 = 0.75)
```

**代码对应**：

```c
static void ldlm_check_and_adjust_lfru_thresh(struct ldlm_namespace *ns,
                                              __u8 score)
{
    // 条件1: 发现了更高的评分，或者达到上限
    if (score > ns->ns_lfru_priv_score_threshold ||
        score == LDLM_LFRU_PRIV_THRESH_CAP) {
        ns->ns_lfru_priv_score_threshold = score;
        ns->ns_lfru_max_freq = LDLM_LFRU_MIN_PRIV_THRESH;  // 重置为1
        ns->ns_lfru_access_window_cnt = 0;  // 重置计数
        return;
    }

    // 追踪当前窗口内的最高评分
    if (score > ns->ns_lfru_max_freq)
        ns->ns_lfru_max_freq = score;
    
    ns->ns_lfru_access_window_cnt++;  // 窗口计数 +1
    
    // 条件2: 当窗口满了
    if (ns->ns_lfru_access_window_cnt == ns->ns_lfru_check_window_size) {
        ns->ns_lfru_priv_score_threshold = ns->ns_lfru_max_freq;
        ns->ns_lfru_max_freq = LDLM_LFRU_MIN_PRIV_THRESH;
        ns->ns_lfru_access_window_cnt = 0;
    }
    // 条件3: 当窗口走了一半
    else if (ns->ns_lfru_access_window_cnt ==
             ns->ns_lfru_check_window_size / 2) {
        // 衰减因子: 3/4 = 0.75
        ns->ns_lfru_max_freq = ns->ns_lfru_max_freq * 3 / 4;
    }
}
```

#### 参数说明：

```c
struct ldlm_namespace {
    __u8 ns_lfru_priv_score_threshold;      // 当前阈值
    __u8 ns_lfru_max_freq;                  // 当前窗口的最大评分
    unsigned int ns_lfru_access_window_cnt; // 窗口内累积的访问次数
    unsigned int ns_lfru_check_window_size; // 窗口大小（初始化值）
};
```

---

### Phase 3: 驱逐锁 (`ldlm_lfru_remove_lock`)

从缓存中删除一个锁：

```c
static int ldlm_lfru_remove_lock(struct ldlm_namespace *ns,
                                 struct ldlm_lock *lock)
{
    int rc = 0;

    // 使用基础LRU移除逻辑
    rc = ldlm_lru_remove_lock(ns, lock);
    
    // 如果是从特权列表中移除，减少特权计数
    if (rc && lock->l_lru_type == LRU_PRIV) {
        LASSERT(ns->ns_nr_priv > 0);
        ns->ns_nr_priv--;
    }
    return rc;
}
```

**驱逐顺序**：
1. 优先驱逐普通列表中最旧的锁
2. 仅当普通列表为空时，才驱逐特权列表

---

### Phase 4: 批量降级 (`ldlm_lfru_try_batch_demote_locks`)

当特权列表过度膨胀时，批量将锁从特权列表降级到普通列表。

#### 触发条件：

```c
static inline bool ldlm_lfru_priv_too_many(struct ldlm_namespace *ns)
{
    return (ns->ns_nr_priv >= (LDLM_DEFAULT_LRU_SIZE >> 3)) &&
           (ns->ns_nr_priv >=
            ns->ns_nr_unused * ns->ns_lfru_priv_ratio_limit_256 >> 8);
}
```

**翻译**：
- 特权锁数 ≥ 默认LRU大小的 1/8（12.5%）**AND**
- 特权锁数 ≥ 总锁数的 某个百分比（默认30%）

#### 降级流程：

```
┌──────────────────────────────┐
│  检查是否有特权锁可降级       │
└──────────────────────────────┘
           ↓
┌──────────────────────────────┐
│  遍历特权列表中最旧的锁       │
│  (链表头部)                  │
└──────────────────────────────┘
           ↓
┌──────────────────────────────┐
│  对每个锁执行:               │
│  1. 从特权列表移除           │
│  2. 评分右移2位 (÷4)         │
│  3. 添加到普通列表           │
└──────────────────────────────┘
           ↓
┌──────────────────────────────┐
│  返回实际降级的锁数量         │
└──────────────────────────────┘
```

**代码对应**：

```c
static void ldlm_lfru_demote_lock(struct ldlm_namespace *ns,
                                  struct ldlm_lock *lock)
{
    if ((lock->l_flags & LDLM_FL_NS_SRV)) {
        LASSERT(list_empty(&lock->l_lru));
        return;  // 服务器锁，不降级
    }
    
    // 从特权列表移除
    LASSERT(lock->l_lru_type == LRU_PRIV);
    ldlm_lfru_remove_lock(ns, lock);
    
    // 添加到普通列表
    ns->ns_nr_unused++;
    list_add_tail(&lock->l_lru, &ns->ns_unused_normal_list);
    lock->l_lru_type = LRU_NORMAL_LIST;
    
    // 削减评分（右移2位 = 除以4）
    lock->l_lru_score >>= 2;
}

static int ldlm_lfru_try_batch_demote_locks(struct ldlm_namespace *ns,
                                            int batch_size)
{
    struct ldlm_lock *lock, *temp;
    int target_evicts = batch_size;
    int evicts = 0;

    if (unlikely(list_empty(&ns->ns_unused_priv_list)))
        return 0;

    // 只在特权列表超限时才降级
    if (target_evicts == LDLM_LFRU_PRIV_PER_ROUND_LIMIT &&
        !ldlm_lfru_priv_too_many(ns))
        return 0;

    // 批量降级
    list_for_each_entry_safe(lock, temp, &ns->ns_unused_priv_list, l_lru) {
        if (evicts < target_evicts) {
            ldlm_lfru_demote_lock(ns, lock);
            evicts++;
        } else {
            break;
        }
    }

    return evicts;
}
```

---

## 扫描抵抗性（Scan Resistance）

LFRU 的核心优势：防止像 `ls -l $large_dir` 这样的一次性大扫描污染缓存。

### 场景示例：

假设有一个包含 100 个文件的大目录。执行 `ls -l` 会依次访问每个锁，每个锁的访问评分递增：

```
初始状态:
  阈值 = 1
  没有特权锁

访问过程:
  Lock#1: score=1 → (不>1) → 普通列表
  Lock#2: score=1 → (不>1) → 普通列表
  Lock#3: score=2 → (>1) ✓ → 特权列表, 阈值↑2
  Lock#4: score=1 → (不>2) → 普通列表
  Lock#5: score=1 → (不>2) → 普通列表
  ...
  Lock#99: score=1 → (不>2) → 普通列表
  Lock#100: score=3 → (>2) ✓ → 特权列表, 阈值↑3

结果:
  特权列表: 2 个锁 (Lock#3, Lock#100)
  普通列表: 98 个锁
  高效的缓存污染防护！
```

**对比 LRU**：
- LRU 会把所有 100 个锁都添加到缓存
- 如果之后访问原来的热点锁，可能已经被驱逐了
- **缓存命中率下降**

**LFRU**：
- 只有最有潜力的锁被保护
- 热点锁优先级高，不易被驱逐
- **缓存命中率保持**

---

## 数据结构关系图

```
┌─────────────────────────────────────┐
│  struct ldlm_namespace              │
│  (命名空间/缓存管理器)               │
├─────────────────────────────────────┤
│  ns_unused_priv_list ────────┐      │
│  ns_unused_normal_list ──┐   │      │
│  ns_nr_priv: 10          │   │      │
│  ns_nr_unused: 100       │   │      │
│                          │   │      │
│  ns_lfru_priv_score_threshold: 3   │
│  ns_lfru_max_freq: 2             │
│  ns_lfru_access_window_cnt: 4    │
│  ns_lfru_check_window_size: 100  │
└─────────────────────────────────────┘
         │             │
         ↓             ↓
  [lock1]→[lock2]→..  [lock50]→[lock51]→..
  特权列表(10个)       普通列表(90个)
  
  每个 lock:
  ├─ l_lru_score: 8    (访问评分)
  ├─ l_lru_type: PRIV  (所属列表类型)
  ├─ l_lru: 链表节点    (双向链表)
  └─ ...其他字段
```

---

## 关键常量

```c
#define LDLM_LFRU_MIN_PRIV_THRESH (1)          // 最小阈值
#define LDLM_LFRU_PRIV_LIST_RATIO_LIMIT (30)   // 特权列表占比上限 30%
#define LDLM_LFRU_PRIV_PER_ROUND_LIMIT (10)    // 每轮降级最多10个
#define LDLM_LFRU_UPDATE_WINDOW_DIV (10)       // 窗口大小 = LRU_SIZE / 10
#define LDLM_LFRU_PRIV_THRESH_CAP (254)        // 评分上限
```

---

## 时间复杂度分析

| 操作 | 复杂度 | 说明 |
|------|--------|------|
| 添加锁 | O(1) | 链表尾部插入 + 阈值调整是常数操作 |
| 移除锁 | O(1) | 链表删除 |
| 批量降级 | O(batch_size) | 最多降级 10 个锁 |
| 查找最旧锁 | O(1) | 链表头总是最旧 |

---

## 与传统 LRU 的对比

| 维度 | LRU | LFRU |
|------|-----|------|
| 核心维度 | 仅考虑最后访问时间 | 频率 + 最近性 |
| 列表数 | 1 个 | 2 个 |
| 对扫描操作 | 易被污染 | 抵抗力强 |
| 热点锁保护 | 中等 | 优秀 |
| 内存开销 | 低 | 低（只增加1字节评分） |
| 实现复杂度 | 简单 | 中等 |

---

## 初始化参数示例

```c
namespace->ns_lfru_priv_score_threshold = LDLM_LFRU_MIN_PRIV_THRESH;  // 1
namespace->ns_lfru_max_freq = LDLM_LFRU_MIN_PRIV_THRESH;              // 1
namespace->ns_lfru_access_window_cnt = 0;
namespace->ns_lfru_check_window_size = ns->ns_max_unused / 
                                       LDLM_LFRU_UPDATE_WINDOW_DIV;   // LRU_SIZE/10
namespace->ns_lfru_priv_ratio_limit_256 = 
    (LDLM_LFRU_PRIV_LIST_RATIO_LIMIT << 8) / 100;  // 30% 转为分母256的形式
namespace->ns_nr_priv = 0;
namespace->ns_lock_cache_ops = &ldlm_lfru_cache_ops;
```

---

## 总结

LFRU 算法通过以下机制高效地管理缓存：

1. **双层设计**：分离热点锁和冷门锁
2. **动态阈值**：自适应地调整晋升标准，适应工作负载变化
3. **衰减机制**：较旧的访问模式自动衰减，反映当前工作集
4. **批量降级**：防止特权列表过度膨胀
5. **扫描抵抗**：通过阈值提升快速隔离一次性扫描操作

**最终效果**：在缓存有限的情况下，保护真正热点的锁，提高缓存命中率。
