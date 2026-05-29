#!/usr/bin/env python3
"""
未来风光场站选址可视化

参考 optimal_stations_viz.ipynb，对不同 SSP 情景下 2030/2040/2050 年
光伏和风电场站选址结果进行可视化（上: 光伏，下: 风电）。

用法:
    python wind_farm_viz.py
"""

import os
import warnings

warnings.filterwarnings("ignore")

import numpy as np
import matplotlib.pyplot as plt
import matplotlib.font_manager as fm
import scipy.io
import h5py
import cartopy.crs as ccrs
import cartopy.feature as cfeature

# ══════════════════════════════════════════════════════════════════════
# 配置
# ══════════════════════════════════════════════════════════════════════

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

SCENARIOS = {
    "Baseline": "Optimization/results",
    "SSP1-2.6": "Optimization_ssp126/results",
    "SSP2-4.5": "Optimization_ssp245/results",
    "SSP5-6.0": "Optimization_ssp560/results",
}

SOLUTION_INDICES = {2030: 5, 2040: 15, 2050: 66}

YEAR_COLORS = {2030: "#c501ff", 2040: "#00ffc5", 2050: "#d48a8b"}

# .mat / .h5 文件名模式（同一年有多种命名时按优先级尝试）
MAT_PATTERNS = {
    2050: ["Opt_SG_2050_Sel.mat", "Opt_SC_2050_Sel.mat"],
    2040: ["Opt_SC_2040_Sel.mat"],
    2030: ["Opt_SA_2030_Sel.mat"],
}
H5_PATTERNS = {
    2050: ["Optimization_SG_2050_Res.h5", "Optimization_SC_2050_Res.h5"],
    2040: ["Optimization_SC_2040_Res.h5"],
    2030: ["Optimization_SA_2030_Res.h5"],
}
PARENT_YEAR = {2030: 2040}

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


def _grid_to_coords(grid):
    """将 180x360 二值栅格转为 (lon, lat) 坐标数组。"""
    nrows = grid.shape[0]
    flat = np.nonzero(grid.ravel(order="F"))[0]
    rows, cols = flat % nrows, flat // nrows
    return -179.5 + cols, 89.5 - rows


def extract_stations_from_mat(mat_path):
    """从 .mat 选择文件提取光伏和风电场站经纬度。

    Returns: (slon, slat, ns, wlon, wlat, nw)
    """
    mat = scipy.io.loadmat(mat_path)
    opt_solar = mat["opt_solar"]
    opt_wind = mat["opt_wind"]
    slon, slat = _grid_to_coords(opt_solar)
    wlon, wlat = _grid_to_coords(opt_wind)
    return slon, slat, len(slon), wlon, wlat, len(wlon)


def extract_stations_from_h5(h5_path, sol_idx, parent_mat_path):
    """从 .h5 帕累托解提取选中场站经纬度（需要上层 .mat 提供候选坐标）。

    Returns: (slon, slat, ns_sel, wlon, wlat, nw_sel)
    """
    parent_mat = scipy.io.loadmat(parent_mat_path)
    opt_solar = parent_mat["opt_solar"]
    opt_wind = parent_mat["opt_wind"]
    nrows = opt_solar.shape[0]

    sflat = np.nonzero(opt_solar.ravel(order="F"))[0]
    wflat = np.nonzero(opt_wind.ravel(order="F"))[0]
    ns, nw = len(sflat), len(wflat)

    with h5py.File(h5_path, "r") as f:
        res_scale = f["/res_scale"][:]
    if res_scale.shape[0] > res_scale.shape[1]:
        res_scale = res_scale.T

    sol = res_scale[sol_idx - 1]
    sel = np.round(sol[: ns + nw]).astype(int)
    solar_sel = sel[:ns]
    wind_sel = sel[ns : ns + nw]

    srows, scols = sflat % nrows, sflat // nrows
    slon_all, slat_all = -179.5 + scols, 89.5 - srows

    wrows, wcols = wflat % nrows, wflat // nrows
    wlon_all, wlat_all = -179.5 + wcols, 89.5 - wrows

    sm = solar_sel == 1
    wm = wind_sel == 1
    return slon_all[sm], slat_all[sm], int(sm.sum()), wlon_all[wm], wlat_all[wm], int(wm.sum())


def get_stations(data_dir, year):
    """获取指定年份的光伏+风电场站坐标。

    Returns: dict {year: (slon, slat, ns, wlon, wlat, nw)} 或 None
    """
    # 优先: 直接从 .mat 提取
    mat_path = _find_file(data_dir, MAT_PATTERNS[year])
    if mat_path:
        return extract_stations_from_mat(mat_path)

    # 回退: .h5 帕累托解 + 上层 .mat 候选坐标
    h5_path = _find_file(data_dir, H5_PATTERNS[year])
    parent_year = PARENT_YEAR.get(year)
    parent_mat_path = (
        _find_file(data_dir, MAT_PATTERNS[parent_year]) if parent_year else None
    )
    if h5_path and parent_mat_path:
        return extract_stations_from_h5(h5_path, SOLUTION_INDICES[year], parent_mat_path)

    return None


# ══════════════════════════════════════════════════════════════════════
# 可视化
# ══════════════════════════════════════════════════════════════════════


def plot_scenario(scenario_name, data_dir, results):
    """单情景：上子图=光伏，下子图=风电，3 个年份叠加。"""
    fig, (ax_s, ax_w) = plt.subplots(
        2, 1, figsize=(16, 14), subplot_kw={"projection": ccrs.Robinson()}
    )
    setup_basemap(ax_s)
    setup_basemap(ax_w)

    for year in [2050, 2040, 2030]:
        if year not in results:
            continue
        slon, slat, ns, wlon, wlat, nw = results[year]

        ax_s.scatter(
            slon, slat, s=3, c=YEAR_COLORS[year],
            transform=ccrs.PlateCarree(),
            label=f"{year} ({ns:,})",
            rasterized=True,
        )
        ax_w.scatter(
            wlon, wlat, s=3, c=YEAR_COLORS[year],
            transform=ccrs.PlateCarree(),
            label=f"{year} ({nw:,})",
            rasterized=True,
        )

    for ax, title in [
        (ax_s, f"{scenario_name} — Solar Farm Station Selection"),
        (ax_w, f"{scenario_name} — Wind Farm Station Selection"),
    ]:
        ax.legend(loc="lower left", fontsize=11, markerscale=5, framealpha=0.9, edgecolor="#888")
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
            data = get_stations(data_dir, year)
            if data is not None:
                slon, slat, ns, wlon, wlat, nw = data
                results[year] = data
                print(f"  {year}: solar={ns:,}  wind={nw:,}")
            else:
                print(f"  {year}: no data")

        if results:
            all_results[scenario_name] = results
            plot_scenario(scenario_name, data_dir, results)

    # 汇总
    print(f"\n{'=' * 60}")
    print("  Summary")
    print(f"{'=' * 60}")
    header = f"  {'Scenario':<12}" + "".join(
        f"  {y} solar/wind    " for y in [2050, 2040, 2030]
    )
    print(header)
    print("  " + "-" * 78)
    for name, results in all_results.items():
        row = f"  {name:<12}"
        for year in [2050, 2040, 2030]:
            if year in results:
                ns, nw = results[year][2], results[year][5]
                row += f"  {ns:>5,}/{nw:<5,}     "
            else:
                row += f"  {'--/--':>12}   "
        print(row)


if __name__ == "__main__":
    main()
