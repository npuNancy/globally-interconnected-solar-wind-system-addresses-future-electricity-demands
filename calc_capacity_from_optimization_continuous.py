#!/usr/bin/env python3
"""
从 .mat 选择文件计算风电/光伏装机容量，并与 AR6 参考数据对比。

用法：
    python calc_capacity_from_optimization.py [--source optimization|ssp126] [--regional]

读取数据：
  - Opt_*_Sel.mat 文件（opt_solar, opt_wind 空间布局）
  - 原始数据文件（构建装机容量栅格）
  - Global_Grid_Division.mat（区域划分）
  - Global_Init_State.mat（当前已装机容量，用作参考）

输出：
  - 选中解的光伏/风电装机容量（GW）
  - 与 AR6 多模型均值参考值的对比
"""

import argparse
import os
import numpy as np
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
    """构建 180×360 光伏/风电装机容量栅格（GW）。

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


def calc_capacity_for_year(opt_dir, res_dir, year, source="optimization"):
    """从 .mat 选择文件计算某年的光伏/风电装机容量。"""
    label = YEAR_LABELS[year]
    if source == "optimization" and year == 2050:
        label = "2050 S-G（全球互联）"

    # 加载 .mat 选择文件
    mat_path = _find_file(res_dir, SEL_PATTERNS[year])
    if mat_path is None:
        raise FileNotFoundError(
            f"未找到 {year} 年的选择文件，期望：{SEL_PATTERNS[year]}（目录：{res_dir}）"
        )

    mat = sio.loadmat(mat_path)
    opt_solar = mat["opt_solar"]  # 180×360 binary
    opt_wind = mat["opt_wind"]  # 180×360 binary

    # 构建容量栅格
    solar_cap, wind_cap = _build_capacity_grids(str(opt_dir))

    # 计算总装机
    solar_gw = float(np.sum(solar_cap * opt_solar))
    wind_gw = float(np.sum(wind_cap * opt_wind))
    n_solar_selected = int(np.count_nonzero(opt_solar))
    n_wind_selected = int(np.count_nonzero(opt_wind))

    # 按区域汇总
    grid_div_path = os.path.join(str(opt_dir), "Global_Grid_Division.mat")
    region_solar = np.zeros(20)
    region_wind = np.zeros(20)
    if os.path.exists(grid_div_path):
        grid_div = sio.loadmat(grid_div_path)["data"]
        for r in range(1, 21):
            mask = grid_div == r
            region_solar[r - 1] = float(np.sum(solar_cap * opt_solar * mask))
            region_wind[r - 1] = float(np.sum(wind_cap * opt_wind * mask))

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
        "n_solar_selected": n_solar_selected,
        "n_wind_selected": n_wind_selected,
        "region_solar": region_solar,
        "region_wind": region_wind,
        "existing": existing,
    }


def print_results(result):
    """打印某年的装机容量分析结果。"""
    year = result["year"]
    solar = result["solar_gw"]
    wind = result["wind_gw"]
    total = result["total_gw"]

    print(f"\n{'═' * 70}")
    print(f"  {result['label']}")
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
    print(f"\n  选中解装机容量：")
    print(f"    光伏：{solar:>10,.0f} GW  （选中 {result['n_solar_selected']} 个格网）")
    print(f"    风电：{wind:>10,.0f} GW  （选中 {result['n_wind_selected']} 个格网）")
    print(f"    合计：{total:>10,.0f} GW")

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
    print(f"  汇总：优化结果 vs AR6 参考值")
    print(f"{'═' * 70}")

    header = f"\n  {'年份':<12} {'来源':<18} {'光伏 (GW)':>12} {'风电 (GW)':>12} {'合计 (GW)':>12}"
    print(header)
    print(f"  {'─' * 66}")

    for res in results:
        if res is None:
            continue
        year = res["year"]
        print(
            f"  {year:<12} {'优化选择解':<18}"
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
    """打印各区域装机分布（前 N 个区域）。"""
    year = result["year"]
    region_solar = result["region_solar"]
    region_wind = result["region_wind"]

    print(f"\n  各区域装机分布（{year}年）：")

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
    parser = argparse.ArgumentParser(description="从 .mat 选择文件计算风电/光伏装机容量")
    parser.add_argument(
        "--source",
        choices=["optimization", "ssp126", "ssp245", "ssp560"],
        default="optimization",
        help="使用哪个优化目录（默认：optimization）",
    )
    parser.add_argument("--res-dir", type=str, default=None, help="自定义结果文件目录（默认：<opt_dir>/results）")
    parser.add_argument("--regional", action="store_true", help="同时打印各区域装机分布")
    args = parser.parse_args()

    base_dir = Path(__file__).parent

    source_dir_map = {
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
    print("  - 优化装机 = 选中格网的最大可安装装机容量（铭牌值）")
    print("  - AR6 参考值 = 综合评估模型的5模型均值")
    print("  - 装机单位：GW（铭牌容量）")
    print(f"{'═' * 70}")


if __name__ == "__main__":
    main()
