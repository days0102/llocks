#!/usr/bin/env python3

"""
Author: Gemini (Based on Outsider's trace script)
Date: 2025-11-20 15:30:00
Description: Reads multiple pairs of CLI and MDS trace files and plots selected metrics 
             on a single graph for comparison.
FilePath: /llocks/client/lock/draw_comparison.py
"""
import sys
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.dates import DateFormatter
import os

# --- 全局配置 ---
# 定义绘制的指标和它们对应的样式
PLOT_METRICS = {
    "lock_granted": {
        "label": "lock_granted",
        "style": "solid",
        "marker": None,
        "priority": 1,
    },
    "pool_limit": {
        "label": "pool_limit",
        "style": "dashdot",
        "marker": None,
        "priority": 2,
    },
    "lock_cancel": {
        "label": "lock_cancel",
        "style": "dashed",
        "marker": "x",
        "priority": 3,
    },
    # 您可以添加更多指标，例如：
    # "ldlm_cancel": {"label": "CLI LDLM Cancel", "style": "dotted", "marker": "o", "priority": 4},
}
# 使用 Matplotlib 的 'tab10' 颜色集，它比 Set1 更柔和
LINE_COLORS = plt.cm.tab10.colors
# 使用简单的线型，让颜色和标记成为主要区分手段
LINE_STYLES = ["-", "--", "-."]
LINE_MARKERS = [None, None, None]


def plot_comparison(
    experiment_list, output_filename="trace_comparison.png", ref_value=634200
):
    """
    读取多个实验的 trace 文件，并将选定的指标绘制在同一张图上进行对比。
    使用经典 Matplotlib 风格，X 轴使用相对时间。
    """
    # 恢复经典风格，使用默认设置，只启用基础网格
    plt.style.use("default")
    fig, ax = plt.subplots(figsize=(12, 7))  # 恢复到一个更常规的尺寸

    # 使用独立的索引来分配线条样式
    exp_index = 0

    for cli_file, mds_file, exp_label in experiment_list:
        print(f"Processing experiment: {exp_label}")

        try:
            # === 读取和合并数据 ===
            df1 = pd.read_csv(cli_file, delim_whitespace=True)
            df2 = pd.read_csv(mds_file, delim_whitespace=True)

            df1["timestamp"] = pd.to_datetime(df1["timestamp"], unit="s")
            df2["timestamp"] = pd.to_datetime(df2["timestamp"], unit="s")

            df = pd.merge(df1, df2, on="timestamp", how="inner").sort_values(
                "timestamp"
            )

            if df.empty:
                print(f"Warning: Merged data for {exp_label} is empty. Skipping.")
                exp_index += 1
                continue

        except FileNotFoundError as e:
            print(f"Error: File not found for {exp_label}. Details: {e}")
            exp_index += 1
            continue
        except Exception as e:
            print(f"Error processing data for {exp_label}: {e}")
            exp_index += 1
            continue

        # 🚨 关键修改：计算相对时间
        start_time = df["timestamp"].min()
        df["relative_time"] = (df["timestamp"] - start_time).dt.total_seconds()

        # === 循环绘制选定的指标 ===
        metric_index = 0
        for metric, style_config in PLOT_METRICS.items():
            if metric in df.columns:

                # 动态分配样式
                color = LINE_COLORS[exp_index % len(LINE_COLORS)]
                # 使用实线或指标定义的线型
                linestyle = style_config["style"]

                # 为 lock_granted 恢复原始的 'x' 标记（如果有），否则使用默认
                marker = (
                    style_config.get("original_marker")
                    if metric == "lock_granted"
                    else LINE_MARKERS[exp_index % len(LINE_MARKERS)]
                )

                full_label = f"{exp_label} - {style_config['label']}"

                ax.plot(
                    df["relative_time"],  # 使用相对时间作为 X 轴
                    df[metric],
                    label=full_label,
                    color=color,
                    linestyle=linestyle,
                    linewidth=2,
                    marker=marker,
                    # 如果有标记，大小为 5，否则为 0
                    markersize=5 if marker else 0,
                )

                metric_index += 1

        exp_index += 1

    # === 添加水平参考线 (使用原始的红色虚线风格) ===
    if ref_value is not None:
        ax.axhline(
            y=ref_value,
            color="r",
            linestyle="--",
            linewidth=2,
            label=f"threshold ({ref_value})",
        )

    # === 图形美化 (恢复原始风格) ===
    # 恢复原始的标题格式
    ax.set_title("Lock Metrics Comparison", fontsize=16)
    ax.set_xlabel("Relative Time (seconds)", fontsize=14)
    ax.set_ylabel("locks", fontsize=14)  # 恢复原始的 Y 轴标签

    plt.xticks(rotation=0, ha="center", fontsize=11)

    ax.grid(True)
    ax.legend(fontsize=12)  # 恢复原始图例大小和默认位置 (loc='best')
    ax.legend(loc="upper left", bbox_to_anchor=(1.01, 1), fontsize=10, frameon=True)

    # 调整布局，为图例留出空间
    plt.subplots_adjust(right=0.75)

    # 移除边界调整，恢复默认 tight_layout
    plt.tight_layout()

    # 保存图表
    plt.savefig(output_filename, dpi=300)
    print(f"\n✅ Comparison plot saved to {output_filename}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 draw_comparison.py <results_directory>")
        sys.exit(1)

    results_dir = sys.argv[1]  # 第一个参数用于确定输出目录，但我们将硬编码文件路径

    # --- 🚨 自定义实验配置数组 🚨 ---
    # 请根据您的实际文件路径和目录结构进行修改！
    # 格式: (CLI_FILE_PATH, MDS_FILE_PATH, 实验标签)

    base_dir = "/home/lwz/llocks/client/lock"

    experiment_configs = [
        (
            os.path.join(
                base_dir,
                "results_20251120_033749/EXP_23_lru_resize=0_lru_max_age=1_lock_reclaim_pol=1_lock_reclaim_batch=0_lock_reclaim_batch_per=5.cli_trace.txt",
            ),
            os.path.join(
                base_dir,
                "results_20251120_033749/EXP_23_lru_resize=0_lru_max_age=1_lock_reclaim_pol=1_lock_reclaim_batch=0_lock_reclaim_batch_per=5.mds_trace.txt",
            ),
            "lru_max_age=1",
        ),
        (
            os.path.join(
                base_dir,
                "results_20251120_033749/EXP_24_lru_resize=0_lru_max_age=3_lock_reclaim_pol=1_lock_reclaim_batch=0_lock_reclaim_batch_per=5.cli_trace.txt",
            ),
            os.path.join(
                base_dir,
                "results_20251120_033749/EXP_24_lru_resize=0_lru_max_age=3_lock_reclaim_pol=1_lock_reclaim_batch=0_lock_reclaim_batch_per=5.mds_trace.txt",
            ),
            "lru_max_age=3",
        ),
        (
            os.path.join(
                base_dir,
                "results_20251120_033749/EXP_25_lru_resize=0_lru_max_age=5_lock_reclaim_pol=1_lock_reclaim_batch=0_lock_reclaim_batch_per=5.cli_trace.txt",
            ),
            os.path.join(
                base_dir,
                "results_20251120_033749/EXP_25_lru_resize=0_lru_max_age=5_lock_reclaim_pol=1_lock_reclaim_batch=0_lock_reclaim_batch_per=5.mds_trace.txt",
            ),
            "lru_max_age=5",
        ),
        (
            os.path.join(
                base_dir,
                "results_20251120_033749/EXP_26_lru_resize=0_lru_max_age=10_lock_reclaim_pol=1_lock_reclaim_batch=0_lock_reclaim_batch_per=5.cli_trace.txt",
            ),
            os.path.join(
                base_dir,
                "results_20251120_033749/EXP_26_lru_resize=0_lru_max_age=10_lock_reclaim_pol=1_lock_reclaim_batch=0_lock_reclaim_batch_per=5.mds_trace.txt",
            ),
            "lru_max_age=10",
        ),
        # (
        #     os.path.join(
        #         base_dir,
        #         "results_20251120_033749/EXP_27_lru_resize=0_lru_max_age=30_lock_reclaim_pol=1_lock_reclaim_batch=0_lock_reclaim_batch_per=5.cli_trace.txt",
        #     ),
        #     os.path.join(
        #         base_dir,
        #         "results_20251120_033749/EXP_27_lru_resize=0_lru_max_age=30_lock_reclaim_pol=1_lock_reclaim_batch=0_lock_reclaim_batch_per=5.mds_trace.txt",
        #     ),
        #     "lru_max_age=30",
        # ),
    ]

    # 示例: 假设您使用了之前 mdtest 中的文件命名约定，但需要手动找到对应的 trace 文件
    # 警告：以下路径是假设，您需要将其替换为实际的 trace 文件名

    # --- 示例配置 (请替换为您的实际文件名) ---
    # experiment_configs = [
    #     (
    #         os.path.join(results_dir, "EXP_01_lru_resize=1..._cli_trace.txt"),
    #         os.path.join(results_dir, "EXP_01_lru_resize=1..._mds_trace.txt"),
    #         "LRU ON | Batch 512",
    #     ),
    #     (
    #         os.path.join(results_dir, "EXP_17_lru_resize=0..._cli_trace.txt"),
    #         os.path.join(results_dir, "EXP_17_lru_resize=0..._mds_trace.txt"),
    #         "LRU OFF | MaxAge 1",
    #     ),
    #     (
    #         os.path.join(results_dir, "EXP_25_lru_resize=0..._cli_trace.txt"),
    #         os.path.join(results_dir, "EXP_25_lru_resize=0..._mds_trace.txt"),
    #         "LRU OFF | MaxAge 30",
    #     ),
    # ]

    # 运行绘图函数
    output_path = os.path.join(results_dir, "trace_comparison_summary.png")
    plot_comparison(experiment_configs, output_path)
