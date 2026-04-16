# 代码说明文档

> 论文："Globally Interconnected Solar-wind System Addresses Future Electricity Demands"
> Zenodo 存储: https://zenodo.org/records/14491983.
---

## 一、整体流程概览

本研究的方法论按以下四阶段流水线执行，各阶段依次依赖前序产出：

```
┌─────────────────────────┐
│ 阶段1: 全球资源潜力评估   │  GlobalPotential/
│  光伏/风电容量因子模拟    │  → 全球发电潜力空间分布
│  年发电量计算            │
└────────────┬────────────┘
             │ 发电量曲线、装机容量、地理格网数据
             ▼
┌─────────────────────────────┐
│ 阶段2: 空间布局优化           │  Optimization/
│  多目标优化 (NSGA-II)        │  → 帕累托最优解集
│  分阶段情景 (2030→2040→2050) │
└────────────┬────────────────┘
             │ 最优空间布局方案
             ▼
┌────────────────────────────┐
│ 阶段3: 效益分析             │  Benefits/
│  能源公平性 (洛伦兹曲线)     │
│  平滑效应、能源交换、经济压力 │
└────────────┬────────────────┘
             │
             ▼
┌────────────────────────────┐
│ 阶段4: 系统韧性分析          │  Resilience/
│  气候变化/发电中断/地缘政治  │
│  大国博弈/市场竞争          │
└────────────────────────────┘
```

---

## 二、各部分详细说明

### 2.1 全球资源潜力评估（GlobalPotential/）

#### 整体流程

```
ERA5气象数据 (小时级, 2000-2022)
         │
    ┌────┴────┐
    ▼         ▼
 光伏CF模拟   风电CF模拟          (Python)
 (GSEE模型)  (windpowerlib)
    │         │
    └────┬────┘
         ▼
  年发电潜力计算                    (MATLAB)
  面积×CF×装机密度
         │
         ▼
  Wind_Solar_AnnualPotential_025.tif (TWh/年)
```

---

#### 文件 1：`1.1_Simulate_Solar_CF_PVLIB.py`

- **语言**：Python
- **功能**：基于 GSEE（Global Solar Energy Estimator）模型模拟全球逐时光伏容量因子（Capacity Factor, CF）

**输入**：ERA5多年小时级气象数据（HDF5格式），包含：GSR（全局太阳辐射 W/m²）、DIR（直接辐射）、Temp（气温）、Wind（风速）；每个文件为1°×1°全球网格。

**核心参数**：倾角 `tilt = 0.35396×lat + 16.84775`（纬度自适应），方位角 `azim = 180`，固定支架 `tracking = 0`，额定容量 `capacity = 1000`。

**处理流程**：
1. 以2000个格点为一批次读取HDF5数据
2. 计算散射比：`diffuse_fraction = (GSR - DIR) / GSR`
3. 构建 xarray Dataset（维度：time × lat × lon）
4. 使用 GSEE 的 `resample_for_gsee` 函数进行76核并行计算
5. 将结果乘以10后取整为 uint16 存储

**输出**：按时刻存储的HDF5文件 `PV_GSEE_Tilt_YYYYMMDDHH.h5`，包含变量 `PV`（720×1440，即0.25°分辨率全球网格的CF值）。

**依赖库**：numpy, pandas, xarray, h5py, gsee, multiprocessing, joblib, scipy

---

#### 文件 2：`1.2_Simulate_Wind_CF_windpowerlib.py`

- **语言**：Python
- **功能**：基于 windpowerlib 库模拟全球逐时风电容量因子

**输入**：`Wind_S{year}.h5`（共22年，每年约30000个格点的小时级气象数据），包含气压(kPa)、温度(K)、10m风速、粗糙度(m)、100m风速；`Onshore_Offshore_Indicator.h5`（陆上=1/海上=2标识）。

**风机参数**：
陆上采用 GE 2.5MW 风机（额定2.53MW，轮毂高度120m，切入风速3m/s，额定风速12m/s，切出风速25m/s）；
海上采用 Vestas 8MW 风机（额定8MW，轮毂高度120m，切入风速4m/s，额定风速13m/s，切出风速25m/s）。
风电场总装机3GW（2×1.5GW），效率系数0.9。

**处理流程**：
1. 逐年循环，读取气象数据和陆/海标识
2. 根据经度计算当地时区，将UTC转换为当地时间
3. 构建多级索引天气DataFrame（变量名+高度层）
4. 根据陆上/海上标识选择对应风机功率曲线
5. 使用 `TurbineClusterModelChain` 计算风电场输出
6. CF = 功率输出 / (1000×1000×3000)

**输出**：`Wind_Farm_CF_{year}.h5`（每个格点×8760小时的容量因子矩阵）。

**依赖库**：numpy, pandas, h5py, windpowerlib

---

#### 文件 3：`1.3_Calculate_Wind_Solar_Annual_Potential.m`

- **语言**：MATLAB
- **功能**：计算全球0.25°×0.25°分辨率的风电和光伏年发电潜力

**输入**：
- `LUCC_Suitability_Add_Egrid_solar.tif`：ArcGIS 输出的太阳能部署 LUCC 适宜性结果
- `LUCC_Suitability_Add_Egrid_wind.tif`：ArcGIS 输出的风机部署 LUCC 适宜性结果
- `fishnet_area_global.tif`：ArcGIS 输出的全球 1° × 1° 网格面积
- `Global_fishnet.tif`：ArcGIS 输出的大陆 1° × 1° 网格面积
- `Wind_Annual_CF.tif`：ArcGIS 输出的风电年平均容量因子
- `Global_land_CF.mat`：大陆 1° × 1° 网格内太阳能年平均容量因子
- `Wind_Solar_AnnualPotential_025.tif`：全球风能与太阳能年发电量结果（单位：TWh/年）

**装机密度**：光伏 74 MW/km²；陆上风电 2.7 MW/km²；海上风电 4.6 MW/km²。

**计算公式**：
- 风电 `gen = density × area × 8760 × CF`；
- 光伏 `gen = 74 × area × annual_CF`。

**处理流程**：
1. 读取风电适宜性格网和面积，区分陆上/海上计算装机容量和年发电量
2. 读取光伏CF和面积，计算光伏装机和发电量
3. 将风电和光伏潜力叠加到720×1440全球格网
4. 输出GeoTIFF

**输出**：`Wind_Solar_AnnualPotential_025.tif`（全球年发电潜力，单位 TWh/年，0.25°分辨率）。

---

### 2.2 空间布局优化（Optimization/）

#### 整体流程

优化采用自上而下的三阶段嵌套策略：

```
2050 全球互联 (S-G)
  │  结果约束上界
  ▼
2040 洲际互联 (S-C)
  │  结果约束上界
  ▼
2030 邻近互联 (S-A)
```

每个阶段共享相同的数据准备流程和优化框架结构，主要差异在于：
- **负荷年份和总量**不同（2030: 37316 TWh, 2040: 56553 TWh, 2050: 71164 TWh）
- **基荷比例**不同（2030: 36%, 2040: 11%, 2050: 9%）
- **输电路径最大节点数**不同（2030: 2, 2040: 3, 2050: 6）
- **输电网络拓扑**不同（2030仅邻近互联，2040洲际互联，2050全球互联）

**与 2050 的关键差异**

| 参数 | 2050（S-G） | 2040（S-C） | 2030（S-A） |
|-----------|-----------|-----------|-----------|
| 负荷层（0-indexed） | 3 | 2 | 1 |
| 总负荷（TWh） | 71164 | 56553 | 37316 |
| 基荷占比 | 9% | 11% | 36% |
| `max_path_nodes` | 6 | 3 | 2 |
| 网格筛选 | 阈值筛选 | 上一情景最优解 | 上一情景最优解 |
| 储能/输电上界（UB） | 固定（load\*1000、72h、10000 GW） | 使用上一情景的最优值 | 使用上一情景的最优值 |
| 移除洲际互联 | 否 | 是 | 是 |
| 手动将 `cur_trans` 置零 | 否 | 是（8 条连线） | 是（8 条连线） |
| 上一情景最优文件 | N/A | `Opt_SG_2050_Sel.mat` | `Opt_SC_2040_Sel.mat` |
| `NonlConData` 文件 | `NonlConData` | `NonlConData2040` | `NonlConData2030` |


#### 优化变量编码

决策变量向量 `scale` 编码如下：

- `scale(1:N_grid)`：各格网是否建设（0/1），整数变量，取值 {0, 1}
- `scale(N_grid+1:N_grid+20)`：20个区域的储能功率（GW），连续变量，取值 当前值 ~ 最大负荷
- `scale(N_grid+21:N_grid+40)`：20个区域的储能时长（小时），连续变量，取值 2 ~ 72
- `scale(N_grid+41:end)`：各输电线路功率（GW），连续变量，取值 当前值 ~ 上界

#### 调度模型逻辑（所有 Dispatch 函数共有的核心逻辑）

```
对每个小时 t = 1...8760:
  1. 计算各区域净发电量: surplus = 发电 - 负荷 - 基荷
  2. 跨区域输电调度:
     - 优先输向传输损耗最小的路径
     - 输电量 = min(剩余盈余, 输电容量, 目标区域缺口/损耗补偿)
  3. 储能调度:
     - 盈余 → 充电（受储能功率和容量上限约束）
     - 缺口 → 放电（受储能功率和剩余电量约束）
  4. 记录弃电(curtailed)和灵活需求(flexible)
```

#### 三个优化目标

1. **弃电率** `f(1) = curtailed / total_generation`
2. **1 - 渗透率** `f(2) = flexible / total_load`
3. **总成本** `f(3) = 装机成本 + 输电成本 + 储能成本`（单位：十亿美元）

#### 成本计算模型

各洲的光伏和风电单位成本不同（分为两个梯队），海上风电统一为 3461 USD/kW：
- **亚洲**：光伏/风电 927.6 / 1313 USD/kW
- **北美**：光伏/风电 1012.6 / 1284.8 USD/kW
- **欧洲**：光伏/风电 1075.9 / 1650.4 USD/kW
- **拉美**：光伏/风电 861.4 / 1499.4 USD/kW
- **非洲**：光伏/风电 1256.6 / 1684.7 USD/kW
- **大洋洲**：光伏/风电 922.5 / 1360.7 USD/kW

输电成本：98 USD/kW；储能成本：350 USD/kWh。

> 注：代码中根据 `CGrid_Index(:,1)` 的区域编号范围判断所属洲，再用 `index <= nonlsol` 和 `index > nonlsol` 区分光伏和风电，分别乘以对应区域的单位成本。

---

#### 文件 4：`Optimization_SG_2050.m`

- **语言**：MATLAB
- **功能**：2050年全球互联情景（S-G）的空间布局优化主程序

**输入**：
- 风电/光伏GeoTIFF数据（净面积、格网面积、陆海掩膜），

- `Global_Wind_Net_Area_Add_Egrid.tif` — 风电净可用面积占比（百分比）
- `Global_Wind_Fishnet_Area.tif` — 风电格网面积（km²）
- `Global_LandMask.tif` — 陆地/海洋掩膜（>100=陆, <100=海）
- `Global_Wind_CFs_Sel.h5`（风电CF），部署风机的网格内风电年平均容量因子

- `Global_Solar_Net_Area_Add_Egrid.tif` — 光伏净可用面积占比（百分比）
- `Global_Solar_Fishnet_Area.tif` — 光伏格网面积（km²）
- `Global_fishnet.tif` — 陆地格网标识（<65536 = 有效陆地格网）
- `Global_Solar_CFs.mat`（光伏CF），大陆 1° × 1° 网格内太阳能年平均容量因子

- `Global_Load_22region.mat`（22区域负荷，取第4层=2050），不同区域的预测负荷曲线
- `Global_Grid_Division.tif`（区域划分），
- `Global_Init_State.mat`（当前储能和输电状态），当前太阳能、风能、储能与输电容量
- `Global_Trans.mat`（输电拓扑和损耗）。可能的跨区域输电路径及相应的损耗矩阵

**数据准备**：
1. 读取风电适宜格网，按陆上/海上计算装机和发电曲线，过滤装机 < 0.1MW 和年发电 < 10TWh 的格网
2. 读取光伏适宜格网，计算装机和发电曲线，过滤装机 < 1MW 和年发电 < 90TWh 的格网
3. 合并风光数据，加载2050负荷（总需求 71164 TWh）
4. 构建区域归属索引，保存非线性约束数据 `NonlConData.mat`

**优化配置**：决策变量 = 格网选择(N) + 储能功率(20) + 储能时长(20) + 输电功率(输电线路数)，整数约束，`gamultiobj` + `@gaplotpareto` 实时显示帕累托前沿。

**输出**：`Optimization_SG_2050_Res.h5`，其中 `/res_scale` 为帕累托解集矩阵，`/prs` 为帕累托前沿。

---

#### 文件 5：`Optimization_SC_2040.m`

- **语言**：MATLAB
- **功能**：2040年洲际互联情景（S-C）的空间布局优化主程序

**输入**：与2050类似，额外加载 `Opt_SG_2050_Sel.mat`（2050最优解：`opt_trans`, `opt_stoCap`, `opt_stoPow`, `opt_wind`, `opt_solar`）。

**与2050的关键差异**：
1. 负荷取第3层 = 2040年（总需求 56553 TWh）
2. 候选格网限制为2050优化中选中的格网
3. 储能和输电上界取2050最优解的值
4. 移除跨洲际输电线路（NA↔EU, SA↔AF）
5. 使用 `OptFun_SC_Dispatch_2040` 和 `nonlcon2040`

**输出**：`NonlConData2040.mat`，`Optimization_SC_2040_Res.h5`。

---

#### 文件 6：`Optimization_SA_2030.m`

- **语言**：MATLAB
- **功能**：2030年邻近互联情景（S-A）的空间布局优化主程序

**输入**：与2040类似，额外加载 `Opt_SC_2040_Sel.mat`（2040最优解）。

**与2040的关键差异**：
1. 负荷取第2层 = 2030年（总需求 37316 TWh）
2. 候选格网限制为2040优化中选中的格网
3. 储能和输电上界取2040最优解的值
4. 使用 `OptFun_SA_Dispatch_2030` 和 `nonlcon2030`

**输出**：`NonlConData2030.mat`，`Optimization_SA_2030_Res.h5`。

---

#### 文件 7：`OptFun_SG_Dispatch_2050.m`

- **语言**：MATLAB（函数）
- **功能**：2050年全球互联情景的多目标调度函数

**输入参数**：
- `ins_cap`：各格网装机容量（TW）
- `gens`：各格网8760h发电曲线（TWh）
- `loads`：20区域8760h负荷（TW）
- `CGrid_Index`：格网区域归属 + 陆海标识
- `scale`：决策变量向量

**调度参数**：基荷比例 9%（IEA NZE情景），储能效率充/放各 95%，输电路径最大6节点，`trans_connections > 0` 全部启用。

**处理流程**：
1. 恢复布局决策 → 计算各区域发电曲线
2. 扣除基荷
3. 恢复输电网络，计算所有可能输电路径及损耗
4. 8760小时逐时调度
5. 计算区域差异化成本

**输出**：`f(1)` 弃电率, `f(2)` 1-渗透率, `f(3)` 总成本（USD billion）。

---

#### 文件 8：`OptFun_SC_Dispatch_2040.m`

- **语言**：MATLAB（函数）
- **功能**：2040年洲际互联情景的多目标调度函数

与2050的关键差异：
- 基荷比例：11%
- 移除跨洲际链路（`trans_connections == 2 → 0`）
- 输电路径最大3节点
- 使用 `NonlConData2040.mat`

---

#### 文件 9：`OptFun_SA_Dispatch_2030.m`

- **语言**：MATLAB（函数）
- **功能**：2030年邻近互联情景的多目标调度函数

与2050的关键差异：
- 基荷比例：36%（更高的灵活性电源需求）
- 移除跨洲际链路
- 输电路径最大2节点（仅邻近互联）
- 使用 `NonlConData2030.mat`

---

#### 文件 10-12：`nonlcon2050.m` / `nonlcon2040.m` / `nonlcon2030.m`

- **语言**：MATLAB（函数）
- **功能**：非线性约束函数，确保各区域风光装机不低于当前水平

**输入**：决策变量 `x`。

**处理流程**：
1. 加载对应年份的约束数据和当前装机量
2. 分别计算20个区域的光伏和风电规划装机（`x × ins_cap`）
3. 约束 `c(1)` = 光伏低于当前水平的区域数, `c(2)` = 风电低于当前水平的区域数

**输出**：`c`（不等式约束，要求 c ≤ 0 即所有区域均不低于当前），`ceq = []`（无等式约束）。

---

### 2.3 效益分析（Benefits/）

---

#### 文件 13：`EnergyEquity.m`

- **语言**：MATLAB
- **功能**：绘制洛伦兹曲线（Lorenz Curve）并计算基尼系数（Gini Coefficient），评估能源公平性

**输入**：`Benefits_Data_Summary.xlsx`（EnergyInequality 工作表）。

**四个情景**：Independent（独立运行）, Neighbour（邻近互联）, Continent（洲际互联）, Global（全球互联）。

**处理流程**：
1. 按人均指标升序排列各区域
2. 计算人口和发电量的累积份额
3. 用梯形法计算基尼系数
4. 绘制4条洛伦兹曲线 + 1:1对角线

**输出**：洛伦兹曲线图（Figure），`gini_cof` 数组（4个基尼系数）。

---

#### 文件 14：`Smoothing_Effects.m`

- **语言**：MATLAB
- **功能**：比较全球互联系统与独立电网的发电波动性（平滑效应分析）

**输入**：风电/光伏发电数据（同优化模块），`Optimization_SG_2050_Res.h5`（2050最优解，帕累托解#66）。

**处理流程**：
1. 加载最优布局，计算20个区域逐日发电量（365天）
2. 添加第21列 = 全球总量
3. 计算各区域和全球的变异系数 CV = std/mean
4. 归一化后绘制所有区域 + 全球的日发电曲线
5. 绘制CV柱状图

**输出**：归一化日发电曲线图（20区域 + 全球），CV柱状图。

---

#### 文件 15：`EnergyExchange.R`

- **语言**：R
- **功能**：可视化区域间能源交换（弦图/Chord Diagram）

**输入**：`Benefits_Data_Summary.xlsx`（EnergyExchange 工作表，20×20矩阵）。

**处理流程**：
1. 读取20×20能源交换矩阵
2. 转换为TW（除以1000）
3. 使用 `circlize` 包的 `chordDiagram` 绘制弦图

**输出**：20区域间能源交换弦图。

**依赖包**：readxl, circlize, tidyverse, ggsci

---

#### 文件 16：`Pressure.R`

- **语言**：R
- **功能**：可视化各区域的经济压力（极坐标柱状图/南丁格尔玫瑰图，即论文 Fig. 3e）

**输入**：`Pressure.txt`（包含列 P1, P2，共20行对应20区域）。

**处理流程**：
1. 读取压力数据
2. 将角度均匀分配到 360°（每18°一个区域）
3. 使用 ggplot2 绘制极坐标柱状图
4. 分别绘制 P1、P2 单图和对比图

**输出**：极坐标柱状图（南丁格尔玫瑰图）。

**依赖包**：ggplot2

---

### 2.4 系统韧性分析（Resilience/）

#### 整体说明

韧性分析基于优化后的最优空间布局，在5种扰动情景下重新运行调度模型，评估系统性能的下降程度。所有韧性脚本共享相同的数据准备流程（加载发电/负荷/输电数据）。

---

#### 文件 17：`Resilience_ClimateChange.m`

- **语言**：MATLAB
- **功能**：气候变化不确定性下的系统韧性分析

**输入**：各时段优化结果（`.h5`），风电/光伏/负荷数据。

**扰动方式**：Monte Carlo模拟（200次）—— 选中格网发电量加 ±5% 随机扰动，未选中格网加 ±1%，负荷加 ±10%。

**评估指标**：渗透率偏差（`sens_climate`），报告最大值、P90、P50。

**处理流程**：分三段执行：
1. 2030 S-A（解#5，基荷36%）
2. 2040 S-C（解#15，基荷11%）
3. 2050 S-G（解#66，基荷9%）

每段进行200次Monte Carlo模拟。

**输出**：`sens_climate` 偏差统计（百分比），max, P90, P50 分位数。

---

#### 文件 18：`Resilience_GenerationFailture.m`

- **语言**：MATLAB
- **功能**：极端天气事件导致发电中断情景下的系统韧性分析

**输入**：2050 S-G 优化结果（解#66），风电/光伏/负荷/输电数据。

**扰动方式**：依次关闭每个区域的全部发电（`scale=0`），保持输电网络运行。

**评估方式**：对每个区域计算4种输电范围下的供电可靠性下降—— maxNodes=6（全球互联）、3（洲际互联）、2（邻近互联）、0（完全独立）。

**处理流程**：
1. 基线运行（全系统正常）→ 得到基准渗透率
2. 逐区域关闭 → 分别用3种输电范围调度
3. 计算各情景下的可靠性下降 Δ = (1-f(2)-基荷) - baseline

**输出**：`res_supply`（20区域×4种互联水平的可靠性下降），boxplot。

---

#### 文件 19：`Resilience_GeopolticalTensions.m`

- **语言**：MATLAB
- **功能**：地缘政治紧张局势导致输电中断情景下的系统韧性分析

**输入**：2050 S-G 优化结果（解#66），输电网络数据。

**扰动方式**：依次断开每个区域的所有输电线路（`trans_power(ii,:)=0; trans_power(:,ii)=0`）。

**评估指标**：弃电率变化、渗透率变化、与该区域输电容量的相关性。

**处理流程**：
1. 基线运行
2. 逐区域断开输电
3. 重新构建决策变量（仅保留未断开的输电线路）
4. 调度并记录结果
5. 绘制弃电率变化柱状图和与输电容量的散点图

**输出**：`res`（20区域×2：弃电率偏差、渗透率偏差），`res_power`（输电容量统计），柱状图和散点图。

---

#### 文件 20：`Resilience_GreatPowerRivalry.m`

- **语言**：MATLAB
- **功能**：大国博弈情景（区域间政策不协调，各国独立规划后叠加到全球系统中）

**输入**：2050 S-G 最优解，独立运行优化结果（`Optimization_SI_2050_Res.h5`），全格网发电数据。

**扰动方式**：将独立优化中各区域额外规划的装机容量叠加到全球互联布局上（上限 ≤ 1 即满选）。

**处理流程**：
1. 加载全格网数据（不过滤小格网）
2. 将S-G解映射到全格网
3. 逐区域叠加独立优化的额外装机
4. 调度并记录弃电率和渗透率变化

**输出**：`res`（20区域×2：弃电率偏差、渗透率偏差），柱状图。

---

#### 文件 21：`CompletingPrices.m`

- **语言**：MATLAB
- **功能**：市场竞争情景（电价竞争对系统可靠性的影响）

**输入**：2050 S-G 最优解，全格网发电数据。

**扰动方式**：对每个目标区域，将其他19个区域的电价权重从1.1×到3.0×逐步提高（每次增加10%），目标区域保持1.0×不变。

**评估指标**：目标区域供电可靠性的边际变化。

**处理流程**：
1. 基线运行得到各区域基准可靠性
2. 双重循环：20个目标区域 × 20个价格水平
3. 计算可靠性变化 Δ = 目标区域可靠性 - 基准
4. 计算边际敏感度

**输出**：`res`（20×20敏感性矩阵），边际敏感度柱状图，散点图。

---

#### 文件 22-24：`Fun_SA_Dispatch_2030.m` / `Fun_SC_Dispatch_2040.m` / `Fun_SG_Dispatch_2050.m`

- **语言**：MATLAB（函数）
- **功能**：韧性分析专用的调度函数，与Optimization中的 `OptFun_*_Dispatch_*` 逻辑一致，但额外返回详细中间变量

**输入**：`ins_cap`, `gens`, `loads`, `CGrid_Index`, `scale`

**额外输出**（相比优化模块中的对应函数）：
- `con`：直接消纳电量（8760×20）
- `flex`：灵活需求电量（8760×20）
- `curtail`：弃电量（8760×20）
- `storage`：储电量（8761×20）
- `shifted`：跨区转移电量（8760×20×20）

---

## 三、关键数据文件索引

### Optimization/ 目录

- `Global_Wind_Net_Area_Add_Egrid.tif` — 风电净可用面积占比（百分比）
- `Global_Wind_Fishnet_Area.tif` — 风电格网面积（km²）
- `Global_LandMask.tif` — 陆地/海洋掩膜（>100=陆, <100=海）
- `Global_Wind_CFs_Sel.h5` — 风电逐时容量因子（筛选后格网）
- `Global_fishnet.tif` — 陆地格网标识（<65536 = 有效陆地格网）
- `Global_Solar_CFs.mat` — 光伏逐时容量因子（变量 `res_CF`，需÷10÷1000）
- `Global_Solar_Net_Area_Add_Egrid.tif` — 光伏净可用面积占比
- `Global_Solar_Fishnet_Area.tif` — 光伏格网面积（km²）
- `Global_Load_22region.mat` — 22区域逐时负荷预测（4层：当前/2030/2040/2050）
- `Global_Grid_Division.tif` — 全球格网的区域归属（1-20）
- `Global_Init_State.mat` — 当前装机状态（`cur_solar`, `cur_wind`, `cur_storage`, `cur_trans`）
- `Global_Trans.mat` — 输电拓扑（`trans_connections`）和损耗（`trans_loss`）
- `NonlConData.mat` / `NonlConData2040.mat` / `NonlConData2030.mat` — 非线性约束矩阵
- `Opt_SG_2050_Sel.mat` — 2050最优解（约束2040的上界）
- `Opt_SC_2040_Sel.mat` — 2040最优解（约束2030的上界）

### Benefits/ 目录

- `Benefits_Data_Summary.xlsx` — 统计数据（EnergyInequality, EnergyExchange 工作表）
- `Pressure.txt` — 各区域经济压力数据（P1, P2列）

### Resilience/ 目录

- `Optimization_SA_2030_Res.h5` — 2030优化结果
- `Optimization_SC_2040_Res.h5` — 2040优化结果
- `Optimization_SG_2050_Res.h5` — 2050优化结果

---

## 四、20个区域编号对照

代码中的区域编号（`CGrid_Index(:,1)`）对应关系如下（根据代码中的区域条件推断）：

- 1: 北美 (North America)
- 2: 中美 (Central America)
- 3: 加勒比 (Caribbean)
- 4: 南美 (South America)
- 5: 北欧 (Northern Europe)
- 6: 西欧 (Western Europe)
- 7: 东欧 (Eastern Europe)
- 8: 南欧 (Southern Europe)
- 9: 中亚 (Central Asia)
- 10: 南亚 (South Asia)
- 11: 东亚 (East Asia)
- 12: 东南亚 (Southeast Asia)
- 13: 大洋洲部分 (Oceania-Asia)
- 14: 澳大利亚/新西兰 (Aus/NZ)
- 15: 太平洋岛屿 (Pacific Islands)
- 16: 北非 (North Africa)
- 17: 西非 (West Africa)
- 18: 中非 (Central Africa)
- 19: 东非 (East Africa)
- 20: 南非 (Southern Africa)

---

## 五、全局假设与参数汇总

- **储能充/放效率**：95% / 95%（`toStorageLoss` / `fromStorageLoss`）
- **储能初始SOC**：50%（`stored_ele(1,:) = storageCap * 0.5`）
- **光伏装机密度**：74 MW/km²
- **陆上风电装机密度**：2.7 MW/km²
- **海上风电装机密度**：4.6 MW/km²
- **输电成本**：98 USD/kW
- **储能成本**：350 USD/kWh
- **求解算法**：`gamultiobj`（NSGA-II），MATLAB全局优化工具箱
- **时间分辨率**：8760小时/年（逐时调度）
- **格网分辨率**：1°×1°（评估），0.25°×0.25°（潜力输出）
- **全球区域划分**：20个区域（6大洲细分为20个子区域）
