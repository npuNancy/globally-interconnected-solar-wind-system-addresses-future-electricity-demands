#!/usr/bin/env python3
"""
S02E02_Global_LandMask.py
======================

使用 Python 包 ``global-land-mask`` 生成 ``Global_LandMask.tif`` 的可复现替代版本。

输出编码
--------
- 陆地格网：0
- 海洋格网：255

输出刻意保留了下游 MATLAB 代码所使用的阈值约定::

    landmask(landmask < 100) = 0;
    landmask(landmask > 100) = 1;

空间网格
--------
- 全球 1°×1° 栅格
- 经度范围：[-180, 180]
- 纬度范围：[-90, 90]
- 像元中心：lon=-179.5,...,179.5；lat=89.5,...,-89.5
- CRS：EPSG:4326

依赖
----
    pip install global-land-mask rasterio numpy

示例
----
    python S02E02_Global_LandMask.py \\
        --output Global_LandMask.tif \\
        --print-stats

与原始文件对比
------------
    python S02E02_Global_LandMask.py \\
        --output Global_LandMask_global_land_mask.tif \\
        --reference Global_LandMask.tif \\
        --print-stats
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Iterable

import numpy as np

# ── 输出目录 ──────────────────────────────────────────────────────────────
_OUTPUT_DIR = Path(__file__).resolve().parent / "outputs"

WIDTH = 360
HEIGHT = 180
WEST = -180.0
NORTH = 90.0
RESOLUTION = 1.0
CRS = "EPSG:4326"

LAND_VALUE = np.uint8(0)
OCEAN_VALUE = np.uint8(255)
NODATA_VALUE = 255


def _import_rasterio():
    """延迟导入 rasterio，便于定位依赖错误。"""
    try:
        import rasterio
        from rasterio.transform import from_origin
    except ImportError as exc:
        raise RuntimeError(
            "缺少依赖 'rasterio'，请安装：\n"
            "  pip install rasterio"
        ) from exc
    return rasterio, from_origin


def _import_global_land_mask():
    """延迟导入 global-land-mask 并返回其 ``globe`` 模块。"""
    try:
        from global_land_mask import globe
    except ImportError as exc:
        raise RuntimeError(
            "缺少依赖 'global-land-mask'，请安装：\n"
            "  pip install global-land-mask"
        ) from exc
    return globe


def build_global_1deg_centers() -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """
    返回全球 1° 栅格的一维和二维像元中心坐标。

    Returns
    -------
    lats, lons, lat_grid, lon_grid
        ``lats`` 由北向南排列，``lons`` 由西向东排列。
        ``lat_grid`` 和 ``lon_grid`` 形状均为 ``(180, 360)``。
    """
    lons = np.arange(-179.5, 180.0, RESOLUTION, dtype=np.float64)
    lats = np.arange(89.5, -90.0, -RESOLUTION, dtype=np.float64)

    if lons.size != WIDTH or lats.size != HEIGHT:
        raise AssertionError(
            f"网格尺寸异常：lat={lats.size}, lon={lons.size}；"
            f"预期 {HEIGHT}×{WIDTH}。"
        )

    lon_grid, lat_grid = np.meshgrid(lons, lats)
    return lats, lons, lat_grid, lon_grid


def get_global_land_mask(lat_grid: np.ndarray, lon_grid: np.ndarray) -> np.ndarray:
    """使用 ``global_land_mask.globe.is_land`` 返回布尔海陆掩膜。"""
    if lat_grid.shape != lon_grid.shape:
        raise ValueError(
            f"经纬度网格形状必须一致，得到 "
            f"{lat_grid.shape} 和 {lon_grid.shape}。"
        )

    globe = _import_global_land_mask()
    is_land = np.asarray(globe.is_land(lat_grid, lon_grid), dtype=bool)

    if is_land.shape != lat_grid.shape:
        raise RuntimeError(
            f"global-land-mask 返回形状 {is_land.shape}；"
            f"预期 {lat_grid.shape}。"
        )
    return is_land


def build_global_landmask(is_land: np.ndarray) -> np.ndarray:
    """将陆地编码为 0，海洋编码为 255。"""
    if is_land.shape != (HEIGHT, WIDTH):
        raise ValueError(f"预期海陆掩膜形状 {(HEIGHT, WIDTH)}，得到 {is_land.shape}。")

    landmask = np.full(is_land.shape, OCEAN_VALUE, dtype=np.uint8)
    landmask[is_land] = LAND_VALUE

    unique_values = set(np.unique(landmask).tolist())
    expected_values = {int(LAND_VALUE), int(OCEAN_VALUE)}
    if not unique_values <= expected_values:
        raise AssertionError(
            f"landmask 中出现非预期值：{sorted(unique_values)}；"
            f"预期仅含 {sorted(expected_values)}。"
        )

    return landmask


def write_geotiff(
    output_path: Path,
    data: np.ndarray,
    *,
    overwrite: bool,
) -> None:
    """将海陆掩膜数组写入带地理参考的 GeoTIFF 文件。"""
    if data.shape != (HEIGHT, WIDTH):
        raise ValueError(f"预期输出形状 {(HEIGHT, WIDTH)}，得到 {data.shape}。")
    if data.dtype != np.uint8:
        raise TypeError(f"预期 uint8 数据，得到 {data.dtype}。")

    if output_path.exists() and not overwrite:
        raise FileExistsError(f"输出文件已存在：{output_path}\n使用 --overwrite 覆盖。")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    rasterio, from_origin = _import_rasterio()
    transform = from_origin(WEST, NORTH, RESOLUTION, RESOLUTION)

    temp_path = output_path.with_suffix(output_path.suffix + ".tmp")
    if temp_path.exists():
        temp_path.unlink()

    try:
        with rasterio.open(
            temp_path,
            "w",
            driver="GTiff",
            width=WIDTH,
            height=HEIGHT,
            count=1,
            dtype="uint8",
            crs=CRS,
            transform=transform,
            nodata=NODATA_VALUE,
            compress="deflate",
        ) as dst:
            dst.write(data, 1)
            dst.update_tags(
                generated_by="S02E02_Global_LandMask.py",
                description="全球 1° 海陆掩膜：陆地=0；海洋=255。",
                longitude_bounds="[-180, 180]",
                latitude_bounds="[-90, 90]",
                source="global-land-mask",
            )
        temp_path.replace(output_path)
    except BaseException:
        if temp_path.exists():
            temp_path.unlink()
        raise


def print_stats(landmask: np.ndarray, is_land: np.ndarray) -> None:
    """打印基本生成统计信息。"""
    total_cells = landmask.size
    land_cells = int(np.count_nonzero(is_land))
    ocean_cells = int(np.count_nonzero(~is_land))

    print("生成统计")
    print("--------")
    print(f"总格网数 : {total_cells}")
    print(f"陆地格网 : {land_cells}")
    print(f"海洋格网 : {ocean_cells}")


def compare_with_reference(generated: np.ndarray, reference_path: Path) -> None:
    """将生成的海陆分类与原始 GeoTIFF 对比。"""
    if not reference_path.exists():
        raise FileNotFoundError(f"参考文件不存在：{reference_path}")

    rasterio, _ = _import_rasterio()
    with rasterio.open(reference_path) as ds:
        reference = ds.read(1)

    if reference.shape != generated.shape:
        raise ValueError(
            f"参考文件形状 {reference.shape} 与生成结果形状 "
            f"{generated.shape} 不一致。"
        )

    generated_land = generated < 100
    reference_land = reference < 100

    same = int(np.count_nonzero(generated_land == reference_land))
    different = int(np.count_nonzero(generated_land != reference_land))
    generated_only = int(np.count_nonzero(generated_land & ~reference_land))
    reference_only = int(np.count_nonzero(~generated_land & reference_land))
    agreement = same / generated.size

    print()
    print("与原始文件对比")
    print("--------------")
    print(f"参考文件               : {reference_path}")
    print(f"生成结果陆地格网数     : {int(np.count_nonzero(generated_land))}")
    print(f"参考文件陆地格网数     : {int(np.count_nonzero(reference_land))}")
    print(f"一致格网数             : {same}")
    print(f"不一致格网数           : {different}")
    print(f"仅生成结果判定为陆地   : {generated_only}")
    print(f"仅参考文件判定为陆地   : {reference_only}")
    print(f"一致率                 : {agreement:.6f}")


def parse_args(argv: Iterable[str] | None = None) -> argparse.Namespace:
    """解析命令行参数。"""
    parser = argparse.ArgumentParser(
        description="使用 global-land-mask 生成 Global_LandMask.tif。陆地=0；海洋=255。"
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=_OUTPUT_DIR / "Global_LandMask.tif",
        help="输出 GeoTIFF 路径（默认：GlobalPotential_10km/outputs/Global_LandMask.tif）",
    )
    parser.add_argument(
        "--reference",
        type=Path,
        default=None,
        help="可选的原始 GeoTIFF，仅用于对比统计。",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="覆盖已有输出文件。",
    )
    parser.add_argument(
        "--print-stats",
        "--print_stats",
        dest="print_stats",
        action="store_true",
        help="打印生成统计信息。",
    )
    return parser.parse_args(argv)


def main(argv: Iterable[str] | None = None) -> int:
    """命令行入口。"""
    args = parse_args(argv)

    _, _, lat_grid, lon_grid = build_global_1deg_centers()
    is_land = get_global_land_mask(lat_grid, lon_grid)
    landmask = build_global_landmask(is_land)

    write_geotiff(args.output, landmask, overwrite=args.overwrite)

    print(f"[ok] 已写入 {args.output}")
    if args.print_stats:
        print_stats(landmask, is_land)
    if args.reference is not None:
        compare_with_reference(landmask, args.reference)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
