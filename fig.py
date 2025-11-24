"""
Author: Outsider
Date: 2025-11-13 10:05:11
LastEditors: Outsider
LastEditTime: 2025-11-13 10:34:14
Description: In User Settings Edit
FilePath: /llocks/client/lock/draw.py
"""
import sys
import pandas as pd
import matplotlib.pyplot as plt

param = sys.argv[1]

# === 参数设置 ===
file1 = sys.argv[2]
file2 = sys.argv[3]

# === 读取数据 ===
df1 = pd.read_csv(file1, delim_whitespace=True)
df2 = pd.read_csv(file2, delim_whitespace=True)

# === 将 timestamp 转为时间格式（如果是秒数，可跳过） ===
# 如果你的 timestamp 是UNIX时间戳（数字），取消下一行注释：
df1["timestamp"] = pd.to_datetime(df1["timestamp"], unit="s")
df2["timestamp"] = pd.to_datetime(df2["timestamp"], unit="s")

# 否则，如果是字符串时间戳（如 '2025-11-13 10:00:00'），保持默认读取即可

# === 按时间合并两个表 ===
df = pd.merge(df1, df2, on="timestamp", how="inner").sort_values("timestamp")

# === 在此修改要绘制的区间 ===
start_time = pd.to_datetime("2025-11-14 02:25:00")  # 可换成 df["timestamp"].iloc[100]
end_time = pd.to_datetime("2025-11-14 02:26:45")

# 或者如果你希望直接用数值时间戳（例如 1762687055）：
# start_time = pd.to_datetime(1762687055, unit='s')
# end_time   = pd.to_datetime(1762687058, unit='s')

# === 过滤指定时间区间的数据 ===
# df = df[(df["timestamp"] >= start_time) & (df["timestamp"] <= end_time)]

# === 绘图 ===
plt.figure(figsize=(10, 6))
if "lock_granted" in df.columns:
    plt.plot(
        df["timestamp"],
        df["lock_granted"],
        label="lock_granted",
        linewidth=2,
        marker="x",
    )
    # plt.scatter(df["timestamp"], df["lock_granted"], s=30, label="lock_granted (points)")
if "lock_cancel" in df.columns:
    plt.plot(df["timestamp"], df["lock_cancel"], label="lock_cancel", linewidth=2)
    # plt.scatter(df["timestamp"], df["lock_cancel"], s=30, label="lock_cancel (points)")
# if "ldlm_cancel" in df.columns:
#     plt.plot(df["timestamp"], df["ldlm_cancel"], label="cli_cancel", linewidth=2)
    # plt.scatter(df["timestamp"], df["ldlm_cancel"], s=30, label="ldlm_cancel (points)")
# if "lock_count" in df.columns:
#     plt.plot(df["timestamp"], df["lock_count"], label="cli_lock_count", linewidth=2)
# if "lock_unused" in df.columns:
#     plt.plot(df["timestamp"], df["lock_unused"], label="cli_lock_unused", linewidth=2)
# if "pool_granted" in df.columns:
#     plt.plot(df["timestamp"], df["pool_granted"], label="pool_granted", linewidth=2)
    # plt.scatter(df["timestamp"], df["pool_granted"], s=30, label="pool_granted (points)")
if "pool_limit" in df.columns:
    plt.plot(df["timestamp"], df["pool_limit"], label="pool_limit", linewidth=2)
    # plt.scatter(df["timestamp"], df["pool_limit"], s=30, label="pool_limit (points)")


# === 添加水平参考线 ===
# ref_value = 431256
ref_value = 634200
plt.axhline(y=ref_value, color='r', linestyle='--', linewidth=2,
            label=f"threshold")

# === 图形美化 ===
plt.title(f"Figure {param}", fontsize=16)
plt.xlabel("time", fontsize=14)
plt.ylabel("locks", fontsize=14)
plt.legend(fontsize=12)
plt.grid(True)
plt.tight_layout()
plt.savefig(f"figure_{param}.png", dpi=300)
