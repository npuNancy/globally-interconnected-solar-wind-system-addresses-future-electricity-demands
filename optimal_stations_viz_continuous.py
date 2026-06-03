#!/usr/bin/env python3
"""
未来风光场站选址可视化 — 连续容量（开发比例）版本

与二进制（0/1）版本不同，本脚本处理连续优化结果，其中每个候选格网的
决策变量为 [0, 1] 范围内的开发比例（fraction）。

读取 Opt_*_Sel.mat 文件中的 opt_solar_frac / opt_wind_frac（或 opt_solar / opt_wind
作为回退），按 EPS_ACTIVE 阈值筛选有效开发格网，并计算实际装机容量
（max_capacity × fraction）。

用法:
    python optimal_stations_viz_continuous.py

输出（每个情景的 results/ 目录下）:
    - stations_<scenario>.csv  — 含年份、类型、经纬度、实际容量、开发比例
    - solar_wind_farm_stations.png — 上下两图（光伏/风电），3 个年份叠加
"""

import os
import warnings

warnings.filterwarnings("ignore")

import numpy as np
import matplotlib.pyplot as plt
import matplotlib.font_manager as fm
import scipy.io
import csv
import cartopy.crs as ccrs
import cartopy.feature as cfeature

# ══════════════════════════════════════════════════════════════════════
# 配置
# ══════════════════════════════════════════════════════════════════════

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# 连续容量实验仅处理 SSP1-2.6 连续版本
SCENARIOS = {
    "SSP1-2.6-continuous": "Optimization_ssp126_test_continuous/results",
}

YEAR_COLORS = {2030: "#c501ff", 2040: "#00ffc5", 2050: "#d48a8b"}

# 判定格网是否有效开发的数值阈值
EPS_ACTIVE = 1e-6

# .mat 选择文件名模式（同一年有多种命名时按优先级尝试）
MAT_PATTERNS = {
    2050: ["Opt_SG_2050_Sel.mat", "Opt_SC_2050_Sel.mat"],
    2040: ["Opt_SC_2040_Sel.mat"],
    2030: ["Opt_SA_2030_Sel.mat"],
}

# ══════════════════════════════════════════════════════════════════════
# 字体
# ══════════════════════════════════════════════════════════════════════

font_path = "/data4/yanxiaokai/SourceHanSansSC-Normal.otf"
if os.path.exists(font_path):
    fm.fontManager.addfont(font_path)
    font_name = fm.FontProperties(fname=font_path).get_name()
    plt.rcParams["font.family"] = [font_name]
plt.rcParams["axes.unicode_minus"] = False
plt.rcParams.update(
    {
        "figure.dpi": 120,
        "font.size": 11,
        "axes.titlesize": 13,
        "axes.labelsize": 11,
    }
)


# ══════════════════════════════════════════════════════════════════════
# 工具函数
# ══════════════════════════════════════════════════════════════════════


def setup_basemap(ax):
    ax.set_global()
    ax.add_feature(cfeature.LAND, color="#f5f5f0", zorder=0)
    ax.add_feature(cfeature.OCEAN, color="#d1e8f0", zorder=0)
    ax.add_feature(cfeature.COASTLINE, linewidth=0.5, color="#888", zorder=1)
    ax.add_feature(cfeature.BORDERS, linewidth=0.3, color="#aaa", zorder=1)
    ax.gridlines(linewidth=0.3, color="gray", alpha=0.4)


def _find_file(data_dir, patterns):
    for p in patterns:
        path = os.path.join(data_dir, p)
        if os.path.exists(path):
            return path
    return None


def _grid_to_coords(mask, frac):
    """将 180×360 布尔掩码和开发比例栅格转为活动格网的 (lon, lat, fraction)。

    Parameters
    ----------
    mask : ndarray of bool, shape (180, 360)
        活动格网掩码（fraction > EPS_ACTIVE）。
    frac : ndarray of float, shape (180, 360)
        开发比例栅格（值域 [0, 1]）。

    Returns
    -------
    lons : ndarray — 活动格网中心经度
    lats : ndarray — 活动格网中心纬度
    fracs : ndarray — 活动格网对应的开发比例
    """
    nrows = mask.shape[0]
    flat = np.nonzero(mask.ravel(order="F"))[0]
    rows, cols = flat % nrows, flat // nrows
    return -179.5 + cols, 89.5 - rows, frac[rows, cols]


def extract_stations_from_mat(mat_path):
    """从 .mat 选择文件提取光伏和风电场站经纬度及开发比例。

    优先读取 opt_solar_frac / opt_wind_frac；若不存在，则回退到
    opt_solar / opt_wind（连续版本中二者值相同）。

    Returns: (slon, slat, sfracs, ns, wlon, wlat, wfracs, nw)
    """
    mat = scipy.io.loadmat(mat_path)

    solar_frac_grid = (
        mat["opt_solar_frac"] if "opt_solar_frac" in mat else mat["opt_solar"]
    )
    wind_frac_grid = (
        mat["opt_wind_frac"] if "opt_wind_frac" in mat else mat["opt_wind"]
    )

    sm = solar_frac_grid > EPS_ACTIVE
    wm = wind_frac_grid > EPS_ACTIVE

    slon, slat, sfracs = _grid_to_coords(sm, solar_frac_grid)
    wlon, wlat, wfracs = _grid_to_coords(wm, wind_frac_grid)

    return slon, slat, sfracs, len(slon), wlon, wlat, wfracs, len(wlon)


def get_stations(data_dir, year):
    """获取指定年份的光伏+风电场站坐标及开发比例。

    Returns: (slon, slat, sfracs, ns, wlon, wlat, wfracs, nw)
    Raises: FileNotFoundError — .mat 选择文件不存在
    """
    mat_path = _find_file(data_dir, MAT_PATTERNS[year])
    if mat_path is None:
        raise FileNotFoundError(
            f"{year} 年选择文件未找到，期望：{MAT_PATTERNS[year]}（目录：{data_dir}）"
        )
    return extract_stations_from_mat(mat_path)


# ══════════════════════════════════════════════════════════════════════
# 装机容量 & CSV 导出
# ══════════════════════════════════════════════════════════════════════


def _build_capacity_grids(opt_dir):
    """构建 180×360 光伏/风电最大装机容量栅格（GW）。

    容量 = 安装密度(MW/km²) × 可用面积比例 × 格网面积(km²) / 1000
    """
    solar_luccs = scipy.io.loadmat(os.path.join(opt_dir, "Global_Solar_Net_Area_Add_Egrid.mat"))["data"] / 100.0
    solar_area = scipy.io.loadmat(os.path.join(opt_dir, "Global_Solar_Fishnet_Area.mat"))["data"].astype(float)
    solar_cap = 74 * solar_luccs * solar_area / 1000

    wind_luccs = scipy.io.loadmat(os.path.join(opt_dir, "Global_Wind_Net_Area_Add_Egrid.mat"))["data"] / 100.0
    wind_area = scipy.io.loadmat(os.path.join(opt_dir, "Global_Wind_Fishnet_Area.mat"))["data"]
    landmask = scipy.io.loadmat(os.path.join(opt_dir, "Global_LandMask.mat"))["data"]
    density = np.where(landmask > 100, 4.6, 2.7)
    wind_cap = density * wind_luccs * wind_area / 1000

    return solar_cap, wind_cap


def get_stations_with_cap(data_dir, year, solar_cap, wind_cap):
    """获取指定年份的光伏+风电场站坐标、实际装机容量和开发比例。

    实际装机容量 = max_capacity × fraction

    Returns: (slon, slat, scap, sfracs, ns, wlon, wlat, wcap, wfracs, nw)
    Raises: FileNotFoundError — .mat 选择文件不存在
    """
    mat_path = _find_file(data_dir, MAT_PATTERNS[year])
    if mat_path is None:
        raise FileNotFoundError(
            f"{year} 年选择文件未找到，期望：{MAT_PATTERNS[year]}（目录：{data_dir}）"
        )

    mat = scipy.io.loadmat(mat_path)

    solar_frac_grid = (
        mat["opt_solar_frac"] if "opt_solar_frac" in mat else mat["opt_solar"]
    )
    wind_frac_grid = (
        mat["opt_wind_frac"] if "opt_wind_frac" in mat else mat["opt_wind"]
    )

    nrows = solar_frac_grid.shape[0]

    # ── 光伏 ──
    sm = solar_frac_grid > EPS_ACTIVE
    sflat = np.nonzero(sm.ravel(order="F"))[0]
    srows, scols = sflat % nrows, sflat // nrows
    slon, slat = -179.5 + scols, 89.5 - srows
    solar_frac = solar_frac_grid[srows, scols]
    scap = solar_cap[srows, scols] * solar_frac

    # ── 风电 ──
    wm = wind_frac_grid > EPS_ACTIVE
    wflat = np.nonzero(wm.ravel(order="F"))[0]
    wrows, wcols = wflat % nrows, wflat // nrows
    wlon, wlat = -179.5 + wcols, 89.5 - wrows
    wind_frac = wind_frac_grid[wrows, wcols]
    wcap = wind_cap[wrows, wcols] * wind_frac

    return slon, slat, scap, solar_frac, len(slon), wlon, wlat, wcap, wind_frac, len(wlon)


def save_stations_csv(data_dir, scenario_name, cap_results):
    """保存场站选址结果为 CSV：year,type,lon,lat,capacity_gw,fraction_of_potential。"""
    csv_path = os.path.join(data_dir, f"stations_{scenario_name}.csv")
    n_rows = 0
    with open(csv_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["year", "type", "lon", "lat", "capacity_gw", "fraction_of_potential"])
        for year in [2050, 2040, 2030]:
            if year not in cap_results:
                continue
            slon, slat, scap, sfracs, ns, wlon, wlat, wcap, wfracs, nw = cap_results[year]
            for i in range(ns):
                writer.writerow([
                    year, "solar",
                    f"{slon[i]:.1f}", f"{slat[i]:.1f}",
                    f"{scap[i]:.4f}", f"{sfracs[i]:.6f}",
                ])
            for i in range(nw):
                writer.writerow([
                    year, "wind",
                    f"{wlon[i]:.1f}", f"{wlat[i]:.1f}",
                    f"{wcap[i]:.4f}", f"{wfracs[i]:.6f}",
                ])
            n_rows += ns + nw
    print(f"  -> {csv_path} ({n_rows} active grids)")


# ══════════════════════════════════════════════════════════════════════
# 可视化
# ══════════════════════════════════════════════════════════════════════


def plot_scenario(scenario_name, data_dir, results, cap_results):
    """单情景：上子图=光伏，下子图=风电，3 个年份叠加。

    点大小与实际装机容量（GW）成正比。
    """
    fig, (ax_s, ax_w) = plt.subplots(2, 1, figsize=(16, 14), subplot_kw={"projection": ccrs.Robinson()})
    setup_basemap(ax_s)
    setup_basemap(ax_w)

    # 点大小缩放因子：将 GW 映射到合理的散点面积
    scale = 5.0

    for year in [2050, 2040, 2030]:
        if year not in results:
            continue
        slon, slat, sfracs, ns, wlon, wlat, wfracs, nw = results[year]

        # 从 cap_results 获取实际容量用于点大小
        ssizes = np.ones(ns) * 3
        wsizes = np.ones(nw) * 3
        if year in cap_results:
            _, _, scap, _, _, _, _, wcap, _, _ = cap_results[year]
            ssizes = np.clip(scap * scale, 1, 50)
            wsizes = np.clip(wcap * scale, 1, 50)

        ax_s.scatter(
            slon,
            slat,
            s=ssizes,
            c=YEAR_COLORS[year],
            transform=ccrs.PlateCarree(),
            label=f"{year} (有效开发格网数: {ns:,})",
            rasterized=True,
        )
        ax_w.scatter(
            wlon,
            wlat,
            s=wsizes,
            c=YEAR_COLORS[year],
            transform=ccrs.PlateCarree(),
            label=f"{year} (有效开发格网数: {nw:,})",
            rasterized=True,
        )

    for ax, title in [
        (ax_s, f"{scenario_name} — Solar Farm Continuous Capacity"),
        (ax_w, f"{scenario_name} — Wind Farm Continuous Capacity"),
    ]:
        ax.legend(loc="lower left", fontsize=11, markerscale=3, framealpha=0.9, edgecolor="#888")
        ax.set_title(title, fontsize=14, pad=10)

    out = os.path.join(data_dir, "solar_wind_farm_stations.png")
    plt.tight_layout()
    plt.savefig(out, dpi=300, bbox_inches="tight")
    plt.close()
    print(f"  -> {out}")


# ══════════════════════════════════════════════════════════════════════
# 主函数
# ══════════════════════════════════════════════════════════════════════


def main():
    all_results = {}

    for scenario_name, rel_path in SCENARIOS.items():
        data_dir = os.path.join(BASE_DIR, rel_path)
        if not os.path.isdir(data_dir):
            print(f"[skip] {data_dir}")
            continue

        print(f"\n{'=' * 60}")
        print(f"  {scenario_name}  ({data_dir})")
        print(f"{'=' * 60}")

        results = {}
        for year in [2050, 2040, 2030]:
            try:
                data = get_stations(data_dir, year)
                slon, slat, sfracs, ns, wlon, wlat, wfracs, nw = data
                results[year] = data
                print(f"  {year}: solar={ns:,}  wind={nw:,}")
            except FileNotFoundError as e:
                print(f"  {year}: {e}")

        # CSV 导出：含装机容量和开发比例
        opt_dir = os.path.dirname(data_dir)
        cap_files = ["Global_Solar_Net_Area_Add_Egrid.mat", "Global_LandMask.mat"]
        cap_results = {}
        if all(os.path.exists(os.path.join(opt_dir, f)) for f in cap_files):
            solar_cap, wind_cap = _build_capacity_grids(opt_dir)
            for year in [2050, 2040, 2030]:
                try:
                    data = get_stations_with_cap(data_dir, year, solar_cap, wind_cap)
                    cap_results[year] = data
                except FileNotFoundError:
                    pass
            if cap_results:
                save_stations_csv(data_dir, scenario_name, cap_results)

        if results:
            all_results[scenario_name] = results
            plot_scenario(scenario_name, data_dir, results, cap_results)

    # 汇总
    print(f"\n{'=' * 60}")
    print("  Summary")
    print(f"{'=' * 60}")
    header = f"  {'Scenario':<25}" + "".join(f"  {y} solar/wind    " for y in [2050, 2040, 2030])
    print(header)
    print("  " + "-" * 90)
    for name, results in all_results.items():
        row = f"  {name:<25}"
        for year in [2050, 2040, 2030]:
            if year in results:
                ns, nw = results[year][3], results[year][7]
                row += f"  {ns:>5,}/{nw:<5,}     "
            else:
                row += f"  {'--/--':>12}   "
        print(row)

    # 容量汇总
    if cap_results:
        print(f"\n  Capacity Summary (GW)")
        print(f"  {'─' * 70}")
        for year in [2050, 2040, 2030]:
            if year in cap_results:
                _, _, scap, sfracs, ns, _, _, wcap, wfracs, nw = cap_results[year]
                total_solar = float(np.sum(scap))
                total_wind = float(np.sum(wcap))
                mean_sf = float(np.mean(sfracs)) if ns > 0 else 0
                mean_wf = float(np.mean(wfracs)) if nw > 0 else 0
                print(
                    f"  {year}: solar={total_solar:>10,.1f} GW ({ns:,} grids, "
                    f"avg frac={mean_sf:.3f})  "
                    f"wind={total_wind:>10,.1f} GW ({nw:,} grids, "
                    f"avg frac={mean_wf:.3f})"
                )


if __name__ == "__main__":
    main()
