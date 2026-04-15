"""
dispatch.py — 8760小时逐时调度模型

对应 MATLAB OptFun_SG_Dispatch_2050.m，实现完整的全年跨区电力调度。
这是计算量最大的核心函数，每个候选解都需要完整运行一次。
"""

import numpy as np
from .config import (
    SCENARIO_SG_2050, N_REGIONS, N_HOURS,
    STORAGE_CHARGE_EFF, STORAGE_DISCHARGE_EFF, STORAGE_INITIAL_SOC,
    COST_TRANSMISSION, COST_STORAGE_ENERGY, COST_OFFSHORE_WIND,
    SOLAR_COST_TABLE, WIND_COST_TABLE,
)
from .path_finding import find_and_sort_paths, calculate_path_capacity


def compute_regional_generation(
    all_gens: np.ndarray,
    CGrid_Index: np.ndarray,
    grid_selection: np.ndarray,
) -> np.ndarray:
    """
    根据格网选择决策，汇总各区域的发电曲线。

    参数:
        all_gens:         (N_grid, 8760) 所有候选格网的发电曲线 (TWh/h)
        CGrid_Index:      (N_grid, 3) [区域编号, 0, 陆海标识]
        grid_selection:   (N_grid,) 0/1 二值选择向量

    返回:
        grid_gens: (20, 8760) 各区域逐时发电量 (TWh/h)
    """
    grid_gens = np.zeros((N_REGIONS, N_HOURS))
    selected = grid_selection == 1
    regions = CGrid_Index[:, 0].astype(int)

    for r in range(N_REGIONS):
        mask = selected & (regions == r + 1)
        if mask.any():
            grid_gens[r] = np.nansum(all_gens[mask], axis=0)

    return grid_gens


def apply_baseload(grid_load: np.ndarray, baseload_fraction: float) -> np.ndarray:
    """
    从各区域负荷中扣除基荷。

    对应 MATLAB 代码: tmp = tmp - sum(tmp) * baseload_fraction / 8760

    参数:
        grid_load: (20, 8760) 原始负荷 (TW)
        baseload_fraction: 基荷比例 (如 0.09)

    返回:
        grid_load: (20, 8760) 扣除基荷后的净负荷 (TW)
    """
    for r in range(N_REGIONS):
        grid_load[r] -= grid_load[r].sum() * baseload_fraction / N_HOURS
    return grid_load


def compute_total_cost(
    grid_selection: np.ndarray,
    all_ins: np.ndarray,
    CGrid_Index: np.ndarray,
    nonlsol: int,
    storage_cap: np.ndarray,
    trans_power_tw: np.ndarray,
) -> float:
    """
    计算总投资成本 (USD billion)。

    对应 OptFun_SG_Dispatch_2050.m 第127-153行。

    参数:
        grid_selection: (N_grid,) 0/1
        all_ins:        (N_grid,) 装机容量 (TW)
        CGrid_Index:    (N_grid, 3)
        nonlsol:        光伏格网数量
        storage_cap:    (20,) 储能容量 (TWh)
        trans_power_tw: (20, 20) 输电容量 (TW)

    返回:
        float: 总成本 (USD billion)
    """
    obj_cost = 0.0
    regions = CGrid_Index[:, 0].astype(int)
    selected = grid_selection == 1

    # 1. 海上风电 (CGrid_Index(:,3)==1, 已选中, index > nonlsol)
    mask_offshore = (CGrid_Index[:, 2] == 1) & selected
    offshore_wind_idx = np.where(mask_offshore)[0]
    offshore_wind_idx = offshore_wind_idx[offshore_wind_idx > nonlsol]
    if len(offshore_wind_idx) > 0:
        obj_cost += COST_OFFSHORE_WIND * all_ins[offshore_wind_idx].sum()

    # 2. 各洲陆上装机成本 (CGrid_Index(:,3)==0, 已选中)
    mask_onshore = (CGrid_Index[:, 2] == 0) & selected
    onshore_idx = np.where(mask_onshore)[0]

    for idx in onshore_idx:
        region_id = int(regions[idx])
        if idx <= nonlsol:
            # 光伏
            obj_cost += SOLAR_COST_TABLE[region_id] * all_ins[idx]
        else:
            # 陆上风电
            obj_cost += WIND_COST_TABLE[region_id] * all_ins[idx]

    # 3. 输电成本
    obj_cost += COST_TRANSMISSION * trans_power_tw.sum()

    # 4. 储能成本
    obj_cost += COST_STORAGE_ENERGY * storage_cap.sum()

    return obj_cost


def dispatch(
    grid_selection: np.ndarray,
    storage_power_gw: np.ndarray,
    storage_duration_h: np.ndarray,
    trans_power_gw: np.ndarray,
    all_gens: np.ndarray,
    all_ins: np.ndarray,
    all_loads: np.ndarray,
    CGrid_Index: np.ndarray,
    trans_connections: np.ndarray,
    trans_loss: np.ndarray,
    trans_mask: np.ndarray,
    nonlsol: int,
    scenario: dict = None,
) -> tuple:
    """
    完整的全年8760小时跨区电力调度。

    对应 MATLAB OptFun_SG_Dispatch_2050.m。

    参数:
        grid_selection:    (N_grid,) 0/1 格网选择
        storage_power_gw:  (20,) 储能功率 (GW)
        storage_duration_h:(20,) 储能时长 (h)
        trans_power_gw:    (n_trans,) 输电功率 (GW)
        all_gens:          (N_grid, 8760) 发电曲线 (TWh/h)
        all_ins:           (N_grid,) 装机 (TW)
        all_loads:         (20, 8760) 负荷 (TW)
        CGrid_Index:       (N_grid, 3)
        trans_connections: (20, 20) 连接矩阵
        trans_loss:        (20, 20) 损耗矩阵
        trans_mask:        (20, 20) 输电决策变量掩码
        nonlsol:           光伏格网数
        scenario:          情景参数

    返回:
        (f1, f2, f3): 弃电率, 1-渗透率, 总成本(USD billion)
    """
    if scenario is None:
        scenario = SCENARIO_SG_2050

    baseload_frac = scenario['baseload_fraction']
    max_nodes = scenario['max_path_nodes']

    # ---- 步骤1: 计算各区域发电曲线 ----
    grid_gens = compute_regional_generation(all_gens, CGrid_Index, grid_selection)

    # ---- 步骤2: 扣除基荷 ----
    grid_load = all_loads.copy()
    grid_load = apply_baseload(grid_load, baseload_frac)

    # ---- 步骤3: 恢复储能和输电参数 ----
    storage_pow = storage_power_gw / 1e3       # GW → TW
    storage_cap = storage_pow * storage_duration_h  # TWh

    # 恢复输电容量矩阵 (TW)
    trans_power_base = np.zeros((N_REGIONS, N_REGIONS))
    trans_power_base[trans_mask] = trans_power_gw / 1e3  # GW → TW

    # ---- 步骤4: 预计算所有输电路径 ----
    all_paths = [None] * N_REGIONS
    all_costs = [None] * N_REGIONS
    for r in range(N_REGIONS):
        paths, costs = find_and_sort_paths(
            trans_power_base, trans_loss, r,
            min_nodes=2, max_nodes=max_nodes,
        )
        all_paths[r] = paths
        all_costs[r] = costs

    # ---- 步骤5: 初始化调度变量 ----
    stored_ele = np.zeros((N_HOURS + 1, N_REGIONS))
    stored_ele[0, :] = storage_cap * STORAGE_INITIAL_SOC
    curtailed_ele = np.zeros((N_HOURS, N_REGIONS))
    flexible_ele = np.zeros((N_HOURS, N_REGIONS))

    # ---- 步骤6: 逐时调度 ----
    to_storage_eff = STORAGE_CHARGE_EFF
    from_storage_eff = STORAGE_DISCHARGE_EFF

    for t in range(N_HOURS):
        # 每个时刻重置输电容量
        trans_power = trans_power_base.copy()

        # 计算各区域净发电量
        generation = grid_gens[:, t]       # (20,)
        demand = grid_load[:, t]            # (20,)
        surplus = generation - demand       # >0 盈余, <0 缺口

        # -- 6a: 跨区域输电调度 --
        for r in range(N_REGIONS):
            if surplus[r] <= 0:
                continue  # 该区域有缺口，跳过

            # 遍历从该区域出发的所有路径（按损耗升序）
            g_paths = all_paths[r]
            g_costs = all_costs[r]

            for p_idx in range(len(g_paths)):
                g_route = g_paths[p_idx]
                dest = g_route[-1]  # 目标区域

                if surplus[dest] >= 0:
                    continue  # 目标区域也有盈余，跳过

                # 计算路径瓶颈容量
                g_cap = calculate_path_capacity(g_route, trans_power)
                if g_cap <= 0:
                    continue

                # 计算实际传输量（考虑损耗补偿）
                t_amount = min(
                    surplus[r],                                        # 发送方盈余
                    abs(surplus[dest]) / (1 - g_costs[p_idx]),          # 接收方需求（含损耗补偿）
                    g_cap,                                              # 路径容量
                )

                if t_amount <= 0:
                    continue

                # 更新盈余/缺口状态
                surplus[r] -= t_amount
                surplus[dest] += t_amount * (1 - g_costs[p_idx])

                # 更新路径上各链路剩余容量
                for j in range(len(g_route) - 1):
                    trans_power[g_route[j], g_route[j + 1]] -= t_amount

        # -- 6b: 储能调度 --
        for r in range(N_REGIONS):
            if surplus[r] >= 0:
                # 盈余 → 充电
                charge_amount = min(
                    surplus[r],
                    storage_pow[r],
                    (storage_cap[r] - stored_ele[t, r]) / to_storage_eff,
                )
                stored_ele[t + 1, r] = stored_ele[t, r] + charge_amount * to_storage_eff
                curtailed_ele[t, r] = surplus[r] - charge_amount
                surplus[r] = 0
            else:
                # 缺口 → 放电
                discharge_amount = min(
                    storage_pow[r] / from_storage_eff,
                    abs(surplus[r]),
                    stored_ele[t, r],
                )
                stored_ele[t + 1, r] = max(stored_ele[t, r] - discharge_amount, 0)
                flexible_ele[t, r] = abs(surplus[r] + discharge_amount)
                surplus[r] = 0

    # ---- 步骤7: 计算三个目标函数 ----
    # f(1) = 弃电率
    total_curtailed = curtailed_ele.sum()
    total_generation = grid_gens.sum()
    f1 = total_curtailed / total_generation if total_generation > 0 else 1.0

    # f(2) = 1 - 渗透率
    total_flexible = flexible_ele.sum()
    total_load = all_loads.sum()
    f2 = total_flexible / total_load if total_load > 0 else 1.0

    # f(3) = 总成本 (USD billion)
    f3 = compute_total_cost(
        grid_selection, all_ins, CGrid_Index, nonlsol,
        storage_cap, trans_power_base,
    )

    return (f1, f2, f3)
