#!/usr/bin/env python3
"""
S04_Global_Wind_Solar_Fishnet_Area.py
=====================================

生成全球 0.1° × 0.1° 格网的面积数据，并将同一套面积矩阵分别保存为
风电和光伏版本。

输出文件
--------
默认写入 ``GlobalPotential_10km/outputs``：

- ``Global_Wind_Fishnet_Area.tif``
- ``Global_Wind_Fishnet_Area.mat``
- ``Global_Solar_Fishnet_Area.tif``
- ``Global_Solar_Fishnet_Area.mat``

输出格式
--------
- 栅格尺寸：1800 × 3600
- 空间分辨率：0.1° × 0.1°
- 经度范围：[-180, 180]
- 纬度范围：[-90, 90]
- 像元方向：行方向北→南，列方向西→东
- 数据类型：float64
- 面积单位：km²
- CRS：EPSG:4326
- MAT 变量名：data

计算方法
--------
使用 WGS84 椭球上的多边形面积直接计算每个纬度带中的单个格网面积。
由于同一纬度带内各经度格网面积相同，只需计算 1800 次，然后沿经度
方向广播到 3600 列。脚本不依赖旧版 1° × 1° 面积数据，也不使用简单
上采样或父格网面积除以 100 的近似方法。

依赖
----
    pip install numpy scipy rasterio pyproj

示例
----
生成四个文件并打印统计信息：

    python S04_Global_Wind_Solar_Fishnet_Area.py \
        --overwrite \
        --print-stats

将结果聚合回 1° 并与旧版参考 TIF 做诊断性对比：

    python S04_Global_Wind_Solar_Fishnet_Area.py \
        --overwrite \
        --print-stats \
        --reference-1deg-tif /path/to/Global_Wind_Fishnet_Area.tif
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Iterable

import numpy as np

# ── 输出目录与固定网格参数 ────────────────────────────────────────────────
BASE_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = BASE_DIR / "outputs"

WIDTH = 3600
HEIGHT = 1800
WEST = -180.0
NORTH = 90.0
RESOLUTION = 0.1
CRS = "EPSG:4326"

WIND_TIF_NAME = "Global_Wind_Fishnet_Area.tif"
WIND_MAT_NAME = "Global_Wind_Fishnet_Area.mat"
SOLAR_TIF_NAME = "Global_Solar_Fishnet_Area.tif"
SOLAR_MAT_NAME = "Global_Solar_Fishnet_Area.mat"

EXPECTED_SHAPE = (HEIGHT, WIDTH)
EXPECTED_DTYPE = np.dtype(np.float64)

# 基于 WGS84 椭球直接计算时的诊断性参考值。仅用于打印说明，不作为
# 严格断言，以避免不同底层库版本产生的微小浮点差异。
EXPECTED_MIN_AREA_KM2 = 0.10887
EXPECTED_MAX_AREA_KM2 = 123.09069
EXPECTED_GLOBAL_AREA_KM2 = 510_065_622.0


def _import_rasterio():
    """延迟导入 rasterio，便于在缺包时给出清晰错误信息。"""
    try:
        import rasterio
        from rasterio.transform import from_origin
    except ImportError as exc:  # pragma: no cover - 依赖错误与环境相关
        raise RuntimeError("缺少依赖 'rasterio'，请安装：\n" "  pip install rasterio") from exc
    return rasterio, from_origin


def _import_pyproj():
    """延迟导入 pyproj，便于在缺包时给出清晰错误信息。"""
    try:
        from pyproj import Geod
    except ImportError as exc:  # pragma: no cover - 依赖错误与环境相关
        raise RuntimeError("缺少依赖 'pyproj'，请安装：\n" "  pip install pyproj") from exc
    return Geod


def _import_scipy_io():
    """延迟导入 scipy.io，便于在缺包时给出清晰错误信息。"""
    try:
        import scipy.io as sio
    except ImportError as exc:  # pragma: no cover - 依赖错误与环境相关
        raise RuntimeError("缺少依赖 'scipy'，请安装：\n" "  pip install scipy") from exc
    return sio


def build_global_01deg_cell_area() -> np.ndarray:
    """
    生成全球 0.1° × 0.1° 格网面积矩阵，单位为 km²。

    Returns
    -------
    numpy.ndarray
        形状为 ``(1800, 3600)`` 的 ``float64`` 数组。行方向由北向南，
        列方向由西向东。

    Notes
    -----
    函数名中的 ``01deg`` 表示 ``0.1 degree``。同一纬度带内各经度格网
    面积相同，因此仅计算 1800 个纬度行，再沿经度方向广播。
    """
    Geod = _import_pyproj()
    geod = Geod(ellps="WGS84")

    row_areas = np.empty(HEIGHT, dtype=np.float64)
    west = WEST
    east = WEST + RESOLUTION

    for row in range(HEIGHT):
        north = NORTH - row * RESOLUTION
        south = north - RESOLUTION

        # pyproj.Geod.polygon_area_perimeter 会自动闭合多边形。
        lons = [west, east, east, west]
        lats = [south, south, north, north]
        area_m2, _ = geod.polygon_area_perimeter(lons, lats)
        row_areas[row] = abs(area_m2) / 1_000_000.0

    # np.broadcast_to 会返回只读视图。写出前转为连续数组，避免第三方库
    # 因非连续内存或只读标记出现兼容性问题。
    area_grid = np.broadcast_to(row_areas[:, np.newaxis], EXPECTED_SHAPE).copy()
    validate_area_grid(area_grid)
    return area_grid


def validate_area_grid(data: np.ndarray) -> None:
    """校验面积矩阵的尺寸、类型、数值范围和纬度变化规律。"""
    if data.shape != EXPECTED_SHAPE:
        raise ValueError(f"预期输出形状 {EXPECTED_SHAPE}，得到 {data.shape}。")
    if data.dtype != EXPECTED_DTYPE:
        raise TypeError(f"预期 float64 数据，得到 {data.dtype}。")
    if not np.all(np.isfinite(data)):
        raise ValueError("面积矩阵中存在 NaN 或 Inf。")
    if not np.all(data > 0.0):
        raise ValueError("面积矩阵中存在非正值。")

    row_areas = data[:, 0]

    # 同一纬度带内面积必须完全一致。
    if not np.all(data == row_areas[:, np.newaxis]):
        raise AssertionError("同一纬度带内出现不一致的格网面积。")

    # WGS84 椭球下，南北半球对应纬度带应基本对称。
    if not np.allclose(row_areas, row_areas[::-1], rtol=0.0, atol=1e-8):
        max_diff = float(np.max(np.abs(row_areas - row_areas[::-1])))
        raise AssertionError("南北半球对应纬度带面积不对称：" f"最大绝对差为 {max_diff:.12g} km²。")

    # 赤道附近最大，两极附近最小。
    equatorial_max = max(float(row_areas[HEIGHT // 2 - 1]), float(row_areas[HEIGHT // 2]))
    polar_min = min(float(row_areas[0]), float(row_areas[-1]))
    if not np.isclose(float(np.max(row_areas)), equatorial_max, rtol=0.0, atol=1e-10):
        raise AssertionError("面积最大值未出现在赤道附近。")
    if not np.isclose(float(np.min(row_areas)), polar_min, rtol=0.0, atol=1e-10):
        raise AssertionError("面积最小值未出现在两极附近。")


def _temp_path_for(output_path: Path) -> Path:
    """返回与正式文件位于同一目录的临时文件路径。"""
    return output_path.with_name(output_path.name + ".tmp")


def _check_overwrite(output_path: Path, *, overwrite: bool) -> None:
    """在写出前检查覆盖策略。"""
    if output_path.exists() and not overwrite:
        raise FileExistsError(f"输出文件已存在：{output_path}\n" "使用 --overwrite 覆盖。")


def write_geotiff(output_path: Path, data: np.ndarray, *, overwrite: bool) -> None:
    """将面积矩阵写入带地理参考的 GeoTIFF。"""
    validate_area_grid(data)
    _check_overwrite(output_path, overwrite=overwrite)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    rasterio, from_origin = _import_rasterio()
    transform = from_origin(WEST, NORTH, RESOLUTION, RESOLUTION)
    temp_path = _temp_path_for(output_path)

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
            dtype="float64",
            crs=CRS,
            transform=transform,
            nodata=None,
            compress="deflate",
            predictor=3,
        ) as dst:
            dst.write(data, 1)
            dst.update_tags(
                AREA_OR_POINT="Area",
                generated_by="S04_Global_Wind_Solar_Fishnet_Area.py",
                description="Global 0.1-degree grid-cell area in km^2.",
                units="km^2",
                longitude_bounds="[-180, 180]",
                latitude_bounds="[-90, 90]",
            )
        temp_path.replace(output_path)
    except BaseException:
        if temp_path.exists():
            temp_path.unlink()
        raise


def write_mat(output_path: Path, data: np.ndarray, *, overwrite: bool) -> None:
    """将面积矩阵写入 MATLAB MAT 文件，变量名固定为 ``data``。"""
    validate_area_grid(data)
    _check_overwrite(output_path, overwrite=overwrite)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    sio = _import_scipy_io()
    temp_path = _temp_path_for(output_path)

    if temp_path.exists():
        temp_path.unlink()

    try:
        # temp_path 以 .tmp 结尾，因此必须设置 appendmat=False，避免 scipy
        # 自动额外添加 .mat 后缀，导致原子替换找不到临时文件。
        sio.savemat(
            temp_path,
            {"data": data},
            appendmat=False,
            do_compression=True,
        )
        temp_path.replace(output_path)
    except BaseException:
        if temp_path.exists():
            temp_path.unlink()
        raise


def get_output_paths(output_dir: Path) -> dict[str, Path]:
    """返回四个输出文件的路径。"""
    return {
        "wind_tif": output_dir / WIND_TIF_NAME,
        "wind_mat": output_dir / WIND_MAT_NAME,
        "solar_tif": output_dir / SOLAR_TIF_NAME,
        "solar_mat": output_dir / SOLAR_MAT_NAME,
    }


def _preflight_outputs(output_paths: dict[str, Path], *, overwrite: bool) -> None:
    """在开始写文件前统一检查已有文件，避免无覆盖权限时产生部分输出。"""
    if overwrite:
        return

    existing = [path for path in output_paths.values() if path.exists()]
    if existing:
        formatted = "\n".join(f"  - {path}" for path in existing)
        raise FileExistsError("以下输出文件已存在：\n" f"{formatted}\n" "使用 --overwrite 覆盖。")


def write_all_outputs(
    output_dir: Path,
    data: np.ndarray,
    *,
    overwrite: bool,
) -> dict[str, Path]:
    """将同一个面积矩阵分别写为风电和光伏的 TIF 与 MAT 文件。"""
    validate_area_grid(data)
    output_dir.mkdir(parents=True, exist_ok=True)
    output_paths = get_output_paths(output_dir)
    _preflight_outputs(output_paths, overwrite=overwrite)

    write_geotiff(output_paths["wind_tif"], data, overwrite=overwrite)
    print(f"[ok] 已写入 {output_paths['wind_tif']}")

    write_mat(output_paths["wind_mat"], data, overwrite=overwrite)
    print(f"[ok] 已写入 {output_paths['wind_mat']}")

    write_geotiff(output_paths["solar_tif"], data, overwrite=overwrite)
    print(f"[ok] 已写入 {output_paths['solar_tif']}")

    write_mat(output_paths["solar_mat"], data, overwrite=overwrite)
    print(f"[ok] 已写入 {output_paths['solar_mat']}")

    return output_paths


def _read_and_validate_geotiff(output_path: Path) -> np.ndarray:
    """读取输出 TIF，并校验地理参考与数据格式。"""
    rasterio, from_origin = _import_rasterio()
    expected_transform = from_origin(WEST, NORTH, RESOLUTION, RESOLUTION)

    with rasterio.open(output_path) as ds:
        if ds.count != 1:
            raise AssertionError(f"{output_path} 波段数异常：{ds.count}。")
        if (ds.height, ds.width) != EXPECTED_SHAPE:
            raise AssertionError(f"{output_path} 形状异常：{(ds.height, ds.width)}，" f"预期 {EXPECTED_SHAPE}。")
        if ds.dtypes[0] != "float64":
            raise AssertionError(f"{output_path} dtype 异常：{ds.dtypes[0]}。")
        if ds.crs is None or ds.crs.to_string() != CRS:
            raise AssertionError(f"{output_path} CRS 异常：{ds.crs}。")
        if ds.transform != expected_transform:
            raise AssertionError(f"{output_path} transform 异常：{ds.transform}，" f"预期 {expected_transform}。")
        if not np.allclose(ds.bounds, (-180.0, -90.0, 180.0, 90.0), atol=1e-12):
            raise AssertionError(f"{output_path} bounds 异常：{ds.bounds}。")
        if not np.allclose(ds.res, (RESOLUTION, RESOLUTION), atol=1e-12):
            raise AssertionError(f"{output_path} resolution 异常：{ds.res}。")
        if ds.nodata is not None:
            raise AssertionError(f"{output_path} nodata 应为 None，得到 {ds.nodata}。")

        tags = ds.tags()
        if tags.get("AREA_OR_POINT") != "Area":
            raise AssertionError(f"{output_path} 的 AREA_OR_POINT 标签异常：" f"{tags.get('AREA_OR_POINT')!r}。")

        data = ds.read(1)

    validate_area_grid(data)
    return data


def _read_and_validate_mat(output_path: Path) -> np.ndarray:
    """读取输出 MAT，并校验变量名与数据格式。"""
    sio = _import_scipy_io()
    content = sio.loadmat(output_path)

    if "data" not in content:
        variables = sorted(key for key in content if not key.startswith("__"))
        raise AssertionError(f"{output_path} 中缺少变量 'data'；现有变量：{variables}。")

    data = np.asarray(content["data"])
    validate_area_grid(data)
    return data


def validate_written_outputs(output_paths: dict[str, Path], expected: np.ndarray) -> None:
    """重新读取四个输出文件，并确认其矩阵与生成结果逐像元完全一致。"""
    validate_area_grid(expected)

    readers = {
        "wind_tif": _read_and_validate_geotiff,
        "wind_mat": _read_and_validate_mat,
        "solar_tif": _read_and_validate_geotiff,
        "solar_mat": _read_and_validate_mat,
    }

    for name, reader in readers.items():
        path = output_paths[name]
        actual = reader(path)
        if not np.array_equal(actual, expected):
            max_abs_diff = float(np.max(np.abs(actual - expected)))
            raise AssertionError(f"{path} 与生成面积矩阵不一致：" f"最大绝对差为 {max_abs_diff:.12g} km²。")

    print("[ok] 四个输出文件已通过一致性校验：TIF、MAT、风电、光伏逐像元完全一致。")


def print_stats(data: np.ndarray) -> None:
    """打印面积矩阵的核心统计信息。"""
    validate_area_grid(data)

    min_area = float(np.min(data))
    max_area = float(np.max(data))
    total_area = float(np.sum(data, dtype=np.float64))
    equator_area = float(data[HEIGHT // 2, 0])
    north_pole_area = float(data[0, 0])
    south_pole_area = float(data[-1, 0])

    print()
    print("生成统计")
    print("--------")
    print(f"shape                 : {data.shape}")
    print(f"dtype                 : {data.dtype}")
    print(f"分辨率                : {RESOLUTION}° × {RESOLUTION}°")
    print(f"面积单位              : km²")
    print(f"最小格网面积          : {min_area:.12f} km²")
    print(f"最大格网面积          : {max_area:.12f} km²")
    print(f"赤道附近格网面积      : {equator_area:.12f} km²")
    print(f"北极附近格网面积      : {north_pole_area:.12f} km²")
    print(f"南极附近格网面积      : {south_pole_area:.12f} km²")
    print(f"全球格网面积总和      : {total_area:.6f} km²")
    print()
    print("WGS84 参考值（诊断用）")
    print("---------------------")
    print(f"最小格网面积约        : {EXPECTED_MIN_AREA_KM2:.5f} km²")
    print(f"最大格网面积约        : {EXPECTED_MAX_AREA_KM2:.5f} km²")
    print(f"全球格网面积总和约    : {EXPECTED_GLOBAL_AREA_KM2:,.0f} km²")


def compare_with_1deg_reference(data: np.ndarray, reference_tif: Path) -> None:
    """
    将 0.1° 面积按 10 × 10 聚合回 1°，并与旧版参考 TIF 做诊断性对比。

    该函数只输出差异报告，不会将旧版文件用于面积生成，也不会强制要求
    两者完全一致。
    """
    validate_area_grid(data)
    if not reference_tif.exists():
        raise FileNotFoundError(f"参考文件不存在：{reference_tif}")

    rasterio, _ = _import_rasterio()
    with rasterio.open(reference_tif) as ds:
        reference = np.asarray(ds.read(1), dtype=np.float64)

    aggregated = data.reshape(180, 10, 360, 10).sum(axis=(1, 3))
    if reference.shape != aggregated.shape:
        raise ValueError(f"参考文件形状 {reference.shape} 与聚合后的形状 " f"{aggregated.shape} 不一致。")
    if not np.all(np.isfinite(reference)):
        raise ValueError(f"参考文件中存在 NaN 或 Inf：{reference_tif}")

    abs_diff = np.abs(aggregated - reference)
    nonzero_reference = reference != 0.0
    if np.any(nonzero_reference):
        relative_diff = abs_diff[nonzero_reference] / np.abs(reference[nonzero_reference])
        mean_relative_diff = float(np.mean(relative_diff))
        max_relative_diff = float(np.max(relative_diff))
    else:
        mean_relative_diff = float("nan")
        max_relative_diff = float("nan")

    print()
    print("与旧版 1° GeoTIFF 的诊断性对比")
    print("-------------------------------")
    print(f"参考文件              : {reference_tif}")
    print(f"参考文件 shape        : {reference.shape}")
    print(f"0.1° 聚合后 shape     : {aggregated.shape}")
    print(f"最大绝对差            : {float(np.max(abs_diff)):.12f} km²")
    print(f"平均绝对差            : {float(np.mean(abs_diff)):.12f} km²")
    print(f"平均相对差            : {mean_relative_diff:.8%}")
    print(f"最大相对差            : {max_relative_diff:.8%}")
    print(f"新版聚合面积总和      : {float(np.sum(aggregated)):.6f} km²")
    print(f"旧版参考面积总和      : {float(np.sum(reference)):.6f} km²")
    print(f"总面积差              : {float(np.sum(aggregated) - np.sum(reference)):.6f} km²")
    print("说明                  : 该差异仅用于诊断，不参与生成逻辑。")


def parse_args(argv: Iterable[str] | None = None) -> argparse.Namespace:
    """解析命令行参数。"""
    parser = argparse.ArgumentParser(
        description=("生成全球 0.1° × 0.1° 格网面积，并将同一面积矩阵分别保存为" "风电和光伏的 GeoTIFF 与 MAT 文件。")
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=OUTPUT_DIR,
        help=("输出目录。默认：脚本所在目录下的 outputs/，即 " "GlobalPotential_10km/outputs/。"),
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
        help="打印 shape、dtype、面积范围和全球面积总和。",
    )
    parser.add_argument(
        "--reference-1deg-tif",
        "--reference_1deg_tif",
        "--reference",
        dest="reference_1deg_tif",
        type=Path,
        default=None,
        help=("可选的旧版 1° 面积 GeoTIFF。脚本会将生成结果聚合回 1° 并输出" "差异报告；该文件不参与生成逻辑。"),
    )
    return parser.parse_args(argv)


def main(argv: Iterable[str] | None = None) -> int:
    """命令行入口。"""
    args = parse_args(argv)

    print("开始计算全球 0.1° × 0.1° 格网面积……")
    area_grid = build_global_01deg_cell_area()
    print("[ok] 面积矩阵计算完成。")

    if args.print_stats:
        print_stats(area_grid)

    output_paths = write_all_outputs(
        args.output_dir,
        area_grid,
        overwrite=args.overwrite,
    )
    validate_written_outputs(output_paths, area_grid)

    if args.reference_1deg_tif is not None:
        compare_with_1deg_reference(area_grid, args.reference_1deg_tif)

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # pragma: no cover - 命令行错误处理
        print(f"[error] {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
