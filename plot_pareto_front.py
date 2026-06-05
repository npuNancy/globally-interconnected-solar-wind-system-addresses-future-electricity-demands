#!/usr/bin/env python3
"""Pareto 前沿可视化脚本。

读取 H5 中的 Pareto 解，可选读取 Sel.mat 中的 preferred solution 元数据，
绘制弃电率 vs 风光渗透率散点图。若提供 Sel.mat，则高亮 preferred solution 并标注约束边界；
否则仅绘制散点图（无最优解标注、无约束边界）。
"""
from __future__ import annotations

import argparse
from pathlib import Path

import h5py
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.ticker import PercentFormatter
from scipy.io import loadmat


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
        has_preferred = False
        sol_idx_python = -1
        base_load_ratio = None
        min_vre_share = None
        max_vre_share = None
        max_curtailment = None

    curtailment = prs[:, 0]
    flexible_ratio = prs[:, 1]
    cost = prs[:, 2]
    vre_share = 1.0 - base_load_ratio - flexible_ratio if base_load_ratio is not None else 1.0 - flexible_ratio

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
    ax.set_xlabel("Solar-wind penetration" if base_load_ratio is not None else "Total coverage (1 - flexible ratio)")
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
