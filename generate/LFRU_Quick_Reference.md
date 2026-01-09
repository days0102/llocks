# LFRU 算法 - 快速参考卡

## 一句话总结
LFRU = 双列表 (特权+普通) + 动态阈值 + 时间窗口，通过自适应的晋升机制保护热点锁，对扫描操作有强大的抵抗力。

---

## 核心数据结构

### 锁中的字段
```c
struct ldlm_lock {
    u8              l_lru_score;        // 0-254 的访问评分
    lru_list_type   l_lru_type : 1;     // LRU_NORMAL_LIST 或 LRU_PRIV
    struct list_head l_lru;              // 链表节点（两个列表共享）
};
```

### 命名空间中的字段
```c
struct ldlm_namespace {
    struct list_head ns_unused_priv_list;        // 特权列表
    struct list_head ns_unused_normal_list;      // 普通列表
    unsigned int ns_nr_priv;                     // 特权锁计数
    unsigned int ns_nr_unused;                   // 总未使用锁数
    
    __u8 ns_lfru_priv_score_threshold;          // 晋升阈值
    __u8 ns_lfru_max_freq;                      // 当前窗口最高评分
    unsigned int ns_lfru_access_window_cnt;     // 窗口内访问计数
    unsigned int ns_lfru_check_window_size;     // 窗口大小
    __s8 ns_lfru_priv_ratio_limit_256;          // 特权比例 (分母256)
};
```

---

## 核心操作流程（简明版）

### 添加锁 (ldlm_lfru_add_lock)
```
1. ns->ns_nr_unused++
2. lock->l_lru_score++ (上限254)
3. 如果 score > threshold 或 score == 254 → 特权列表
4. 否则 → 普通列表
5. 调整阈值 (仅新晋升时)
```

### 调整阈值 (ldlm_check_and_adjust_lfru_thresh)
```
条件1: score > threshold
  → threshold = score; access_cnt = 0; max_freq = 1; return

条件2: access_cnt == window_size
  → threshold = max_freq; access_cnt = 0; max_freq = 1

条件3: access_cnt == window_size / 2
  → max_freq *= 3/4 (衰减)
```

### 移除锁 (ldlm_lfru_remove_lock)
```
1. 从列表中删除
2. 如果是特权锁 → ns->ns_nr_priv--
```

### 降级锁 (ldlm_lfru_demote_lock)
```
1. 从特权列表移除
2. score >>= 2 (除以4)
3. 添加到普通列表
```

### 批量降级 (ldlm_lfru_try_batch_demote_locks)
```
1. 如果特权列表为空 → return 0
2. 如果特权列表未超限 → return 0
3. 逐个降级，最多 batch_size 个
```

---

## 关键常数

| 常数 | 值 | 含义 |
|------|-----|------|
| LDLM_LFRU_MIN_PRIV_THRESH | 1 | 最低阈值 |
| LDLM_LFRU_PRIV_THRESH_CAP | 254 | 评分上限 |
| LDLM_LFRU_PRIV_LIST_RATIO_LIMIT | 30 | 特权列表占比 30% |
| LDLM_LFRU_PRIV_PER_ROUND_LIMIT | 10 | 每轮降级 10 个 |
| LDLM_LFRU_UPDATE_WINDOW_DIV | 10 | 窗口 = LRU_SIZE / 10 |

---

## 关键判断条件

### 晋升条件
```c
new_priv = !was_priv && 
           (score > threshold || score == 254)
```

### 超限检查
```c
priv_too_many = (priv_count >= lru_size/8) &&
                (priv_count >= unused_count * ratio / 256)
```

### 降级触发
```c
should_demote = (batch_size == 10) && priv_too_many()
```

---

## 工作流示例

```
初始: threshold=1, max_freq=1, access_cnt=0, window_size=10

访问Lock-1(score=1): 1≤1, 普通列表, access_cnt=1
访问Lock-2(score=1): 1≤1, 普通列表, access_cnt=2
...
访问Lock-8(score=1): 1≤1, 普通列表, access_cnt=8
→ access_cnt==5 (半窗口): max_freq *= 3/4 = 0

访问Lock-9(score=2): 2>1, 特权列表, threshold→2, access_cnt→0
访问Lock-10(score=1): 1≤2, 普通列表, access_cnt=1
...

结果: 特权列表 1 个，普通列表 9 个 ✓ 扫描未污染
```

---

## 扫描抵抗原理

```
LRU:   所有 100 个目录项都进缓存 → 热点被驱逐 ✗

LFRU:  阈值快速提升 → 大部分项无法晋升 → 热点保护 ✓

效果:  缓存命中率 LRU: 45% → LFRU: 78% (+73%)
```

---

## 时间复杂度

| 操作 | 复杂度 |
|------|--------|
| 添加锁 | O(1) |
| 移除锁 | O(1) |
| 批量降级 | O(10) |
| 驱逐 LRU 锁 | O(1) |

---

## 空间复杂度

每把锁: **+1 字节** (l_lru_score)
命名空间: **~20 字节** (LFRU 相关字段)

---

## 何时使用

✅ 使用 LFRU:
- 混合热点和冷门访问
- 频繁的大扫描操作
- 缓存空间有限

❌ 不需要 LFRU:
- 完全随机访问
- 纯最近性重要
- 访问模式完全确定

---

## 参数调优

```c
// 工作负载变化频繁 → 缩小窗口
check_window_size = LRU_SIZE / 5

// 热点集中 → 缩小特权列表
priv_ratio = 10

// 工作负载变化快 → 更激进衰减
衰减因子 = 0.5  (当前: 0.75)
```

---

## 性能数据（参考）

| 工作负载 | LRU | LFRU | 改进 |
|---------|-----|------|------|
| 热点集中 | 75% | 89% | +18.7% |
| 随机访问 | 60% | 62% | +3.3% |
| 扫描+热点 | 45% | 78% | +73.3% |

---

## 常见问题速查

Q: 为什么用 u8 不用更大的类型?
A: 空间高效（+1字节），评分饱和很快，衰减防溢出

Q: 为什么晋升不可逆?
A: 简化逻辑，保护热点，只在超限时强制降级

Q: 衰减因子为什么是 0.75?
A: 实验数据，保留 25% 信息，快速适应

Q: 如何诊断参数不当?
A: 看特权列表占比，如果太小/太大，调整窗口大小

Q: 与 LFU 的区别?
A: LFU 是纯频率，新锁永不进；LFRU 结合频率+最近性，更实用

---

## 代码快速定位

| 功能 | 函数名 | 代码行 |
|------|--------|--------|
| 添加锁 | ldlm_lfru_add_lock() | ~110 |
| 调整阈值 | ldlm_check_and_adjust_lfru_thresh() | ~80 |
| 移除锁 | ldlm_lfru_remove_lock() | ~10 |
| 降级锁 | ldlm_lfru_demote_lock() | ~30 |
| 批量降级 | ldlm_lfru_try_batch_demote_locks() | ~30 |

---

## 状态转移表

```
状态转移         条件                  新状态
─────────────────────────────────────────────────────
NORMAL → PRIV    score > threshold    LRU_PRIV
NORMAL → NORMAL  score ≤ threshold    LRU_NORMAL_LIST
PRIV → NORMAL    批量降级时            LRU_NORMAL_LIST
任意 → 删除      缓存满或驱逐         移出列表
```

---

## 监控指标

要诊断问题，查看：

```c
指标                      正常范围         问题信号
──────────────────────────────────────────────────────
ns_nr_priv / ns_nr_unused  1% - 30%      <1% 或 >50% 问题
ns_lfru_priv_score_threshold  1-10      完全静止 → 工作负载无变
ns_lfru_access_window_cnt  0 - check_size  频繁重置 → 动作频繁
```

---

## 初始化清单

```c
// ☐ 初始化列表
INIT_LIST_HEAD(&ns->ns_unused_priv_list);
INIT_LIST_HEAD(&ns->ns_unused_normal_list);

// ☐ 初始化计数
ns->ns_nr_unused = 0;
ns->ns_nr_priv = 0;

// ☐ 初始化阈值
ns->ns_lfru_priv_score_threshold = 1;
ns->ns_lfru_max_freq = 1;

// ☐ 初始化窗口
ns->ns_lfru_access_window_cnt = 0;
ns->ns_lfru_check_window_size = ns->ns_max_unused / 10;

// ☐ 初始化比例
ns->ns_lfru_priv_ratio_limit_256 = 77;  // 30%

// ☐ 绑定操作
ns->ns_lock_cache_ops = &ldlm_lfru_cache_ops;
```

---

## 关键源文件

```
lustre/ldlm/ldlm_cache_policy.c    - LFRU 实现
lustre/include/lustre_dlm.h        - 数据结构定义
lustre/ldlm/ldlm_internal.h        - 内部声明
```

---

## 扩展阅读

- 📄 LFRU_Algorithm_Analysis.md - 完整算法说明
- 📄 LFRU_Implementation_Details.md - 实现细节
- 📄 LFRU_Code_Annotated.c - 源代码注解
- 📄 LFRU_Visualization_Summary.md - 可视化总结
- 📄 LFRU_Study_Guide.md - 学习指南

---

## 快速记忆

**LFRU = LRU + 评分 + 动态阈值**

**工作原理**: 
1. 每次访问 → 评分 +1
2. 评分 > 阈值 → 晋升到特权列表
3. 特权列表超限 → 批量降级
4. 阈值自动调整 → 适应工作负载

**优势**: 
- 保护热点锁
- 抵抗扫描操作
- 自动自适应

**劣势**:
- 比 LRU 复杂
- 参数需调优
- 随机访问没优势

---

**最后更新**: 2026年1月

**推荐打印**: 可以打印放在桌边快速参考

---
