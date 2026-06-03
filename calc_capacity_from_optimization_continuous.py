#!/usr/bin/env python3
"""
从 .mat 选择文件计算风电/光伏装机容量（连续容量版），并与 AR6 参考数据对比。

与二值版本的区别：
  - opt_solar / opt_wind 为连续分数（0~1），而非二值（0/1）
  - 容量计算 = 最大可安装容量 × 开发比例分数
  - 新增部分开发（partial）格网统计

用法：
    python calc_capacity_from_optimization_continuous.py [--source continuous|optimization|ssp126|ssp245|ssp560] [--regional]

读取数据：
  - Opt_*_Sel.mat 文件（opt_solar_frac/opt_wind_frac 或 opt_solar/opt_wind 空间布局）
  - 原始数据文件（构建装机容量栅格）
  - Global_Grid_Division.mat（区域划分）
  - Global_Init_State.mat（当前已装机容量，用作参考）

输出：
  - 选中解的光伏/风电实际装机容量（GW）= 最大容量 × 开发比例
  - 开发比例统计（active / partial / full 格网数）
  - 与 AR6 多模型均值参考值的对比
"""

import argparse
import os
import numpy as np
import scipy.io as sio
from pathlib import Path

# ── 阈值：视为"已开发"的最小分数 ────────────────────────────────────
EPS_ACTIVE = 1e-6

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

# ── 年份 → .mat 选择文件名模式 ──────────────────────────────────────
SEL_PATTERNS = {
    2050: ["Opt_SG_2050_Sel.mat", "Opt_SC_2050_Sel.mat"],
    2040: ["Opt_SC_2040_Sel.mat"],
    2030: ["Opt_SA_2030_Sel.mat"],
}

YEAR_LABELS = {
    2050: "2050 S-C（大陆互联）",
    2040: "2040 S-C（大陆互联）",
    2030: "2030 S-A（邻近互联）",
}


def _find_file(directory, patterns):
    """按优先级在 directory 中查找文件。"""
    for p in patterns:
        path = os.path.join(directory, p)
        if os.path.exists(path):
            return path
    return None


def _build_capacity_grids(opt_dir):
    """构建 180×360 光伏/风电最大可安装装机容量栅格（GW）。

    容量 = 安装密度(MW/km²) × 可用面积比例 × 格网面积(km²) / 1000
    """
    solar_luccs = sio.loadmat(os.path.join(opt_dir, "Global_Solar_Net_Area_Add_Egrid.mat"))["data"] / 100.0
    solar_area = sio.loadmat(os.path.join(opt_dir, "Global_Solar_Fishnet_Area.mat"))["data"].astype(float)
    solar_cap = 74 * solar_luccs * solar_area / 1000

    wind_luccs = sio.loadmat(os.path.join(opt_dir, "Global_Wind_Net_Area_Add_Egrid.mat"))["data"] / 100.0
    wind_area = sio.loadmat(os.path.join(opt_dir, "Global_Wind_Fishnet_Area.mat"))["data"]
    landmask = sio.loadmat(os.path.join(opt_dir, "Global_LandMask.mat"))["data"]
    density = np.where(landmask > 100, 4.6, 2.7)
    wind_cap = density * wind_luccs * wind_area / 1000

    return solar_cap, wind_cap


def _load_fraction(mat, key_primary, key_fallback):
    """从 mat 字典中加载分数数组，优先使用 key_primary，不存在时回退到 key_fallback。"""
    if key_primary in mat:
        return np.asarray(mat[key_primary], dtype=float)
    return np.asarray(mat[key_fallback], dtype=float)


def _frac_stats(frac, label):
    """计算分数数组的 active / partial / full 统计。"""
    active_mask = frac > EPS_ACTIVE
    n_active = int(np.count_nonzero(active_mask))
    n_partial = int(np.count_nonzero(active_mask & (frac < 1 - EPS_ACTIVE)))
    n_full = int(np.count_nonzero(frac >= 1 - EPS_ACTIVE))
    mean_frac = float(np.mean(frac[active_mask])) if n_active > 0 else 0.0
    median_frac = float(np.median(frac[active_mask])) if n_active > 0 else 0.0
    return {
        f"n_{label}_active": n_active,
        f"n_{label}_partial": n_partial,
        f"n_{label}_full": n_full,
        f"{label}_mean_frac": mean_frac,
        f"{label}_median_frac": median_frac,
    }


def calc_capacity_for_year(opt_dir, res_dir, year, source="continuous"):
    """从 .mat 选择文件计算某年的光伏/风电实际装机容量（连续分数版）。"""
    label = YEAR_LABELS[year]
    if source in ("optimization", "continuous") and year == 2050:
        label = "2050 S-G（全球互联）"

    # 加载 .mat 选择文件
    mat_path = _find_file(res_dir, SEL_PATTERNS[year])
    if mat_path is None:
        raise FileNotFoundError(
            f"未找到 {year} 年的选择文件，期望：{SEL_PATTERNS[year]}（目录：{res_dir}）"
        )

    mat = sio.loadmat(mat_path)

    # 优先读取 opt_solar_frac / opt_wind_frac（连续版 convert 脚本保存的键名），
    # 回退到 opt_solar / opt_wind（兼容旧版 mat 文件）
    opt_solar_frac = _load_fraction(mat, "opt_solar_frac", "opt_solar")
    opt_wind_frac = _load_fraction(mat, "opt_wind_frac", "opt_wind")

    # 构建最大可安装容量栅格
    solar_cap, wind_cap = _build_capacity_grids(str(opt_dir))

    # 计算实际装机 = 最大容量 × 开发比例分数
    solar_gw = float(np.sum(solar_cap * opt_solar_frac))
    wind_gw = float(np.sum(wind_cap * opt_wind_frac))

    # 分数统计
    solar_stats = _frac_stats(opt_solar_frac, "solar")
    wind_stats = _frac_stats(opt_wind_frac, "wind")

    # 按区域汇总（分数 × 容量）
    grid_div_path = os.path.join(str(opt_dir), "Global_Grid_Division.mat")
    region_solar = np.zeros(20)
    region_wind = np.zeros(20)
    if os.path.exists(grid_div_path):
        grid_div = sio.loadmat(grid_div_path)["data"]
        for r in range(1, 21):
            mask = grid_div == r
            region_solar[r - 1] = float(np.sum(solar_cap * opt_solar_frac * mask))
            region_wind[r - 1] = float(np.sum(wind_cap * opt_wind_frac * mask))

    # 从 Global_Init_State 读取当前已装机容量
    init_path = os.path.join(str(opt_dir), "Global_Init_State.mat")
    existing = {}
    if os.path.exists(init_path):
        init_data = sio.loadmat(init_path)
        existing["solar_gw"] = float(init_data["cur_solar"].flatten().sum() / 1000)  # MW → GW
        existing["wind_gw"] = float(init_data["cur_wind"].flatten().sum() / 1000)

    return {
        "year": year,
        "label": label,
        "solar_gw": solar_gw,
        "wind_gw": wind_gw,
        "total_gw": solar_gw + wind_gw,
        "region_solar": region_solar,
        "region_wind": region_wind,
        "existing": existing,
        **solar_stats,
        **wind_stats,
    }


def print_results(result):
    """打印某年的装机容量分析结果（连续版）。"""
    year = result["year"]
    solar = result["solar_gw"]
    wind = result["wind_gw"]
    total = result["total_gw"]

    print(f"\n{'═' * 70}")
    print(f"  {result['label']}（连续容量版）")
    print(f"{'═' * 70}")

    # 当前已装机容量
    if result["existing"]:
        ex_s = result["existing"]["solar_gw"]
        ex_w = result["existing"]["wind_gw"]
        print(f"\n  当前已装机容量（基准）：")
        print(f"    光伏：{ex_s:>10,.0f} GW")
        print(f"    风电：{ex_w:>10,.0f} GW")
        print(f"    合计：{ex_s + ex_w:>10,.0f} GW")

    # 选中解装机容量
    print(f"\n  优化实际装机容量（= 最大容量 × 开发比例）：")
    print(f"    光伏：{solar:>10,.0f} GW")
    print(f"    风电：{wind:>10,.0f} GW")
    print(f"    合计：{total:>10,.0f} GW")

    # 开发比例统计
    print(f"\n  开发比例统计：")
    print(f"    {'':12s}  {'Active':>8s}  {'Partial':>8s}  {'Full':>8s}  {'Mean Frac':>10s}  {'Median Frac':>12s}")
    print(f"    {'光伏':<12s}  {result['n_solar_active']:>8d}  {result['n_solar_partial']:>8d}  {result['n_solar_full']:>8d}"
          f"  {result['solar_mean_frac']:>10.4f}  {result['solar_median_frac']:>12.4f}")
    print(f"    {'风电':<12s}  {result['n_wind_active']:>8d}  {result['n_wind_partial']:>8d}  {result['n_wind_full']:>8d}"
          f"  {result['wind_mean_frac']:>10.4f}  {result['wind_median_frac']:>12.4f}")

    # AR6 参考值对比
    print(f"\n  AR6 多模型均值参考（{year}年）：")
    print(
        f"    {'SSP':<10}  {'光伏 (GW)':>10} {'优化/AR6':>9}  {'风电 (GW)':>10} {'优化/AR6':>9}"
    )
    for ssp_name, ssp_data in AR6_REFERENCE.items():
        if year in ssp_data:
            ref_s = ssp_data[year]["solar_gw"]
            ref_w = ssp_data[year]["wind_gw"]
            ratio_s = solar / ref_s if ref_s > 0 else float("inf")
            ratio_w = wind / ref_w if ref_w > 0 else float("inf")
            print(
                f"    {ssp_name:<10}  {ref_s:>10,} {ratio_s:>8.2f}x"
                f"  {ref_w:>10,} {ratio_w:>8.2f}x"
            )


def print_comparison_table(results):
    """打印各年份的汇总对比表。"""
    print(f"\n\n{'═' * 70}")
    print(f"  汇总：优化结果 vs AR6 参考值（连续容量版）")
    print(f"{'═' * 70}")

    header = f"\n  {'年份':<12} {'来源':<18} {'光伏 (GW)':>12} {'风电 (GW)':>12} {'合计 (GW)':>12}"
    print(header)
    print(f"  {'─' * 66}")

    for res in results:
        if res is None:
            continue
        year = res["year"]
        print(
            f"  {year:<12} {'优化（连续）':<18}"
            f" {res['solar_gw']:>12,.0f} {res['wind_gw']:>12,.0f} {res['total_gw']:>12,.0f}"
        )
        for ssp_name in ["SSP1-26", "SSP2-45", "SSP5-60"]:
            ref = AR6_REFERENCE[ssp_name].get(year)
            if ref:
                print(
                    f"  {'':<12} {ssp_name:<18}"
                    f" {ref['solar_gw']:>12,} {ref['wind_gw']:>12,}"
                    f" {ref['solar_gw'] + ref['wind_gw']:>12,}"
                )
        print(f"  {'─' * 66}")


def print_regional_breakdown(result, top_n=5):
    """打印各区域装机分布（前 N 个区域，使用分数×容量）。"""
    year = result["year"]
    region_solar = result["region_solar"]
    region_wind = result["region_wind"]

    print(f"\n  各区域装机分布（{year}年，连续容量）：")

    top_sol_idx = np.argsort(region_solar)[::-1][:top_n]
    print(f"\n    光伏前 {top_n} 个区域：")
    print(f"    {'区域':<10} {'光伏 (GW)':>12}")
    for idx in top_sol_idx:
        print(f"    {idx + 1:<10} {region_solar[idx]:>12,.0f}")

    top_win_idx = np.argsort(region_wind)[::-1][:top_n]
    print(f"\n    风电前 {top_n} 个区域：")
    print(f"    {'区域':<10} {'风电 (GW)':>12}")
    for idx in top_win_idx:
        print(f"    {idx + 1:<10} {region_wind[idx]:>12,.0f}")


def main():
    parser = argparse.ArgumentParser(
        description="从 .mat 选择文件计算风电/光伏装机容量（连续容量版）"
    )
    parser.add_argument(
        "--source",
        choices=["continuous", "optimization", "ssp126", "ssp245", "ssp560"],
        default="continuous",
        help="使用哪个优化目录（默认：continuous → Optimization_ssp126_test_continuous）",
    )
    parser.add_argument(
        "--res-dir",
        type=str,
        default=None,
        help="自定义结果文件目录（默认：<opt_dir>/results）",
    )
    parser.add_argument("--regional", action="store_true", help="同时打印各区域装机分布")
    args = parser.parse_args()

    base_dir = Path(__file__).parent

    source_dir_map = {
        "continuous": "Optimization_ssp126_test_continuous",
        "optimization": "Optimization",
        "ssp126": "Optimization_ssp126",
        "ssp245": "Optimization_ssp245",
        "ssp560": "Optimization_ssp560",
    }
    opt_dir = base_dir / source_dir_map[args.source]

    if args.res_dir:
        res_dir = Path(args.res_dir)
    else:
        res_dir = opt_dir / "results"

    print(f"优化目录：{opt_dir}")
    print(f"结果目录：{res_dir}")
    print(f"模式：连续容量（分数 0~1，EPS_ACTIVE={EPS_ACTIVE}）")

    results = []
    for year in [2050, 2040, 2030]:
        try:
            res = calc_capacity_for_year(opt_dir, res_dir, year, args.source)
            print_results(res)
            if args.regional:
                print_regional_breakdown(res)
            results.append(res)
        except FileNotFoundError as e:
            print(f"  [错误] {e}")

    valid_results = [r for r in results if r is not None]
    if valid_results:
        print_comparison_table(valid_results)

    print(f"\n{'═' * 70}")
    print("  说明：")
    print("  - 连续容量版：opt_solar/opt_wind 为开发比例分数（0~1）")
    print("  - 实际装机 = 最大可安装容量 × 开发比例分数")
    print("  - Active = 分数 > EPS；Partial = 0 < 分数 < 1；Full = 分数 ≈ 1")
    print("  - AR6 参考值 = 综合评估模型的5模型均值")
    print("  - 装机单位：GW（铭牌容量）")
    print(f"{'═' * 70}")


if __name__ == "__main__":
    main()
