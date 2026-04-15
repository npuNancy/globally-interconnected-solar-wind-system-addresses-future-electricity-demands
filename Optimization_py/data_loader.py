"""
data_loader.py — 数据加载模块

加载所有 GeoTIFF、HDF5、MAT 输入文件，返回结构化数据。
对应 Optimization_SG_2050.m / Optimization_SC_2040.m / Optimization_SA_2030.m 的数据准备阶段。
支持三套情景:
  - 2050 S-G: 使用阈值筛选候选格网
  - 2040 S-C: 从 2050 最优解中筛选格网
  - 2030 S-A: 从 2040 最优解中筛选格网
"""

import numpy as np
import rasterio
import h5py
from scipy.io import loadmat, savemat
from .config import (
    SCENARIO_SG_2050,
    SOLAR_DENSITY,
    WIND_ONSHORE_DENSITY,
    WIND_OFFSHORE_DENSITY,
    N_REGIONS,
    N_HOURS,
)


def load_previous_optimal(opt_dir: str, filename: str) -> dict:
    """
    加载前序情景的最优解数据。

    对应 MATLAB: load Opt_SG_2050_Sel / load Opt_SC_2040_Sel

    参数:
        opt_dir:  数据目录
        filename: MAT 文件名 (如 "Opt_SG_2050_Sel.mat")

    返回:
        opt_solar: (180, 360) uint8, 1=选中的光伏格网
        opt_wind:  (180, 360) uint8, 1=选中的风电格网
        opt_stoPow: (1, 20) 前序情景的储能功率 (GW)
        opt_stoCap: (1, 20) 前序情景的储能时长 (h)
        opt_trans: (20, 20) 前序情景的输电容量 (GW)
    """
    mat_data = loadmat(f"{opt_dir}/{filename}")
    return {
        "opt_solar": mat_data["opt_solar"].astype(np.float64),
        "opt_wind": mat_data["opt_wind"].astype(np.float64),
        "opt_stoPow": mat_data["opt_stoPow"].flatten().astype(np.float64),
        "opt_stoCap": mat_data["opt_stoCap"].flatten().astype(np.float64),
        "opt_trans": mat_data["opt_trans"].astype(np.float64),
    }


def load_wind_data(opt_dir: str, previous_optimal: dict = None) -> dict:
    """
    加载风电空间数据和发电曲线。

    对应 Optimization_SG_2050.m 第2-27行（阈值筛选）
    或 Optimization_SC_2040.m / Optimization_SA_2030.m（前序最优筛选）。

    参数:
        opt_dir: 数据目录
        previous_optimal: 若非 None，从中筛选格网（2040/2030 情景）

    返回:
        win_index:  1D int, 风电格网的线性索引（在全局格网中）
        wind_ins:   1D float (TW), 筛选后的装机容量
        wind_gen:   2D float (N_wind x 8760), TWh/h 的发电曲线
        landmask:   1D int, 筛选后格网的陆海标识 (0=海, 1=陆)
    """
    # 读取风电用地适宜性数据（百分比，原始值需除以100）
    with rasterio.open(f"{opt_dir}/Global_Wind_Net_Area_Add_Egrid.tif") as src:
        luccs = src.read(1).astype(np.float64)
    luccs = luccs / 100

    # 获取适宜性大于0的格网位置
    win_index = np.where(luccs.flatten() > 0)[0]
    mask = luccs > 0

    # 读取风电格网面积 (km²)
    with rasterio.open(f"{opt_dir}/Global_Wind_Fishnet_Area.tif") as src:
        fish_area = src.read(1).astype(np.float64)

    # 计算适宜面积
    areas = luccs[mask] * fish_area[mask]

    # 读取陆海掩膜
    with rasterio.open(f"{opt_dir}/Global_LandMask.tif") as src:
        landmask_raw = src.read(1).astype(np.float64)
    landmask_raw[landmask_raw < 100] = 0  # 海洋
    landmask_raw[landmask_raw > 100] = 1  # 陆地
    landmask = landmask_raw[mask]

    # 计算装机容量 (TW)
    # 默认海上风电密度 2.7 MW/km², 陆上 4.6 MW/km²
    wind_ins = (WIND_OFFSHORE_DENSITY * areas) / 1e6  # TW
    wind_ins[landmask == 1] = (WIND_ONSHORE_DENSITY * areas[landmask == 1]) / 1e6

    # 读取风电容量因子并计算发电曲线
    with h5py.File(f"{opt_dir}/Global_Wind_CFs_Sel.h5", "r") as f:
        wind_gen = f["/data"][:].astype(np.float64)
    # 注意：HDF5 存储可能转置，确保 shape 为 (N_grids, 8760)
    if wind_gen.shape[0] == N_HOURS:
        wind_gen = wind_gen.T

    # 发电量 = CF × 装机容量 (TWh)
    wind_gen = wind_gen * wind_ins[:, np.newaxis]

    if previous_optimal is not None:
        # ---- 2040/2030: 使用前序最优解筛选格网 ----
        # 对应 MATLAB: win_index2=find(opt_wind==1);
        #              [~, loc]=ismember(win_index2, win_index);
        #              wind_ins=wind_ins(loc); ...
        opt_wind_flat = previous_optimal["opt_wind"].flatten()
        win_index2 = np.where(opt_wind_flat > 0)[0]
        # ismember: 在 win_index 中找到 win_index2 的位置
        sorter = np.argsort(win_index)
        loc = np.searchsorted(win_index, win_index2, sorter=sorter)
        loc = sorter[np.clip(loc, 0, len(sorter) - 1)]
        valid = win_index[sorter[loc]] == win_index2
        loc = loc[valid]
        # 筛选
        wind_gen = wind_gen[loc]
        wind_ins = wind_ins[loc]
        win_index = win_index[loc]
        landmask = landmask[loc]
    else:
        # ---- 2050: 使用阈值筛选格网 ----
        # 第一轮筛选：装机 > 0.0001 TW
        valid = wind_ins > 0.0001
        wind_gen = wind_gen[valid]
        wind_ins = wind_ins[valid]
        win_index = win_index[valid]
        landmask = landmask[valid]

        # 第二轮筛选：保留年发电量 < 10 TWh 的格网（匹配 MATLAB 代码逻辑）
        # MATLAB: wind_ind2=win_index(tmp>=10); tmp=tmp<10; 保留 tmp<10
        annual_gen = wind_gen.sum(axis=1)
        valid = annual_gen < 10
        wind_gen = wind_gen[valid]
        wind_ins = wind_ins[valid]
        win_index = win_index[valid]
        landmask = landmask[valid]

    print(f"风电: 筛选后保留 {len(win_index)} 个格网, " f"总装机 {wind_ins.sum()*1000:.1f} GW")

    return {
        "win_index": win_index,
        "wind_ins": wind_ins,
        "wind_gen": wind_gen,
        "landmask": landmask,
    }


def load_solar_data(opt_dir: str, previous_optimal: dict = None) -> dict:
    """
    加载光伏空间数据和发电曲线。

    对应 Optimization_SG_2050.m 第29-56行（阈值筛选）
    或 Optimization_SC_2040.m / Optimization_SA_2030.m（前序最优筛选）。

    参数:
        opt_dir: 数据目录
        previous_optimal: 若非 None，从中筛选格网（2040/2030 情景）

    返回:
        solar_index: 1D int, 光伏格网的线性索引
        solar_ins:   1D float (TW), 筛选后的装机容量
        solar_gen:   2D float (N_solar x 8760), TWh/h 的发电曲线
    """
    # 读取全球格网标识（1°×1° 分辨率）
    with rasterio.open(f"{opt_dir}/Global_fishnet.tif") as src:
        grids = src.read(1).astype(np.float64)

    # 有效陆地格网标识值 < 65536
    solar_index = np.where(grids.flatten() < 65536)[0]
    grid_mask = grids < 65536

    # 加载光伏容量因子数据
    mat_data = loadmat(f"{opt_dir}/Global_Solar_CFs.mat")
    res_CF = mat_data["res_CF"].astype(np.float64)
    res_CF = res_CF / 10.0 / 1000.0  # 单位转换

    # 读取光伏用地适宜性数据
    with rasterio.open(f"{opt_dir}/Global_Solar_Net_Area_Add_Egrid.tif") as src:
        luccs = src.read(1).astype(np.float64)
    luccs = luccs / 100

    # 读取光伏格网面积 (km²)
    with rasterio.open(f"{opt_dir}/Global_Solar_Fishnet_Area.tif") as src:
        fish_area = src.read(1).astype(np.float64)
    fish_area[fish_area < 0] = 0

    # 计算适宜面积（使用 solar_index 作为线性索引提取 luccs 和 fish_area 的值）
    # 对应 MATLAB: areas = luccs(solar_index) .* fish_area(solar_index)
    luccs_flat = luccs.flatten()
    fish_area_flat = fish_area.flatten()
    areas = luccs_flat[solar_index] * fish_area_flat[solar_index]

    # 计算装机容量 (TW) 和发电曲线 (TWh)
    solar_ins = (SOLAR_DENSITY * areas) / 1e6
    solar_gen = res_CF * solar_ins[:, np.newaxis]

    if previous_optimal is not None:
        # ---- 2040/2030: 使用前序最优解筛选格网 ----
        # 对应 MATLAB: solar_index2=find(opt_solar==1);
        #              [~, loc]=ismember(solar_index2, solar_index);
        #              solar_ins=solar_ins(loc); ...
        opt_solar_flat = previous_optimal["opt_solar"].flatten()
        solar_index2 = np.where(opt_solar_flat > 0)[0]
        # ismember: 在 solar_index 中找到 solar_index2 的位置
        sorter = np.argsort(solar_index)
        loc = np.searchsorted(solar_index, solar_index2, sorter=sorter)
        loc = sorter[np.clip(loc, 0, len(sorter) - 1)]
        valid = solar_index[sorter[loc]] == solar_index2
        loc = loc[valid]
        # 筛选
        solar_gen = solar_gen[loc]
        solar_ins = solar_ins[loc]
        solar_index = solar_index[loc]
    else:
        # ---- 2050: 使用阈值筛选格网 ----
        # 第一轮筛选：装机 > 0.001 TW
        valid = solar_ins > 0.001
        solar_gen = solar_gen[valid]
        solar_ins = solar_ins[valid]
        solar_index = solar_index[valid]

        # 第二轮筛选：保留年发电量 < 90 TWh 的格网（匹配 MATLAB 代码逻辑）
        # MATLAB: solar_ind2=solar_index(tmp>=90); tmp=tmp<90; 保留 tmp<90
        annual_gen = solar_gen.sum(axis=1)
        valid = annual_gen < 90
        solar_gen = solar_gen[valid]
        solar_ins = solar_ins[valid]
        solar_index = solar_index[valid]

    print(f"光伏: 筛选后保留 {len(solar_index)} 个格网, " f"总装机 {solar_ins.sum()*1000:.1f} GW")

    return {
        "solar_index": solar_index,
        "solar_ins": solar_ins,
        "solar_gen": solar_gen,
    }


def load_load_profiles(opt_dir: str, scenario: dict = None) -> np.ndarray:
    """
    加载电力负荷曲线。

    对应 Optimization_SG_2050.m 第64-67行。

    返回:
        all_loads: (20, 8760) float, 各区域逐时负荷 (TW)
    """
    if scenario is None:
        scenario = SCENARIO_SG_2050

    mat_data = loadmat(f"{opt_dir}/Global_Load_22region.mat")
    all_loads = mat_data["all_loads"].astype(np.float64)

    # 提取对应年份的负荷层（MATLAB 索引从1开始，Python 从0开始）
    layer = scenario["load_layer"]
    # all_loads shape: (layers, 20, 8760) 或类似
    all_loads = all_loads[layer, :, :]  # (20, 8760)
    # squeeze 处理可能的额外维度
    all_loads = np.squeeze(all_loads) / 1e6  # GW → TW

    # 归一化到目标总负荷
    total_load = all_loads.sum()
    target = scenario["total_load_twh"]  # TWh/年
    # total_load 是 TW × 8760h 的总和 = TWh/年
    all_loads = all_loads / (total_load.sum() / target)

    print(f"负荷: 总需求 {all_loads.sum():.0f} TWh/年 " f"(目标 {target} TWh/年)")

    return all_loads


def load_grid_division(opt_dir: str) -> np.ndarray:
    """
    读取全球区域划分图。

    返回:
        grid_ind: 2D int, 每个格网的区域编号 (1-20)
    """
    with rasterio.open(f"{opt_dir}/Global_Grid_Division.tif") as src:
        grid_ind = src.read(1).astype(np.float64)
    return grid_ind


def load_transmission_data(opt_dir: str, scenario: dict = None) -> dict:
    """
    加载输电网络拓扑和损耗数据。

    返回:
        trans_connections: (20, 20) int, 连接矩阵
        trans_loss: (20, 20) float, 损耗矩阵
    """
    if scenario is None:
        scenario = SCENARIO_SG_2050

    mat_data = loadmat(f"{opt_dir}/Global_Trans.mat")
    trans_connections = mat_data["trans_connections"].astype(np.float64)
    trans_loss = mat_data["trans_loss"].astype(np.float64)

    # 将所有 > 0 的连接设为 1
    trans_connections[trans_connections > 0] = 1

    # 如果情景需要移除跨洲际链路 (trans_connections==2)
    # 2050 S-G 不移除，2040 S-C 和 2030 S-A 移除
    if scenario.get("remove_intercontinental", False):
        # 原始值中 2 表示跨洲际链路，已在上面被设为1
        # 需要从原始数据重新处理
        mat_data2 = loadmat(f"{opt_dir}/Global_Trans.mat")
        tc_raw = mat_data2["trans_connections"].astype(np.float64)
        tc_raw[tc_raw == 2] = 0
        tc_raw[tc_raw > 0] = 1
        trans_connections = tc_raw

    return {
        "trans_connections": trans_connections,
        "trans_loss": trans_loss,
    }


def load_init_state(opt_dir: str) -> dict:
    """
    加载当前装机状态数据。

    返回:
        cur_solar, cur_wind, cur_storage: (20,) float, 各区域当前装机 (GW)
        cur_trans: (20, 20) float, 当前输电容量 (GW)
    """
    mat_data = loadmat(f"{opt_dir}/Global_Init_State.mat")
    return {
        "cur_solar": mat_data["cur_solar"].flatten().astype(np.float64),
        "cur_wind": mat_data["cur_wind"].flatten().astype(np.float64),
        "cur_storage": mat_data["cur_storage"].flatten().astype(np.float64),
        "cur_trans": mat_data["cur_trans"].astype(np.float64),
    }


def build_combined_data(
    solar: dict,
    wind: dict,
    all_loads: np.ndarray,
    opt_dir: str,
    scenario: dict = None,
) -> dict:
    """
    合并光伏和风电数据，构建优化所需的数据结构。

    对应 Optimization_SG_2050.m 第58-92行。

    返回:
        all_gens:      (N_total, 8760) 发电量矩阵 (TWh/h)
        all_ins:       (N_total,) 装机容量 (TW)
        CGrid_Index:   (N_total, 3) [区域编号, 0, 陆海标识]
        all_loads:     (20, 8760) 负荷曲线 (TW)
        nonlsol:       int, 光伏格网数
        nonlwin:       int, 风电格网数
        cur_solar_tw:  (20,) 当前光伏装机 (TW)
        cur_wind_tw:   (20,) 当前风电装机 (TW)
    """
    if scenario is None:
        scenario = SCENARIO_SG_2050

    # 合并发电量和装机数据
    all_gens = np.vstack([solar["solar_gen"], wind["wind_gen"]])
    all_ins = np.concatenate([solar["solar_ins"], wind["wind_ins"]])

    nonlsol = len(solar["solar_ins"])
    nonlwin = len(wind["wind_ins"])
    print(f"合并: {nonlsol} 光伏 + {nonlwin} 风电 = {nonlsol + nonlwin} 候选格网")

    # 读取区域划分
    grid_ind = load_grid_division(opt_dir)
    grid_flat = grid_ind.flatten()

    # 构建 CGrid_Index
    n_total = nonlsol + nonlwin
    CGrid_Index = np.zeros((n_total, 3), dtype=np.float64)

    # 第1列: 区域编号 (1-20)
    solar_regions = grid_flat[solar["solar_index"]]
    wind_regions = grid_flat[wind["win_index"]]
    CGrid_Index[:nonlsol, 0] = solar_regions
    CGrid_Index[nonlsol:, 0] = wind_regions

    # 第2列: 初始为0（优化过程中被 round(scale) 覆盖）
    CGrid_Index[:, 1] = 0

    # 第3列: 陆海标识（仅风电格网有值，光伏格网为0）
    CGrid_Index[nonlsol:, 2] = wind["landmask"]

    # 加载当前装机状态（用于约束）
    init_state = load_init_state(opt_dir)
    cur_solar_tw = init_state["cur_solar"] / 1e6  # GW → TW
    cur_wind_tw = init_state["cur_wind"] / 1e6

    # 保存 NonlConData （与 MATLAB 兼容）
    nonlcon_name = scenario.get("nonlcon_data_name", "NonlConData_reRun")
    nonlcon_sel = CGrid_Index[:, 0:1].copy()  # 只取区域编号列
    nonlcon_ins = all_ins.copy()
    savemat(
        f"{opt_dir}/../Optimization_py/{nonlcon_name}.mat",
        {
            "nonlcon_sel": nonlcon_sel,
            "nonlcon_ins": nonlcon_ins,
            "nonlsol": nonlsol,
            "nonlwin": nonlwin,
        },
    )

    return {
        "all_gens": all_gens,
        "all_ins": all_ins,
        "CGrid_Index": CGrid_Index,
        "all_loads": all_loads,
        "nonlsol": nonlsol,
        "nonlwin": nonlwin,
        "cur_solar_tw": cur_solar_tw,
        "cur_wind_tw": cur_wind_tw,
    }


def build_variable_bounds(
    combined: dict,
    opt_dir: str,
    scenario: dict = None,
) -> dict:
    """
    构建决策变量的上下界。

    对应 Optimization_SG_2050.m 第96-109行。

    变量布局:
        [0, n_grid):                    格网选择 (0/1)
        [n_grid, n_grid+20):            储能功率 (GW)
        [n_grid+20, n_grid+40):         储能时长 (h)
        [n_grid+40, n_grid+40+n_trans): 输电功率 (GW)

    返回:
        n_grid:     格网选择变量数
        n_trans:    输电变量数
        lb, ub:     1D float, 上下界
        trans_mask: (20, 20) bool, 哪些链路有决策变量
    """
    if scenario is None:
        scenario = SCENARIO_SG_2050

    n_grid = len(combined["all_ins"])

    # 加载输电拓扑和初始状态
    trans_data = load_transmission_data(opt_dir, scenario)
    trans_connections = trans_data["trans_connections"]
    init_state = load_init_state(opt_dir)

    # 输电链路掩码
    cur_trans = init_state["cur_trans"]
    cur_trans[cur_trans < 2] = 0  # 小于2 GW 的视为无连接
    trans_mask = cur_trans > 0
    n_trans = int(trans_mask.sum())

    # 储能功率上下界 (GW)
    al = combined["all_loads"].max(axis=1)  # 各区域最大负荷 (TW)
    cur_storage = init_state["cur_storage"]

    storage_pow_lb = cur_storage / 1e3  # GW (原始单位可能是 MW)
    storage_pow_ub = al * 1e3  # TW → GW (MATLAB: al*1000)

    # 确保下界非负
    storage_pow_lb = np.maximum(storage_pow_lb, 0)

    # 储能时长上下界 (h)
    storage_dur_lb = np.full(N_REGIONS, 2.0)
    storage_dur_ub = np.full(N_REGIONS, 72.0)

    # 输电功率上下界 (GW)
    trans_lb = cur_trans[trans_mask] / 1e3  # → GW
    trans_ub = np.full(n_trans, 10000.0)  # GW

    # 组装完整上下界
    lb = np.concatenate(
        [
            np.zeros(n_grid),  # 格网选择
            storage_pow_lb,  # 储能功率
            storage_dur_lb,  # 储能时长
            trans_lb,  # 输电功率
        ]
    )
    ub = np.concatenate(
        [
            np.ones(n_grid),  # 格网选择
            storage_pow_ub,  # 储能功率
            storage_dur_ub,  # 储能时长
            trans_ub,  # 输电功率
        ]
    )

    print(f"变量: {n_grid} 格网 + 40 储能 + {n_trans} 输电 = {len(lb)} 总变量")

    return {
        "n_grid": n_grid,
        "n_trans": n_trans,
        "lb": lb,
        "ub": ub,
        "trans_mask": trans_mask,
        "trans_connections": trans_connections,
        "trans_loss": trans_data["trans_loss"],
    }


def build_variable_bounds_from_previous(
    combined: dict,
    opt_dir: str,
    previous_optimal: dict,
    scenario: dict,
) -> dict:
    """
    从前序情景最优解构建决策变量的上下界（用于 2040/2030 情景）。

    对应 Optimization_SC_2040.m / Optimization_SA_2030.m 第87-102行。
    与 build_variable_bounds() 的区别:
      - 储能功率上界 = 前序情景的 opt_stoPow
      - 储能时长上界 = 前序情景的 opt_stoCap
      - 输电功率上界 = 前序情景的 opt_trans
      - 手动置零特定链路后再构建掩码

    参数:
        combined:          build_combined_data() 的返回值
        opt_dir:           数据目录
        previous_optimal:  load_previous_optimal() 的返回值
        scenario:          情景参数 (SC_2040 或 SA_2030)

    返回:
        与 build_variable_bounds() 相同结构的字典
    """
    n_grid = len(combined["all_ins"])

    # 加载输电拓扑和初始状态
    trans_data = load_transmission_data(opt_dir, scenario)
    trans_connections = trans_data["trans_connections"]
    init_state = load_init_state(opt_dir)

    # 输电链路掩码
    cur_trans = init_state["cur_trans"].copy()

    # 手动置零特定链路
    for (i, j) in scenario.get("manual_trans_zeros", []):
        cur_trans[i, j] = 0

    cur_trans[cur_trans < 2] = 0  # 小于2 GW 的视为无连接
    trans_mask = cur_trans > 0
    n_trans = int(trans_mask.sum())

    # 储能功率上下界 (GW)
    cur_storage = init_state["cur_storage"]
    storage_pow_lb = np.maximum(cur_storage / 1e3, 0)  # 下界: 当前装机
    storage_pow_ub = previous_optimal["opt_stoPow"]      # 上界: 前序最优

    # 储能时长上下界 (h)
    storage_dur_lb = np.full(N_REGIONS, 2.0)
    storage_dur_ub = previous_optimal["opt_stoCap"]       # 上界: 前序最优

    # 输电功率上下界 (GW)
    opt_trans = previous_optimal["opt_trans"]
    trans_lb = cur_trans[trans_mask] / 1e3  # 下界: 当前容量
    trans_ub = opt_trans[trans_mask]         # 上界: 前序最优

    # 组装完整上下界
    lb = np.concatenate(
        [
            np.zeros(n_grid),       # 格网选择
            storage_pow_lb,         # 储能功率
            storage_dur_lb,         # 储能时长
            trans_lb,               # 输电功率
        ]
    )
    ub = np.concatenate(
        [
            np.ones(n_grid),        # 格网选择
            storage_pow_ub,         # 储能功率
            storage_dur_ub,         # 储能时长
            trans_ub,               # 输电功率
        ]
    )

    print(f"变量: {n_grid} 格网 + 40 储能 + {n_trans} 输电 = {len(lb)} 总变量")

    return {
        "n_grid": n_grid,
        "n_trans": n_trans,
        "lb": lb,
        "ub": ub,
        "trans_mask": trans_mask,
        "trans_connections": trans_connections,
        "trans_loss": trans_data["trans_loss"],
    }
