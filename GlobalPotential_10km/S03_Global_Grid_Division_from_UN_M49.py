#!/usr/bin/env python3
"""
基于 UN M49 与 Natural Earth 重新生成全球区域划分栅格
===================================================

脚本名称：
    S03_Global_Grid_Division_from_UN_M49.py

目标：
    生成全球 0.1° × 0.1° 的区域划分栅格，对应论文
    “Globally Interconnected Solar-wind System Addresses Future Electricity Demands”
    使用的 20 个区域电网。

与旧版脚本的区别：
    旧版脚本只是把原论文的 1° × 1° 区域栅格直接重复放大到 0.1° × 0.1°，
    因此每个 1° 父格网内部的 100 个子格网都继承同一个区域编号。

    本脚本会读取 Natural Earth 国家边界，并使用其 SUBREGION 字段将陆地区域
    重新栅格化到目标分辨率，从而改善国界和海岸线附近的区域归属精度。

为何仍需读取原论文的 1° 栅格：
    Natural Earth 国家边界只能直接确定陆地国家的区域归属。对于海洋像元、
    小岛屿、南极洲、Micronesia、Polynesia，以及未能安全映射的特殊区域，
    本脚本会使用原论文 1° Global_Grid_Division.tif 的最近邻重采样结果作为
    兼容性回退值。这样既能细化陆地区域边界，也能尽量保留原论文的海上风电
    和跨区域调度逻辑。

默认输入位置：
    data/natural_earth/ne_110m_admin_0_countries.shp
    ../data/natural_earth/ne_110m_admin_0_countries.shp
    inputs/Global_Grid_Division.tif
    ../Optimization/Global_Grid_Division.tif

默认输出位置：
    outputs/Global_Grid_Division.tif
    outputs/Global_Grid_Division.mat
    outputs/country_to_region.csv
    outputs/region_id_to_name.json
    outputs/Global_Grid_Division_from_UN_M49_report.json

运行示例：
    # 自动搜索输入文件
    python S03_Global_Grid_Division_from_UN_M49.py \
        --overwrite \
        --print-stats

    # 显式指定输入文件
    python S03_Global_Grid_Division_from_UN_M49.py \
        --natural-earth-shp ../data/natural_earth/ne_110m_admin_0_countries.shp \
        --reference-1deg-tif ../Optimization/Global_Grid_Division.tif \
        --overwrite \
        --print-stats

    # 后续获得更精细的 Natural Earth 数据后，可直接替换 shp 文件
    python S03_Global_Grid_Division_from_UN_M49.py \
        --natural-earth-shp ../data/natural_earth/ne_10m_admin_0_countries.shp \
        --reference-1deg-tif ../Optimization/Global_Grid_Division.tif \
        --overwrite \
        --print-stats

可选国家覆盖表：
    参数 --country-overrides-csv 可传入 UTF-8 CSV 文件。CSV 必须包含
    region_id 列，并至少包含一个国家标识列，例如 ADM0_A3、ISO_A3、
    SOV_A3、NAME 或 NAME_LONG。

    示例：
        ADM0_A3,region_id,note
        KOS,7,将 Kosovo 指定为 Southern Europe

    该机制适用于处理争议地区或不同 Natural Earth 版本之间的字段差异。
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import sys
import unicodedata
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping, Sequence

import numpy as np

# ============================================================================
# 全局常量
# ============================================================================

BASE_DIR = Path(__file__).resolve().parent
DEFAULT_OUTPUT_DIR = BASE_DIR / "outputs"

DEFAULT_RESOLUTION = 0.1
WEST = -180.0
SOUTH = -90.0
EAST = 180.0
NORTH = 90.0
TARGET_CRS = "EPSG:4326"

# 论文使用的 20 个区域电网。编号顺序必须与 Global_Grid_Division.tif 保持一致。
REGION_ID_TO_NAME: dict[int, str] = {
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

# Natural Earth 的 SUBREGION 字段与论文区域编号之间的映射。
# 为兼容不同版本的拼写差异，保留若干同义写法。
SUBREGION_TO_REGION_ID_RAW: dict[str, int] = {
    "Northern America": 1,
    "Central America": 2,
    "Caribbean": 3,
    "South America": 4,
    "Northern Europe": 5,
    "Western Europe": 6,
    "Southern Europe": 7,
    "Eastern Europe": 8,
    "Central Asia": 9,
    "Eastern Asia": 10,
    "Western Asia": 11,
    "Southern Asia": 12,
    "South-eastern Asia": 13,
    "South-Eastern Asia": 13,
    "South Eastern Asia": 13,
    "Southeastern Asia": 13,
    "Melanesia": 14,
    "Australia and New Zealand": 15,
    "Australia-New Zealand": 15,
    "Australia / New Zealand": 15,
    "Northern Africa": 16,
    "Western Africa": 17,
    "Middle Africa": 18,
    "Eastern Africa": 19,
    "Southern Africa": 20,
}

# 论文没有将 Micronesia 和 Polynesia 单独建模为区域电网。
# 这些区域会保留原论文栅格中的回退编号，而不是通过国家边界覆盖。
INTENTIONALLY_OMITTED_SUBREGIONS_RAW = {
    "Micronesia",
    "Polynesia",
    "Antarctica",
    "Seven seas (open ocean)",
    "Seven Seas (open ocean)",
}

# 可用于覆盖特殊国家映射的字段。
IDENTIFIER_FIELDS = ("ADM0_A3", "ISO_A3", "SOV_A3", "NAME", "NAME_LONG")


# ============================================================================
# 第三方依赖：延迟导入并提供明确的安装提示
# ============================================================================


def _import_rasterio():
    """导入 rasterio 及其常用组件。"""
    try:
        import rasterio
        from rasterio.crs import CRS
        from rasterio.features import rasterize
        from rasterio.transform import from_origin
        from rasterio.warp import Resampling, reproject, transform_geom
    except ImportError as exc:
        raise RuntimeError("缺少 rasterio。请执行：pip install rasterio") from exc

    return rasterio, CRS, rasterize, from_origin, Resampling, reproject, transform_geom


def _import_fiona():
    """导入 fiona。"""
    try:
        import fiona
    except ImportError as exc:
        raise RuntimeError("缺少 fiona。请执行：pip install fiona") from exc

    return fiona


def _import_scipy_io():
    """导入 scipy.io。"""
    try:
        import scipy.io as sio
    except ImportError as exc:
        raise RuntimeError("缺少 scipy。请执行：pip install scipy") from exc

    return sio


# ============================================================================
# 数据结构
# ============================================================================


@dataclass(frozen=True)
class CountryFeature:
    """Natural Earth 中一个国家或地区要素的映射结果。"""

    feature_index: int
    geometry: Mapping[str, Any]
    name: str
    name_long: str
    adm0_a3: str
    iso_a3: str
    sov_a3: str
    subregion_raw: str
    region_id: int
    region_name: str
    assignment_status: str
    assignment_source: str


@dataclass(frozen=True)
class TargetGrid:
    """目标栅格的基本参数。"""

    resolution: float
    height: int
    width: int
    transform: Any


# ============================================================================
# 文本归一化与区域映射
# ============================================================================


def _normalize_text(value: Any) -> str:
    """归一化字符串，以兼容大小写、连字符和空格差异。"""
    if value is None:
        return ""

    text = str(value).strip()
    if not text:
        return ""

    text = unicodedata.normalize("NFKD", text)
    text = text.replace("&", " and ")

    for token in ("-", "_", "/", "\\", "(", ")", ",", "."):
        text = text.replace(token, " ")

    return " ".join(text.lower().split())


SUBREGION_TO_REGION_ID = {_normalize_text(name): region_id for name, region_id in SUBREGION_TO_REGION_ID_RAW.items()}

INTENTIONALLY_OMITTED_SUBREGIONS = {_normalize_text(name) for name in INTENTIONALLY_OMITTED_SUBREGIONS_RAW}


def region_id_from_subregion(subregion: Any) -> int:
    """根据 Natural Earth 的 SUBREGION 字段返回论文中的区域编号。"""
    return SUBREGION_TO_REGION_ID.get(_normalize_text(subregion), 0)


def _properties_casefold(properties: Mapping[str, Any]) -> dict[str, Any]:
    """将属性表字段名统一转换为大写。"""
    return {str(key).upper(): value for key, value in properties.items()}


def _property(properties: Mapping[str, Any], *candidate_names: str) -> str:
    """按优先级读取属性值。"""
    folded = _properties_casefold(properties)

    for name in candidate_names:
        value = folded.get(name.upper())
        if value is not None and str(value).strip():
            return str(value).strip()

    return ""


def _override_key(field: str, value: Any) -> tuple[str, str]:
    """构造国家覆盖规则的查找键。"""
    return field.upper(), _normalize_text(value)


def load_country_overrides(csv_path: Path | None) -> dict[tuple[str, str], int]:
    """
    读取可选国家覆盖表。

    CSV 必须包含：
      - region_id 列；
      - IDENTIFIER_FIELDS 中的至少一个国家标识列。
    """
    if csv_path is None:
        return {}

    if not csv_path.exists():
        raise FileNotFoundError(f"国家覆盖表不存在：{csv_path}")

    overrides: dict[tuple[str, str], int] = {}

    with csv_path.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)

        if not reader.fieldnames:
            raise ValueError(f"国家覆盖表没有表头：{csv_path}")

        field_lookup = {field.upper(): field for field in reader.fieldnames}

        if "REGION_ID" not in field_lookup:
            raise ValueError(f"国家覆盖表缺少 region_id 列：{csv_path}；" f"现有列：{reader.fieldnames}")

        identifier_columns = [field_lookup[field] for field in IDENTIFIER_FIELDS if field in field_lookup]

        if not identifier_columns:
            raise ValueError("国家覆盖表至少需要一个国家标识列：" + ", ".join(IDENTIFIER_FIELDS))

        for line_no, row in enumerate(reader, start=2):
            raw_region_id = row[field_lookup["REGION_ID"]].strip()

            if not raw_region_id:
                raise ValueError(f"{csv_path}:{line_no} 的 region_id 为空")

            region_id = int(raw_region_id)

            if region_id not in REGION_ID_TO_NAME:
                raise ValueError(f"{csv_path}:{line_no} 的 region_id={region_id} 无效；" "必须位于 1..20")

            added = False

            for column in identifier_columns:
                value = row.get(column, "")
                if value and value.strip():
                    overrides[_override_key(column, value)] = region_id
                    added = True

            if not added:
                raise ValueError(f"{csv_path}:{line_no} 没有可用的国家标识值")

    return overrides


def lookup_override_region_id(
    properties: Mapping[str, Any],
    overrides: Mapping[tuple[str, str], int],
) -> int | None:
    """查询某个 Natural Earth 要素是否存在显式覆盖规则。"""
    folded = _properties_casefold(properties)

    for field in IDENTIFIER_FIELDS:
        value = folded.get(field)

        if value is None or not str(value).strip():
            continue

        key = _override_key(field, value)

        if key in overrides:
            return int(overrides[key])

    return None


# ============================================================================
# 自动搜索输入路径
# ============================================================================


def _first_existing_path(candidates: Sequence[Path]) -> Path | None:
    """返回候选路径中第一个真实存在的文件。"""
    for candidate in candidates:
        if candidate.exists():
            return candidate.resolve()

    return None


def detect_default_natural_earth_shp() -> Path | None:
    """自动搜索 Natural Earth Admin-0 国家边界文件。"""
    filename = "ne_110m_admin_0_countries.shp"

    return _first_existing_path(
        [
            BASE_DIR / "data" / "natural_earth" / filename,
            BASE_DIR.parent / "data" / "natural_earth" / filename,
            Path.cwd() / "data" / "natural_earth" / filename,
        ]
    )


def detect_default_reference_tif() -> Path | None:
    """自动搜索原论文的 1° Global_Grid_Division.tif。"""
    return _first_existing_path(
        [
            BASE_DIR / "inputs" / "Global_Grid_Division.tif",
            BASE_DIR.parent / "Optimization" / "Global_Grid_Division.tif",
            Path.cwd() / "inputs" / "Global_Grid_Division.tif",
            Path.cwd() / "Optimization" / "Global_Grid_Division.tif",
        ]
    )


# ============================================================================
# 目标栅格
# ============================================================================


def build_target_grid(resolution: float) -> TargetGrid:
    """构造覆盖全球的目标栅格。"""
    if resolution <= 0:
        raise ValueError(f"分辨率必须大于 0：{resolution}")

    width_float = (EAST - WEST) / resolution
    height_float = (NORTH - SOUTH) / resolution

    width = int(round(width_float))
    height = int(round(height_float))

    if not math.isclose(width_float, width, rel_tol=0.0, abs_tol=1e-9):
        raise ValueError(f"经度范围 360° 不能被 resolution={resolution} 整除")

    if not math.isclose(height_float, height, rel_tol=0.0, abs_tol=1e-9):
        raise ValueError(f"纬度范围 180° 不能被 resolution={resolution} 整除")

    _, _, _, from_origin, _, _, _ = _import_rasterio()
    transform = from_origin(WEST, NORTH, resolution, resolution)

    return TargetGrid(
        resolution=float(resolution),
        height=height,
        width=width,
        transform=transform,
    )


# ============================================================================
# 读取 Natural Earth 国家边界
# ============================================================================


def read_country_features(
    shp_path: Path,
    overrides: Mapping[tuple[str, str], int],
) -> tuple[list[CountryFeature], dict[str, Any]]:
    """
    读取 Natural Earth 国家或地区要素，并映射到论文的 20 个区域。

    默认依据 SUBREGION 字段映射。若提供了国家覆盖表，则优先使用覆盖规则。
    """
    fiona = _import_fiona()
    _, CRS, _, _, _, _, transform_geom = _import_rasterio()

    if not shp_path.exists():
        raise FileNotFoundError(f"Natural Earth shp 文件不存在：{shp_path}")

    features: list[CountryFeature] = []
    schema_properties: list[str] = []
    source_crs_text = ""

    with fiona.open(shp_path) as src:
        schema_properties = list(src.schema.get("properties", {}).keys())
        source_crs_input: Any = src.crs_wkt or src.crs or TARGET_CRS
        source_crs = CRS.from_user_input(source_crs_input)
        target_crs = CRS.from_user_input(TARGET_CRS)
        source_crs_text = source_crs.to_string()

        if "SUBREGION" not in {name.upper() for name in schema_properties}:
            raise ValueError("Natural Earth 属性表中缺少 SUBREGION 字段。" f"可用字段：{schema_properties}")

        for feature_index, feature in enumerate(src):
            geometry = feature.get("geometry")

            if geometry is None:
                continue

            properties = dict(feature.get("properties") or {})
            subregion_raw = _property(properties, "SUBREGION")

            override_region_id = lookup_override_region_id(
                properties,
                overrides,
            )

            if override_region_id is not None:
                region_id = override_region_id
                assignment_source = "override_csv"
                assignment_status = "mapped"
            else:
                region_id = region_id_from_subregion(subregion_raw)
                assignment_source = "natural_earth_subregion"

                normalized_subregion = _normalize_text(subregion_raw)

                if region_id:
                    assignment_status = "mapped"
                elif normalized_subregion in INTENTIONALLY_OMITTED_SUBREGIONS:
                    assignment_status = "intentionally_omitted"
                else:
                    assignment_status = "unmapped"

            if source_crs != target_crs:
                geometry = transform_geom(
                    source_crs,
                    target_crs,
                    geometry,
                    precision=10,
                )

            features.append(
                CountryFeature(
                    feature_index=feature_index,
                    geometry=geometry,
                    name=_property(properties, "NAME", "ADMIN"),
                    name_long=_property(properties, "NAME_LONG", "FORMAL_EN"),
                    adm0_a3=_property(properties, "ADM0_A3"),
                    iso_a3=_property(properties, "ISO_A3"),
                    sov_a3=_property(properties, "SOV_A3"),
                    subregion_raw=subregion_raw,
                    region_id=region_id,
                    region_name=REGION_ID_TO_NAME.get(region_id, ""),
                    assignment_status=assignment_status,
                    assignment_source=assignment_source,
                )
            )

    metadata = {
        "natural_earth_shapefile": str(shp_path),
        "source_crs": source_crs_text,
        "schema_properties": schema_properties,
        "feature_count": len(features),
        "mapped_feature_count": sum(feature.assignment_status == "mapped" for feature in features),
        "intentionally_omitted_feature_count": sum(
            feature.assignment_status == "intentionally_omitted" for feature in features
        ),
        "unmapped_feature_count": sum(feature.assignment_status == "unmapped" for feature in features),
        "override_feature_count": sum(feature.assignment_source == "override_csv" for feature in features),
    }

    return features, metadata


# ============================================================================
# 读取并重采样原论文的 1° 参考栅格
# ============================================================================


def value_counts(data: np.ndarray) -> dict[str, int]:
    """统计每一个整数区域编号对应的像元数量。"""
    values, counts = np.unique(data, return_counts=True)

    return {str(int(value)): int(count) for value, count in zip(values, counts)}


def read_reference_1deg(
    tif_path: Path,
) -> tuple[np.ndarray, Any, Any, dict[str, Any]]:
    """读取原论文的 1° 区域划分栅格，并检查其基本格式。"""
    rasterio, CRS, _, _, _, _, _ = _import_rasterio()

    if not tif_path.exists():
        raise FileNotFoundError(f"原论文 1° 参考 TIF 不存在：{tif_path}")

    with rasterio.open(tif_path) as src:
        raw = src.read(1)
        transform = src.transform
        crs = src.crs
        bounds = src.bounds
        tags = src.tags()

    if crs is None:
        raise ValueError(f"原论文参考 TIF 缺少 CRS：{tif_path}")

    if CRS.from_user_input(crs) != CRS.from_user_input(TARGET_CRS):
        raise ValueError(f"原论文参考 TIF 必须为 {TARGET_CRS}，当前为 {crs}：{tif_path}")

    if not np.all(np.isfinite(raw)):
        raise ValueError(f"原论文参考 TIF 含有 NaN 或 Inf：{tif_path}")

    if not np.allclose(raw, np.rint(raw), atol=1e-6):
        raise ValueError(f"原论文参考 TIF 含有非整数区域编号：{tif_path}")

    reference = np.rint(raw).astype(np.int32)
    unique_values = np.unique(reference)
    invalid = unique_values[(unique_values < 0) | (unique_values > 20)]

    if invalid.size:
        raise ValueError(f"原论文参考 TIF 出现 0..20 之外的区域编号：{invalid.tolist()}")

    metadata = {
        "reference_1deg_tif": str(tif_path),
        "shape": list(reference.shape),
        "crs": str(crs),
        "bounds": [
            float(bounds.left),
            float(bounds.bottom),
            float(bounds.right),
            float(bounds.top),
        ],
        "transform": [float(value) for value in tuple(transform)[:6]],
        "tags": dict(tags),
        "region_cell_counts": value_counts(reference),
    }

    return reference, transform, crs, metadata


def resample_reference_nearest(
    reference: np.ndarray,
    source_transform: Any,
    source_crs: Any,
    target_grid: TargetGrid,
) -> np.ndarray:
    """使用最近邻方法将原论文 1° 栅格重采样到目标分辨率。"""
    _, _, _, _, Resampling, reproject, _ = _import_rasterio()

    destination = np.zeros(
        (target_grid.height, target_grid.width),
        dtype=np.int32,
    )

    reproject(
        source=reference,
        destination=destination,
        src_transform=source_transform,
        src_crs=source_crs,
        dst_transform=target_grid.transform,
        dst_crs=TARGET_CRS,
        src_nodata=None,
        dst_nodata=0,
        resampling=Resampling.nearest,
    )

    return destination


# ============================================================================
# 栅格化 Natural Earth 国家边界并与参考栅格合并
# ============================================================================


def rasterize_land_regions(
    features: Sequence[CountryFeature],
    target_grid: TargetGrid,
    *,
    all_touched: bool,
) -> tuple[np.ndarray, np.ndarray]:
    """
    将 Natural Earth 国家边界栅格化。

    返回：
      1. land_regions：仅包含成功映射到 1..20 的陆地区域；
      2. all_country_mask：包含全部 Natural Earth 国家多边形的掩膜。
    """
    _, _, rasterize, _, _, _, _ = _import_rasterio()

    mapped_shapes = [
        (feature.geometry, int(feature.region_id)) for feature in features if feature.region_id in REGION_ID_TO_NAME
    ]

    all_country_shapes = [(feature.geometry, 1) for feature in features]

    land_regions = rasterize(
        mapped_shapes,
        out_shape=(target_grid.height, target_grid.width),
        transform=target_grid.transform,
        fill=0,
        all_touched=all_touched,
        dtype=np.int32,
    )

    all_country_mask = rasterize(
        all_country_shapes,
        out_shape=(target_grid.height, target_grid.width),
        transform=target_grid.transform,
        fill=0,
        all_touched=all_touched,
        dtype=np.uint8,
    ).astype(bool)

    return land_regions, all_country_mask


def combine_land_and_reference(
    reference_high_resolution: np.ndarray,
    land_regions: np.ndarray,
) -> tuple[np.ndarray, np.ndarray]:
    """
    使用 Natural Earth 的陆地区域覆盖参考栅格。

    海洋和未能通过 Natural Earth 安全映射的区域，继续使用原论文参考栅格
    最近邻重采样后的值。
    """
    if reference_high_resolution.shape != land_regions.shape:
        raise ValueError(
            "参考栅格与 Natural Earth 陆地区域栅格的 shape 不一致："
            f"{reference_high_resolution.shape} 与 {land_regions.shape}"
        )

    combined = reference_high_resolution.copy()
    overlay_mask = land_regions > 0
    combined[overlay_mask] = land_regions[overlay_mask]

    return combined, overlay_mask


# ============================================================================
# 校验与诊断统计
# ============================================================================


def validate_output_grid(data: np.ndarray, target_grid: TargetGrid) -> None:
    """校验内存中的最终区域划分矩阵。"""
    expected_shape = (target_grid.height, target_grid.width)

    if data.shape != expected_shape:
        raise ValueError(f"输出 shape 错误：{data.shape}，期望 {expected_shape}")

    if data.dtype != np.int32:
        raise ValueError(f"输出 dtype 错误：{data.dtype}，期望 int32")

    if not np.all(np.isfinite(data)):
        raise ValueError("输出包含 NaN 或 Inf")

    invalid = np.unique(data[(data < 0) | (data > 20)])

    if invalid.size:
        raise ValueError(f"输出出现 0..20 之外的区域编号：{invalid.tolist()}")


def _transition_counts(
    old_values: np.ndarray,
    new_values: np.ndarray,
) -> dict[str, int]:
    """高效统计区域编号变化类型，例如 10->12。"""
    if old_values.size == 0:
        return {}

    pairs = np.column_stack(
        (
            old_values.astype(np.int16, copy=False),
            new_values.astype(np.int16, copy=False),
        )
    )

    unique_pairs, counts = np.unique(pairs, axis=0, return_counts=True)

    order = np.argsort(counts)[::-1]

    return {f"{int(unique_pairs[index, 0])}->{int(unique_pairs[index, 1])}": int(counts[index]) for index in order}


def compare_with_reference(
    combined: np.ndarray,
    reference_high_resolution: np.ndarray,
    reference_1deg: np.ndarray,
) -> dict[str, Any]:
    """比较新区域划分与原论文区域划分之间的差异。"""
    diff_mask = combined != reference_high_resolution

    report: dict[str, Any] = {
        "changed_high_resolution_cell_count": int(np.count_nonzero(diff_mask)),
        "changed_high_resolution_cell_fraction": float(np.mean(diff_mask)),
        "changed_high_resolution_transition_counts": _transition_counts(
            reference_high_resolution[diff_mask],
            combined[diff_mask],
        ),
    }

    reference_height, reference_width = reference_1deg.shape
    target_height, target_width = combined.shape

    if target_height % reference_height != 0 or target_width % reference_width != 0:
        report["downsample_comparison_skipped"] = "目标 shape 无法按整数倍聚合回参考 shape"
        return report

    row_factor = target_height // reference_height
    column_factor = target_width // reference_width

    if row_factor != column_factor:
        report["downsample_comparison_skipped"] = "纬度方向和经度方向的缩放倍数不一致"
        return report

    factor = row_factor
    center_offset = factor // 2

    # 诊断方法 1：从每个 1° 父格网内部取一个中心子像元。
    center_sample = combined[
        center_offset::factor,
        center_offset::factor,
    ][:reference_height, :reference_width]

    # 诊断方法 2：统计每个 1° 父格网内部出现次数最多的区域编号。
    blocks = (
        combined.reshape(
            reference_height,
            factor,
            reference_width,
            factor,
        )
        .transpose(0, 2, 1, 3)
        .reshape(reference_height, reference_width, factor * factor)
    )

    counts = np.stack(
        [(blocks == region_id).sum(axis=2) for region_id in range(21)],
        axis=2,
    )

    mode_downsample = np.argmax(counts, axis=2).astype(np.int32)

    center_diff = center_sample != reference_1deg
    mode_diff = mode_downsample != reference_1deg

    report.update(
        {
            "integer_scale_factor": int(factor),
            "center_sample_changed_1deg_cell_count": int(np.count_nonzero(center_diff)),
            "center_sample_changed_1deg_cell_fraction": float(np.mean(center_diff)),
            "mode_downsample_changed_1deg_cell_count": int(np.count_nonzero(mode_diff)),
            "mode_downsample_changed_1deg_cell_fraction": float(np.mean(mode_diff)),
        }
    )

    return report


def build_report(
    *,
    args: argparse.Namespace,
    natural_earth_metadata: Mapping[str, Any],
    reference_metadata: Mapping[str, Any],
    features: Sequence[CountryFeature],
    target_grid: TargetGrid,
    reference_high_resolution: np.ndarray,
    land_regions: np.ndarray,
    all_country_mask: np.ndarray,
    overlay_mask: np.ndarray,
    combined: np.ndarray,
    comparison: Mapping[str, Any],
) -> dict[str, Any]:
    """构造 JSON 诊断报告。"""
    unresolved_features = [
        {
            "feature_index": feature.feature_index,
            "name": feature.name,
            "name_long": feature.name_long,
            "adm0_a3": feature.adm0_a3,
            "iso_a3": feature.iso_a3,
            "sov_a3": feature.sov_a3,
            "subregion_raw": feature.subregion_raw,
            "assignment_status": feature.assignment_status,
        }
        for feature in features
        if feature.assignment_status != "mapped"
    ]

    return {
        "script": Path(__file__).name,
        "algorithm": {
            "land_assignment": (
                "读取 Natural Earth Admin-0 国家多边形，并依据兼容 UN M49 的 " "SUBREGION 字段分配陆地区域。"
            ),
            "land_pixel_rule": (
                "所有相交像元均覆盖（all_touched=True）"
                if args.all_touched
                else "使用像元中心点规则（all_touched=False）"
            ),
            "fallback_assignment": (
                "对于海洋和未能映射的区域，使用原论文 1° 区域栅格的最近邻" "重采样结果作为回退值。"
            ),
            "modeled_region_count": 20,
            "intentionally_unmodeled_subregions": [
                "Micronesia",
                "Polynesia",
            ],
        },
        "target_grid": {
            "shape": [target_grid.height, target_grid.width],
            "resolution_degrees": target_grid.resolution,
            "bounds": [WEST, SOUTH, EAST, NORTH],
            "crs": TARGET_CRS,
            "dtype": str(combined.dtype),
        },
        "natural_earth": dict(natural_earth_metadata),
        "reference": dict(reference_metadata),
        "output_grid": {
            "region_cell_counts": value_counts(combined),
            "reference_nearest_region_cell_counts": value_counts(reference_high_resolution),
            "natural_earth_land_region_cell_counts": value_counts(land_regions),
            "natural_earth_all_country_cell_count": int(np.count_nonzero(all_country_mask)),
            "natural_earth_modeled_land_cell_count": int(np.count_nonzero(land_regions)),
            "natural_earth_overlay_cell_count": int(np.count_nonzero(overlay_mask)),
            "natural_earth_country_cells_without_modeled_region_count": int(
                np.count_nonzero(all_country_mask & (land_regions == 0))
            ),
            "remaining_zero_cell_count": int(np.count_nonzero(combined == 0)),
        },
        "comparison_with_original_reference": dict(comparison),
        "unresolved_or_intentionally_omitted_features": unresolved_features,
    }


def print_stats(
    *,
    target_grid: TargetGrid,
    natural_earth_metadata: Mapping[str, Any],
    reference_high_resolution: np.ndarray,
    land_regions: np.ndarray,
    all_country_mask: np.ndarray,
    combined: np.ndarray,
    comparison: Mapping[str, Any],
) -> None:
    """打印诊断统计。"""
    print()
    print("生成统计")
    print("--------")
    print(f"shape                         ：{combined.shape}")
    print(f"dtype                         ：{combined.dtype}")
    print("分辨率                        ：" f"{target_grid.resolution}° × {target_grid.resolution}°")
    print(f"区域编号范围                  ：[{combined.min()}, {combined.max()}]")
    print(f"Natural Earth 要素数量        ：{natural_earth_metadata['feature_count']}")
    print("已映射要素数量                ：" f"{natural_earth_metadata['mapped_feature_count']}")
    print("主动忽略要素数量              ：" f"{natural_earth_metadata['intentionally_omitted_feature_count']}")
    print("未识别要素数量                ：" f"{natural_earth_metadata['unmapped_feature_count']}")
    print("Natural Earth 国家像元数量    ：" f"{np.count_nonzero(all_country_mask):,}")
    print("Natural Earth 已映射陆地像元数：" f"{np.count_nonzero(land_regions):,}")
    print("最终为 0 的像元数量           ：" f"{np.count_nonzero(combined == 0):,}")

    print()
    print("与原论文 1° 栅格最近邻放大结果的对比")
    print("------------------------------------")
    print("发生变化的 0.1° 像元数量       ：" f"{comparison['changed_high_resolution_cell_count']:,}")
    print("发生变化的 0.1° 像元比例       ：" f"{comparison['changed_high_resolution_cell_fraction']:.6%}")

    if "center_sample_changed_1deg_cell_count" in comparison:
        print("中心点降采样后变化的 1° 像元数：" f"{comparison['center_sample_changed_1deg_cell_count']:,}")
        print("众数降采样后变化的 1° 像元数  ：" f"{comparison['mode_downsample_changed_1deg_cell_count']:,}")

    print()
    print("最终输出中各区域的像元数量")
    print("--------------------------")

    counts = value_counts(combined)

    for region_id in range(21):
        if region_id == 0:
            name = "未分配或背景区域"
        else:
            name = REGION_ID_TO_NAME[region_id]

        print(f"{region_id:>2d}  {name:<24s}：{counts.get(str(region_id), 0):>10,}")


# ============================================================================
# 写出文件
# ============================================================================


def _prepare_output_path(path: Path, overwrite: bool) -> None:
    """检查输出路径并创建父目录。"""
    path.parent.mkdir(parents=True, exist_ok=True)

    if path.exists() and not overwrite:
        raise FileExistsError(f"输出文件已存在：{path}\n" "如需覆盖，请添加 --overwrite")


def _atomic_replace(temp_path: Path, final_path: Path) -> None:
    """使用原子替换，将临时文件移动为正式文件。"""
    os.replace(temp_path, final_path)


def write_geotiff(
    path: Path,
    data: np.ndarray,
    target_grid: TargetGrid,
    *,
    overwrite: bool,
) -> None:
    """将区域划分矩阵写出为 GeoTIFF。"""
    rasterio, _, _, _, _, _, _ = _import_rasterio()
    _prepare_output_path(path, overwrite)

    temp_path = path.with_name(path.name + ".tmp")

    if temp_path.exists():
        temp_path.unlink()

    try:
        with rasterio.open(
            temp_path,
            "w",
            driver="GTiff",
            height=target_grid.height,
            width=target_grid.width,
            count=1,
            dtype=np.int32,
            crs=TARGET_CRS,
            transform=target_grid.transform,
            nodata=0,
            compress="deflate",
        ) as dst:
            dst.write(data, 1)
            dst.update_tags(
                AREA_OR_POINT="Area",
                generated_by=Path(__file__).name,
                description=(
                    "全球区域划分栅格。陆地区域依据 Natural Earth Admin-0 的 "
                    "SUBREGION 字段映射到论文使用的 20 个 UN geoscheme 区域；"
                    "海洋和未映射区域使用原论文 1° 栅格的最近邻重采样值。"
                ),
                region_ids="0=背景；1..20=论文使用的区域电网",
            )

        _atomic_replace(temp_path, path)

    except Exception:
        if temp_path.exists():
            temp_path.unlink()
        raise

    print(f"[完成] 已写入：{path}")


def write_mat(
    path: Path,
    data: np.ndarray,
    *,
    overwrite: bool,
) -> None:
    """将区域划分矩阵写出为 MATLAB MAT 文件。"""
    sio = _import_scipy_io()
    _prepare_output_path(path, overwrite)

    temp_path = path.with_name(path.name + ".tmp")

    if temp_path.exists():
        temp_path.unlink()

    try:
        sio.savemat(
            temp_path,
            {"Global_Grid_Division": data},
            do_compression=True,
            appendmat=False,
        )

        _atomic_replace(temp_path, path)

    except Exception:
        if temp_path.exists():
            temp_path.unlink()
        raise

    print(f"[完成] 已写入：{path}")


def write_json(
    path: Path,
    payload: Mapping[str, Any],
    *,
    overwrite: bool,
) -> None:
    """写出 UTF-8 JSON 文件。"""
    _prepare_output_path(path, overwrite)

    temp_path = path.with_name(path.name + ".tmp")

    if temp_path.exists():
        temp_path.unlink()

    try:
        with temp_path.open("w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=False, indent=2)
            handle.write("\n")

        _atomic_replace(temp_path, path)

    except Exception:
        if temp_path.exists():
            temp_path.unlink()
        raise

    print(f"[完成] 已写入：{path}")


def write_country_mapping_csv(
    path: Path,
    features: Sequence[CountryFeature],
    *,
    overwrite: bool,
) -> None:
    """写出国家或地区到模型区域的映射表。"""
    _prepare_output_path(path, overwrite)

    temp_path = path.with_name(path.name + ".tmp")

    if temp_path.exists():
        temp_path.unlink()

    fieldnames = [
        "feature_index",
        "name",
        "name_long",
        "ADM0_A3",
        "ISO_A3",
        "SOV_A3",
        "subregion_raw",
        "region_id",
        "region_name",
        "assignment_status",
        "assignment_source",
    ]

    try:
        with temp_path.open("w", encoding="utf-8-sig", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fieldnames)
            writer.writeheader()

            for feature in features:
                writer.writerow(
                    {
                        "feature_index": feature.feature_index,
                        "name": feature.name,
                        "name_long": feature.name_long,
                        "ADM0_A3": feature.adm0_a3,
                        "ISO_A3": feature.iso_a3,
                        "SOV_A3": feature.sov_a3,
                        "subregion_raw": feature.subregion_raw,
                        "region_id": feature.region_id,
                        "region_name": feature.region_name,
                        "assignment_status": feature.assignment_status,
                        "assignment_source": feature.assignment_source,
                    }
                )

        _atomic_replace(temp_path, path)

    except Exception:
        if temp_path.exists():
            temp_path.unlink()
        raise

    print(f"[完成] 已写入：{path}")


def validate_written_geotiff(path: Path, target_grid: TargetGrid) -> None:
    """重新读取写出的 GeoTIFF，并校验其基本属性。"""
    rasterio, CRS, _, _, _, _, _ = _import_rasterio()

    with rasterio.open(path) as src:
        data = src.read(1)

        expected_bounds = (WEST, SOUTH, EAST, NORTH)
        actual_bounds = (
            float(src.bounds.left),
            float(src.bounds.bottom),
            float(src.bounds.right),
            float(src.bounds.top),
        )

        if data.shape != (target_grid.height, target_grid.width):
            raise ValueError(f"写出 TIF 的 shape 错误：{data.shape}")

        if data.dtype != np.int32:
            raise ValueError(f"写出 TIF 的 dtype 错误：{data.dtype}")

        if CRS.from_user_input(src.crs) != CRS.from_user_input(TARGET_CRS):
            raise ValueError(f"写出 TIF 的 CRS 错误：{src.crs}")

        if not np.allclose(actual_bounds, expected_bounds, atol=1e-9):
            raise ValueError(f"写出 TIF 的 bounds 错误：{actual_bounds}，" f"期望：{expected_bounds}")


def validate_written_mat(path: Path, expected: np.ndarray) -> None:
    """重新读取写出的 MAT 文件，并校验变量名与矩阵内容。"""
    sio = _import_scipy_io()
    mat = sio.loadmat(path)

    if "Global_Grid_Division" not in mat:
        raise ValueError(f"写出 MAT 缺少变量 Global_Grid_Division：{path}")

    data = np.asarray(mat["Global_Grid_Division"])

    if data.shape != expected.shape:
        raise ValueError(f"写出 MAT 的 shape 错误：{data.shape}")

    if data.dtype != np.int32:
        raise ValueError(f"写出 MAT 的 dtype 错误：{data.dtype}")

    if not np.array_equal(data, expected):
        raise ValueError(f"写出 MAT 与内存矩阵不一致：{path}")


# ============================================================================
# 命令行接口
# ============================================================================


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    """解析命令行参数。"""
    detected_shp = detect_default_natural_earth_shp()
    detected_reference = detect_default_reference_tif()

    parser = argparse.ArgumentParser(
        description=("基于 Natural Earth Admin-0 国家边界和原论文 1° 参考栅格，" "生成全球 0.1° 区域划分。")
    )

    parser.add_argument(
        "--natural-earth-shp",
        type=Path,
        default=detected_shp,
        help=("Natural Earth Admin-0 国家边界 shp。默认自动搜索 " "data/natural_earth/ne_110m_admin_0_countries.shp"),
    )

    parser.add_argument(
        "--reference-1deg-tif",
        type=Path,
        default=detected_reference,
        help=(
            "原论文的 Global_Grid_Division.tif。用于海洋和未映射区域的"
            "兼容性回退。默认自动搜索 inputs/ 或 ../Optimization/。"
        ),
    )

    parser.add_argument(
        "--country-overrides-csv",
        type=Path,
        default=None,
        help="可选国家映射覆盖表，需包含 region_id 和国家标识列。",
    )

    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help=f"输出目录。默认：{DEFAULT_OUTPUT_DIR}",
    )

    parser.add_argument(
        "--resolution",
        type=float,
        default=DEFAULT_RESOLUTION,
        help=f"输出分辨率，单位为度。默认：{DEFAULT_RESOLUTION}",
    )

    parser.add_argument(
        "--all-touched",
        action="store_true",
        help=("栅格化时，将所有与国家多边形相交的像元视为陆地。" "默认关闭，即使用像元中心点规则。"),
    )

    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="覆盖已存在的输出文件。",
    )

    parser.add_argument(
        "--print-stats",
        action="store_true",
        help="打印详细统计信息。",
    )

    args = parser.parse_args(argv)

    if args.natural_earth_shp is None:
        parser.error("未找到 Natural Earth shp。请使用 --natural-earth-shp 指定路径。")

    if args.reference_1deg_tif is None:
        parser.error("未找到原论文 1° Global_Grid_Division.tif。" "请使用 --reference-1deg-tif 指定路径。")

    args.natural_earth_shp = args.natural_earth_shp.resolve()
    args.reference_1deg_tif = args.reference_1deg_tif.resolve()
    args.output_dir = args.output_dir.resolve()

    if args.country_overrides_csv is not None:
        args.country_overrides_csv = args.country_overrides_csv.resolve()

    return args


def main(argv: Sequence[str] | None = None) -> int:
    """执行主流程。"""
    args = parse_args(argv)

    print("基于 UN M49 与 Natural Earth 重新生成全球区域划分")
    print("================================================")
    print(f"Natural Earth shp 文件 ：{args.natural_earth_shp}")
    print(f"原论文 1° 参考 TIF     ：{args.reference_1deg_tif}")
    print(f"输出目录               ：{args.output_dir}")
    print(f"输出分辨率             ：{args.resolution}°")
    print("边界栅格化规则         ：" + ("覆盖所有相交像元" if args.all_touched else "使用像元中心点"))

    target_grid = build_target_grid(args.resolution)

    print("\n[1/7] 读取可选国家覆盖表……")
    overrides = load_country_overrides(args.country_overrides_csv)
    print(f"[完成] 覆盖规则数量：{len(overrides)}")

    print("\n[2/7] 读取 Natural Earth 国家边界并映射 UN M49 子区域……")
    features, natural_earth_metadata = read_country_features(
        args.natural_earth_shp,
        overrides,
    )
    print(
        "[完成] "
        f"要素总数={natural_earth_metadata['feature_count']}，"
        f"已映射={natural_earth_metadata['mapped_feature_count']}，"
        "主动忽略="
        f"{natural_earth_metadata['intentionally_omitted_feature_count']}，"
        f"未识别={natural_earth_metadata['unmapped_feature_count']}"
    )

    print("\n[3/7] 读取原论文 1° 区域划分并执行最近邻重采样……")
    reference_1deg, source_transform, source_crs, reference_metadata = read_reference_1deg(args.reference_1deg_tif)
    reference_high_resolution = resample_reference_nearest(
        reference_1deg,
        source_transform,
        source_crs,
        target_grid,
    )
    print("[完成] " f"{reference_1deg.shape} → {reference_high_resolution.shape}")

    print("\n[4/7] 将 Natural Earth 国家边界栅格化……")
    land_regions, all_country_mask = rasterize_land_regions(
        features,
        target_grid,
        all_touched=args.all_touched,
    )
    print(
        "[完成] "
        f"已映射陆地像元={np.count_nonzero(land_regions):,}，"
        f"全部国家多边形像元={np.count_nonzero(all_country_mask):,}"
    )

    print("\n[5/7] 合并陆地区域与原论文海洋回退值……")
    combined, overlay_mask = combine_land_and_reference(
        reference_high_resolution,
        land_regions,
    )
    validate_output_grid(combined, target_grid)

    comparison = compare_with_reference(
        combined,
        reference_high_resolution,
        reference_1deg,
    )

    print(
        "[完成] "
        f"覆盖像元={np.count_nonzero(overlay_mask):,}，"
        "相对原论文最近邻结果发生变化的像元="
        f"{comparison['changed_high_resolution_cell_count']:,}"
    )

    report = build_report(
        args=args,
        natural_earth_metadata=natural_earth_metadata,
        reference_metadata=reference_metadata,
        features=features,
        target_grid=target_grid,
        reference_high_resolution=reference_high_resolution,
        land_regions=land_regions,
        all_country_mask=all_country_mask,
        overlay_mask=overlay_mask,
        combined=combined,
        comparison=comparison,
    )

    print("\n[6/7] 写出结果……")
    output_dir = args.output_dir
    output_tif = output_dir / "Global_Grid_Division.tif"
    output_mat = output_dir / "Global_Grid_Division.mat"
    output_country_csv = output_dir / "country_to_region.csv"
    output_region_json = output_dir / "region_id_to_name.json"
    output_report_json = output_dir / "Global_Grid_Division_from_UN_M49_report.json"

    write_geotiff(
        output_tif,
        combined,
        target_grid,
        overwrite=args.overwrite,
    )

    write_mat(
        output_mat,
        combined,
        overwrite=args.overwrite,
    )

    write_country_mapping_csv(
        output_country_csv,
        features,
        overwrite=args.overwrite,
    )

    write_json(
        output_region_json,
        {str(key): value for key, value in REGION_ID_TO_NAME.items()},
        overwrite=args.overwrite,
    )

    write_json(
        output_report_json,
        report,
        overwrite=args.overwrite,
    )

    print("\n[7/7] 重新读取输出并校验……")
    validate_written_geotiff(output_tif, target_grid)
    validate_written_mat(output_mat, combined)
    print("[完成] TIF 与 MAT 均已通过校验。")

    if args.print_stats:
        print_stats(
            target_grid=target_grid,
            natural_earth_metadata=natural_earth_metadata,
            reference_high_resolution=reference_high_resolution,
            land_regions=land_regions,
            all_country_mask=all_country_mask,
            combined=combined,
            comparison=comparison,
        )

    print("\n全部完成。")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"\n[错误] {exc}", file=sys.stderr)
        raise
