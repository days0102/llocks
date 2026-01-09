# LFRU 算法实现细节补充说明

## 一、函数调用关系图

```
应用层（缓存管理）
    │
    ├─ ldlm_lfru_add_lock()            [添加锁到缓存]
    │   │
    │   ├─ ns->ns_nr_unused++
    │   ├─ lock->l_lru_score 递增
    │   ├─ 判断是否晋升到特权列表
    │   ├─ 添加到 priv_list 或 normal_list
    │   └─ ldlm_check_and_adjust_lfru_thresh()  [动态调整阈值]
    │       ├─ 条件1: score > threshold → 立即更新
    │       ├─ 条件2: 窗口满 → 基于max_freq更新
    │       └─ 条件3: 窗口半满 → 衰减max_freq
    │
    ├─ ldlm_lfru_remove_lock()         [从缓存移除]
    │   ├─ ldlm_lru_remove_lock()      [基础移除逻辑]
    │   └─ 如果是特权锁，ns->ns_nr_priv--
    │
    └─ ldlm_lfru_try_batch_demote_locks()  [批量降级]
        ├─ ldlm_lfru_priv_too_many()       [检查是否超限]
        │   ├─ ns->ns_nr_priv >= LRU_SIZE/8
        │   └─ ns->ns_nr_priv >= total*ratio/256
        └─ 遍历特权列表
            └─ ldlm_lfru_demote_lock()     [单个降级]
                ├─ 从特权列表移除
                ├─ score >>= 2 (除以4)
                └─ 添加到普通列表
```

---

## 二、状态转移图

```
┌─────────────────────┐
│  新锁进入缓存        │ (score = 0)
└──────────┬──────────┘
           │
           ↓ ldlm_lfru_add_lock()
┌─────────────────────────────────────┐
│ score++  (score = 1)                │
│ 检查: score > threshold?            │
└─────────────────────────────────────┘
      │
      ├─ 否 (score ≤ threshold)
      │   │
      │   ↓
      │  ┌──────────────────┐
      │  │ LRU_NORMAL_LIST  │
      │  │ (普通列表)        │
      │  └──────┬───────────┘
      │         │
      │         ├─ 再被访问 → score++
      │         │  (可能晋升到特权)
      │         │
      │         └─ 缓存满 → 驱逐
      │             (普通列表优先驱逐)
      │
      └─ 是 (score > threshold)
          │
          ↓
         ┌──────────────────┐
         │ LRU_PRIV         │
         │ (特权列表)        │
         └──────┬───────────┘
                │
                ├─ 再被访问 → score++
                │  (但不会被降级回普通)
                │
                └─ 特权列表超限 → 批量降级
                    ├─ score >>= 2
                    └─ 回到 LRU_NORMAL_LIST
```

---

## 三、动态阈值更新的详细流程

### 场景：缓存中有 100 把锁的文件目录遍历

#### 初始状态
```
threshold = 1
max_freq = 1
access_cnt = 0
window_size = 10 (假设)
```

#### 访问序列
```
访问#1: Lock-A, score=1
  → score (1) ≤ threshold (1)? 不是
  → EQUAL 不算，添加到普通列表
  → access_cnt = 1

访问#2: Lock-B, score=1
  → 普通列表
  → access_cnt = 2

...访问#8: Lock-H, score=1
  → 普通列表
  → access_cnt = 8

访问#9: Lock-I, score=2
  → score (2) > threshold (1)? 是！✓
  → 晋升到特权列表
  → threshold 更新为 2
  → max_freq 重置为 1
  → access_cnt 重置为 0 (RESET!)

访问#10: Lock-J, score=1
  → score (1) > threshold (2)? 否
  → 普通列表
  → access_cnt = 1, max_freq = 1

访问#11: Lock-K, score=1
  → access_cnt = 2, max_freq = 1

...访问#15: Lock-O, score=1
  → access_cnt = 5
  → 现在 access_cnt == window_size / 2
  → max_freq = max_freq * 3 / 4 = 1 * 3 / 4 = 0 (衰减)

访问#16: Lock-P, score=1
  → access_cnt = 6, max_freq = 0

...访问#25: Lock-Y, score=1
  → access_cnt = 10
  → 现在 access_cnt == window_size
  → threshold 更新为 max_freq (0 或 1)
  → access_cnt 重置为 0

```

#### 效果
```
特权列表: Lock-A (score 达到 2)
普通列表: 其他 99 把锁

阈值快速提升到 2，防止大量普通锁被晋升
缓存污染得到有效控制
```

---

## 四、评分递减（Score Decay）

降级时的评分处理：

```
降级前: lock->l_lru_score = 8 (0b00001000)
操作:   lock->l_lru_score >>= 2  (右移2位 = 除以4)
降级后: lock->l_lru_score = 2 (0b00000010)

作用: 
  - 防止被降级的锁立即再次晋升
  - 给新兴热点锁机会
  - 实现公平的竞争
```

---

## 五、关键判断条件详解

### 5.1 晋升条件

```c
new_priv = !was_priv &&
           (lock->l_lru_score > ns->ns_lfru_priv_score_threshold ||
            lock->l_lru_score == LDLM_LFRU_PRIV_THRESH_CAP);
```

**三个子条件的AND关系**：
1. `!was_priv` - 锁还不在特权列表（避免重复处理）
2. `score > threshold` - 评分超过动态阈值
3. OR `score == 254` - 或者达到评分上限

**含义**：评分足够高 OR 达到最高值，且还不在特权列表

### 5.2 超限判断

```c
ldlm_lfru_priv_too_many(ns)
{
    return (ns->ns_nr_priv >= (LDLM_DEFAULT_LRU_SIZE >> 3)) &&
           (ns->ns_nr_priv >= 
            ns->ns_nr_unused * ns->ns_lfru_priv_ratio_limit_256 >> 8);
}
```

**两个条件的AND**：
1. `priv_count >= total_lru_size / 8` (12.5%)
2. `priv_count >= unused_count * ratio / 256`

**例子**：
```
假设:
  LDLM_DEFAULT_LRU_SIZE = 10000
  ns_nr_priv = 2000
  ns_nr_unused = 5000
  ns_lfru_priv_ratio_limit_256 = 77 (30% 转换)

检查:
  2000 >= 10000 >> 3?  → 2000 >= 1250? 是
  2000 >= 5000 * 77 >> 8?  → 2000 >= 96? 是
  
结果: 超限，需要降级
```

### 5.3 降级条件

```c
if (target_evicts == LDLM_LFRU_PRIV_PER_ROUND_LIMIT &&
    !ldlm_lfru_priv_too_many(ns))
    return 0;  // 不降级
```

**降级发生的条件**：
- 且是定期降级检查（batch_size == 10）
- 且特权列表已超限

**避免的问题**：即使特权列表不超限，也不会无必要地降级

---

## 六、性能特性分析

### 6.1 最坏情况下的访问模式

```
场景: 持续有新的高频访问锁加入

初始: threshold = 1
Lock-1: score=2 → threshold 更新为 2, access_cnt 重置为 0
Lock-2: score=2 → threshold 保持 2
        ... (多个普通锁，评分都=1)
        (当access_cnt达到一半时)
        max_freq 衰减为 max_freq * 3/4

Lock-N: score=3 → threshold 更新为 3, access_cnt 重置为 0

结果: 
  - 阈值随着工作负载演变而提升
  - 防止过多的低频锁晋升
  - 自适应性强
```

### 6.2 缓存流量特征

```
热点访问:
  锁会快速累积评分
  快速晋升到特权列表
  稳定驻留在缓存中
  
冷门访问:
  评分积累缓慢
  可能永远无法晋升
  在缓存满时优先驱逐
  
扫描操作:
  大量一次性访问
  评分从1开始，快速递增
  但阈值也快速上升
  最后只有少数锁被保护
```

---

## 七、与其他缓存算法的对比

### 7.1 LRU vs LFRU

```
LRU 保护: 最后访问时间最近的 N 把锁
├─ 优点: 简单，实现快速
└─ 缺点: 对扫描无防护

LFRU 保护: 访问频率最高的 M 把锁（M < N）
├─ 优点: 扫描抵抗，热点保护
└─ 缺点: 需要维护阈值和评分
```

### 7.2 LFU vs LFRU

```
LFU (纯频率): 按访问计数排序
├─ 优点: 理论最优
└─ 缺点: 新锁永远无法进入；旧冷门锁永不驱逐

LFRU (频率+最近性): 结合两个维度
├─ 优点: 权衡两者，自适应强
└─ 缺点: 参数调优复杂度增加
```

---

## 八、代码中的关键宏和常量

```c
LDLM_LFRU_MIN_PRIV_THRESH       = 1
  - 最低起始阈值
  - 确保至少最频繁的1把锁能被保护

LDLM_LFRU_PRIV_THRESH_CAP       = 254
  - 评分和阈值的上限
  - 用 u8 存储，范围 0-255
  - 避免整数溢出

LDLM_LFRU_PRIV_LIST_RATIO_LIMIT = 30
  - 特权列表占总列表的最大百分比
  - 30% 是经验值

LDLM_LFRU_PRIV_PER_ROUND_LIMIT  = 10
  - 每次降级最多处理的锁数
  - 避免单次降级操作耗时过长

LDLM_LFRU_UPDATE_WINDOW_DIV      = 10
  - 时间窗口大小 = LRU总大小 / 10
  - 更新周期决定了阈值自适应速度
```

---

## 九、实现中的内存优化

### 9.1 字段紧凑设计

```c
struct ldlm_lock {
    // ...
    enum ldlm_mode l_req_mode : 9;       // 位字段，节省空间
    enum ldlm_mode l_granted_mode : 9;   // 位字段
    unsigned int l_bl_ast_run : 1;       // 1 位布尔
    enum lvb_type l_lvb_type : 3;        // 位字段
    enum lru_list_type l_lru_type : 1;   // 1 位，仅存 NORMAL 或 PRIV
    u8 l_lru_score;                      // 1 字节，存评分 0-254
    // ...
}
```

**优势**：
- 每把锁只增加 1 字节（l_lru_score）
- l_lru_type 复用为位字段
- 缓存行效率高

### 9.2 列表节点复用

```c
struct ldlm_lock {
    struct list_head l_lru;  // 双向链表节点
    // 同时用于 ns_unused_priv_list 和 ns_unused_normal_list
    // 通过 l_lru_type 标记属于哪个列表
}
```

**设计巧妙处**：
- 不需要两个独立的链表节点
- 通过 l_lru_type 字段快速识别所属列表
- 内存开销最小化

---

## 十、实际应用场景

### 场景1: 服务器端文件锁管理

```
大量客户端并发访问同一目录
├─ 元数据操作频繁
├─ 少数热点文件被反复访问
└─ 大量冷门文件偶尔被扫描

LFRU优势:
  ✓ 热点文件的锁始终驻留
  ✓ 扫描不会驱逐热点锁
  ✓ 缓存空间利用效率高
```

### 场景2: 客户端锁缓存

```
客户端主动缓存服务器授权的锁
├─ 减少回源请求
├─ 加速本地文件操作
└─ 内存受限

LFRU优势:
  ✓ 自动识别常用的锁
  ✓ 优先保留对性能影响大的锁
  ✓ 根据工作负载动态调整
```

---

## 十一、调试和监控要点

### 重要状态变量

```c
// 监控特权列表的膨胀
ns->ns_nr_priv  
  - 应该 < ns->ns_nr_unused * 30 / 100
  - 异常高 → 阈值调整有问题

ns->ns_lfru_priv_score_threshold
  - 应该根据工作负载动态变化
  - 完全静止 → 工作负载变化不适应
  - 频繁跳变 → 窗口大小设置不当

ns->ns_lfru_access_window_cnt
  - 应该在 [0, check_window_size] 范围
  - 用于诊断阈值更新时机
```

### 性能指标

```c
// 建议跟踪
1. 特权列表占比: ns_nr_priv / ns_nr_unused
2. 晋升速率: 单位时间内新晋升的锁数
3. 降级批次: 每次降级处理的锁数
4. 阈值变化: threshold 的历史序列
5. 缓存命中率: (访问命中数) / (总访问数)
```

---

## 十二、潜在改进方向

### 1. 自适应窗口大小
```c
// 当前实现
ns_lfru_check_window_size = ns_max_unused / LDLM_LFRU_UPDATE_WINDOW_DIV;

// 改进: 根据特权列表膨胀情况动态调整
if (ns_nr_priv > 期望大小) {
    窗口大小 *= 1.2;  // 放缓阈值更新
} else if (ns_nr_priv < 期望大小) {
    窗口大小 *= 0.8;  // 加快阈值更新
}
```

### 2. 多层级晋升机制
```c
// 当前: 一次性晋升到顶
// 改进: 普通→候选→特权 三层

// 候选层: 评分 > threshold / 2
// 特权层: 评分 > threshold

// 优点: 更平滑的晋升，避免激进变化
```

### 3. 时间衰减
```c
// 当前: 仅按访问窗口衰减
// 改进: 根据绝对时间衰减

// 长期未使用的锁应该自动降级
if (now - lock->l_last_used > 衰减时间) {
    lock->l_lru_score *= 衰减因子;
}
```

---

## 总结

LFRU 算法实现中的关键创新：

1. **双列表分离** - 简单但有效的分层保护
2. **动态阈值调整** - 自适应工作负载变化
3. **时间窗口机制** - 平衡历史和当前
4. **批量降级控制** - 防止列表膨胀
5. **位字段优化** - 最小化内存开销

这些组件共同实现了一个**简洁、高效、自适应**的缓存管理算法。
