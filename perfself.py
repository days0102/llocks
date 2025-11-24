#!/usr/bin/env python3

"""
Author: Outsider
Date: 2025-11-19 22:11:15
LastEditors: Outsider
LastEditTime: 2025-11-20 09:56:10
Description: In User Settings Edit
FilePath: /llocks/client/lock/perf.py
"""
"""
Author: Gemini
Date: 2025-11-19 21:15:00
Description: Script to extract mdtest 'Directory stat' rates from multiple experiment logs,
             calculate the average, and plot the results for comparison.
FilePath: /llocks/client/lock/extract_and_plot_mdtest.py
"""
import sys
import os
import re
import glob
import pandas as pd
import matplotlib.pyplot as plt


def extract_mdtest_data(log_files):
    data = {}

    if not log_files:
        print(f"Error: No log files 'EXP_*.log'")
        return data

    # 正则表达式用于匹配 Mean 速率
    # 查找 Directory stat 行，并捕获 Mean 列的值 (float)
    rate_pattern = re.compile(
        r"^\s+Directory stat\s+[\d\.]+\s+[\d\.]+\s+([\d\.]+)", re.MULTILINE
    )

    for log_path in log_files:
        filename = os.path.basename(log_path)

        # 提取实验配置名称 (e.g., 'EXP_12_lru_resize=1_lock_reclaim_pol=1_...')
        # 移除前缀 'EXP_XX_' 和后缀 '.log'
        match = re.search(r"EXP_\d\d_(.*)\.log", filename)
        if not match:
            print(f"Warning: Skipping file with non-standard name: {filename}")
            continue

        # 简化实验名称，只保留配置参数部分
        experiment_config = match.group(1)

        rates = []
        try:
            with open(log_path, "r") as f:
                content = f.read()

                # 查找所有匹配的速率
                rates_found = rate_pattern.findall(content)

                # 转换为浮点数
                rates = [float(r) for r in rates_found]

        except Exception as e:
            print(f"Error processing file {filename}: {e}")
            continue

        if rates:
            # 只取前三次 mdtest 的结果，并计算平均值
            valid_rates = rates[:3]
            avg_rate = sum(valid_rates) / len(valid_rates)
            data[experiment_config] = avg_rate
            print(
                f"Processed {filename}: Rates={valid_rates}, Avg={avg_rate:.2f} ops/sec"
            )
        else:
            print(f"Warning: No 'Directory stat' rates found in {filename}")

    return data


def plot_mdtest_comparison(data, output_dir):
    """
    绘制平均 Directory Stat 速率的对比图。
    """
    if not data:
        print("No data to plot.")
        return

    # 将数据转换为 Pandas Series 以方便排序
    rates = pd.Series(data).sort_values(ascending=False)

    configs = rates.index.tolist()
    avg_rates = rates.values.tolist()

    # 格式化配置名称，使其更适合图表显示
    # 例如：将 'lru_resize=1_lock_reclaim_pol=1...' 简化为多行标签
    formatted_labels = [c.replace("_", "\n") for c in configs]

    plt.figure(figsize=(12, 7))
    bars = plt.bar(formatted_labels, avg_rates, color="skyblue")

    # 在柱状图顶部添加数值标签
    for bar in bars:
        yval = bar.get_height()
        plt.text(
            bar.get_x() + bar.get_width() / 2.0,
            yval + (max(avg_rates) * 0.01),
            f"{yval:.0f}",
            ha="center",
            va="bottom",
            fontsize=10,
        )

    # === 图形美化 ===
    plt.title("mdtest Directory Stat Rate Comparison (Average of 3 Runs)", fontsize=16)
    plt.xlabel("Experiment Configuration", fontsize=14)
    plt.ylabel("Average Directory Stat Rate (ops/sec)", fontsize=14)

    # 旋转X轴标签，以便阅读
    plt.xticks(rotation=0, ha="center", fontsize=10)

    plt.grid(axis="y", linestyle="--", alpha=0.7)
    plt.tight_layout()

    plot_filename = os.path.join(output_dir, "mdtest_summary_comparison.png")
    plt.savefig(plot_filename, dpi=300)
    print(f"\n✅ Comparison plot saved to {plot_filename}")


def plot_mdtest_comparison2(data, output_dir):
    """
    绘制平均 Directory Stat 速率的对比图，使用颜色和斜线填充美化。
    """
    if not data:
        print("No data to plot.")
        return

    # 将数据转换为 Pandas Series 以方便排序
    rates = pd.Series(data).sort_values(ascending=False)

    configs = rates.index.tolist()
    avg_rates = rates.values.tolist()

    # --- 美化配置 ---
    # 颜色列表 (可以根据实验数量调整)
    colors = ["#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd", "#8c564b"]
    # 斜线填充图案列表
    patterns = ["", "///", "xxx", "\\\\", "---", "ooo"]

    # 格式化配置名称，使其更适合图表显示
    formatted_labels = []
    # 创建一个字典来映射配置到颜色/图案索引，以便更灵活地分配
    config_map = {}
    for i, c in enumerate(configs):
        # 尝试简化标签：只保留关键变化，例如 ELC 和 LRU 的状态
        label = (
            c.replace("lru_resize", "LRU")
            .replace("elc", "ELC")
            .replace("lock_reclaim_", "LRC_")
            .replace("_", "\n")
        )
        formatted_labels.append(label)
        config_map[c] = i % len(colors)  # 循环使用颜色和图案索引

    plt.style.use("seaborn-v0_8-whitegrid")  # 使用一个更清晰的 matplotlib 样式
    plt.figure(figsize=(14, 8))  # 增加图表大小

    # --- 绘制柱状图 ---
    bars = plt.bar(formatted_labels, avg_rates, width=0.7)

    # 应用颜色和斜线填充
    for i, bar in enumerate(bars):
        index = config_map[configs[i]]
        bar.set_color(colors[index % len(colors)])
        bar.set_hatch(patterns[index % len(patterns)])
        bar.set_edgecolor("black")  # 添加边框以突出斜线填充

        # 在柱状图顶部添加数值标签
        yval = bar.get_height()
        plt.text(
            bar.get_x() + bar.get_width() / 2.0,
            yval + (max(avg_rates) * 0.015),
            f"{yval/1000:.1f}k",
            ha="center",
            va="bottom",
            fontsize=11,
            fontweight="bold",
        )  # 标签使用k为单位，并加粗

    # --- 图形美化 ---
    plt.title(
        "mdtest Directory Stat Rate Comparison (Average of 3 Runs)",
        fontsize=18,
        fontweight="bold",
        pad=20,
    )
    plt.xlabel("Experiment Configuration", fontsize=14)
    plt.ylabel("Average Directory Stat Rate (ops/sec)", fontsize=14)

    # Y轴刻度使用科学记数法或更易读的格式（如果值很大）
    # plt.ticklabel_format(style='sci', axis='y', scilimits=(0,0))

    # 优化X轴标签，确保其居中
    plt.xticks(rotation=0, ha="center", fontsize=12)
    plt.yticks(fontsize=12)

    # 移除图表顶部和右侧的边框线
    ax = plt.gca()
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)

    plt.tight_layout()

    plot_filename = os.path.join(output_dir, "mdtest_summary_comparison.png")
    plt.savefig(plot_filename, dpi=300)
    print(f"\n✅ Comparison plot saved to {plot_filename}")


def plot_mdtest_comparison3(data, output_dir):
    """
    绘制平均 Directory Stat 速率的对比图，使用 Matplotlib Colormap 自动分配颜色。
    """
    if not data:
        print("No data to plot.")
        return

    # 将数据转换为 Pandas Series 以方便排序
    rates = pd.Series(data).sort_values(ascending=False)

    configs = rates.index.tolist()
    avg_rates = rates.values.tolist()
    N = len(configs)  # 实验数量

    # --- 美化配置 ---
    # 🚨 自动颜色分配：使用 Matplotlib 内置的 Colormap
    # 推荐使用 'tab10', 'Set1', 或 'Dark2' 等分类 Colormap
    # cmap = plt.get_cmap('Set1')
    # cmap = plt.get_cmap("Pastel1")
    # cmap = plt.get_cmap('Paired')
    cmap = plt.get_cmap('Set3')

    # 斜线填充图案列表 (保持手动定义，因为它不受 Colormap 控制)
    # patterns = ['', '///', 'xxx', '\\\\', '---', 'ooo', '+++', '///', 'xxx', '\\\\']
    # patterns = ['///', 'xxx', '\\\\', '///', 'xxx', '\\\\']
    patterns = ["", "///", "", "\\\\"]

    # 格式化配置名称，使其更适合图表显示
    # formatted_labels = []
    # for c in configs:
    #     # 尝试简化标签：只保留关键变化
    #     label = (
    #         c.replace("lru_resize", "LRU")
    #         .replace("elc", "ELC")
    #         .replace("lock_reclaim_", "LRC_")
    #         .replace("_", "\n")
    #     )
    #     formatted_labels.append(label)
    formatted_labels = [c.replace("_", "\n") for c in configs]
    

    plt.style.use("seaborn-v0_8-whitegrid")
    plt.figure(figsize=(14, 8))

    # --- 绘制柱状图 ---
    bars = plt.bar(formatted_labels, avg_rates, width=0.7)
    # bars = plt.bar(
    #     formatted_labels, 
    #     avg_rates, 
    #     width=0.7,
    #     edgecolor='gray',  # 使用浅灰色边框来显示斜线
    #     linewidth=0.5      # 使用极细的线宽
    # )

    # 自动应用颜色和斜线填充
    for i, bar in enumerate(bars):
        # 🚨 动态分配颜色：使用 Colormap 根据索引 i 分配颜色
        bar.set_color(cmap(i / N))

        # 循环使用斜线填充图案
        bar.set_hatch(patterns[i % len(patterns)])
        # bar.set_edgecolor("black")
        bar.set_edgecolor("gray")

        # 在柱状图顶部添加数值标签
        yval = bar.get_height()
        plt.text(
            bar.get_x() + bar.get_width() / 2.0,
            yval + (max(avg_rates) * 0.015),
            f"{yval/1000:.1f}k",
            ha="center",
            va="bottom",
            fontsize=11,
            fontweight="bold",
        )

    # --- 图形美化 (保持不变) ---
    plt.title(
        "mdtest Directory Stat Rate Comparison (Average of 3 Runs)",
        fontsize=18,
        fontweight="bold",
        pad=20,
    )
    plt.xlabel("Experiment Configuration", fontsize=14)
    plt.ylabel("Average Directory Stat Rate (ops/sec)", fontsize=14)

    plt.xticks(rotation=0, ha="center", fontsize=12)
    plt.yticks(fontsize=12)

    ax = plt.gca()
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)

    plt.tight_layout()

    plot_filename = os.path.join(output_dir, "mdtest_summary_comparison.png")
    plt.savefig(plot_filename, dpi=300)
    print(f"\n✅ Comparison plot saved to {plot_filename}")

def plot_mdtest_comparison4(data, output_dir):
    """
    绘制平均 Directory Stat 速率的对比图，动态调整图表宽度以保持柱子视觉比例。
    """
    if not data:
        print("No data to plot.")
        return

    # 将数据转换为 Pandas Series 以方便排序
    # rates = pd.Series(data).sort_values(ascending=False)
    rates = pd.Series(data)

    configs = rates.index.tolist()
    avg_rates = rates.values.tolist()
    N = len(configs)  # 实验数量

    # --- 动态调整图表宽度 ---
    # 目标：保持每个柱子的视觉宽度和间距不变。
    # 设定每个柱子（含间距）在图表上占据的目标宽度 (单位: inch)
    TARGET_WIDTH_PER_BAR = 1.5  # 每个柱子占据 2.0 英寸，这是视觉上合理的宽度
    MIN_WIDTH = 6.0             # 图表最小宽度
    MAX_WIDTH = 18.0            # 图表最大宽度
    
    # 动态宽度 = (柱子数量 * 每个柱子的目标宽度) + 边距
    dynamic_width = max(MIN_WIDTH, N * TARGET_WIDTH_PER_BAR)
    dynamic_width = min(dynamic_width, MAX_WIDTH)
    
    dynamic_height = 8 # 高度保持不变或根据需要调整

    # --- 美化配置 ---
    cmap = plt.get_cmap('Set3')
    patterns = ["", "///", "", "\\\\"]

    # 格式化配置名称
    formatted_labels = [c.replace("_", "\n") for c in configs]
    
    # 🚨 应用动态尺寸
    plt.style.use("seaborn-v0_8-whitegrid")
    plt.figure(figsize=(dynamic_width, dynamic_height)) 

    # --- 绘制柱状图 ---
    BAR_WIDTH = 0.7 # 柱子的相对宽度保持不变
    bars = plt.bar(formatted_labels, avg_rates, width=BAR_WIDTH)

    # 自动应用颜色和斜线填充
    for i, bar in enumerate(bars):
        # 动态分配颜色
        bar.set_color(cmap(i / N))

        # 循环使用斜线填充图案
        bar.set_hatch(patterns[i % len(patterns)])
        bar.set_edgecolor("gray")

        # 在柱状图顶部添加数值标签
        yval = bar.get_height()
        # 注意：这里的定位是基于轴坐标，与 figsize 无关。
        plt.text(
            bar.get_x() + bar.get_width() / 2.0,
            yval + (max(avg_rates) * 0.015),
            f"{yval/1000:.1f}k",
            ha="center",
            va="bottom",
            fontsize=11,
            fontweight="bold",
        )

    # --- 图形美化 (保持不变) ---
    plt.title(
        "mdtest Directory Stat Rate Comparison (Average of 3 Runs)",
        fontsize=13,
        fontweight="bold",
        pad=20,
    )
    plt.xlabel("Experiment Configuration", fontsize=14)
    plt.ylabel("Average Directory Stat Rate (ops/sec)", fontsize=14)

    # 调整 X 轴标签字体大小和旋转角度
    if N < 8:
        plt.xticks(rotation=0, ha="center", fontsize=12)
    else:
        plt.xticks(rotation=15, ha="right", fontsize=10) 
        
    plt.yticks(fontsize=12)

    ax = plt.gca()
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)

    plt.tight_layout()

    plot_filename = os.path.join(output_dir, "mdtest_summary_comparison.png")
    plt.savefig(plot_filename, dpi=300)
    print(f"\n✅ Comparison plot saved to {plot_filename}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 extract_and_plot_mdtest.py <results_directory>")
        sys.exit(1)

    results_dir = sys.argv[1]

    # logs=[
    #     "/home/lwz/llocks/client/lock/results_20251119_093951/EXP_01_lru_resize=1_lock_reclaim_pol=1_lock_reclaim_batch=512_lock_reclaim_batch_per=1.log",
    #     "/home/lwz/llocks/client/lock/results_20251119_142620/EXP_17_lru_resize=0_lock_reclaim_pol=1_lock_reclaim_batch=0_lock_reclaim_batch_per=5.log",
    #     "/home/lwz/llocks/client/lock/results_20251119_142620/EXP_23_lru_resize=0_lru_max_age=1_lock_reclaim_pol=1_lock_reclaim_batch=0_lock_reclaim_batch_per=5.log",
    #     "/home/lwz/llocks/client/lock/results_20251119_142620/EXP_24_lru_resize=0_lru_max_age=5_lock_reclaim_pol=1_lock_reclaim_batch=0_lock_reclaim_batch_per=5.log",
    #     "/home/lwz/llocks/client/lock/results_20251119_142620/EXP_25_lru_resize=0_lru_max_age=30_lock_reclaim_pol=1_lock_reclaim_batch=0_lock_reclaim_batch_per=5.log",
    # ]
    # logs=[
    #     "/home/lwz/llocks/client/lock/temp/EXP_01_lru_resize=1_1.log",
    #     "/home/lwz/llocks/client/lock/temp/EXP_01_lru_resize=1_2.log",
    #     "/home/lwz/llocks/client/lock/temp/EXP_01_lru_resize=1_3.log",
    #     "/home/lwz/llocks/client/lock/temp/EXP_01_lru_resize=1_4.log",
    # ]
    logs=[
        "/home/lwz/llocks/client/lock/temp1/EXP_01_lru_resize=1.log",
        # "/home/lwz/llocks/client/lock/results_20251119_093951/EXP_01_lru_resize=1_lock_reclaim_pol=1_lock_reclaim_batch=512_lock_reclaim_batch_per=1.log",
        "/home/lwz/llocks/client/lock/temp1/EXP_01_lru_max_age=1.log",
        "/home/lwz/llocks/client/lock/temp1/EXP_01_lru_max_age=3.log",
        "/home/lwz/llocks/client/lock/temp1/EXP_01_lru_max_age=5.log",
        "/home/lwz/llocks/client/lock/temp1/EXP_01_lru_max_age=10.log",
    ]

    # 提取数据
    mdtest_data = extract_mdtest_data(logs)

    # 绘图
    plot_mdtest_comparison4(mdtest_data, results_dir)
