#!/usr/bin/env python3
"""
S04_Global_fishnet.py
=====================

使用 Python 包 ``global-land-mask`` 生成 ``Global_fishnet.tif`` 的可复现简化替代版本。

输出编码
--------
- 普通陆地格网：0
- 海洋格网：65536
- 格陵兰格网：65536
- 南极洲格网：65536

下游 MATLAB 代码仅使用::

    solar_index = find(grids < 65536);

因此无需复现原始 ArcGIS 的 fishnet 编号。

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
    python S04_Global_fishnet.py \\
        --output Global_fishnet.tif \\
        --print-stats

与原始文件对比
------------
    python S04_Global_fishnet.py \\
        --output Global_fishnet_global_land_mask.tif \\
        --reference Global_fishnet.tif \\
        --print-stats
"""

from __future__ import annotations

import argparse
from collections import deque
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

VALID_LAND_VALUE = np.uint32(0)
INVALID_VALUE = np.uint32(65536)
NODATA_VALUE = 65536

# 格陵兰保守包围盒。
# 从内部种子点做四邻域洪泛填充，避免误排除冰岛或加拿大北极群岛。
GREENLAND_LAT_MIN = 59.0
GREENLAND_LAT_MAX = 84.0
GREENLAND_LON_MIN = -74.0
GREENLAND_LON_MAX = -10.0
GREENLAND_SEED_LAT = 72.5
GREENLAND_SEED_LON = -40.5

# 南极洲排除规则。1° 分辨率下此简单纬度规则清晰且可复现。
ANTARCTICA_MAX_LAT = -60.0


def _import_rasterio():
    """延迟导入 rasterio，便于定位依赖错误。"""
    try:
        import rasterio
        from rasterio.transform import from_origin
    except ImportError as exc:  # pragma: no cover - 环境相关
        raise RuntimeError(
            "缺少依赖 'rasterio'，请安装：\n"
            "  pip install rasterio"
        ) from exc
    return rasterio, from_origin


def _import_global_land_mask():
    """延迟导入 global-land-mask 并返回其 ``globe`` 模块。"""
    try:
        from global_land_mask import globe
    except ImportError as exc:  # pragma: no cover - 环境相关
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


def nearest_grid_index(values: np.ndarray, target: float) -> int:
    """返回一维坐标轴上距离目标值最近的像元中心索引。"""
    if values.ndim != 1 or values.size == 0:
        raise ValueError("values 必须是非空的一维坐标数组。")
    return int(np.argmin(np.abs(values - target)))


def flood_fill_4_connected(mask: np.ndarray, seed_row: int, seed_col: int) -> np.ndarray:
    """
    返回包含 ``(seed_row, seed_col)`` 的四邻域连通分量。

    Parameters
    ----------
    mask
        布尔候选掩膜。
    seed_row, seed_col
        种子像元索引。

    Notes
    -----
    刻意使用四邻域而非八邻域，以降低 1° 分辨率下穿越狭窄对角缝隙
    将不同岛屿错误连通的风险。
    """
    if mask.ndim != 2:
        raise ValueError(f"mask 必须为二维，得到形状 {mask.shape}。")

    nrows, ncols = mask.shape
    if not (0 <= seed_row < nrows and 0 <= seed_col < ncols):
        raise IndexError(
            f"种子点 ({seed_row}, {seed_col}) 超出掩膜范围 {mask.shape}。"
        )
    if not bool(mask[seed_row, seed_col]):
        raise ValueError(
            "格陵兰种子点未被 global-land-mask 判定为陆地。"
            "请检查种子坐标或输入网格。"
        )

    component = np.zeros(mask.shape, dtype=bool)
    component[seed_row, seed_col] = True
    queue: deque[tuple[int, int]] = deque([(seed_row, seed_col)])

    while queue:
        row, col = queue.popleft()
        for next_row, next_col in (
            (row - 1, col),
            (row + 1, col),
            (row, col - 1),
            (row, col + 1),
        ):
            if (
                0 <= next_row < nrows
                and 0 <= next_col < ncols
                and mask[next_row, next_col]
                and not component[next_row, next_col]
            ):
                component[next_row, next_col] = True
                queue.append((next_row, next_col))

    return component


def build_greenland_mask(
    is_land: np.ndarray,
    lat_grid: np.ndarray,
    lon_grid: np.ndarray,
    *,
    seed_lat: float = GREENLAND_SEED_LAT,
    seed_lon: float = GREENLAND_SEED_LON,
) -> np.ndarray:
    """
    通过包围盒 + 四邻域洪泛填充识别格陵兰。
    """
    if not (is_land.shape == lat_grid.shape == lon_grid.shape):
        raise ValueError("is_land、lat_grid、lon_grid 形状必须一致。")

    greenland_bbox = (
        (lat_grid >= GREENLAND_LAT_MIN)
        & (lat_grid <= GREENLAND_LAT_MAX)
        & (lon_grid >= GREENLAND_LON_MIN)
        & (lon_grid <= GREENLAND_LON_MAX)
    )
    candidates = is_land & greenland_bbox

    lats = lat_grid[:, 0]
    lons = lon_grid[0, :]
    seed_row = nearest_grid_index(lats, seed_lat)
    seed_col = nearest_grid_index(lons, seed_lon)

    if not candidates[seed_row, seed_col]:
        raise ValueError(
            "格陵兰种子点在包围盒内未被判定为陆地。"
            f"种子坐标=({seed_lat}, {seed_lon})，"
            f"最近像元中心=({lats[seed_row]}, {lons[seed_col]})。"
        )

    return flood_fill_4_connected(candidates, seed_row, seed_col)


def build_antarctica_mask(lat_grid: np.ndarray) -> np.ndarray:
    """返回南纬 60° 及以南的掩膜。"""
    return np.asarray(lat_grid <= ANTARCTICA_MAX_LAT, dtype=bool)


def build_global_fishnet(
    is_land: np.ndarray,
    lat_grid: np.ndarray,
    lon_grid: np.ndarray,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """
    构建简化的 Global_fishnet 栅格。

    Returns
    -------
    fishnet, greenland_mask, antarctica_mask
    """
    if not (is_land.shape == lat_grid.shape == lon_grid.shape):
        raise ValueError("is_land、lat_grid、lon_grid 形状必须一致。")

    fishnet = np.full(is_land.shape, INVALID_VALUE, dtype=np.uint32)
    fishnet[is_land] = VALID_LAND_VALUE

    greenland_mask = build_greenland_mask(is_land, lat_grid, lon_grid)
    antarctica_mask = build_antarctica_mask(lat_grid)

    fishnet[greenland_mask] = INVALID_VALUE
    fishnet[antarctica_mask] = INVALID_VALUE

    unique_values = set(np.unique(fishnet).tolist())
    expected_values = {int(VALID_LAND_VALUE), int(INVALID_VALUE)}
    if not unique_values <= expected_values:
        raise AssertionError(
            f"fishnet 中出现非预期值：{sorted(unique_values)}；"
            f"预期仅含 {sorted(expected_values)}。"
        )

    return fishnet, greenland_mask, antarctica_mask


def write_geotiff(
    output_path: Path,
    data: np.ndarray,
    *,
    overwrite: bool,
) -> None:
    """将 fishnet 数组写入带地理参考的 GeoTIFF 文件。"""
    if data.shape != (HEIGHT, WIDTH):
        raise ValueError(
            f"预期输出形状 {(HEIGHT, WIDTH)}，得到 {data.shape}。"
        )
    if data.dtype != np.uint32:
        raise TypeError(f"预期 uint32 数据，得到 {data.dtype}。")

    if output_path.exists() and not overwrite:
        raise FileExistsError(
            f"输出文件已存在：{output_path}\n"
            "使用 --overwrite 覆盖。"
        )

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
            dtype="uint32",
            crs=CRS,
            transform=transform,
            nodata=NODATA_VALUE,
            compress="deflate",
        ) as dst:
            dst.write(data, 1)
            dst.update_tags(
                generated_by="S04_Global_fishnet.py",
                description=(
                    "简化的全球 1° 光伏候选陆地掩膜："
                    "普通陆地=0；海洋、格陵兰、南极洲=65536。"
                ),
                longitude_bounds="[-180, 180]",
                latitude_bounds="[-90, 90]",
                source="global-land-mask",
            )
        temp_path.replace(output_path)
    except BaseException:
        if temp_path.exists():
            temp_path.unlink()
        raise


def print_stats(
    fishnet: np.ndarray,
    is_land: np.ndarray,
    greenland_mask: np.ndarray,
    antarctica_mask: np.ndarray,
) -> None:
    """打印基本生成统计信息。"""
    total_cells = fishnet.size
    land_before = int(np.count_nonzero(is_land))
    ocean_cells = int(np.count_nonzero(~is_land))
    greenland_excluded = int(np.count_nonzero(greenland_mask))
    antarctica_land_excluded = int(np.count_nonzero(antarctica_mask & is_land))
    valid_after = int(np.count_nonzero(fishnet < INVALID_VALUE))
    invalid_after = int(np.count_nonzero(fishnet == INVALID_VALUE))

    print("生成统计")
    print("--------")
    print(f"总格网数                      : {total_cells}")
    print(f"排除前陆地格网数              : {land_before}")
    print(f"海洋格网数                    : {ocean_cells}")
    print(f"格陵兰排除的陆地格网数        : {greenland_excluded}")
    print(f"南极洲排除的陆地格网数        : {antarctica_land_excluded}")
    print(f"排除后有效 fishnet 格网数     : {valid_after}")
    print(f"无效格网数                    : {invalid_after}")


def compare_with_reference(generated: np.ndarray, reference_path: Path) -> None:
    """将生成的有效格网掩膜与原始 fishnet GeoTIFF 对比。"""
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

    generated_valid = generated < INVALID_VALUE
    reference_valid = reference < NODATA_VALUE

    same = int(np.count_nonzero(generated_valid == reference_valid))
    different = int(np.count_nonzero(generated_valid != reference_valid))
    generated_only = int(np.count_nonzero(generated_valid & ~reference_valid))
    reference_only = int(np.count_nonzero(~generated_valid & reference_valid))
    agreement = same / generated.size

    print()
    print("与原始文件对比")
    print("--------------")
    print(f"参考文件               : {reference_path}")
    print(f"生成结果有效格网数     : {int(np.count_nonzero(generated_valid))}")
    print(f"参考文件有效格网数     : {int(np.count_nonzero(reference_valid))}")
    print(f"一致格网数             : {same}")
    print(f"不一致格网数           : {different}")
    print(f"仅生成结果有效         : {generated_only}")
    print(f"仅参考文件有效         : {reference_only}")
    print(f"一致率                 : {agreement:.6f}")


def parse_args(argv: Iterable[str] | None = None) -> argparse.Namespace:
    """解析命令行参数。"""
    parser = argparse.ArgumentParser(
        description=(
            "使用 global-land-mask 生成 Global_fishnet.tif。"
            "普通陆地=0；海洋、格陵兰、南极洲=65536。"
        )
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=_OUTPUT_DIR / "Global_fishnet.tif",
        help="输出 GeoTIFF 路径（默认：GlobalPotential_10km/outputs/Global_fishnet.tif）",
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
    fishnet, greenland_mask, antarctica_mask = build_global_fishnet(
        is_land, lat_grid, lon_grid
    )

    write_geotiff(args.output, fishnet, overwrite=args.overwrite)

    print(f"[ok] 已写入 {args.output}")
    if args.print_stats:
        print_stats(fishnet, is_land, greenland_mask, antarctica_mask)
    if args.reference is not None:
        compare_with_reference(fishnet, args.reference)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
