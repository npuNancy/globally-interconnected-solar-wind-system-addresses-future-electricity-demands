#!/usr/bin/env python3
"""plot_hourly_energy_output.py — 逐小时能源出力可视化（风光合并版）

生成两张图：
  图 A：发电侧原始出力（原始风光发电量 + 负荷曲线）
  图 B：负荷侧实际供电结构（实际风光 + 储能放电 + 基荷 + 灵活电源 + 负荷曲线）

用法：
  python plot_hourly_energy_output.py \\
    --ssp ssp245 \\
    --year 2050 \\
    --input Optimization_ssp245/results/hourly/hourly_dispatch_2050.csv \\
    --output-dir Optimization_ssp245/results/img/hourly
"""

import argparse
import os
import sys

import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import numpy as np
import pandas as pd


def load_data(csv_path: str) -> pd.DataFrame:
    df = pd.read_csv(csv_path)
    required = [
        "hour", "load_twh", "raw_vre_twh", "actual_vre_twh",
        "storage_discharge_twh", "base_twh", "flexible_twh",
        "curtailment_twh", "storage_charge_twh",
    ]
    for col in required:
        if col not in df.columns:
            sys.exit(f"CSV 缺少必要列: {col}")
    return df


def check_energy_balance(df: pd.DataFrame) -> None:
    supply = (
        df["actual_vre_twh"]
        + df["storage_discharge_twh"]
        + df["base_twh"]
        + df["flexible_twh"]
    )
    error = supply - df["load_twh"]
    max_err = error.abs().max()
    mean_err = error.abs().mean()
    print(f"能量平衡校验: max_abs_error={max_err:.2e}, mean_abs_error={mean_err:.2e}")
    if max_err > 1e-6:
        print(f"  ⚠ 警告: 能量平衡最大偏差 {max_err:.2e} 超过 1e-6 TWh")


def check_annual_totals(df: pd.DataFrame) -> None:
    print("\n年度总量:")
    print(f"  sum(load_twh)        = {df['load_twh'].sum():.6f}")
    print(f"  sum(raw_vre_twh)     = {df['raw_vre_twh'].sum():.6f}")
    print(f"  sum(actual_vre_twh)  = {df['actual_vre_twh'].sum():.6f}")
    print(f"  sum(base_twh)        = {df['base_twh'].sum():.6f}")
    print(f"  sum(flexible_twh)    = {df['flexible_twh'].sum():.6f}")
    print(f"  sum(curtailment_twh) = {df['curtailment_twh'].sum():.6f}")
    print(f"  sum(storage_discharge)= {df['storage_discharge_twh'].sum():.6f}")
    print(f"  sum(storage_charge)  = {df['storage_charge_twh'].sum():.6f}")
    net_storage = df["storage_discharge_twh"].sum() - df["storage_charge_twh"].sum()
    print(f"  净储能放电           = {net_storage:.6f}")


def plot_figure_a(
    df: pd.DataFrame, x: np.ndarray, title_suffix: str
) -> plt.Figure:
    fig, ax = plt.subplots(figsize=(14, 4.5))

    ax.fill_between(
        x, 0, df["raw_vre_twh"].values, alpha=0.75, label="Raw VRE generation", color="#2ca02c"
    )
    ax.plot(x, df["load_twh"].values, label="Load", linewidth=1.0, color="#d62728")

    ax.set_xlabel("Hour of year")
    ax.set_ylabel("Electricity (TWh/h)")
    ax.set_title(f"Figure A. Generation-side raw hourly VRE output  ({title_suffix})")
    ax.legend(loc="upper right")
    ax.set_xlim(x[0], x[-1])
    ax.yaxis.set_major_formatter(ticker.FormatStrFormatter("%.2f"))
    fig.tight_layout()
    return fig


def plot_figure_b(
    df: pd.DataFrame, x: np.ndarray, title_suffix: str
) -> plt.Figure:
    fig, ax = plt.subplots(figsize=(14, 4.5))

    stack = [
        df["actual_vre_twh"].values,
        df["storage_discharge_twh"].values,
        df["base_twh"].values,
        df["flexible_twh"].values,
    ]
    labels = [
        "Actual VRE generation",
        "Storage discharge",
        "Baseload",
        "Flexible generation",
    ]
    colors = ["#2ca02c", "#1f77b4", "#ff7f0e", "#9467bd"]

    ax.stackplot(x, stack, labels=labels, colors=colors, alpha=0.85)
    ax.plot(
        x, df["load_twh"].values, label="Load", linewidth=1.0, color="#d62728"
    )

    ax.set_xlabel("Hour of year")
    ax.set_ylabel("Electricity (TWh/h)")
    ax.set_title(f"Figure B. Load-side actual hourly supply structure  ({title_suffix})")
    ax.legend(loc="upper right")
    ax.set_xlim(x[0], x[-1])
    ax.yaxis.set_major_formatter(ticker.FormatStrFormatter("%.2f"))
    fig.tight_layout()
    return fig


def main():
    parser = argparse.ArgumentParser(description="逐小时能源出力可视化")
    parser.add_argument("--ssp", required=True, help="SSP scenario, e.g. ssp245")
    parser.add_argument("--year", required=True, type=int, help="Year, e.g. 2050")
    parser.add_argument("--input", required=True, help="Path to hourly_dispatch CSV")
    parser.add_argument(
        "--output-dir", required=True, help="Directory for output images"
    )
    args = parser.parse_args()

    df = load_data(args.input)
    print(f"已加载 {len(df)} 行数据 ({args.ssp} {args.year})")

    check_energy_balance(df)
    check_annual_totals(df)

    os.makedirs(args.output_dir, exist_ok=True)

    ssp_year = f"{args.ssp.upper()} {args.year}"

    # --- full year ---
    x_full = df["hour"].values
    fig_a = plot_figure_a(df, x_full, f"{ssp_year} — full year")
    path_a = os.path.join(
        args.output_dir,
        f"hourly_energy_A_generation_side_{args.year}_full_year.png",
    )
    fig_a.savefig(path_a, dpi=200)
    print(f"\n已保存: {path_a}")
    plt.close(fig_a)

    fig_b = plot_figure_b(df, x_full, f"{ssp_year} — full year")
    path_b = os.path.join(
        args.output_dir,
        f"hourly_energy_B_load_side_{args.year}_full_year.png",
    )
    fig_b.savefig(path_b, dpi=200)
    print(f"已保存: {path_b}")
    plt.close(fig_b)

    # --- first month ---
    df_jan = df[df["month"] == 1].copy()
    if len(df_jan) > 0:
        x_jan = df_jan["hour"].values
        fig_a_jan = plot_figure_a(df_jan, x_jan, f"{ssp_year} — January")
        path_a_jan = os.path.join(
            args.output_dir,
            f"hourly_energy_A_generation_side_{args.year}_first_month.png",
        )
        fig_a_jan.savefig(path_a_jan, dpi=200)
        print(f"已保存: {path_a_jan}")
        plt.close(fig_a_jan)

        fig_b_jan = plot_figure_b(df_jan, x_jan, f"{ssp_year} — January")
        path_b_jan = os.path.join(
            args.output_dir,
            f"hourly_energy_B_load_side_{args.year}_first_month.png",
        )
        fig_b_jan.savefig(path_b_jan, dpi=200)
        print(f"已保存: {path_b_jan}")
        plt.close(fig_b_jan)

    # --- sample week (days 183-189, early July) ---
    week_days = range(183, 190)
    df_week = df[df["day_of_year"].isin(week_days)].copy()
    if len(df_week) > 0:
        x_week = df_week["hour"].values
        fig_a_w = plot_figure_a(df_week, x_week, f"{ssp_year} — sample week (Jul)")
        path_a_w = os.path.join(
            args.output_dir,
            f"hourly_energy_A_generation_side_{args.year}_sample_week.png",
        )
        fig_a_w.savefig(path_a_w, dpi=200)
        print(f"已保存: {path_a_w}")
        plt.close(fig_a_w)

        fig_b_w = plot_figure_b(df_week, x_week, f"{ssp_year} — sample week (Jul)")
        path_b_w = os.path.join(
            args.output_dir,
            f"hourly_energy_B_load_side_{args.year}_sample_week.png",
        )
        fig_b_w.savefig(path_b_w, dpi=200)
        print(f"已保存: {path_b_w}")
        plt.close(fig_b_w)

    print("\n全部图形输出完成。")


if __name__ == "__main__":
    main()
