"""
density_config.py — 与 MATLAB 代码一致的装机密度参数和函数

密度来源（document/装机密度修改计划.md）：
  - 陆上风电：3.68 MW/km²
  - 海上风电：6.07 MW/km²
  - 光伏：纬度依赖 161.9 × Ω(lat) × 0.15 MW/km²
"""

import numpy as np

# ── 风电密度常量（MW/km²） ──────────────────────────────────────────────
WIND_ONSHORE = 3.68
WIND_OFFSHORE = 6.07

# ── 光伏参数 ──────────────────────────────────────────────────────────
PV_STC_DENSITY = 161.9  # W/m²，标准测试条件功率密度
PV_FR = 0.15            # 统一适宜性系数


def compute_pv_density_grid(shape=(180, 360)):
    """计算 180×360 纬度依赖光伏装机密度栅格（MW/km²）。

    与 MATLAB compute_pv_density.m 公式一致：
      pv_density = 161.9 × Ω(lat) × FR
      Ω = cos(β) / (cos(β) + sin(β)/tan(α_min))
      β = 0.35396 × |lat| + 16.84775
      α_min = max(90 - |lat| - 23.45, 0.1)

    Parameters
    ----------
    shape : tuple
        输出栅格尺寸，默认 (180, 360)。

    Returns
    -------
    pv_density : ndarray, shape (180, 360)
        每个格网的光伏装机密度（MW/km²）。
    """
    nrows, ncols = shape
    lats = 90.5 - np.arange(1, nrows + 1)  # row 0 → lat 89.5, row 179 → lat -89.5（与 MATLAB 1-based 行号一致）

    beta = 0.35396 * np.abs(lats) + 16.84775
    alpha_min = np.maximum(90 - np.abs(lats) - 23.45, 0.1)

    beta_rad = np.deg2rad(beta)
    alpha_min_rad = np.deg2rad(alpha_min)

    Omega = np.cos(beta_rad) / (np.cos(beta_rad) + np.sin(beta_rad) / np.tan(alpha_min_rad))
    pv_density_1d = PV_STC_DENSITY * Omega * PV_FR  # MW/km²

    return np.broadcast_to(pv_density_1d[:, np.newaxis], shape).copy()


def wind_density_grid(landmask, threshold=100):
    """根据 landmask 构建陆上/海上风电密度栅格（MW/km²）。

    Parameters
    ----------
    landmask : ndarray
        原始 landmask 栅格（>threshold 为海上）。
    threshold : int
        海上判定阈值，默认 100。

    Returns
    -------
    density : ndarray, same shape as landmask
        每个格网的风电装机密度（MW/km²）。
    """
    return np.where(landmask > threshold, WIND_OFFSHORE, WIND_ONSHORE).astype(float)


def build_solar_capacity_gw(solar_luccs, solar_area):
    """计算光伏最大可安装容量栅格（GW）。

    与 MATLAB 一致：pv_density × luccs × area / 1000 → GW
    自动修正 solar_area 中的负值（fish_area < 0 → 0）。

    Parameters
    ----------
    solar_luccs : ndarray — 可用面积比例（0~1）
    solar_area  : ndarray — 格网面积（km²）

    Returns
    -------
    solar_cap_gw : ndarray, same shape
    """
    solar_area = np.maximum(solar_area, 0)
    pv_density = compute_pv_density_grid(solar_luccs.shape)
    return pv_density * solar_luccs * solar_area / 1000.0


def build_wind_capacity_gw(wind_luccs, wind_area, landmask):
    """计算风电最大可安装容量栅格（GW）。

    与 MATLAB 一致：wind_density × luccs × area / 1000 → GW

    Parameters
    ----------
    wind_luccs : ndarray — 可用面积比例（0~1）
    wind_area  : ndarray — 格网面积（km²）
    landmask   : ndarray — 原始 landmask（>100 为海上）

    Returns
    -------
    wind_cap_gw : ndarray, same shape
    """
    density = wind_density_grid(landmask)
    return density * wind_luccs * wind_area / 1000.0
