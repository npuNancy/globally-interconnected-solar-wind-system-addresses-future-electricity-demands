#!/usr/bin/env python3
"""Pareto 前沿可视化脚本。

读取 H5 中的 Pareto 解，可选读取 Sel.mat 中的 preferred solution 元数据，
绘制弃电率 vs 风光渗透率散点图。若提供 Sel.mat，则高亮 preferred solution 并标注约束边界；
否则从 CONFIG_LOOKUP 获取约束参数（仍绘制约束边界，但不标注最优解）。
"""
from __future__ import annotations

import argparse
from pathlib import Path

import h5py
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.ticker import PercentFormatter
from scipy.io import loadmat

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


def load_prs(h5_path: Path) -> np.ndarray:
    with h5py.File(h5_path, "r") as f:
        prs = np.asarray(f["prs"])

    if prs.ndim != 2:
        raise ValueError(f"/prs 必须是二维矩阵，实际 shape={prs.shape}")

    if prs.shape[1] == 3:
        return prs

    if prs.shape[0] == 3:
        return prs.T

    raise ValueError(f"无法识别 /prs 的形状：{prs.shape}")


def scalar_from_mat(mat: dict, key: str) -> float:
    if key not in mat:
        raise KeyError(f"Sel.mat 缺少字段：{key}")
    return float(np.asarray(mat[key]).squeeze())


def optional_scalar_from_mat(mat: dict, key: str) -> float | None:
    value = scalar_from_mat(mat, key)
    if np.isnan(value):
        return None
    return value


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scenario", required=True)
    parser.add_argument("--year", type=int, required=True)
    parser.add_argument("--h5", type=Path, required=True)
    parser.add_argument("--sel-mat", type=Path, required=False)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    prs = load_prs(args.h5)

    if args.sel_mat is not None:
        mat = loadmat(args.sel_mat)

        sol_idx_matlab = int(round(scalar_from_mat(mat, "preferred_sol_idx")))
        has_preferred = sol_idx_matlab > 0
        sol_idx_python = sol_idx_matlab - 1 if has_preferred else -1

        base_load_ratio = scalar_from_mat(mat, "preferred_base_load_ratio")
        min_vre_share = optional_scalar_from_mat(mat, "preferred_min_vre_share")
        max_vre_share = scalar_from_mat(mat, "preferred_max_vre_share")
        max_curtailment = scalar_from_mat(mat, "preferred_max_curtailment")
    else:
        key = (args.scenario, args.year)
        if key not in CONFIG_LOOKUP:
            raise ValueError(f"未知情景/年份组合：{key}，请提供 --sel-mat")

        base_load_ratio, min_vre_share, max_vre_share, max_curtailment = CONFIG_LOOKUP[key]
        has_preferred = False
        sol_idx_python = -1

    curtailment = prs[:, 0]
    flexible_ratio = prs[:, 1]
    cost = prs[:, 2]
    vre_share = 1.0 - base_load_ratio - flexible_ratio

    args.output.parent.mkdir(parents=True, exist_ok=True)

    fig, ax = plt.subplots(figsize=(8, 6))

    scatter = ax.scatter(
        vre_share,
        curtailment,
        c=cost,
        s=28,
        alpha=0.8,
    )

    if has_preferred:
        ax.scatter(
            [vre_share[sol_idx_python]],
            [curtailment[sol_idx_python]],
            marker="*",
            s=260,
            edgecolors="black",
            linewidths=1.2,
            label=f"Preferred solution #{sol_idx_matlab}",
            zorder=5,
        )

    if min_vre_share is not None:
        ax.axvline(
            min_vre_share,
            linestyle="--",
            linewidth=1.2,
            label=f"VRE lower bound: {min_vre_share:.1%}",
        )

    if max_vre_share is not None:
        ax.axvline(
            max_vre_share,
            linestyle="--",
            linewidth=1.2,
            label=f"VRE upper bound: {max_vre_share:.1%}",
        )

    if max_curtailment is not None:
        ax.axhline(
            max_curtailment,
            linestyle="--",
            linewidth=1.2,
            label=f"Curtailment upper bound: {max_curtailment:.1%}",
        )

    title_suffix = "" if has_preferred else " (no qualified solution)"
    ax.set_title(f"{args.scenario} Pareto Front ({args.year}){title_suffix}")
    ax.set_xlabel("Solar-wind penetration")
    ax.set_ylabel("Curtailment rate")
    ax.xaxis.set_major_formatter(PercentFormatter(1.0))
    ax.yaxis.set_major_formatter(PercentFormatter(1.0))
    ax.grid(True, alpha=0.25)
    ax.legend(loc="best")

    colorbar = fig.colorbar(scatter, ax=ax)
    colorbar.set_label("System cost (billion USD)")

    fig.tight_layout()
    fig.savefig(args.output, dpi=220)
    plt.close(fig)


if __name__ == "__main__":
    main()
