#!/usr/bin/env python3
"""
绘制 Global_Wind_Fishnet_Area.tif 格网面积分布图

用法:
    python plot_fishnet_area.py [--input PATH] [--output PATH]
"""

import argparse
import os

import numpy as np
import matplotlib.pyplot as plt
import matplotlib.font_manager as fm
import matplotlib.ticker as mticker
import cartopy.crs as ccrs
import cartopy.feature as cfeature
import rasterio

# ══════════════════════════════════════════════════════════════════════
# 配置
# ══════════════════════════════════════════════════════════════════════

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

font_path = "/data4/yanxiaokai/SourceHanSansSC-Normal.otf"
if os.path.exists(font_path):
    fm.fontManager.addfont(font_path)
    font_name = fm.FontProperties(fname=font_path).get_name()
    plt.rcParams["font.family"] = [font_name]
plt.rcParams["axes.unicode_minus"] = False
plt.rcParams.update(
    {
        "figure.dpi": 150,
        "font.size": 11,
        "axes.titlesize": 14,
        "axes.labelsize": 11,
    }
)


# ══════════════════════════════════════════════════════════════════════
# 主函数
# ══════════════════════════════════════════════════════════════════════


def main():
    parser = argparse.ArgumentParser(description="绘制格网面积 GeoTIFF")
    parser.add_argument(
        "--input", default=os.path.join(BASE_DIR, "Optimization", "Global_Wind_Fishnet_Area.tif"),
        help="输入 GeoTIFF 路径",
    )
    parser.add_argument(
        "--output", default=os.path.join(BASE_DIR, "output", "Global_Wind_Fishnet_Area.png"),
        help="输出图片路径",
    )
    args = parser.parse_args()

    # 读取数据
    with rasterio.open(args.input) as ds:
        data = ds.read(1).astype(np.float64)
        transform = ds.transform

    nrows, ncols = data.shape
    lon = np.array([transform.c + (j + 0.5) * transform.a for j in range(ncols)])
    lat = np.array([transform.f + (i + 0.5) * transform.e for i in range(nrows)])

    # 绘图
    fig = plt.figure(figsize=(14, 6))
    ax = fig.add_subplot(1, 1, 1, projection=ccrs.PlateCarree())

    ax.set_global()
    ax.add_feature(cfeature.OCEAN, color="#d1e8f0", zorder=0)
    ax.add_feature(cfeature.COASTLINE, linewidth=0.5, color="#555", zorder=3)
    ax.add_feature(cfeature.BORDERS, linewidth=0.3, color="#aaa", zorder=3)

    mesh = ax.pcolormesh(
        lon - 0.5, lat - 0.5, data,
        cmap="YlOrRd", transform=ccrs.PlateCarree(), zorder=2,
    )

    cbar = fig.colorbar(mesh, ax=ax, orientation="horizontal", pad=0.06,
                        shrink=0.6, aspect=30)
    cbar.set_label("Grid Cell Area (km²)")
    cbar.ax.xaxis.set_major_formatter(mticker.FuncFormatter(lambda x, _: f"{x:,.0f}"))

    ax.set_title("Global Wind Fishnet Area (1°×1° Grid)", pad=10)

    gl = ax.gridlines(linewidth=0.3, color="gray", alpha=0.4,
                      draw_labels=True)
    gl.top_labels = False
    gl.right_labels = False

    fig.savefig(args.output, bbox_inches="tight", facecolor="white")
    print(f"Saved to {args.output}")


if __name__ == "__main__":
    main()
