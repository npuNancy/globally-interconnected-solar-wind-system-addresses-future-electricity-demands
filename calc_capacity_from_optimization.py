#!/usr/bin/env python3
"""
从优化结果（.h5）计算风电/光伏装机容量，并与 AR6 参考数据对比。

用法：
    python calc_capacity_from_optimization.py [--source optimization|ssp126]

读取数据：
  - 优化结果 .h5 文件（res_scale 决策向量）
  - NonlConData*.mat 文件（候选格网装机容量）
  - Global_Init_State.mat（当前已装机容量，用作参考）

输出：
  - 每个 Pareto 解的光伏/风电装机容量（GW）
  - Pareto 前沿统计信息
  - 与 AR6 多模型均值参考值的对比
"""

import argparse
import numpy as np
import h5py
import scipy.io as sio
from pathlib import Path


# ── AR6 参考值（5模型均值，单位 GW） ──────────────────────────────────
AR6_REFERENCE = {
    "SSP1-26": {
        2030: {"solar_gw": 1172, "wind_gw": 2358},
        2040: {"solar_gw": 3318, "wind_gw": 4443},
        2050: {"solar_gw": 5799, "wind_gw": 6418},
    },
    "SSP2-45": {
        2030: {"solar_gw": 713, "wind_gw": 1360},
        2040: {"solar_gw": 1608, "wind_gw": 2173},
        2050: {"solar_gw": 2951, "wind_gw": 3232},
    },
    "SSP5-60": {
        2030: {"solar_gw": 378, "wind_gw": 950},
        2040: {"solar_gw": 717, "wind_gw": 1449},
        2050: {"solar_gw": 1317, "wind_gw": 2143},
    },
}

# ── 年份 → 文件映射 ─────────────────────────────────────────────────────
YEAR_CONFIG = {
    2050: {
        "h5_name": "Optimization_SC_2050_Res.h5",
        "nonlcon_name": "NonlConData.mat",
        "label": "2050 S-C（大陆互联）",
    },
    2040: {
        "h5_name": "Optimization_SC_2040_Res.h5",
        "nonlcon_name": "NonlConData2040.mat",
        "label": "2040 S-C（大陆互联）",
    },
    2030: {
        "h5_name": "Optimization_SA_2030_Res.h5",
        "nonlcon_name": "NonlConData2030.mat",
        "label": "2030 S-A（邻近互联）",
    },
}


def calc_capacity_for_year(opt_dir: Path, res_dir: Path, year: int):
    """从某年的优化结果计算光伏/风电装机容量。"""
    cfg = YEAR_CONFIG[year]

    # 加载 NonlConData（候选格网装机容量数据）
    nonlcon_path = opt_dir / cfg["nonlcon_name"]
    if not nonlcon_path.exists():
        print(f"  [警告] {nonlcon_path} 未找到，跳过 {year}")
        return None

    ncd = sio.loadmat(str(nonlcon_path))
    nonlsol = int(ncd["nonlsol"].flatten()[0])      # 光伏候选格网数
    nonlcon_ins = ncd["nonlcon_ins"].flatten()       # 各候选格网装机容量（TWp）
    nonlcon_sel = ncd["nonlcon_sel"].flatten()       # 各候选格网所属区域编号（1-20）
    N = len(nonlcon_ins)

    # 加载 h5 优化结果
    h5_path = res_dir / cfg["h5_name"]
    if not h5_path.exists():
        print(f"  [警告] {h5_path} 未找到，跳过 {year}")
        return None

    with h5py.File(str(h5_path)) as f:
        res_scale = f["res_scale"][:]  # (nvars, n_pareto) — 决策向量矩阵
        prs = f["prs"][:]              # (n_objectives, n_pareto) — 目标函数值矩阵

    n_pareto = res_scale.shape[1]
    n_objectives = prs.shape[0]

    # 逐解计算装机容量
    solar_caps = np.zeros(n_pareto)          # 各解光伏总装机（GW）
    wind_caps = np.zeros(n_pareto)           # 各解风电总装机（GW）
    n_solar_selected = np.zeros(n_pareto, dtype=int)  # 各解选中的光伏格网数
    n_wind_selected = np.zeros(n_pareto, dtype=int)   # 各解选中的风电格网数

    # 各区域装机（用于中位成本解的区域分布分析）
    region_solar = np.zeros((20, n_pareto))
    region_wind = np.zeros((20, n_pareto))

    for i in range(n_pareto):
        site_sel = np.round(res_scale[:N, i]).astype(int)  # 选址决策变量（0/1）

        # 光伏
        solar_sel = site_sel[:nonlsol]
        solar_caps[i] = np.sum(nonlcon_ins[:nonlsol] * solar_sel) * 1000  # TWp → GW
        n_solar_selected[i] = solar_sel.sum()

        # 风电
        wind_sel = site_sel[nonlsol:N]
        wind_caps[i] = np.sum(nonlcon_ins[nonlsol:N] * wind_sel) * 1000  # TWp → GW
        n_wind_selected[i] = wind_sel.sum()

        # 按区域汇总
        for r in range(1, 21):
            sol_mask = (nonlcon_sel[:nonlsol] == r)
            win_mask = (nonlcon_sel[nonlsol:N] == r)
            region_solar[r - 1, i] = np.sum(nonlcon_ins[:nonlsol][sol_mask] * solar_sel[sol_mask]) * 1000
            region_wind[r - 1, i] = np.sum(nonlcon_ins[nonlsol:N][win_mask] * wind_sel[win_mask]) * 1000

    # 找到中位成本解（按成本排序后取中间位置）
    if n_objectives >= 3:
        cost_vals = prs[2, :]
        median_cost_idx = np.argsort(cost_vals)[n_pareto // 2]
    else:
        median_cost_idx = 0

    # 从 Global_Init_State 读取当前已装机容量
    init_path = opt_dir / "Global_Init_State.mat"
    existing = {}
    if init_path.exists():
        init_data = sio.loadmat(str(init_path))
        existing["solar_gw"] = init_data["cur_solar"].flatten().sum() / 1000  # MW → GW
        existing["wind_gw"] = init_data["cur_wind"].flatten().sum() / 1000

    return {
        "year": year,
        "label": cfg["label"],
        "n_pareto": n_pareto,
        "n_objectives": n_objectives,
        "solar_gw": solar_caps,
        "wind_gw": wind_caps,
        "total_gw": solar_caps + wind_caps,
        "n_solar_selected": n_solar_selected,
        "n_wind_selected": n_wind_selected,
        "region_solar": region_solar,
        "region_wind": region_wind,
        "median_cost_idx": median_cost_idx,
        "existing": existing,
        "prs": prs,
    }


def print_results(result: dict):
    """打印某年的装机容量分析结果。"""
    year = result["year"]
    solar = result["solar_gw"]
    wind = result["wind_gw"]
    total = result["total_gw"]
    mid = result["median_cost_idx"]

    print(f"\n{'═' * 70}")
    print(f"  {result['label']}  （{result['n_pareto']} 个 Pareto 解）")
    print(f"{'═' * 70}")

    # 当前已装机容量
    if result["existing"]:
        ex_s = result["existing"]["solar_gw"]
        ex_w = result["existing"]["wind_gw"]
        print(f"\n  当前已装机容量（基准）：")
        print(f"    光伏：{ex_s:>10,.0f} GW")
        print(f"    风电：{ex_w:>10,.0f} GW")
        print(f"    合计：{ex_s + ex_w:>10,.0f} GW")

    # Pareto 前沿统计
    print(f"\n  {'统计量':<20} {'光伏 (GW)':>12} {'风电 (GW)':>12} {'合计 (GW)':>12}")
    print(f"  {'─' * 56}")
    print(f"  {'最小值':<20} {solar.min():>12,.0f} {wind.min():>12,.0f} {total.min():>12,.0f}")
    print(f"  {'25%分位数':<20} {np.percentile(solar, 25):>12,.0f} {np.percentile(wind, 25):>12,.0f} {np.percentile(total, 25):>12,.0f}")
    print(f"  {'中位数':<20} {np.median(solar):>12,.0f} {np.median(wind):>12,.0f} {np.median(total):>12,.0f}")
    print(f"  {'75%分位数':<20} {np.percentile(solar, 75):>12,.0f} {np.percentile(wind, 75):>12,.0f} {np.percentile(total, 75):>12,.0f}")
    print(f"  {'最大值':<20} {solar.max():>12,.0f} {wind.max():>12,.0f} {total.max():>12,.0f}")
    print(f"  {'均值':<20} {solar.mean():>12,.0f} {wind.mean():>12,.0f} {total.mean():>12,.0f}")

    # 中位成本解详情
    print(f"\n  中位成本 Pareto 解（编号 {mid}）：")
    print(f"    光伏：{solar[mid]:>10,.0f} GW  （选中 {result['n_solar_selected'][mid]} 个格网）")
    print(f"    风电：{wind[mid]:>10,.0f} GW  （选中 {result['n_wind_selected'][mid]} 个格网）")
    print(f"    合计：{total[mid]:>10,.0f} GW")
    prs = result["prs"]
    if prs.shape[0] >= 3:
        print(f"    目标函数：弃电率={prs[0, mid]:.4f}, 1-渗透率={prs[1, mid]:.4f}, 成本={prs[2, mid]:,.0f} 十亿美元")

    # AR6 参考值对比
    print(f"\n  AR6 多模型均值参考（{year}年）：")
    for ssp_name, ssp_data in AR6_REFERENCE.items():
        if year in ssp_data:
            ref_s = ssp_data[year]["solar_gw"]
            ref_w = ssp_data[year]["wind_gw"]
            ratio_s = np.median(solar) / ref_s if ref_s > 0 else float("inf")
            ratio_w = np.median(wind) / ref_w if ref_w > 0 else float("inf")
            print(f"    {ssp_name:<10}  光伏：{ref_s:>7,} GW（优化/参考 = {ratio_s:.2f}x）"
                  f"  风电：{ref_w:>7,} GW（优化/参考 = {ratio_w:.2f}x）")


def print_comparison_table(results: list):
    """打印各年份的汇总对比表。"""
    print(f"\n\n{'═' * 70}")
    print(f"  汇总：优化结果 vs AR6 参考值")
    print(f"{'═' * 70}")

    header = f"\n  {'年份':<12} {'来源':<18} {'光伏 (GW)':>12} {'风电 (GW)':>12} {'合计 (GW)':>12}"
    print(header)
    print(f"  {'─' * 66}")

    for res in results:
        if res is None:
            continue
        year = res["year"]
        s_med = np.median(res["solar_gw"])
        w_med = np.median(res["wind_gw"])
        t_med = np.median(res["total_gw"])
        print(f"  {year:<12} {'优化结果':<18} {s_med:>12,.0f} {w_med:>12,.0f} {t_med:>12,.0f}")

        for ssp_name in ["SSP1-26", "SSP2-45", "SSP5-60"]:
            ref = AR6_REFERENCE[ssp_name].get(year)
            if ref:
                print(f"  {'':<12} {ssp_name:<18} {ref['solar_gw']:>12,} {ref['wind_gw']:>12,} {ref['solar_gw']+ref['wind_gw']:>12,}")
        print(f"  {'─' * 66}")


def print_regional_breakdown(result: dict, top_n: int = 5):
    """打印中位成本解的各区域装机分布（前 N 个区域）。"""
    mid = result["median_cost_idx"]
    year = result["year"]
    region_solar = result["region_solar"][:, mid]
    region_wind = result["region_wind"][:, mid]

    print(f"\n  各区域装机分布（中位成本解，{year}年）：")

    # 光伏前 N 个区域
    top_sol_idx = np.argsort(region_solar)[::-1][:top_n]
    print(f"\n    光伏前 {top_n} 个区域：")
    print(f"    {'区域':<10} {'光伏 (GW)':>12}")
    for idx in top_sol_idx:
        print(f"    {idx + 1:<10} {region_solar[idx]:>12,.0f}")

    # 风电前 N 个区域
    top_win_idx = np.argsort(region_wind)[::-1][:top_n]
    print(f"\n    风电前 {top_n} 个区域：")
    print(f"    {'区域':<10} {'风电 (GW)':>12}")
    for idx in top_win_idx:
        print(f"    {idx + 1:<10} {region_wind[idx]:>12,.0f}")


def main():
    parser = argparse.ArgumentParser(description="从优化结果计算风电/光伏装机容量")
    parser.add_argument("--source", choices=["optimization", "ssp126", "ssp245", "ssp560"], default="optimization",
                        help="使用哪个优化目录（默认：optimization）")
    parser.add_argument("--res-dir", type=str, default=None,
                        help="自定义 .h5 结果文件目录（默认：Resilience/）")
    parser.add_argument("--regional", action="store_true",
                        help="同时打印各区域装机分布")
    args = parser.parse_args()

    base_dir = Path(__file__).parent

    source_dir_map = {
        "optimization": "Optimization",
        "ssp126": "Optimization_ssp126",
        "ssp245": "Optimization_ssp245",
        "ssp560": "Optimization_ssp560",
    }
    opt_dir = base_dir / source_dir_map[args.source]

    res_dir = Path(args.res_dir) if args.res_dir else base_dir / "Resilience"

    print(f"优化目录：{opt_dir}")
    print(f"结果目录：{res_dir}")

    results = []
    for year in [2050, 2040, 2030]:
        res = calc_capacity_for_year(opt_dir, res_dir, year)
        if res:
            print_results(res)
            if args.regional:
                print_regional_breakdown(res)
        results.append(res)

    # 过滤空结果
    valid_results = [r for r in results if r is not None]
    if valid_results:
        print_comparison_table(valid_results)

    print(f"\n{'═' * 70}")
    print("  说明：")
    print("  - 优化装机 = 选中格网的最大可安装装机容量（铭牌值）")
    print("  - AR6 参考值 = 综合评估模型的5模型均值")
    print("  - 优化目标为 91% 风光（IEA NZE）；AR6 SSP1-26 目标约 55%")
    print("  - 装机单位：GW（铭牌容量）")
    print(f"{'═' * 70}")


if __name__ == "__main__":
    main()
