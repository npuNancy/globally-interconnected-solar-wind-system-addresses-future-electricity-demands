#!/usr/bin/env python3
"""单目标优化最优解指标可视化。

读取 H5 中的最优解指标（/metrics）和成本分解（/cost_breakdown），
绘制关键指标摘要与年度成本分解条形图。

用法:
    python plot_pareto_front.py --scenario SSP2-4.5 --year 2050 \
        --h5 Optimization_ssp245/results/Optimization_SC_2050_Res.h5 \
        --output output/ssp245_2050_metrics.png
"""
from __future__ import annotations

import argparse
from pathlib import Path

import h5py
import matplotlib.pyplot as plt
import numpy as np

# 各情景/年份的约束参数（与 optimization_config.m 保持同步）
# (scenario, year) -> (base_load_ratio, min_vre_share, max_vre_share, max_curtailment)
CONFIG_LOOKUP: dict[tuple[str, int], tuple[float, float | None, float, float]] = {
    ("SSP1-2.6", 2050): (0.239, 0.5544, 0.7111, 0.15),
    ("SSP1-2.6", 2040): (0.375, 0.4308, 0.6823, 0.15),
    ("SSP1-2.6", 2030): (0.558, 0.2635, 0.5789, 0.15),
    ("SSP2-4.5", 2050): (0.518, 0.2871, 0.4646, 0.15),
    ("SSP2-4.5", 2040): (0.639, 0.2091, 0.3572, 0.15),
    ("SSP2-4.5", 2030): (0.717, 0.1417, 0.2579, 0.15),
    ("SSP5-6.0", 2050): (0.642, None,   0.1420, 0.15),
    ("SSP5-6.0", 2040): (0.747, None,   0.1173, 0.15),
    ("SSP5-6.0", 2030): (0.788, None,   0.0890, 0.15),
}

# 年度成本分解项 (索引, 标签, 颜色)
# 索引对应 Optimization_SC_2050.m 中 cost_bd_vec 的位置
ANNUAL_ITEMS = [
    (2,  "Annualized VRE CAPEX",             "#4C72B0"),
    (5,  "Annualized Storage CAPEX",         "#55A868"),
    (8,  "Annualized Transmission CAPEX",    "#C44E52"),
    (9,  "VRE O&M",                          "#8172B2"),
    (10, "Storage O&M",                      "#CCB974"),
    (11, "Transmission O&M",                 "#64B5CD"),
    (12, "Flexible Generation OPEX",         "#D65F5F"),
]


def load_optimal_metrics(h5_path: Path) -> tuple[dict, np.ndarray | None]:
    """从 H5 文件读取最优解指标和成本分解。"""
    with h5py.File(h5_path, "r") as f:
        if "metrics" in f:
            m = np.asarray(f["metrics"]).squeeze()
            metrics = {
                "curtailment_rate": float(m[0]),
                "flexible_ratio": float(m[1]),
                "vre_share": float(m[2]) if len(m) > 2 else None,
                "total_annual_cost": float(m[3]) if len(m) > 3 else float(m[-1]),
            }
        elif "prs" in f:
            prs = np.asarray(f["prs"]).squeeze()
            metrics = {
                "curtailment_rate": float(prs[0]),
                "flexible_ratio": float(prs[1]),
                "vre_share": None,
                "total_annual_cost": float(prs[2]) if len(prs) > 2 else 0.0,
            }
        else:
            raise ValueError(f"H5 文件缺少 /metrics 或 /prs: {h5_path}")

        cost_breakdown = None
        if "cost_breakdown" in f:
            cost_breakdown = np.asarray(f["cost_breakdown"]).squeeze()

    return metrics, cost_breakdown


def _status(value: float | None, bound: float | None, cmp: str) -> str:
    """约束满足状态标记。"""
    if value is None or bound is None:
        return ""
    ok = (value >= bound) if cmp == ">=" else (value <= bound)
    return "  OK" if ok else "  VIOLATED"


def main() -> None:
    parser = argparse.ArgumentParser(description="单目标优化最优解指标可视化")
    parser.add_argument("--scenario", required=True)
    parser.add_argument("--year", type=int, required=True)
    parser.add_argument("--h5", type=Path, required=True, help="优化结果 H5 文件路径")
    parser.add_argument("--sel-mat", type=Path, required=False, help="(保留兼容，未使用)")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    metrics, cost_breakdown = load_optimal_metrics(args.h5)

    key = (args.scenario, args.year)
    _, min_vre, max_vre, max_cur = CONFIG_LOOKUP.get(key, (None, None, None, None))

    args.output.parent.mkdir(parents=True, exist_ok=True)

    cr = metrics["curtailment_rate"]
    fr = metrics["flexible_ratio"]
    vs = metrics["vre_share"]
    tc = metrics["total_annual_cost"]

    has_breakdown = cost_breakdown is not None and len(cost_breakdown) >= 13

    # ── 创建画布 ──
    if has_breakdown:
        fig, (ax_info, ax_bar) = plt.subplots(
            1, 2, figsize=(15, 5), gridspec_kw={"width_ratios": [1, 1.6]}
        )
    else:
        fig, ax_info = plt.subplots(1, 1, figsize=(8, 5))
        ax_bar = None

    # ── 左侧: 指标摘要 ──
    ax_info.axis("off")

    lines = [
        f"Scenario: {args.scenario}    Year: {args.year}",
        "",
        f"  Curtailment Rate       {cr:>8.2%}{_status(cr, max_cur, '<=')}",
        f"  Flexible Gen Ratio     {fr:>8.2%}",
    ]
    if vs is not None and vs > 0:
        lines.append(f"  VRE Penetration        {vs:>8.2%}")
        if min_vre is not None:
            lines.append(
                f"    Lower Bound          {min_vre:>8.2%}{_status(vs, min_vre, '>=')}"
            )
        if max_vre is not None:
            lines.append(
                f"    Upper Bound          {max_vre:>8.2%}{_status(vs, max_vre, '<=')}"
            )
    lines.append("")
    lines.append(f"  Total Annual Cost  {tc:>10.1f} B USD/yr")

    ax_info.text(
        0.05, 0.95, "\n".join(lines),
        transform=ax_info.transAxes, fontsize=11, fontfamily="monospace",
        verticalalignment="top",
        bbox=dict(boxstyle="round,pad=0.6", facecolor="#fffff0", edgecolor="#ccc", alpha=0.9),
    )
    ax_info.set_title(
        f"Optimal Solution — {args.scenario} ({args.year})", fontsize=14, pad=12
    )

    # ── 右侧: 年度成本分解条形图 ──
    if ax_bar is not None:
        indices, labels, colors = zip(*ANNUAL_ITEMS)
        values = np.array([cost_breakdown[i] for i in indices])

        nonzero = values > 0
        vals = values[nonzero]
        labs = [l for l, n in zip(labels, nonzero) if n]
        cols = [c for c, n in zip(colors, nonzero) if n]

        if len(vals) == 0:
            vals, labs, cols = values, list(labels), list(colors)

        y_pos = np.arange(len(vals))
        bars = ax_bar.barh(y_pos, vals, color=cols, edgecolor="white", height=0.55)
        ax_bar.set_yticks(y_pos)
        ax_bar.set_yticklabels(labs, fontsize=10)
        ax_bar.set_xlabel("Billion USD / year", fontsize=11)
        ax_bar.invert_yaxis()
        ax_bar.grid(axis="x", alpha=0.25)

        x_max = max(vals) if len(vals) > 0 else 1
        for bar, val in zip(bars, vals):
            ax_bar.text(
                bar.get_width() + x_max * 0.02,
                bar.get_y() + bar.get_height() / 2,
                f"{val:.1f}",
                va="center", fontsize=9,
            )
        ax_bar.set_title("Annual Cost Breakdown", fontsize=13, pad=10)

    fig.tight_layout()
    fig.savefig(args.output, dpi=220)
    plt.close(fig)


if __name__ == "__main__":
    main()
