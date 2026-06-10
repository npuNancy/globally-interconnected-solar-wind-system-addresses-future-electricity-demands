"""
全球区域划分栅格升级 (1° → 0.1°)
=================================

将 Global_Grid_Division 从 180×360 (1°×1°) 升级到 1800×3600 (0.1°×0.1°)。
每个 1°×1° 网格内的 100 个 0.1°×0.1° 子网格继承相同的区域编号。

输入
----
  inputs/Global_Grid_Division.mat  或  inputs/Global_Grid_Division.tif

输出
----
  outputs/Global_Grid_Division.mat  — MATLAB 可读的 .mat 文件
  outputs/Global_Grid_Division.tif  — GeoTIFF（WGS84）

示例
----
  python S06_Global_Grid_Division.py
  python S06_Global_Grid_Division.py --source tif
  python S06_Global_Grid_Division.py --source mat
"""

from __future__ import annotations

import argparse
import os

import numpy as np

# ---------------------------------------------------------------------------
# 路径
# ---------------------------------------------------------------------------
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
INPUT_DIR = os.path.join(BASE_DIR, "inputs")
OUTPUT_DIR = os.path.join(BASE_DIR, "outputs")
os.makedirs(OUTPUT_DIR, exist_ok=True)


def load_grid_division(source: str) -> np.ndarray:
    """读取 180×360 的区域划分数组。"""
    if source == "mat":
        import scipy.io as sio

        path = os.path.join(INPUT_DIR, "Global_Grid_Division.mat")
        mat = sio.loadmat(path)
        # 尝试常见变量名
        for key in ("grid_division", "Global_Grid_Division", "grid_ind"):
            if key in mat and isinstance(mat[key], np.ndarray):
                return np.array(mat[key], dtype=np.int32)
        # 取第一个非元数据的二维数组
        for key, val in mat.items():
            if not key.startswith("_") and isinstance(val, np.ndarray) and val.ndim == 2:
                return np.array(val, dtype=np.int32)
        raise ValueError(f"无法在 {path} 中找到区域划分数组，可用键: {[k for k in mat if not k.startswith('_')]}")

    else:  # tif
        import rasterio

        path = os.path.join(INPUT_DIR, "Global_Grid_Division.tif")
        with rasterio.open(path) as src:
            data = src.read(1)
        return np.array(data, dtype=np.int32)


def upscale_nearest(grid: np.ndarray, factor: int = 10) -> np.ndarray:
    """最近邻上采样：每个像素重复 factor×factor 次。"""
    return np.repeat(np.repeat(grid, factor, axis=0), factor, axis=1)


def save_mat(grid: np.ndarray, path: str) -> None:
    """保存为 MATLAB v7.3 .mat（兼容大数组）。"""
    import scipy.io as sio

    sio.savemat(path, {"Global_Grid_Division": grid}, do_compression=True)
    print(f"  已保存: {path}  shape={grid.shape}  dtype={grid.dtype}")


def save_tif(grid: np.ndarray, path: str) -> None:
    """保存为 GeoTIFF (WGS84, 全局覆盖 0.1° 分辨率)。"""
    import rasterio
    from rasterio.transform import from_bounds

    transform = from_bounds(-180, -90, 180, 90, grid.shape[1], grid.shape[0])
    with rasterio.open(
        path,
        "w",
        driver="GTiff",
        height=grid.shape[0],
        width=grid.shape[1],
        count=1,
        dtype=np.int32,
        crs="EPSG:4326",
        transform=transform,
        compress="lzw",
    ) as dst:
        dst.write(grid, 1)
    print(f"  已保存: {path}  shape={grid.shape}  dtype={grid.dtype}")


def main() -> None:
    parser = argparse.ArgumentParser(description="全球区域划分 1°→0.1° 升级")
    parser.add_argument(
        "--source",
        choices=["mat", "tif"],
        default="tif",
        help="输入文件格式 (默认: tif)",
    )
    args = parser.parse_args()

    # 1. 读取
    print(f"[1/3] 读取输入 ({args.source}) ...")
    grid = load_grid_division(args.source)
    print(f"  输入 shape: {grid.shape}, 区域范围: [{grid.min()}, {grid.max()}]")

    # 2. 上采样
    print("[2/3] 上采样 180×360 → 1800×3600 ...")
    grid_hr = upscale_nearest(grid, factor=10)
    print(f"  输出 shape: {grid_hr.shape}")

    # 3. 保存
    print("[3/3] 保存输出 ...")
    save_mat(grid_hr, os.path.join(OUTPUT_DIR, "Global_Grid_Division.mat"))
    save_tif(grid_hr, os.path.join(OUTPUT_DIR, "Global_Grid_Division.tif"))
    print("完成!")


if __name__ == "__main__":
    main()
