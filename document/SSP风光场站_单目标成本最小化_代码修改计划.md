# SSP 风光场站单目标成本最小化：代码修改计划

## 1. 修改目标

将 `dev-SSPs-cost-only` 分支当前的 NSGA-II 三目标优化：

```text
minimize:
    弃电率
    灵活电源比例（等价于最大化风光渗透率）
    风光-储能-输电投资成本
```

修改为单目标成本最小化：

```text
minimize:
    风光扩张年度化增量系统成本

subject to:
    MIN_VRE_SHARE <= 风光渗透率 <= MAX_VRE_SHARE
    逐小时供需调度逻辑
    已有装机容量约束
    储能与输电容量约束
```

主版本不改变以下设定：

- 基荷年度占比均匀分摊至 8,760 小时；
- 场站格网变量保持 0/1；
- 既有逐小时调度顺序；
- 2030 年 S-A、2040/2050 年 S-C 的互联拓扑；
- 弃电率不再作为优化目标，保留为输出诊断指标；
- 灵活电源运行成本默认关闭，但保留接口。

---

## 2. 成本边界

新增了运维成本和可选的灵活电源运行成本，它们都是年度费用；现有风光、储能和输电成本则是一次性投资。如果直接相加，单位不一致。因此，推荐使用“风光扩张年度化增量系统成本”，单位统一为 `billion USD / year`：

```text
annual_total_cost =
    annualized_vre_capex
  + annualized_storage_capex
  + annualized_interregional_tx_capex
  + annual_vre_om
  + optional_annual_storage_om
  + optional_annual_tx_om
  + optional_flexible_generation_opex
```

### 2.1 风光建设成本

第一版继续使用当前代码已经存在的区域差异化 CAPEX，避免一次修改过多：

- 光伏：按洲使用已有 `USD/kW` 系数；
- 陆上风电：按洲使用已有 `USD/kW` 系数；
- 海上风电：继续使用 `3461 USD/kW`。

### 2.2 储能建设成本

第一版继续使用当前代码：

```text
350 USD/kWh
```

即：

```text
storage_capex_billion = 350 * storage_capacity_TWh
```

### 2.3 跨区域输电建设成本：增加线路长度

#### 当前计算方式

当前 `OptFun_*_Dispatch_*.m` 在调度完成后，按照输电容量之和计算跨区域输电建设成本：

```matlab
trans_power=zeros(20,20);
trans_power(trans_connections==1)=scale(length(CGrid_Index)+41:end)/1000; % TW
obj_cost=obj_cost+98*sum(trans_power(:));
```

即：

```text
跨区域输电建设成本 = 98 × Σ 每条线路的输电容量
```

该方式没有考虑线路长度，因此短距离线路和长距离线路的单位容量建设成本相同。

#### 修改方案

改为：

```text
跨区域输电建设成本 = Σ 每条线路的容量 × 线路长度 × 单位输电成本
```

统一单位：

```text
线路容量：TW
线路长度：km
单位输电成本：billion USD / (TW·km)
跨区域输电建设成本：billion USD
```

沿用当前优化变量中的全部输电容量，不额外区分已有容量和新增容量。沿用当前有向线路矩阵 `trans_connections`，不改变输电拓扑和逐小时调度逻辑。

#### 区域间距离计算

新增脚本：

```text
utils/build_transmission_distance_matrix.py
```

参考仓库根目录的 `plot_transmission_network.py`：

1. 读取 `Global_Grid_Division.tif`；
2. 使用光伏与风电适宜网格掩膜过滤海洋像元；
3. 对 20 个区域分别计算地理中心经纬度；
4. 使用两个区域地理中心之间的大圆距离作为区域间线路长度；
5. 仅对 `trans_connections > 0` 的线路保存距离。

输出：

```text
Global_Trans_CostData.mat
    trans_distance_km      20×20
```

#### 具体代码修改

新增配置项，写入 `utils/cost_model_config.m`：

```matlab
TX_UNIT_COST_BILLION_PER_TW_KM = ...;  % billion USD / (TW·km)
```

在 `OptFun_SC_Dispatch_2050_costmin.m`、`OptFun_SC_Dispatch_2040_costmin.m` 和 `OptFun_SA_Dispatch_2030_costmin.m` 中，将原有：

```matlab
obj_cost=obj_cost+98*sum(trans_power(:));
```

替换为：

```matlab
load Global_Trans_CostData.mat trans_distance_km
run('../utils/cost_model_config.m');

tx_capex_billion = TX_UNIT_COST_BILLION_PER_TW_KM * ...
    sum(trans_power(:) .* trans_distance_km(:));

obj_cost = obj_cost + tx_capex_billion;
```

结果文件中增加输出指标：

```text
transmission_capacity_TW
transmission_distance_weighted_TW_km
transmission_capex_billion_USD
```

其中：

```matlab
transmission_distance_weighted_TW_km = ...
    sum(trans_power(:) .* trans_distance_km(:));
```

### 2.4 运维成本

第一版增加风光固定 O&M：

```text
annual_pv_om      = pv_capex      * 0.01
annual_onwind_om  = onwind_capex  * 0.03
annual_offwind_om = offwind_capex * 0.03
```

储能和跨区域输电 O&M 暂时保留配置接口：

```text
ENABLE_STORAGE_OM = false
ENABLE_TX_OM      = false
```

将这些比例全部放入配置文件，不要直接写死在目标函数中。

### 2.5 灵活电源运行成本

当前代码已经计算每个小时、每个区域需要的灵活电源电量：`flexible_ele(time_ind, gg_ind)`


默认关闭，但保留接口：

```text
ENABLE_FLEXIBLE_OPEX = false
FLEXIBLE_MC_USD_PER_MWH = zeros(20, 1)
```

启用后：

```text
flexible_opex_billion =
    sum_r,t(flexible_ele_TWh(r,t) * flexible_mc_USD_per_MWh(r)) / 1000
```

因为: `TWh × USD/MWh ÷ 1000 = billion USD`

由于当前模型只有聚合后的 `flexible_ele`，并未区分水电、气电、煤电或其他灵活资源，第一版不应直接写死一个边际成本。

### 2.6 年度化

增加统一的资本回收系数：

```text
CRF(r,n) = r * (1+r)^n / ((1+r)^n - 1)
annualized_capex = upfront_capex * CRF
```

建议配置项：

```text
WACC = 0.074
LIFETIME_PV = 25
LIFETIME_ONWIND = 25
LIFETIME_OFFWIND = 25
LIFETIME_STORAGE = 15
LIFETIME_TX = 40
```

所有值均放入配置文件，可做敏感性分析。

---

## 3. 建议新增的共享文件

### 3.1 `utils/cost_model_config.m`

集中存放：

- CAPEX；
- WACC 与寿命；
- O&M 比例；
- 跨区域输电单位成本与线路长度；
- 灵活电源成本开关；
- 弃电约束与弃电成本开关；
- 兼容旧成本口径的开关。

建议保留：

```text
COST_MODE = 'legacy_capex' | 'annualized_incremental'
TX_UNIT_COST_BILLION_PER_TW_KM = ...
ENABLE_FLEXIBLE_OPEX = false
ENABLE_CURTAILMENT_CONSTRAINT = false
ENABLE_CURTAILMENT_COST = false
```

### 3.2 `utils/evaluate_dispatch_and_cost.m`

将逐小时调度与成本核算封装成一个共享函数，返回结构体：

```text
metrics.curtailment_rate
metrics.flexible_ratio
metrics.vre_share
metrics.total_annual_cost
metrics.cost_breakdown.vre_capex
metrics.cost_breakdown.storage_capex
metrics.cost_breakdown.tx_capex
metrics.cost_breakdown.vre_om
metrics.cost_breakdown.flexible_opex
metrics.grid_gens
metrics.flexible_ele
metrics.curtailed_ele
```

调度逻辑第一版直接从现有 `OptFun_*_Dispatch_*.m` 平移，不调整基荷、0/1 选址和充放电顺序。

### 3.3 `utils/objective_total_cost.m`

只返回标量：

```matlab
function f = objective_total_cost(scale, model_data, scenario_cfg, cost_cfg)
    metrics = evaluate_dispatch_and_cost(scale, model_data, scenario_cfg, cost_cfg);
    f = metrics.total_annual_cost;
end
```

### 3.4 `utils/nonlcon_costmin.m`

加入 VRE 上下界：

```text
c_vre_lower = MIN_VRE_SHARE - vre_share
c_vre_upper = vre_share - MAX_VRE_SHARE
```

保留既有最低装机约束。

可选保留弃电率约束接口：

```text
if ENABLE_CURTAILMENT_CONSTRAINT
    c_curtailment = curtailment_rate - MAX_CURTAILMENT
end
```

### 3.5 `utils/build_transmission_distance_matrix.py`

生成：

```text
Global_Trans_CostData.mat
    trans_distance_km      20x20
```

线路距离统一使用区域地理中心之间的大圆距离。区域地理中心的计算参考仓库根目录 `plot_transmission_network.py`：基于光伏与风电适宜网格掩膜过滤海洋像元后，对每个区域的有效格网经纬度取均值。仅对 `trans_connections > 0` 的线路写入距离，其余位置保持为 0。

---

## 4. 对现有文件的修改

## 4.1 第一阶段：只修改 SSP245 2050，保留旧代码

新增平行文件，不直接覆盖：

```text
Optimization_ssp245/Optimization_SC_2050_costmin.m
Optimization_ssp245/OptFun_SC_Dispatch_2050_costmin.m
Optimization_ssp245/nonlcon2050_costmin.m
Optimization_ssp245/convert_costmin_h5_to_sel.m
```

### `Optimization_SC_2050_costmin.m`

将：

```matlab
[res_scale,prs] = gamultiobj(...)
```

替换为：

```matlab
[best_scale,best_cost,exitflag,output,population,scores] = ga(...)
```

理由：方案 C 是单目标成本最小化，不需要生成 Pareto 前沿。

### `OptFun_SC_Dispatch_2050_costmin.m`

从三目标：

```matlab
f(1) = curtailment_rate;
f(2) = flexible_ratio;
f(3) = obj_cost;
```

改为：

```matlab
f = metrics.total_annual_cost;
```

但仍输出日志和 sidecar 指标：

```text
curtailment_rate
flexible_ratio
vre_share
cost_breakdown
```

### `nonlcon2050_costmin.m`

除已有装机约束外，增加：

```matlab
c(end+1) = min_vre_share - metrics.vre_share;
c(end+1) = metrics.vre_share - max_vre_share;
```

### `convert_costmin_h5_to_sel.m`

单目标模式下不再调用 Pareto preferred solution 筛选函数。直接：

1. 读取唯一最优解；
2. 校验 VRE 上下界；
3. 输出弃电率、灵活电源比例和成本分解；
4. 映射为 `Opt_SC_2050_Sel.mat`。

---

## 4.2 第二阶段：推广至 SSP245 2040 和 2030

对应新增：

```text
Optimization_ssp245/Optimization_SC_2040_costmin.m
Optimization_ssp245/Optimization_SA_2030_costmin.m
```

注意：当前 2040、2030 脚本分别使用：

```text
ConstraintTolerance = 4
ConstraintTolerance = 8
```

来容忍部分区域的既有风电约束未满足。

增加 VRE 比例约束后，不能继续使用这种全局宽松容差，否则 `0.1` 量级的 VRE 约束违反也会被错误容忍。

正确做法：

```text
ConstraintTolerance = 1e-6
```

并将允许违反区域数量显式写入约束：

```text
c_existing_wind = unmet_wind_region_count - ALLOWED_UNMET_WIND_REGIONS
```

配置：

```text
ALLOWED_UNMET_WIND_REGIONS_2040 = 4
ALLOWED_UNMET_WIND_REGIONS_2030 = 8
```

---

## 4.3 第三阶段：推广至 SSP126 和 SSP560

复制经过验证的共享函数，仅替换情景配置：

```text
DEMAND_YEAR
BASE_LOAD_RATIO_YEAR
MIN_VRE_SHARE_YEAR
MAX_VRE_SHARE_YEAR
interconnection_mode
```

避免维护 9 份重复成本函数。

---

## 5. 结果文件格式

为了兼容旧流程，可以继续保存：

```text
/res_scale    1 x nvars
/prs          1 x 3
```

其中：

```text
prs(1) = curtailment_rate
prs(2) = flexible_ratio
prs(3) = annual_total_cost
```

新增：

```text
/metrics      指标向量
/cost_breakdown
```

并保存一个 sidecar MAT：

```text
results/Optimization_SC_2050_costmin_metrics.mat
```

---

## 6. 缓存与性能

目标函数和非线性约束都会调用 8,760 小时调度。为避免每个候选解重复计算两次，建议在：

```text
utils/evaluate_dispatch_and_cost_cached.m
```

中使用 `persistent` 缓存最近一次 `scale` 及其 `metrics`。

此外：

- `Global_Trans`、`NonlConData` 和成本配置使用 `persistent`，避免每次评价重复读取；
- 若拓扑不随解改变，预计算路径；
- 第一版不要同时重构调度算法和成本逻辑。

---

## 7. 测试计划

### 7.1 回归测试

关闭新增项：

```text
COST_MODE = legacy_capex
ENABLE_FLEXIBLE_OPEX = false
```

对同一个 `scale`，应满足：

```text
旧版和新版的：
curtailment_rate 完全一致
flexible_ratio 完全一致
obj_cost 完全一致
```

### 7.2 单元测试

1. 输电距离翻倍时，对应线路成本翻倍；
2. O&M 开启后，年度成本按设定比例增加；
3. `ENABLE_FLEXIBLE_OPEX=false` 时灵活电源成本恒为 0；
4. `ENABLE_FLEXIBLE_OPEX=true` 时成本增量与 `sum(flexible_ele * MC)` 一致；
5. VRE 比例低于下界或高于上界时，非线性约束为正；
6. VRE 比例位于区间内时，约束不违反；
7. 单目标 H5 能正确转换为 Sel 文件。

### 7.3 场景测试

优先运行：

```text
SSP245 2050
```

检查：

- `vre_share` 是否落入 `[0.2871, 0.4646]`；
- 弃电率；
- 成本分解；
- 选中光伏和风电格网数量；
- 储能容量；
- 跨区域输电容量和 TW-km；
- 与旧 Pareto 前沿最低成本方案对比。

确认无误后，再运行：

```text
SSP245 2040
SSP245 2030
SSP126 2050 → 2040 → 2030
SSP560 2050 → 2040 → 2030
```

---

## 8. 关键敏感性分析

主结果至少保留四组敏感性实验：

```text
A. 旧输电成本 vs 长度加权 UHV 成本
B. 不计 O&M vs 计入 O&M
C. 灵活电源成本关闭 vs 开启
D. 不设置弃电上限 vs 可选设置弃电率 <= 15%
```

如果成本最小化方案总是贴近 `MIN_VRE_SHARE`，这是预期现象。若需要代表 AR6 中心路径，应进一步将 VRE 区间改为围绕 AR6 均值的窄区间，或使用目标值约束。

---

## 9. 可复用成本数据来源

### 当前中科院 NC25 代码

可继续直接复用：

```text
区域光伏 CAPEX
区域陆上风电 CAPEX
海上风电 CAPEX = 3461 USD/kW
储能 CAPEX = 350 USD/kWh
旧输电基准 = 98 million USD/GW
```

### 复旦 NC25 附录与 MATLAB 代码

可复用：

```text
PV O&M ratio = 1%
Wind O&M ratio = 3%
```

长度相关 UHV 成本可使用 Supplementary Method 5：

```text
±800 kV DC:
    line cost = 732 USD/m
    converter cost = 82 USD/kW
    circuit capacity = 8 GW

±1100 kV DC:
    line cost = 800 USD/m
    converter cost = 92 USD/kW
    circuit capacity = 12 GW

1000 kV AC:
    line cost = 671 USD/m
    converter cost = 41 USD/kW
    circuit capacity = 3–6 GW
```

### Nature Energy 2026

主要复用其成本核算思想：

```text
SCOE = annualized capital expenditures + operational expenditures
```

以及区分：

```text
spur line
trunk line
UHV / inter-grid transmission
```

当前项目第一版只实现 `UHV / interregional transmission`。

---

## 10. 需要注意的解释边界

新的方案不是完整复现 GISPO。它仍然是：

```text
在 SSP 外生能源结构约束下，
寻找经济合理的风光-储能-跨区输电布局。
```

因此，建议称为：

```text
风光扩张年度化增量系统成本最小化
```

而不是：

```text
完整电力系统总成本最小化
```


----

不需要提交commit