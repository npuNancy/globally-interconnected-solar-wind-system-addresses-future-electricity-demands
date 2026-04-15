"""
constraints.py — 非线性约束函数

对应 MATLAB nonlcon2050.m。
确保各区域的光伏和风电规划装机不低于当前水平。
"""

import numpy as np
from .config import N_REGIONS


def nonlcon(
    grid_selection: np.ndarray,
    all_ins: np.ndarray,
    CGrid_Index_col1: np.ndarray,
    nonlsol: int,
    cur_solar_tw: np.ndarray,
    cur_wind_tw: np.ndarray,
) -> np.ndarray:
    """
    计算非线性约束值。

    约束含义: c <= 0 为可行解（所有区域均满足最低装机要求）。
    c[0] = 光伏装机不达标的区域数（规划 < 当前）
    c[1] = 风电装机不达标的区域数（规划 < 当前）

    对应 MATLAB nonlcon2050.m 的完整逻辑。

    参数:
        grid_selection:  (N_grid,) 0/1 二值选择
        all_ins:         (N_grid,) 各格网装机容量 (TW)
        CGrid_Index_col1: (N_grid,) 区域编号 (1-20)
        nonlsol:         光伏格网数量
        cur_solar_tw:    (20,) 各区域当前光伏装机 (TW)
        cur_wind_tw:     (20,) 各区域当前风电装机 (TW)

    返回:
        c: (2,) 不等式约束值 (<=0 可行)
    """
    regions = CGrid_Index_col1.astype(int)

    # ---- 光伏约束 ----
    # 前 nonlsol 个格网为光伏
    solar_sel = grid_selection[:nonlsol].astype(np.float64)
    solar_planned = solar_sel * all_ins[:nonlsol]

    # 按区域汇总规划装机
    solar_per_region = np.zeros(N_REGIONS)
    for r in range(N_REGIONS):
        mask = regions[:nonlsol] == (r + 1)
        if mask.any():
            solar_per_region[r] = solar_planned[mask].sum()

    # 统计不达标区域数
    c0 = int(np.sum(solar_per_region < cur_solar_tw))

    # ---- 风电约束 ----
    # nonlsol 之后为风电
    wind_sel = grid_selection[nonlsol:].astype(np.float64)
    wind_planned = wind_sel * all_ins[nonlsol:]

    wind_per_region = np.zeros(N_REGIONS)
    for r in range(N_REGIONS):
        mask = regions[nonlsol:] == (r + 1)
        if mask.any():
            wind_per_region[r] = wind_planned[mask].sum()

    c1 = int(np.sum(wind_per_region < cur_wind_tw))

    return np.array([c0, c1], dtype=np.float64)
