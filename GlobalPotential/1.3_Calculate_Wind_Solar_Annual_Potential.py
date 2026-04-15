"""
1.3_Calculate_Wind_Solar_Annual_Potential.py

功能：计算全球 0.25°×0.25° 分辨率的风电和光伏年发电潜力。

由 MATLAB 脚本 1.3_Calculate_Wind_Solar_Annual_Potential.m 改写而来，
保持原始逻辑、功能、计算公式完全一致。

输出：Wind_Solar_AnnualPotential_025_reRun.tif（全球年发电潜力，单位 TWh/年）
"""

import numpy as np
from scipy.io import loadmat
from scipy.ndimage import zoom
import rasterio
from rasterio.transform import from_bounds
from rasterio.crs import CRS

# ==================== 初始化 ====================
# 创建 720×1440 的零矩阵（对应全球 0.25°×0.25° 格网）
final_res = np.zeros((720, 1440))

# ======================================================================
# 第一部分：风电潜力计算
# ======================================================================

# --- 读取风电用地适宜性数据 ---
# 原始值为百分比整数（如 50 表示 50%），需要除以 100 转为比例值
with rasterio.open('LUCC_Suitability_Add_Egrid_wind.tif') as src:
    luccs = src.read(1).astype(np.float64)
luccs = luccs / 100  # 转换为百分比比例（0~1）

# 获取适宜性大于 0 的格网位置（布尔掩码）
# 对应 MATLAB 中的 index = find(luccs > 0)
mask = luccs > 0

# --- 读取全球格网面积数据 ---
# fishnet_area_global.tif 为 1°×1° 分辨率（180×360），单位 km²
with rasterio.open('fishnet_area_global.tif') as src:
    fish_area = src.read(1).astype(np.float64)

# 将面积重采样到 720×1440（0.25°×0.25°），使用最近邻插值
# 对应 MATLAB 的 imresize(fish_area, [720,1440], 'nearest')
zoom_h = 720 / fish_area.shape[0]
zoom_w = 1440 / fish_area.shape[1]
fish_area = zoom(fish_area, (zoom_h, zoom_w), order=0)

# 每个 1°×1° 格网被细分为 16 个 0.25°×0.25° 子格网，面积按比例缩小
fish_area = fish_area / 16

# 计算风电适宜面积 = 适宜性比例 × 格网面积（km²）
areas = luccs[mask] * fish_area[mask]

# --- 读取风电年容量因子 ---
with rasterio.open('Wind_Annual_CF.tif') as src:
    CFs = src.read(1).astype(np.float64)
CFs = CFs[mask]

# --- 读取陆地/海洋掩膜 ---
# Global_LandMask.tif 位于 Optimization/ 目录下
# 值 > 100 为陆地（设为 1），值 < 100 为海洋（设为 0）
with rasterio.open('../Optimization/Global_LandMask.tif') as src:
    landmask = src.read(1).astype(np.float64)

landmask[landmask < 100] = 0   # 海洋
landmask[landmask > 100] = 1   # 陆地
# 注意：值恰好等于 100 的保持不变

# 将掩膜重采样到 720×1440（最近邻插值）
landmask = zoom(landmask, (720 / landmask.shape[0], 1440 / landmask.shape[1]), order=0)
landmask = landmask[mask]

# --- 计算风电年发电量 ---
# 公式：装机密度(MW/km²) × 面积(km²) × 8760(h) × 容量因子 / 10^6 = TWh/年
# 默认先按海上风电装机密度 2.7 MW/km² 计算所有格网
gen_wind = (2.7 * areas) * (8760 * CFs) / 1000 / 1000

# 陆地区域（landmask==1）覆盖为陆上风电装机密度 4.6 MW/km²
gen_wind[landmask == 1] = (4.6 * areas[landmask == 1]) * \
    (8760 * CFs[landmask == 1]) / 1000 / 1000

# 将风电结果写入最终结果矩阵的对应位置
final_res[mask] = gen_wind

# ======================================================================
# 第二部分：光伏潜力计算
# ======================================================================

# --- 读取全球格网标识文件 ---
# Global_fishnet.tif 为 180×360（1°×1°）分辨率的陆地格网标识
# 值 < 65536 的格网为有效陆地格网
with rasterio.open('Global_fishnet.tif') as src:
    grids = src.read(1).astype(np.float64)

# 获取有效陆地格网的位置
grid_mask = grids < 65536
# 将有效陆地格网的标识值清零（对应 MATLAB 的 grids(index) = 0）
grids[grid_mask] = 0

# --- 加载光伏容量因子数据 ---
# res_CF 为 (N_grids, 8760) 矩阵，N_grids 为有效陆地格网数
# 原始数据为 uint16，需要先除以 10 再除以 1000 进行单位转换
mat_data = loadmat('Global_land_CF.mat')
res_CF = mat_data['res_CF'].astype(np.float64)
res_CF = res_CF / 10 / 1000

# 沿时间维度（axis=1）求和，得到每个格网的年总容量因子（等效满发小时数/比例）
# 对应 MATLAB 的 nansum(res_CF, 2)
res_CF = np.nansum(res_CF, axis=1)

# --- 将光伏年容量因子映射到 180×360 全球格网 ---
CFs_solar = np.zeros((180, 360))
CFs_solar[grid_mask] = res_CF

# 重采样到 720×1440（0.25°×0.25°），最近邻插值
CFs_solar = zoom(CFs_solar, (720 / 180, 1440 / 360), order=0)

# --- 读取光伏用地适宜性数据 ---
with rasterio.open('LUCC_Suitability_Add_Egrid_solar.tif') as src:
    luccs = src.read(1).astype(np.float64)
luccs = luccs / 100  # 转换为百分比比例

# --- 重新读取全球格网面积数据并重采样 ---
with rasterio.open('fishnet_area_global.tif') as src:
    fish_area = src.read(1).astype(np.float64)
fish_area = zoom(fish_area, (720 / fish_area.shape[0], 1440 / fish_area.shape[1]), order=0)
fish_area = fish_area / 16

# 获取光伏适宜性大于 0 的格网位置
solar_mask = luccs > 0

# 计算光伏适宜面积
areas = luccs[solar_mask] * fish_area[solar_mask]

# --- 计算光伏年发电量 ---
# 公式：装机密度 74 MW/km² × 面积(km²) × 年容量因子 / 10^6 = TWh/年
# 光伏的年容量因子已经是年总等效小时（经 nansum 得到），不需要再乘 8760
gen_solar = (74 * areas) * CFs_solar[solar_mask] / 1000 / 1000

# 将光伏结果叠加到最终结果矩阵
final_res[solar_mask] = final_res[solar_mask] + gen_solar

# ======================================================================
# 第三部分：输出 GeoTIFF
# ======================================================================

# 构建空间参考信息
# 全球范围：纬度 -90° ~ 90°，经度 -180° ~ 180°
# 分辨率：0.25°×0.25°（720 行 × 1440 列）
# 起始行从北方开始（ColumnsStartFrom='north'）
transform = from_bounds(-180, -90, 180, 90, 1440, 720)

output_filename = 'Wind_Solar_AnnualPotential_025_reRun.tif'
with rasterio.open(
    output_filename,
    'w',
    driver='GTiff',
    height=720,
    width=1440,
    count=1,
    dtype=final_res.dtype,
    crs=CRS.from_epsg(4326),
    transform=transform,
) as dst:
    dst.write(final_res, 1)

print(f'输出文件：{output_filename}')
print(f'数据范围：{final_res.min():.6f} ~ {final_res.max():.6f} TWh/年')
print(f'非零格网数：{np.count_nonzero(final_res)}')
