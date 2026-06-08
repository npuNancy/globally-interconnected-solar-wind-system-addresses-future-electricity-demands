"""
plot_transmission_network_v2.py
全球输电网络可视化 —— 20 区域分色标注（完整名称）

改进点（相对 v1）：
  1. 用适宜网格（太阳能+风能候选格网）过滤海洋像元，区域质心仅基于陆地计算
  2. 区域着色仅渲染适宜格网覆盖的陆地区域，避免海洋区域误导
  3. 区域名称使用全称，不使用缩写
  4. 输电线路使用 Geodetic（大圆弧线），避免 PlateCarree 直线偏移
  5. cartopy 绘制国家边界线
"""

import os
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import matplotlib.font_manager as fm
import scipy.io as sio
import rasterio
import cartopy.crs as ccrs
import cartopy.feature as cfeature

# ── 字体（支持中文显示） ──
FONT_PATH = "/data4/yanxiaokai/SourceHanSansSC-Normal.otf"
if os.path.exists(FONT_PATH):
    fm.fontManager.addfont(FONT_PATH)
    _font_name = fm.FontProperties(fname=FONT_PATH).get_name()
    plt.rcParams["font.family"] = [_font_name]
    plt.rcParams["axes.unicode_minus"] = False


# ── 20 个全球区域全称（按 TIF 区域编号 1-20 排列） ──
REGION_FULL_NAMES = {
    1: "Northern America",
    2: "Central America",
    3: "Caribbean",
    4: "South America",
    5: "Northern Europe",
    6: "Western Europe",
    7: "Southern Europe",
    8: "Eastern Europe",
    9: "Central Asia",
    10: "Eastern Asia",
    11: "Western Asia",
    12: "Southern Asia",
    13: "South-eastern Asia",
    14: "Melanesia",
    15: "Australia-New Zealand",
    16: "Northern Africa",
    17: "Western Africa",
    18: "Middle Africa",
    19: "Eastern Africa",
    20: "Southern Africa",
}

# ── 20 色调色板（高对比度，各大洲色系区分明显） ──
REGION_COLORS = {
    1: "#1b9e77",  # Northern America
    2: "#d95f02",  # Central America
    3: "#7570b3",  # Caribbean
    4: "#e7298a",  # South America
    5: "#66a61e",  # Northern Europe
    6: "#e6ab02",  # Western Europe
    7: "#a6761d",  # Southern Europe
    8: "#666666",  # Eastern Europe
    9: "#1f78b4",  # Central Asia
    10: "#e31a1c",  # Eastern Asia
    11: "#b15928",  # Western Asia
    12: "#fb9a99",  # Southern Asia
    13: "#33a02c",  # South-eastern Asia
    14: "#cab2d6",  # Melanesia
    15: "#a6cee3",  # Australia-New Zealand
    16: "#ff7f00",  # Northern Africa
    17: "#ffff33",  # Western Africa
    18: "#b2df8a",  # Middle Africa
    19: "#fdbf6f",  # Eastern Africa
    20: "#969696",  # Southern Africa
}


# ════════════════════ 工具函数 ════════════════════


def load_region_grid(tif_path):
    """读取区域划分 GeoTIFF，返回 (data, lons, lats)。"""
    with rasterio.open(tif_path) as src:
        data = src.read(1).astype(float)
        ny, nx = data.shape
        lons = np.linspace(
            src.transform[2] + src.transform[0] / 2,
            src.transform[2] + nx * src.transform[0] - src.transform[0] / 2,
            nx,
        )
        lats = np.linspace(
            src.transform[5] + src.transform[4] / 2,
            src.transform[5] + ny * src.transform[4] - src.transform[4] / 2,
            ny,
        )
    data[data == 0] = np.nan
    return data, lons, lats


def load_suitable_mask(data_dir):
    """
    加载适宜网格掩码（太阳能 + 风能候选格网的并集）。
    太阳能候选：Global_fishnet 中 ID < 65536 的格网
    风能候选：Global_Wind_Net_Area_Add_Egrid 中 > 0 的格网
    返回 bool 数组 (180, 360)。
    """
    # 太阳能候选网格
    fish_path = os.path.join(data_dir, "Global_fishnet.mat")
    fish_data = sio.loadmat(fish_path)["data"]
    solar_mask = fish_data < 65536

    # 风能候选网格
    wind_path = os.path.join(data_dir, "Global_Wind_Net_Area_Add_Egrid.mat")
    wind_data = sio.loadmat(wind_path)["data"]
    wind_mask = wind_data > 0

    combined = solar_mask | wind_mask
    print(f"  适宜网格: 太阳能 {solar_mask.sum()} + 风能 {wind_mask.sum()} → 合计 {combined.sum()} 个格网")
    return combined


def compute_centroids_masked(region_grid, lons, lats):
    """从掩码后的区域网格计算各区域质心经纬度（仅基于陆地适宜格网）。"""
    centroids = {}
    for rid in range(1, 21):
        rows, cols = np.where(region_grid == rid)
        if len(rows) == 0:
            continue
        centroids[rid] = (float(np.mean(lats[rows])), float(np.mean(lons[cols])))
    return centroids


def load_trans_matrix(mat_path):
    """从 .mat 文件加载 opt_trans 输电容量矩阵。"""
    return sio.loadmat(mat_path)["opt_trans"].astype(float)


# ════════════════════ 主程序 ════════════════════


def main(dir_Optimization="Optimization_ssp126"):
    base_dir = os.path.dirname(os.path.abspath(__file__))
    data_dir = os.path.join(base_dir, dir_Optimization)
    results_dir = os.path.join(data_dir, "results")
    # 查找最新的 results_<timestamp> 子目录
    if os.path.isdir(results_dir):
        subdirs = sorted([
            os.path.join(results_dir, d)
            for d in os.listdir(results_dir)
            if d.startswith("results_") and os.path.isdir(os.path.join(results_dir, d))
        ])
        if subdirs:
            results_dir = subdirs[-1]
    tif_path = os.path.join(data_dir, "Global_Grid_Division.tif")

    # ── 读取区域地理数据 + 适宜网格掩码 ──
    region_grid, lons, lats = load_region_grid(tif_path)

    # 用适宜网格（太阳能+风能候选格网）过滤海洋像元，修正区域质心
    suitable_mask = load_suitable_mask(data_dir)
    region_grid[~suitable_mask] = np.nan
    print(f"  掩码后区域格网数: {int(np.sum(~np.isnan(region_grid)))}")

    centroids = compute_centroids_masked(region_grid, lons, lats)

    # ── 加载三个年份的输电容量矩阵 ──
    year_files = {
        2030: ("Opt_SA_2030_Sel.mat", "2030 (S-A Adjacent)"),
        2040: ("Opt_SC_2040_Sel.mat", "2040 (S-C Continental)"),
        2050: ("Opt_SC_2050_Sel.mat", "2050 (S-C Continental)"),
    }
    trans_data = {}
    for year, (fname, title) in year_files.items():
        fpath = os.path.join(results_dir, fname)
        if os.path.exists(fpath):
            trans_data[year] = (load_trans_matrix(fpath), title)
            print(f"  已加载 {fname}")
        else:
            print(f"  ⚠ 未找到 {fpath}")

    # ══════════════════ 绘图 ══════════════════
    projection = ccrs.PlateCarree()
    fig, axes = plt.subplots(
        1,
        3,
        figsize=(28, 10),
        subplot_kw={"projection": projection},
    )

    cmap_regions = plt.get_cmap("tab20", 20)

    for ax_idx, (ax, (year, (trans, title))) in enumerate(zip(axes, trans_data.items())):
        # ── 1. 区域地理范围着色（仅渲染适宜网格覆盖的陆地像元） ──
        ax.pcolormesh(
            lons,
            lats,
            region_grid,
            cmap=cmap_regions,
            vmin=0.5,
            vmax=20.5,
            transform=ccrs.PlateCarree(),
            zorder=0,
            alpha=0.50,
        )

        # ── 2. 底图要素：海洋 + 陆地底色 + 海岸线 + 国界 ──
        ax.add_feature(cfeature.OCEAN, facecolor="#e8f0fe", zorder=-1)
        ax.add_feature(cfeature.LAND, facecolor="none", zorder=-1)
        ax.add_feature(cfeature.COASTLINE, linewidth=0.5, edgecolor="#333333", zorder=1)
        ax.add_feature(
            cfeature.BORDERS,
            linewidth=0.3,
            edgecolor="#777777",
            linestyle="-",
            zorder=1,
        )
        ax.set_global()

        # ── 3. 输电线路（Geodetic 大圆弧线，避免 PlateCarree 直线偏移） ──
        # 跨洋链路：1-6、1-7、4-17、4-18 用紫色标注
        cross_ocean_pairs = {(1, 6), (1, 7), (4, 17), (4, 18)}
        trans_sym = (trans + trans.T) / 2.0
        rows, cols = np.where(np.triu(trans_sym, k=1) > 0)

        if len(rows) > 0:
            caps = trans_sym[rows, cols]
            max_cap = caps.max()

            for r, c, cap in zip(rows, cols, caps):
                lat1, lon1 = centroids[r + 1]
                lat2, lon2 = centroids[c + 1]
                norm = cap / max_cap
                lw = 0.4 + norm * 3.5
                alpha = 0.25 + 0.65 * norm
                # 判断是否为跨洋链路
                pair = (min(r + 1, c + 1), max(r + 1, c + 1))
                color = "#7b3294" if pair in cross_ocean_pairs else "#2166ac"
                ax.plot(
                    [lon1, lon2],
                    [lat1, lat2],
                    color=color,
                    linewidth=lw,
                    alpha=alpha,
                    transform=ccrs.Geodetic(),  # 大圆弧线
                    zorder=2,
                )

        # ── 4. 区域节点（不同颜色圆点） ──
        for rid in range(1, 21):
            lat, lon = centroids[rid]
            color = REGION_COLORS[rid]
            ax.plot(
                lon,
                lat,
                marker="o",
                color=color,
                markersize=7,
                markeredgecolor="white",
                markeredgewidth=1.2,
                transform=ccrs.PlateCarree(),
                zorder=3,
            )

        # ── 5. 区域名称标签（编号 + 全称） ──
        for rid in range(1, 21):
            lat, lon = centroids[rid]
            name = REGION_FULL_NAMES[rid]
            # 为小区域或密集区域调整标签偏移
            dlon, dlat = 2.0, 1.5
            ha = "left"
            if rid in (6, 7):  # Western / Southern Europe（密集区）
                dlon = 3.0
            elif rid in (3,):  # Caribbean（小区域）
                dlon = 3.0
            elif rid in (9, 11, 12):  # Central Asia / Western Asia / Southern Asia
                dlon = 3.0

            ax.text(
                lon + dlon,
                lat + dlat,
                f"{rid}. {name}",
                fontsize=4.5,
                fontweight="bold",
                color="black",
                ha=ha,
                va="bottom",
                bbox=dict(
                    boxstyle="round,pad=0.15",
                    facecolor="white",
                    edgecolor="none",
                    alpha=0.80,
                ),
                transform=ccrs.PlateCarree(),
                zorder=4,
            )

        ax.set_title(title, fontsize=14, fontweight="bold", pad=12)

    # ── 6. 图例：20 区域完整名称 + 对应颜色 ──
    legend_patches = []
    for rid in range(1, 21):
        patch = mpatches.Patch(
            facecolor=REGION_COLORS[rid],
            edgecolor="#aaaaaa",
            linewidth=0.5,
            label=f"{rid:2d}. {REGION_FULL_NAMES[rid]}",
        )
        legend_patches.append(patch)

    # fig.legend(
    #     handles=legend_patches,
    #     loc="lower center",
    #     ncol=4,
    #     fontsize=8,
    #     frameon=True,
    #     fancybox=True,
    #     shadow=False,
    #     borderaxespad=-4,
    #     title="20 Global Regions",
    #     title_fontsize=10,
    #     columnspacing=1.5,
    #     handletextpad=0.5,
    # )

    # ── 保存 ──
    plt.subplots_adjust(bottom=0.24, top=0.93, wspace=0.04)
    out_path = os.path.join(results_dir, "transmission_network.png")
    fig.savefig(out_path, dpi=300, bbox_inches="tight")
    print(f"\n图已保存至: {out_path}")
    plt.show()


if __name__ == "__main__":
    # Optimization_ssp126
    # Optimization_ssp245
    # Optimization_ssp560
    main("Optimization_ssp126")
