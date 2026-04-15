"""
config.py — 全局常量、情景参数和成本模型

由 MATLAB Optimization_SG_2050 改写，集中管理所有参数，
便于 2040（S-C）和 2030（S-A）情景复用代码。
"""

# ======================================================================
# 情景参数
# ======================================================================

SCENARIO_SG_2050 = {
    "name": "SG_2050",
    "load_layer": 3,                # all_loads[3,:,:]（0-indexed，对应 MATLAB 第4层）
    "total_load_twh": 71164,        # IEA NZE 2050 全球总用电量 (TWh/年)
    "baseload_fraction": 0.09,      # 基荷比例 9%
    "max_path_nodes": 6,            # 输电路径最大节点数
    "remove_intercontinental": False,  # 保留所有跨洲际链路
    "manual_trans_zeros": [],       # 不需要手动置零的链路
    "previous_optimal_file": None,  # 不依赖前序情景
    "nonlcon_data_name": "NonlConData_reRun",
    "grid_filter": {
        "wind_ins_min_tw": 0.0001,  # 风电最小装机阈值 (TW)
        "wind_gen_min_twh": 10,     # 风电最小年发电量 (TWh)
        "solar_ins_min_tw": 0.001,  # 光伏最小装机阈值 (TW)
        "solar_gen_min_twh": 90,    # 光伏最小年发电量 (TWh)
    },
}

SCENARIO_SC_2040 = {
    "name": "SC_2040",
    "load_layer": 2,                # all_loads[2,:,:]（对应 MATLAB 第3层）
    "total_load_twh": 56553,        # 2040 全球总用电量 (TWh/年)
    "baseload_fraction": 0.11,      # 基荷比例 11%
    "max_path_nodes": 3,            # 输电路径最大节点数（洲内互联）
    "remove_intercontinental": True,   # 移除跨洲际链路
    "manual_trans_zeros": [         # 手动置零的特定链路 (MATLAB 索引, 转为 0-indexed)
        (5, 0), (6, 0),             # cur_trans(6,1)=0; cur_trans(7,1)=0
        (0, 5), (0, 6),             # cur_trans(1,6)=0; cur_trans(1,7)=0
        (16, 3), (17, 3),           # cur_trans(17,4)=0; cur_trans(18,4)=0
        (3, 16), (3, 17),           # cur_trans(4,17)=0; cur_trans(4,18)=0
    ],
    "previous_optimal_file": "Opt_SG_2050_Sel.mat",
    "nonlcon_data_name": "NonlConData2040_reRun",
    # 不使用阈值筛选，使用前序情景的最优解筛选格网
}

SCENARIO_SA_2030 = {
    "name": "SA_2030",
    "load_layer": 1,                # all_loads[1,:,:]（对应 MATLAB 第2层）
    "total_load_twh": 37316,        # 2030 全球总用电量 (TWh/年)
    "baseload_fraction": 0.36,      # 基荷比例 36%
    "max_path_nodes": 2,            # 输电路径最大节点数（仅相邻区域）
    "remove_intercontinental": True,   # 移除跨洲际链路
    "manual_trans_zeros": [         # 与 2040 相同的手动置零链路
        (5, 0), (6, 0),
        (0, 5), (0, 6),
        (16, 3), (17, 3),
        (3, 16), (3, 17),
    ],
    "previous_optimal_file": "Opt_SC_2040_Sel.mat",
    "nonlcon_data_name": "NonlConData2030_reRun",
}

# ======================================================================
# 物理参数
# ======================================================================

STORAGE_CHARGE_EFF = 0.95       # 储能充电效率
STORAGE_DISCHARGE_EFF = 0.95    # 储能放电效率
STORAGE_INITIAL_SOC = 0.5       # 储能初始荷电状态 (50%)
N_REGIONS = 20                  # 全球区域数
N_HOURS = 8760                  # 年小时数

# 装机密度 (MW/km²)
SOLAR_DENSITY = 74              # 光伏
WIND_OFFSHORE_DENSITY = 2.7     # 海上风电（默认值，适用于 landmask==0）
WIND_ONSHORE_DENSITY = 4.6      # 陆上风电（适用于 landmask==1）

# ======================================================================
# 成本模型 (USD/kW)
# ======================================================================

COST_TRANSMISSION = 98          # 输电成本 (USD/kW)
COST_STORAGE_ENERGY = 350       # 储能成本 (USD/kWh)
COST_OFFSHORE_WIND = 3461       # 海上风电成本 (USD/kW)

# 各洲光伏/风电单位成本 (USD/kW)
# 区域编号参考 Code_Documentation.md §四
# 注：MATLAB 代码中 Oceania 风电成本为 136.07，疑似笔误，此处修正为 1360.7
CONTINENT_COSTS = {
    # (solar_cost, wind_cost, region_range)
    # 亚洲: regions 9-13
    "asia":          {"solar": 927.6,  "wind": 1313},
    # 北美: region 1
    "north_america": {"solar": 1012.6, "wind": 1284.8},
    # 欧洲: regions 5-8
    "europe":        {"solar": 1075.9, "wind": 1650.4},
    # 拉美: regions 2-4
    "latin_america": {"solar": 861.4,  "wind": 1499.4},
    # 非洲: regions 16-20
    "africa":        {"solar": 1256.6, "wind": 1684.7},
    # 大洋洲: regions 14-15
    "oceania":       {"solar": 922.5,  "wind": 1360.7},
}

# 区域 → 洲际映射 (1-based region_id → continent_name)
REGION_CONTINENT = {
    1: "north_america",
    2: "latin_america", 3: "latin_america", 4: "latin_america",
    5: "europe", 6: "europe", 7: "europe", 8: "europe",
    9: "asia", 10: "asia", 11: "asia", 12: "asia", 13: "asia",
    14: "oceania", 15: "oceania",
    16: "africa", 17: "africa", 18: "africa", 19: "africa", 20: "africa",
}

# 区域 → 洲际映射，用于 numpy 向量化（按区域索引直接查表）
# continent_index[region_id] → cost_solar, cost_wind
def _build_cost_tables():
    """构建按区域编号索引的成本查找表 (1-indexed, 位置0未使用)"""
    n = N_REGIONS + 1
    solar_costs = np.zeros(n)
    wind_costs = np.zeros(n)
    for rid, cont in REGION_CONTINENT.items():
        solar_costs[rid] = CONTINENT_COSTS[cont]["solar"]
        wind_costs[rid] = CONTINENT_COSTS[cont]["wind"]
    return solar_costs, wind_costs

import numpy as np
SOLAR_COST_TABLE, WIND_COST_TABLE = _build_cost_tables()
