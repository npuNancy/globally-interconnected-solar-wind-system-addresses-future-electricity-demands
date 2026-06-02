# 说明（中文）

本代码集包含论文《Globally Interconnected Solar-wind System Addresses Future Electricity Demands》的分析代码，包括：

- 全球风能与太阳能潜力评估
- 全球互联情景下的空间布局优化
- 能源可及性公平（Energy Access Equity）分析

## 文件夹结构

### 1. GlobalPotential.zip
全球风能与太阳能潜力评估相关代码与数据。

- LUCC_Suitability_Add_Egrid_solar.tif：ArcGIS 输出的太阳能部署 LUCC 适宜性结果
- LUCC_Suitability_Add_Egrid_wind.tif：ArcGIS 输出的风机部署 LUCC 适宜性结果
- fishnet_area_global.tif：ArcGIS 输出的全球 1° × 1° 网格面积
- Global_fishnet.tif：ArcGIS 输出的大陆 1° × 1° 网格面积
- Wind_Annual_CF.tif：ArcGIS 输出的风电年平均容量因子
- Global_land_CF.mat：大陆 1° × 1° 网格内太阳能年平均容量因子
- Wind_Solar_AnnualPotential_025.tif：全球风能与太阳能年发电量结果（单位：TWh/年）

- 1.1_Simulate_Solar_CF_PVLIB.py: 使用 PVLIB 模拟太阳能容量因子的代码
- 1.2_Simulate_Wind_CF_windpowerlib.py: 使用 windpowerlib 模拟风电容量因子的代码
- 1.3_Calculate_Wind_Solar_Annual_Potential.m: 计算全球风能与太阳能年发电量的代码

### 2. Optimization.zip
全球互联情景下的空间布局优化相关代码与数据。

- Optimization_SG_2050.m：2050 年全球互联情景下获取最优空间布局的代码
- Global_Wind_Net_Area_Add_Egrid.tif：每个网格可用于风电部署的净陆地面积
- Global_Wind_Fishnet_Area.tif：ArcGIS 输出的用于风电潜力评估的全球 1° × 1° 网格面积
- Global_LandMask.tif：ArcGIS 输出的用于风电潜力评估的大陆 1° × 1° 网格面积
- Global_Wind_CFs_Sel.h5：部署风机的网格内风电年平均容量因子
- Global_fishnet.tif：ArcGIS 输出的用于太阳能潜力评估的全球 1° × 1° 网格面积
- Global_Solar_CFs.mat：大陆 1° × 1° 网格内太阳能年平均容量因子
- Global_Solar_Net_Area_Add_Egrid.tif：每个网格可用于太阳能部署的净陆地面积
- Global_Solar_Fishnet_Area.tif：ArcGIS 输出的用于太阳能潜力评估的大陆 1° × 1° 网格面积
- Global_Load_22region.mat：不同区域的预测负荷曲线
- Global_Grid_Division.tif：指示每个网格所属的区域电网
- Global_Init_State.mat：当前太阳能、风能、储能与输电容量

- OptFun_SG_Dispatch_2050.m：2050 年代全球互联情景下的电力调度分析代码
- nonlcon2050.m：2050 年代全球互联情景下的非线性约束函数
- NonlConData.mat：2050 年代全球互联情景下的非线性约束矩阵
- Global_Trans.mat：可能的跨区域输电路径及相应的损耗矩阵

- Optimization_SC_2040.m：2040 年洲际互联情景下获取最优空间布局的代码
- Opt_SG_2050_Sel.mat：2040 年布局优化的约束矩阵
- OptFun_SC_Dispatch_2040.m：2040 年代全球互联情景下的电力调度分析代码
- nonlcon2040.m：2040 年代全球互联情景下的非线性约束函数
- NonlConData2040.mat：2040 年代全球互联情景下的非线性约束矩阵

- Optimization_SA_2030.m：2030 年洲际互联情景下获取最优空间布局的代码
- Opt_SC_2040_Sel.mat：2030 年布局优化的约束矩阵
- OptFun_SA_Dispatch_2030.m：2030 年代全球互联情景下的电力调度分析代码
- nonlcon2030.m：2030 年代全球互联情景下的非线性约束函数
- NonlConData2030.mat：2030 年代全球互联情景下的非线性约束矩阵

### 3. Benefits.zip
潜在收益分析相关代码与数据。

- Benefits_Data_Summary.xlsx：用于支持潜在收益分析的统计数据
- EnergyEquity.m：绘制洛伦兹曲线并计算基尼系数的代码
- EnergyExchange.R：可视化跨区域电力传输的代码
- Pressure.txt：用于支持经济压力分析的数据
- Pressure.R：可视化经济压力（图 3e）的代码
- Smoothing_Effects.m：比较全球互联与独立电网情景下发电曲线波动的代码

### 4. Resilience.zip
全球互联系统韧性（resilience）分析相关代码与数据。

- Resilience_ClimateChange.m：气候变化情景代码
- Optimization_SA_2030_Res.h5：2030 年代优化结果
- Fun_SA_Dispatch_2030.m：在给定 2030 年代空间布局下进行电力调度分析的函数
- Optimization_SC_2040_Res.h5：2040 年代优化结果
- Fun_SC_Dispatch_2040.m：在给定 2040 年代空间布局下进行电力调度分析的函数
- Optimization_SG_2050_Res.h5：2050 年代优化结果
- Fun_SG_Dispatch_2050.m：在给定 2050 年代空间布局下进行电力调度分析的函数
- Resilience_GenerationFailture.m：极端天气事件情景代码
- Resilience_GreatPowerRivalry.m：区域政策不兼容情景代码
- Resilience_GeopolticalTensions.m：地缘政治紧张情景代码
- CompletingPrices.m：市场竞争情景代码


# 其他数据


| 数据类型 | 来源 | 下载地址 |
|----------|------|----------|
| **土地覆盖数据**（ESA CCI，~500m分辨率） | 欧洲空间局气候变化倡议 | https://doi.org/10.24381/cds.006f2c9a |
| **地形数据**（SRTM，航天飞机雷达地形任务） | NASA Earthdata | https://www.earthdata.nasa.gov/sensors/srtm |
| **全球道路数据**（GRIP数据集） | GLOBIO | https://www.globio.info/download-grip-dataset |
| **气象数据**（ERA5，逐小时太阳辐射/气温/风速） | Copernicus C3S CDS | https://doi.org/10.24381/cds.adbb2d47 |
| **GDP与人口预测**（SSP情景） | IIASA SSP数据库 | http://tntcat.iiasa.ac.at/SspDb |
| **太阳能/风能装机成本** | IRENA 2022年报告 | https://www.irena.org/Publications/2023/Aug/Renewable-power-generation-costs-in-2022 |
| **输电线路成本** | 德克萨斯大学/ERCOT | https://energy.utexas.edu/sites/default/files/UTAustin_FCe_TransmissionCosts_2017.pdf |
| **储能成本** | 美国能源部（DOE/PNNL） | https://www.pnnl.gov/ESGC-cost-performance |
| **可再生能源装机容量统计** | IRENA 2024年统计报告 | https://www.irena.org/Publications/2024/Jul/Renewable-energy-statistics-2024 |
| **海岸线与行政边界** | Natural Earth（公共域） | / |
| **专属经济区（EEZ）** | Flanders Marine Institute，CC BY 4.0 | / |

### 其他数据在各代码中的使用情况

| # | 数据类型 | 使用的代码文件 | 在代码中的体现方式 |
|---|---------|--------------|------------------|
| 1 | **土地覆盖数据**（ESA CCI） | ArcGIS 预处理 → `1.3_Calculate_Wind_Solar_Annual_Potential.m` + 所有 Optimization `.m` | 间接使用：经 ArcGIS 生成 `LUCC_Suitability_Add_Egrid_solar.tif` / `LUCC_Suitability_Add_Egrid_wind.tif`，代码直接读取这些 TIF |
| 2 | **地形数据**（SRTM） | ArcGIS 预处理 + `1.2_Simulate_Wind_CF_windpowerlib.py` | ArcGIS 生成适宜性 TIF；Python 中 ERA5 数据含粗糙度（roughness）也部分来源于地形 |
| 3 | **全球道路数据**（GRIP） | ArcGIS 预处理 | 间接使用：经 ArcGIS 参与生成 LUCC 适宜性 TIF |
| 4 | **气象数据**（ERA5） | `1.1_Simulate_Solar_CF_PVLIB.py` + `1.2_Simulate_Wind_CF_windpowerlib.py` | **直接读取**：Python 加载 HDF5 格式的小时级辐射/气温/风速/气压数据 |
| 5 | **GDP与人口预测**（SSP） | 预处理 → 所有 Optimization `.m` | 间接使用：预处理为 `Global_Load_22region.mat`（22区域逐时负荷，4层对应当前/2030/2040/2050），代码直接读取该 mat |
| 6 | **太阳能/风能装机成本**（IRENA） | `OptFun_SG_Dispatch_2050.m` + `OptFun_SC_Dispatch_2040.m` + `OptFun_SA_Dispatch_2030.m` + `Fun_*_Dispatch_*.m`（Resilience/） | **硬编码**为各洲差异化单价（如亚洲光伏 927.6 USD/kW、风电 1313 USD/kW 等），用于计算 `f(3)` 总成本 |
| 7 | **输电线路成本** | 同上 | **硬编码**为 98 USD/kW，用于计算输电成本分量 |
| 8 | **储能成本** | 同上 | **硬编码**为 350 USD/kWh，用于计算储能成本分量 |
| 9 | **可再生能源装机统计**（IRENA） | 预处理 → `Optimization_SG_2050.m` / `Optimization_SC_2040.m` / `Optimization_SA_2030.m` + `nonlcon*.m` | 间接使用：预处理为 `Global_Init_State.mat`（`cur_solar`, `cur_wind`），用于非线性约束——确保优化后各区域装机不低于当前水平 |
| 10 | **海岸线与行政边界**（Natural Earth） | ArcGIS 预处理 + `EnergyExchange.R`（可能用于地图底图） | ArcGIS 生成格网与掩膜 TIF；R 可视化中可能作为底图 |
| 11 | **专属经济区**（EEZ） | ArcGIS 预处理 → `1.2_Simulate_Wind_CF_windpowerlib.py` | 间接使用：生成 `Onshore_Offshore_Indicator.h5`（陆上=1/海上=2），Python 代码读取后选择对应风机参数 |

**总结**：以上 11 类数据中，仅 **ERA5 气象数据**（第 4 项）被代码直接从原始数据源读取；**装机/输电/储能成本**（第 6–8 项）以硬编码参数形式写入代码；其余数据均经 ArcGIS 或其他预处理，转化为 `.tif` / `.mat` / `.h5` 等中间文件后才被代码使用。

## ArcGIS 简介

### 什么是 ArcGIS？

**ArcGIS** 是由 Esri（Environmental Systems Research Institute）开发的**地理信息系统（GIS）**软件平台，用于地图制作、空间分析、地理数据管理和共享。

### ArcGIS 能做什么？

| 功能 | 说明 |
|------|------|
| **制图与可视化** | 将空间数据渲染为专业地图 |
| **空间分析** | 基于地理位置进行叠加分析、缓冲区分析、栅格计算等 |
| **栅格/矢量数据处理** | 处理遥感影像、地形、土地利用等空间栅格数据 |
| **地理计算** | 对空间数据进行批量运算（如面积计算、适宜性评价） |

### 怎么用 ArcGIS？

典型工作流：**导入空间数据（.tif、.shp 等）→ 空间分析/栅格计算 → 输出处理结果（.tif、.shp 等）**。操作方式以图形界面为主（ArcGIS Pro），也可通过 Python（ArcPy）脚本化。

### 本项目中 ArcGIS 做了什么？

本项目中的 ArcGIS 工作属于**上游数据预处理环节**，不在本代码集中体现。它负责将原始地理数据加工为代码可直接使用的 `.tif` / `.mat` 中间文件，具体产出：

| ArcGIS 产出文件 | 用到的原始数据 | 说明 |
|---|---|---|
| `LUCC_Suitability_Add_Egrid_solar.tif` | ESA CCI 土地覆盖 + SRTM 地形 + GRIP 道路 | 太阳能部署的 LUCC 适宜性（综合坡度、土地类型、距道路距离等） |
| `LUCC_Suitability_Add_Egrid_wind.tif` | 同上 | 风机部署的 LUCC 适宜性 |
| `fishnet_area_global.tif` / `Global_fishnet.tif` | Natural Earth 海岸线与行政边界 | 全球 1°×1° 网格面积 |
| `Global_LandMask.tif` | Natural Earth + EEZ | 陆地/海洋掩膜 |
| `Global_Grid_Division.tif` | Natural Earth 行政边界 | 每个网格所属的区域（1-20） |
| `Wind_Annual_CF.tif` | ERA5 气象数据 + EEZ | 风电年平均容量因子的 ArcGIS 侧汇总 |
| `Onshore_Offshore_Indicator.h5` | EEZ 专属经济区 | 陆上/海上标识（1=陆, 2=海） |

简言之：**ArcGIS 把卫星遥感、地形、道路、边界等原始空间数据"切分"成 1°×1° 网格并做适宜性评价，产出的 TIF 文件再被 Python/MATLAB 代码读取用于后续模拟和优化。**


