/*
 * LFRU (Least Frequently and Recently Used) 缓存策略实现 - 详细注解版
 * 
 * 算法概述:
 * ========
 * LFRU 将锁分为两个列表:
 * 1. 特权列表 (Privileged List) - 存放频繁访问的高价值锁
 * 2. 普通列表 (Normal List) - 存放低频或冷门锁
 * 
 * 当缓存满时，优先驱逐普通列表中最旧的锁。
 * 
 * 核心优势: 对大量扫描操作有抵抗力
 * 例: 执行 ls -l 遍历大目录时，不会大量污染缓存
 */

#include <lustre_swab.h>
#include <obd_class.h>
#include "ldlm_internal.h"

/* ==================== 基础 LRU 实现 ==================== */

/**
 * ldlm_lru_add_lock - 将锁添加到 LRU 列表
 * @ns: LDLM 命名空间
 * @lock: 要添加的锁
 * 
 * 操作:
 *   1. 增加未使用锁的计数
 *   2. 将锁加入 LRU 列表尾部（最新）
 *   3. 标记锁的类型为普通列表
 */
static void ldlm_lru_add_lock(struct ldlm_namespace *ns,
			      struct ldlm_lock *lock)
{
	ns->ns_nr_unused++;  // 增加未使用锁计数
	list_add_tail(&lock->l_lru, &ns->ns_unused_normal_list);  // 链表尾部插入（最新）
	lock->l_lru_type = LRU_NORMAL_LIST;  // 标记为普通列表
}

/**
 * ldlm_lru_remove_lock - 从 LRU 列表移除锁
 * @ns: LDLM 命名空间
 * @lock: 要移除的锁
 * 
 * 返回值: 1 表示成功移除，0 表示锁不在列表中
 * 
 * 操作:
 *   1. 检查锁是否在 LRU 列表中
 *   2. 如果最后位置指针指向该锁，更新指针
 *   3. 从列表中删除
 *   4. 减少计数
 */
static int ldlm_lru_remove_lock(struct ldlm_namespace *ns,
				struct ldlm_lock *lock)
{
	int rc = 0;

	if (!list_empty(&lock->l_lru)) {
		LASSERT(lock->l_resource->lr_type != LDLM_FLOCK);
		
		// 更新最后位置指针，防止野指针
		if (ns->ns_last_pos == &lock->l_lru)
			ns->ns_last_pos = lock->l_lru.prev;
		
		list_del_init(&lock->l_lru);  // 从链表删除
		LASSERT(ns->ns_nr_unused > 0);
		ns->ns_nr_unused--;  // 递减计数
		rc = 1;  // 成功标记
	}
	return rc;
}

struct ldlm_lock_cache_ops ldlm_lru_cache_ops = {
	.llco_add_lock = ldlm_lru_add_lock,
	.llco_remove_lock = ldlm_lru_remove_lock,
};

/* ==================== LFRU 核心实现 ==================== */

/**
 * ldlm_check_and_adjust_lfru_thresh - 动态调整特权列表的晋升阈值
 * @ns: LDLM 命名空间
 * @score: 当前锁的访问评分
 * 
 * 这是LFRU算法的灵魂所在！通过时间窗口机制实现自适应的阈值调整。
 * 
 * 工作原理:
 * --------
 * 1. 条件1 - 发现更高评分的锁:
 *    如果 score > 当前阈值，说明有更优秀的锁出现
 *    立即将阈值提升到该分数，重置时间窗口
 *    这样可以快速隔离出最有价值的锁
 * 
 * 2. 条件2 - 时间窗口满:
 *    累积访问次数达到窗口大小后，基于窗口内的最高评分更新阈值
 *    这反映了当前工作负载的特征
 * 
 * 3. 条件3 - 窗口半满时衰减:
 *    将最高评分乘以 3/4 (衰减因子)
 *    作用: 逐渐降低旧访问模式的影响，快速适应新工作负载
 * 
 * 示例:
 * ----
 * 初始: threshold=1, max_freq=1, access_cnt=0, window_size=10
 * 
 * 访问Lock-A, score=1: access_cnt=1, max_freq=1
 * 访问Lock-B, score=2: score > threshold(1) → 
 *   |→ 阈值提升为2
 *   |→ max_freq重置为1
 *   |→ access_cnt重置为0
 * 访问Lock-C, score=1: access_cnt=1, max_freq=1
 * ... [继续5次访问] ...
 * 访问Lock-H, score=1: access_cnt=5 (半窗口)
 *   |→ max_freq = max_freq * 3/4 = 0 (衰减)
 * ... [继续5次访问] ...
 * 访问Lock-M, score=1: access_cnt=10 (满窗口)
 *   |→ 阈值提升为max_freq(可能=1)
 *   |→ 重置计数和max_freq
 * 
 * 效果: 阈值持续演变，适应不同的工作负载
 */
static void ldlm_check_and_adjust_lfru_thresh(struct ldlm_namespace *ns,
					      __u8 score)
{
	// ========== 条件1: 发现更高的评分 ==========
	// 如果当前锁的评分高于历史阈值，或达到评分上限
	if (score > ns->ns_lfru_priv_score_threshold ||
	    score == LDLM_LFRU_PRIV_THRESH_CAP) {  // 254 是上限
		
		// 立即更新阈值 - 表示我们找到了更有价值的锁
		ns->ns_lfru_priv_score_threshold = score;
		
		// 重置时间窗口中的相关状态
		ns->ns_lfru_max_freq = LDLM_LFRU_MIN_PRIV_THRESH;  // 重置为1
		ns->ns_lfru_access_window_cnt = 0;  // 窗口计数清零
		return;  // 直接返回，不执行下面的窗口逻辑
	}

	// ========== 条件2和3: 时间窗口机制 ==========
	// 在当前窗口内追踪最高的评分
	if (score > ns->ns_lfru_max_freq)
		ns->ns_lfru_max_freq = score;  // 更新最高分
	
	// 每次访问都增加窗口计数
	ns->ns_lfru_access_window_cnt++;
	
	// 检查窗口是否满了
	if (ns->ns_lfru_access_window_cnt == ns->ns_lfru_check_window_size) {
		// ===== 窗口满 (完整周期) =====
		// 基于这个窗口内的最高评分更新阈值
		// 这反映了当前工作负载的特征
		ns->ns_lfru_priv_score_threshold = ns->ns_lfru_max_freq;
		
		// 重置所有窗口相关状态
		ns->ns_lfru_max_freq = LDLM_LFRU_MIN_PRIV_THRESH;
		ns->ns_lfru_access_window_cnt = 0;
		
	} else if (ns->ns_lfru_access_window_cnt ==
		   ns->ns_lfru_check_window_size / 2) {
		// ===== 窗口走到一半 =====
		// 执行衰减操作: 乘以 3/4 = 0.75
		// 目的: 逐渐降低旧访问模式的权重，让新热点锁有机会提升
		// 例: max_freq=4 → 4*3/4 = 3
		ns->ns_lfru_max_freq = ns->ns_lfru_max_freq * 3 / 4;
	}
}

/**
 * ldlm_lfru_add_lock - 将锁添加到LFRU缓存（关键函数）
 * @ns: LDLM 命名空间
 * @lock: 要添加的锁
 * 
 * 整体流程:
 * 1. 增加未使用锁总数
 * 2. 提高锁的访问评分（反映访问频率）
 * 3. 判断是否需要晋升到特权列表
 * 4. 添加到相应列表
 * 5. 调整晋升阈值（自适应机制）
 * 
 * 重要约束:
 * - 一旦晋升到特权列表，就永远不会被自动降级（直到驱逐）
 *   这确保了热点锁的稳定性
 * - 只有新晋升的锁才触发阈值调整
 *   既晋升的锁只是继续存在
 */
static void ldlm_lfru_add_lock(struct ldlm_namespace *ns,
			       struct ldlm_lock *lock)
{
	// 记录锁当前的状态（是否已在特权列表）
	bool was_priv = lock->l_lru_type == LRU_PRIV;
	bool new_priv = false;

	// ===== Step 1: 更新全局计数 =====
	ns->ns_nr_unused++;  // 未使用锁总数 +1

	// ===== Step 2: 提高锁的访问评分 =====
	// 每次添加时评分 +1，上限 254
	// 这是对"频率"的简单但有效的编码
	lock->l_lru_score = min_t(int, lock->l_lru_score + 1,
				  LDLM_LFRU_PRIV_THRESH_CAP);  // 254是上限

	// ===== Step 3: 判断是否晋升 =====
	// 三个条件的AND:
	// 1. !was_priv: 锁还不在特权列表
	// 2. score > threshold: 评分超过动态阈值（频率足够高）
	// 3. OR score == 254: 或者已经达到最高评分
	new_priv = !was_priv &&
		   (lock->l_lru_score > ns->ns_lfru_priv_score_threshold ||
		    lock->l_lru_score == LDLM_LFRU_PRIV_THRESH_CAP);

	// ===== Step 4: 添加到相应列表 =====
	// 注释: "一旦晋升到特权列表，就应该停留在那里直到被驱逐"
	// 这是一个设计决定，确保热点锁不被污染
	
	if (was_priv || new_priv) {
		// 已在特权或新晋升 → 添加到特权列表
		list_add_tail(&lock->l_lru, &ns->ns_unused_priv_list);
		ns->ns_nr_priv++;  // 特权锁计数 +1
		lock->l_lru_type = LRU_PRIV;  // 标记为特权
	} else {
		// 不晋升 → 添加到普通列表
		list_add_tail(&lock->l_lru, &ns->ns_unused_normal_list);
		lock->l_lru_type = LRU_NORMAL_LIST;  // 标记为普通
	}

	// ===== Step 5: 调整晋升阈值 =====
	// 关键: 只在新晋升时调整，不在既晋升时调整
	// 这样可以避免频繁的阈值波动
	if (!was_priv)  // 仅当这是新晋升（或第一次添加）
		ldlm_check_and_adjust_lfru_thresh(ns, lock->l_lru_score);
}

/**
 * ldlm_lfru_remove_lock - 从LFRU缓存移除锁（驱逐时调用）
 * @ns: LDLM 命名空间
 * @lock: 要移除的锁
 * 
 * 返回值: 1 成功移除，0 锁不在列表中
 * 
 * 操作:
 * 1. 使用基础LRU的移除逻辑处理链表删除
 * 2. 如果移除的是特权锁，减少特权锁计数
 * 
 * 为什么分离?
 * LFRU中的特权锁需要额外的簿记（ns_nr_priv计数）
 * 而普通列表可以复用基础LRU逻辑
 */
static int ldlm_lfru_remove_lock(struct ldlm_namespace *ns,
				 struct ldlm_lock *lock)
{
	int rc = 0;

	// 调用基础LRU移除逻辑（处理链表删除）
	rc = ldlm_lru_remove_lock(ns, lock);
	
	// 如果成功移除，且是特权锁，更新特权计数
	if (rc && lock->l_lru_type == LRU_PRIV) {
		LASSERT(ns->ns_nr_priv > 0);  // 断言特权锁计数>0
		ns->ns_nr_priv--;  // 特权锁计数 -1
	}
	return rc;
}

/**
 * ldlm_lfru_demote_lock - 将锁从特权列表降级到普通列表
 * @ns: LDLM 命名空间
 * @lock: 要降级的锁
 * 
 * 场景: 当特权列表过度膨胀时，批量将锁降级回普通列表
 * 
 * 操作:
 * 1. 从特权列表移除（包括更新特权计数）
 * 2. 评分大幅削减（右移2位 = 除以4）
 * 3. 添加到普通列表
 * 
 * 评分削减的含义:
 * - 防止被降级的锁立即再次晋升
 * - 给其他热点锁机会竞争
 * - 例: score=8 → 8>>2 = 2（大幅降低，但不是0）
 */
static void ldlm_lfru_demote_lock(struct ldlm_namespace *ns,
				  struct ldlm_lock *lock)
{
	// 服务器端的锁有特殊处理，这里直接返回
	if ((lock->l_flags & LDLM_FL_NS_SRV)) {
		LASSERT(list_empty(&lock->l_lru));
		return;
	}

	// ===== 从特权列表移除 =====
	LASSERT(lock->l_lru_type == LRU_PRIV);  // 必须是特权锁
	ldlm_lfru_remove_lock(ns, lock);  // 移除并更新计数

	// ===== 添加到普通列表 =====
	ns->ns_nr_unused++;  // 重新计算未使用锁总数
	list_add_tail(&lock->l_lru, &ns->ns_unused_normal_list);
	lock->l_lru_type = LRU_NORMAL_LIST;  // 标记为普通列表

	// ===== 削减评分 =====
	// 右移2位 = 除以4
	// 例: 8 (0b1000) >> 2 = 2 (0b0010)
	// 这样可以防止被降级的锁立即再次晋升
	lock->l_lru_score >>= 2;
}

/**
 * ldlm_lfru_priv_too_many - 判断特权列表是否过度膨胀
 * @ns: LDLM 命名空间
 * 
 * 返回: true 表示特权列表超限，需要降级；false 表示正常
 * 
 * 判断标准（必须同时满足）:
 * 1. 特权锁数 >= (默认LRU大小 / 8) = 12.5% 的绝对值
 *    目的: 确保触发点绝对值够大，不会频繁波动
 * 
 * 2. 特权锁数 >= (总锁数 * 限制比例 / 256)
 *    目的: 特权锁占总锁数的比例不超过限制
 *    256是分母（因为用>>8来实现除法优化）
 *    例: 比例30% = 30*256/100 = 77
 * 
 * 两个条件的AND: 既要超过绝对阈值，又要超过相对比例
 * 这样可以在小缓存中不降级，在大缓存中按比例降级
 * 
 * 例子:
 * ----
 * 假设 LDLM_DEFAULT_LRU_SIZE = 10000
 *     ns_nr_priv = 2000
 *     ns_nr_unused = 5000
 *     ns_lfru_priv_ratio_limit_256 = 77 (30%)
 * 
 * 检查:
 *   2000 >= 10000 >> 3?  →  2000 >= 1250?  → true
 *   2000 >= 5000 * 77 >> 8?  →  2000 >= 96?  → true
 *   结果: 超限，需要降级
 */
static inline bool ldlm_lfru_priv_too_many(struct ldlm_namespace *ns)
{
	return (ns->ns_nr_priv >= (LDLM_DEFAULT_LRU_SIZE >> 3)) &&
	       (ns->ns_nr_priv >=
		ns->ns_nr_unused * ns->ns_lfru_priv_ratio_limit_256 >> 8);
}

/**
 * ldlm_lfru_try_batch_demote_locks - 批量降级特权列表中的锁
 * @ns: LDLM 命名空间
 * @batch_size: 一次最多降级多少个锁
 * 
 * 返回值: 实际降级的锁数量
 * 
 * 工作流程:
 * 1. 检查特权列表是否为空（快速路径）
 * 2. 判断是否需要降级（只在特权列表超限时）
 * 3. 遍历特权列表（从最旧的开始）
 * 4. 逐个降级锁，直到达到batch_size上限
 * 
 * 为什么需要批量降级?
 * - 防止特权列表无限膨胀
 * - 保证缓存使用的高效性
 * - batch_size限制确保单次操作不会耗时过长
 * 
 * 驱逐顺序的影响:
 * - 特权列表中最旧的锁首先被降级
 * - 这结合了LRU的"最近性"原则
 * - LFRU = 频率（是否在特权列表）+ 最近性（列表内顺序）
 */
static int ldlm_lfru_try_batch_demote_locks(struct ldlm_namespace *ns,
					    int batch_size)
{
	struct ldlm_lock *lock, *temp;
	int target_evicts = batch_size;  // 目标降级数量
	int evicts = 0;  // 实际已降级数量

	// ===== 快速路径: 如果特权列表为空，直接返回 =====
	if (unlikely(list_empty(&ns->ns_unused_priv_list)))
		return 0;

	// ===== 判断是否需要降级 =====
	// 条件:
	// 1. batch_size == LDLM_LFRU_PRIV_PER_ROUND_LIMIT (10)
	//    这是定期检查（vs 立即驱逐）
	// 2. 特权列表未超限
	//    如果未超限就不强制降级（保护热点锁）
	if (target_evicts == LDLM_LFRU_PRIV_PER_ROUND_LIMIT &&
	    !ldlm_lfru_priv_too_many(ns))
		return 0;  // 条件不满足，不降级

	// ===== 批量降级 =====
	// 使用 list_for_each_entry_safe 遍历，因为降级会修改列表
	list_for_each_entry_safe(lock, temp, &ns->ns_unused_priv_list, l_lru) {
		if (evicts < target_evicts) {
			// 还没达到降级上限，降级这个锁
			ldlm_lfru_demote_lock(ns, lock);
			evicts++;
		} else {
			// 已达到批次上限，停止降级
			break;
		}
	}

	return evicts;  // 返回实际降级的数量
}

/**
 * ldlm_lfru_cache_ops - LFRU缓存操作接口
 * 
 * 这个结构定义了LFRU算法的所有操作回调
 * 在命名空间初始化时，根据缓存策略选择这个或LRU版本
 */
struct ldlm_lock_cache_ops ldlm_lfru_cache_ops = {
	.llco_add_lock = ldlm_lfru_add_lock,              // 添加锁
	.llco_remove_lock = ldlm_lfru_remove_lock,        // 移除锁
	.llco_demote_lock = ldlm_lfru_demote_lock,        // 单个降级（可选）
	.llco_try_batch_demote_locks = ldlm_lfru_try_batch_demote_locks,  // 批量降级
};

/* ==================== 算法总结 ==================== 

LFRU 算法的优雅之处在于:

1. 简单的数据结构
   - 只增加1字节的评分字段
   - 复用现有的链表节点
   - 两个列表共享存储空间

2. 自适应的阈值机制
   - 通过时间窗口追踪工作负载特征
   - 动态调整晋升标准
   - 自动衰减旧的访问模式

3. 有效的扫描抵抗
   - 快速提升阈值隔离扫描操作
   - 最终只有少数高价值锁被保护
   - 防止缓存污染

4. 强大的适应性
   - 工作负载变化时自动调整
   - 无需人工调优参数
   - 既适应频繁访问也适应稀疏访问

实际应用中，相比纯LRU，LFRU能显著提高:
- 缓存命中率
- 热点锁的驻留时间
- 大量扫描场景的性能

=====================================================*/
