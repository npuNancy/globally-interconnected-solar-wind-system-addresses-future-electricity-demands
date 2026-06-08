# `dev-SSPs-cost-only`：代码测试与代码修改计划

## 0. 目标与范围

本计划适用于以下三个目录，并要求同步修改：

```text
Optimization_ssp126/
Optimization_ssp245/
Optimization_ssp560/
```

本轮只处理四类问题：

1. 先确认 `landmask == 1` 究竟表示陆地还是海洋，再决定是否修正风电装机密度和风电成本分类。
2. 为每次优化补充装机、发电、弃电、负荷服务、约束残差等诊断输出。
3. 对最终解执行严格的可行性检查：不可行解不得生成 `Sel.mat`，流水线必须立即终止。
4. 改善 2050 年 GA 搜索，使结果不再长期停留在接近随机初始种群的状态。

本轮明确不处理：

- 储能初始状态设置为 50% 的问题；
- `landmask` 变量重命名；
- SSP2-4.5、SSP5-6.0 区域负荷曲线仍沿用 SSP1-2.6 空间分布近似的问题；
- 是否启用 15% 弃电率约束的问题。该开关保持现状，另行讨论。

---

## 1. 当前代码中的关键现象

### 1.1 三个 SSP 的 2050 年候选场站构建逻辑相同

三个 SSP 的 2050 年脚本均读取相同的输入：

```matlab
Global_Wind_CFs_Sel.h5
Global_Solar_CFs.mat
Global_Wind_Net_Area_Add_Egrid.tif
Global_Solar_Net_Area_Add_Egrid.tif
Global_LandMask.tif
```

区别主要在于：

```matlab
DEMAND_2050
BASE_LOAD_RATIO_2050
MIN_VRE_SHARE_2050
MAX_VRE_SHARE_2050
```

因此，三个 SSP 的总装机容量接近，并不意味着代码真的找到了稳定的情景差异化最优解。尤其是三个 SSP 的 2050 年选中格网比例均接近 50%，需要优先排查 GA 是否仍停留在随机初始种群附近。

### 1.2 当前 `vre_share` 是残差定义，不是原始风光发电占比

共享函数中：

```matlab
flexible_ratio = sum(flexible_ele(:)) / sum(loads(:));
vre_share      = 1 - base_load_ratio - flexible_ratio;
```

因此，之前计算的：

```text
30.40 PWh
17.32 PWh
16.61 PWh
```

应称为：

```text
residual_vre_service_twh
风光、输电与储能共同承担的剩余负荷等价值
```

不能称为原始风光发电量。原始风光发电量需要从选中格网的 `gens` 时序重新汇总。

### 1.3 当前不可行解仍会继续进入后处理

当前流程中：

1. `ga(...)` 返回 `best_scale`；
2. 优化脚本直接保存 HDF5 和 MAT；
3. `convert_h5_to_sel.m` 检测到 VRE 越界后只打印警告；
4. 仍然继续生成 `Opt_*_Sel.mat`；
5. 后续年份继续读取该布局。

需要改为：最终解不可行时，只保存失败诊断文件，不保存正式结果，不生成 `Sel.mat`，流水线立即停止。

---

## 2. 总体实施策略

将修改拆成四个阶段，严格按顺序执行：

```text
阶段 A：landmask 语义测试
    ↓
阶段 B：增加诊断输出
    ↓
阶段 C：增加最终可行性硬检查
    ↓
阶段 D：改进 GA 初始化与搜索
```

阶段 A 未完成前，不修改风电陆上/海上逻辑。

---

# 阶段 A：确认 `landmask == 1` 的语义

## A1. 新增测试脚本

新增共享 MATLAB 测试：

```text
utils/test_landmask_semantics.m
```

新增统一入口：

```text
utils/run_landmask_semantics_test_all.m
```

入口依次测试：

```text
Optimization_ssp126/
Optimization_ssp245/
Optimization_ssp560/
```

## A2. 测试内容

### A2.1 检查三个目录中的栅格是否一致

对三个目录中的：

```text
Global_LandMask.tif
```

读取后执行：

```matlab
isequal(mask126, mask245)
isequal(mask126, mask560)
```

输出：

```text
landmask_equal_126_245
landmask_equal_126_560
```

如果不一致，三个目录分别继续测试，不允许只测一个目录。

### A2.2 输出原始值分布

当前代码使用：

```matlab
landmask(landmask < 100) = 0;
landmask(landmask > 100) = 1;
```

但 `landmask == 100` 会被保留为 100，未真正二值化。因此测试必须输出：

```text
count(mask < 100)
count(mask == 100)
count(mask > 100)
unique(mask)
```

如果存在 `mask == 100`，后续修改时必须改成一个显式布尔表达式，例如：

```matlab
landmask = landmask > 100;
```

或者：

```matlab
landmask = landmask >= 100;
```

阈值方向必须根据测试结果决定，不能提前假设。

### A2.3 用远离海岸线的已知坐标人工核验

至少检查以下点：

| 类型 | 地点 | 参考坐标 |
|---|---|---|
| 陆地 | 中国内陆 | 35°N, 105°E |
| 陆地 | 美国中部 | 40°N, 100°W |
| 陆地 | 撒哈拉 | 23°N, 10°E |
| 陆地 | 澳大利亚内陆 | 25°S, 135°E |
| 海洋 | 北大西洋 | 30°N, 40°W |
| 海洋 | 南太平洋 | 20°S, 150°W |
| 海洋 | 印度洋 | 20°S, 80°E |
| 海洋 | 北太平洋 | 30°N, 170°W |

输出 CSV：

```text
results/tests/landmask_known_points.csv
```

字段：

```text
scenario_dir
location_name
lat
lon
expected_surface
raw_mask_value
binary_mask_value
pass
```

### A2.4 生成可视化图

生成：

```text
results/tests/landmask_binary_map.png
```

图中显示二值化后的全球栅格。人工检查大陆轮廓是否落在 `1` 区域。

## A3. 测试完成后的两种修改路径

### 路径 A：确认 `landmask == 1` 表示海洋

保留当前计算方向，仅补充注释：

```matlab
% Global_LandMask.tif 经测试确认：
%   landmask == 1 表示海洋格网（offshore）
%   landmask == 0 表示陆地格网（onshore）
```

并确认：

```matlab
wind_ins(landmask == 1) = offshore_density * area;
CGrid_Index(:, 3) == 1  -> offshore CAPEX
```

语义一致。

### 路径 B：确认 `landmask == 1` 表示陆地

需要同步修正：

```matlab
wind_ins(...)
CGrid_Index(:, 3) 的成本分类
calc_capacity_from_optimization.py
convert_h5_to_sel.m
```

确保：

```text
陆上风电 -> 陆上密度、陆上 CAPEX
海上风电 -> 海上密度、海上 CAPEX
```

### A4. 涉及文件

三个 SSP 中均检查并按测试结果修改：

```text
Optimization_ssp126/Optimization_SC_2050.m
Optimization_ssp126/Optimization_SC_2040.m
Optimization_ssp126/Optimization_SA_2030.m
Optimization_ssp126/convert_h5_to_sel.m

Optimization_ssp245/Optimization_SC_2050.m
Optimization_ssp245/Optimization_SC_2040.m
Optimization_ssp245/Optimization_SA_2030.m
Optimization_ssp245/convert_h5_to_sel.m

Optimization_ssp560/Optimization_SC_2050.m
Optimization_ssp560/Optimization_SC_2040.m
Optimization_ssp560/Optimization_SA_2030.m
Optimization_ssp560/convert_h5_to_sel.m

utils/evaluate_dispatch_and_cost.m
calc_capacity_from_optimization.py
```

---

# 阶段 B：增加每次运行的诊断输出

## B1. 修改共享调度函数

修改：

```text
utils/evaluate_dispatch_and_cost.m
```

保留现有输出，并新增以下变量。

## B2. 新增容量指标

```text
pv_capacity_gw
wind_capacity_gw
onshore_wind_capacity_gw
offshore_wind_capacity_gw
total_vre_capacity_gw
selected_pv_grid_count
selected_wind_grid_count
```

其中陆上、海上拆分必须等阶段 A 结论确认后再实现。

## B3. 新增原始发电量指标

```text
gross_pv_generation_twh
gross_wind_generation_twh
gross_vre_generation_twh
gross_vre_share
```

定义：

```text
gross_pv_generation_twh
= 选中光伏格网的 gens 时序总和

gross_wind_generation_twh
= 选中风电格网的 gens 时序总和

gross_vre_generation_twh
= gross_pv_generation_twh + gross_wind_generation_twh

gross_vre_share
= gross_vre_generation_twh / total_load_twh
```

这组指标用于回答：

> 相近装机容量是否真的对应相近的原始风光发电量？

## B4. 新增负荷服务与调度指标

```text
base_load_twh
flexible_generation_twh
residual_vre_service_twh
curtailed_vre_twh
curtailment_rate
total_load_twh
transmission_capacity_tw
```

定义：

```text
base_load_twh
= base_load_ratio × total_load_twh

flexible_generation_twh
= sum(flexible_ele(:))

residual_vre_service_twh
= vre_share × total_load_twh

curtailed_vre_twh
= sum(curtailed_ele(:))
```

注意：

```text
residual_vre_service_twh
```

不能命名为 `vre_generation_twh`，避免再次与原始风光发电量混淆。

## B5. 保持 HDF5 向后兼容

保留现有：

```text
/metrics
```

内容不变：

```text
[curtailment_rate, flexible_ratio, vre_share, total_annual_cost]
```

新增：

```text
/diagnostics
/constraint_values
/max_constraint_violation
/is_feasible
/exitflag
```

在 Sidecar MAT 中额外保存：

```matlab
diagnostic_names
diagnostic_values
constraint_values
max_constraint_violation
is_feasible
```

建议新增共享辅助函数：

```text
utils/build_diagnostics_vector.m
utils/print_dispatch_diagnostics.m
```

避免三个 SSP、三个年份复制大段输出代码。

## B6. 修改优化脚本输出

对以下九个脚本同步增加诊断输出：

```text
Optimization_ssp126/Optimization_SC_2050.m
Optimization_ssp126/Optimization_SC_2040.m
Optimization_ssp126/Optimization_SA_2030.m

Optimization_ssp245/Optimization_SC_2050.m
Optimization_ssp245/Optimization_SC_2040.m
Optimization_ssp245/Optimization_SA_2030.m

Optimization_ssp560/Optimization_SC_2050.m
Optimization_ssp560/Optimization_SC_2040.m
Optimization_ssp560/Optimization_SA_2030.m
```

每次至少打印：

```text
光伏装机容量
风电装机容量
光伏原始发电量
风电原始发电量
原始风光发电量
原始风光发电占比
风光承担的剩余负荷等价值
灵活电源发电量
弃电量
弃电率
最大约束违反量
是否可行
```

## B7. 新增汇总脚本

新增：

```text
summarize_costmin_results.py
```

读取三个 SSP 的 Sidecar MAT，输出：

```text
results/SSPs_2050_diagnostics.csv
results/SSPs_all_years_diagnostics.csv
results/SSPs_优化结果汇总_诊断增强版.md
```

---

# 阶段 C：最终约束硬检查与流水线阻断

## C1. 新增共享约束检查函数

新增：

```text
utils/check_solution_feasibility.m
```

接口建议：

```matlab
function feasibility = check_solution_feasibility(c, ceq, tolerance)
```

输出：

```matlab
feasibility.constraint_values
feasibility.equality_values
feasibility.max_constraint_violation
feasibility.is_feasible
```

计算：

```matlab
ineq_violation = max([0; c(:)]);
eq_violation   = max([0; abs(ceq(:))]);
max_constraint_violation = max(ineq_violation, eq_violation);
is_feasible = max_constraint_violation <= tolerance;
```

## C2. 在九个优化脚本中检查最终解

在：

```matlab
[best_scale, best_cost, exitflag, output] = ga(...)
```

之后，先重新调用对应年份的 `nonlcon*.m`：

```matlab
[c_best, ceq_best] = nonlcon2050( ...
    best_scale, cost_cfg, scenario_cfg, model_data, persistent_data);

feasibility = check_solution_feasibility(c_best, ceq_best, 1e-6);
```

2040、2030 年分别调用：

```text
nonlcon2040
nonlcon2030
```

## C3. 严格执行三种结果分支

### C3.1 约束未满足

必须执行：

```text
不得生成正式 HDF5
不得生成正式 Sidecar MAT
不得生成 Sel.mat
流水线立即终止
```

为了保留诊断信息，另存失败快照：

```text
results/failed/Optimization_SC_2050_failed_<timestamp>.mat
results/failed/Optimization_SC_2040_failed_<timestamp>.mat
results/failed/Optimization_SA_2030_failed_<timestamp>.mat
```

失败快照至少包含：

```matlab
best_scale
best_cost
best_metrics
exitflag
output
scenario_cfg
constraint_values
max_constraint_violation
```

然后：

```matlab
error('Optimization:InfeasibleResult', ...)
```

### C3.2 满足约束且收敛

即：

```text
is_feasible == true
exitflag > 0
```

正常保存正式结果。

### C3.3 满足约束但未完全收敛

即：

```text
is_feasible == true
exitflag <= 0
```

按照要求，也正常保存正式结果，不增加额外状态标记。日志中保留一条普通提示即可：

```matlab
fprintf('提示：当前解满足全部约束，但 GA 未完全收敛，exitflag=%d\n', exitflag);
```

## C4. 修改 `convert_h5_to_sel.m`

三个目录中的：

```text
Optimization_ssp126/convert_h5_to_sel.m
Optimization_ssp245/convert_h5_to_sel.m
Optimization_ssp560/convert_h5_to_sel.m
```

当前越界时只打印警告。需要改为硬错误：

```matlab
if ~isnan(min_vre_share) && vre_share < min_vre_share - 1e-6
    error('Convert:VRELowerBoundViolation', ...);
end

if vre_share > max_vre_share + 1e-6
    error('Convert:VREUpperBoundViolation', ...);
end
```

同时读取：

```text
/is_feasible
```

如果值不是 `1`，直接终止。

## C5. 修改流水线

同步修改：

```text
Optimization_ssp126/run_full_pipeline.sh
Optimization_ssp245/run_full_pipeline.sh
Optimization_ssp560/run_full_pipeline.sh
```

### C5.1 每个阶段开始前删除可能误用的旧文件

例如 2050 年运行前：

```bash
rm -f results/Optimization_SC_2050_Res.h5
rm -f results/Optimization_SC_2050_metrics.mat
rm -f results/Opt_SC_2050_Sel.mat
```

2040、2030 同理。

### C5.2 `convert_h5_to_sel` 失败后立即退出

当前脚本在转换失败后仍会尝试绘图。改为：

```bash
if ! run_matlab "year=2050; convert_h5_to_sel" "$LOGDIR/convert2050.log"; then
    echo "流水线在 2050 后处理阶段停止"
    exit 1
fi

plot_pareto ...
```

2040、2030 同理。

---

# 阶段 D：改善 2050 年 GA 搜索

## D1. 保留现有整数变量设定

本轮不修改整数约束范围，继续沿用当前代码：

```matlab
intcon = 1:1:length(lb);
```

即场站选择、储能功率、储能时长和输电容量仍全部按照整数变量处理。

本计划不再包含缩小整数变量范围、将储能功率或输电容量改为连续变量等修改。

## D2. 将随机种子集中配置为 `GA_SEED = 42`

在三个 SSP 目录的：

```text
optimization_config.m
```

中新增：

```matlab
%% 7. GA 随机种子
% 默认固定为 42，便于复现实验。
% 如需调整，只修改本文件中的 GA_SEED。
GA_SEED = 42;
```

九个优化脚本中，将：

```matlab
rng default
```

替换为：

```matlab
rng(GA_SEED, 'twister');
fprintf('GA 随机种子: %d
', GA_SEED);
```

本轮不增加环境变量覆盖，不增加多随机种子运行脚本。

## D3. 新增贪心可行初始解

新增共享函数：

```text
utils/build_greedy_initial_solution.m
utils/build_initial_population.m
```

### D3.1 基础初始解

先构造最低成本基础解：

1. 场站变量全部初始化为 0；
2. 储能功率、储能时长、输电容量取下界；
3. 对 20 个区域分别处理现有光伏最低装机要求；
4. 对 20 个区域分别处理现有风电最低装机要求；
5. 在每个区域内，按以下指标排序并逐格网加入：

```text
annual_generation_twh / annualized_capex
```

### D3.2 SSP1-2.6 和 SSP2-4.5

这两个情景存在 VRE 下界。满足现有装机约束后，继续按成本效率逐步加入场站，直到：

```text
vre_share >= MIN_VRE_SHARE
```

每增加一批场站后，调用一次：

```text
evaluate_dispatch_and_cost(...)
```

检查渗透率。

### D3.3 SSP5-6.0

SSP5-6.0 只有 VRE 上界。满足现有装机约束后，立即评估：

```text
vre_share_min_existing
```

如果：

```text
vre_share_min_existing > MAX_VRE_SHARE
```

则直接报告：

```text
当前既有装机约束与 SSP5-6.0 VRE 上界不可同时满足
```

此时继续运行 GA 没有意义，应终止并输出可行性诊断。

如果基础解满足上界，则将其作为 SSP5-6.0 的核心初始解。

## D4. 构建初始种群矩阵

不要让所有个体完全随机生成。构造：

```matlab
options = optimoptions(options, ...
    'InitialPopulationMatrix', initial_population);
```

初始种群建议包含：

| 类型 | 比例 |
|---|---:|
| 贪心可行解 | 至少 1 个 |
| 贪心解附近的小扰动解 | 50% |
| 根据 VRE 上下界定向增删场站的解 | 30% |
| 完全随机解 | 20% |

扰动时：

- 优先在同一区域内交换格网；
- 避免立即破坏已有装机约束；
- SSP5-6.0 主要执行删减和低 VRE 扰动；
- SSP1-2.6 主要执行扩张和高容量因子替换；
- SSP2-4.5 介于两者之间；
- 所有变量继续保持整数。

## D5. 增加“是否仍停留在随机初始状态”的诊断

每次运行输出：

```text
initial_selected_pv_ratio
initial_selected_wind_ratio
final_selected_pv_ratio
final_selected_wind_ratio
initial_final_hamming_distance
initial_final_jaccard_similarity
initial_cost
final_cost
initial_max_constraint_violation
final_max_constraint_violation
```

判定参考：

```text
final_cost < initial_cost
final_max_constraint_violation <= 1e-6
```

且最终布局不应仅因为随机初始化而长期维持在约 50%。

注意：

```text
最终场站比例接近 50%
```

本身不是错误。真正需要排查的是：

```text
最终解与初始解高度重合
成本几乎没有改善
约束残差没有下降
```

---

# 3. 测试计划

## T1. landmask 单元测试

执行：

```bash
matlab -batch "addpath('utils'); run_landmask_semantics_test_all"
```

验收标准：

```text
已明确 landmask == 1 表示陆地或海洋
三个目录结果均已核验
不存在未处理的 mask == 100
已生成 CSV 和 PNG
```

## T2. 诊断指标单元测试

新增：

```text
utils/test_dispatch_diagnostics.m
```

检查：

```text
gross_vre_generation_twh
= gross_pv_generation_twh + gross_wind_generation_twh

gross_vre_share
= gross_vre_generation_twh / total_load_twh

residual_vre_service_twh
= vre_share × total_load_twh

curtailed_vre_twh
= sum(curtailed_ele(:))
```

## T3. 最终约束检查单元测试

新增：

```text
utils/test_check_solution_feasibility.m
```

覆盖：

| 输入 | 预期 |
|---|---|
| 全部 `c <= 0`，`ceq = []` | `is_feasible = true` |
| VRE 上界违反 `0.01` | `is_feasible = false` |
| VRE 下界违反 `0.0001` | `is_feasible = false` |
| 既有装机约束违反 | `is_feasible = false` |
| `exitflag = 0` 但约束满足 | 允许保存 |
| `exitflag = -2` 且约束不满足 | 禁止保存 |

## T4. `convert_h5_to_sel` 阻断测试

构造或复制一个 VRE 越界的 HDF5，执行：

```bash
matlab -batch "year=2050; convert_h5_to_sel"
```

验收标准：

```text
MATLAB 返回非零退出码
不得生成 Opt_SC_2050_Sel.mat
```

SSP5-6.0 当前 2050 年越界结果可以作为回归测试样例。

## T5. 流水线阻断测试

在 SSP5-6.0 中运行：

```bash
bash run_full_pipeline.sh
```

若 2050 年不可行，验收标准：

```text
流水线在 2050 阶段终止
不得启动 2040
不得启动 2030
不得保留新的 Opt_SC_2050_Sel.mat
```

## T6. GA 初始化测试

新增：

```text
utils/test_build_greedy_initial_solution.m
utils/test_build_initial_population.m
```

验收标准：

```text
初始解维度正确
场站变量为 0/1
储能和输电变量落在上下界内
满足已有装机约束
SSP1-2.6、SSP2-4.5 初始解尽量达到 VRE 下界
SSP5-6.0 可以明确报告最低可达 VRE 是否超过上界
```

## T7. 2050 年定向重跑

先只运行三个 SSP 的 2050 年：

```bash
cd Optimization_ssp126
matlab -batch "Optimization_SC_2050"

cd ../Optimization_ssp245
matlab -batch "Optimization_SC_2050"

cd ../Optimization_ssp560
matlab -batch "Optimization_SC_2050"
```

输出增强版汇总表，重点比较：

```text
是否可行
最大约束违反量
光伏装机容量
风电装机容量
光伏原始发电量
风电原始发电量
原始风光发电占比
风光承担的剩余负荷等价值
初始到最终的 Hamming 距离
初始成本与最终成本
```

## T8. 三阶段完整重跑

只有在三个 SSP 的 2050 年结果均可接受后，才分别运行：

```bash
bash run_full_pipeline.sh
```

---

# 4. 文件修改清单

## 4.1 新增共享文件

```text
utils/test_landmask_semantics.m
utils/run_landmask_semantics_test_all.m
utils/build_diagnostics_vector.m
utils/print_dispatch_diagnostics.m
utils/check_solution_feasibility.m
utils/build_greedy_initial_solution.m
utils/build_initial_population.m
utils/test_dispatch_diagnostics.m
utils/test_check_solution_feasibility.m
utils/test_build_greedy_initial_solution.m
utils/test_build_initial_population.m
summarize_costmin_results.py
```

## 4.2 修改共享文件

```text
utils/evaluate_dispatch_and_cost.m
utils/evaluate_dispatch_and_cost_cached.m
calc_capacity_from_optimization.py
```

`evaluate_dispatch_and_cost_cached.m` 的缓存键建议补充：

```text
base_load_ratio
interconnection_mode
nonlsol
```

避免同一 MATLAB 会话切换年份或情景时误用旧缓存。

## 4.3 修改三个 SSP 目录

每个目录同步修改：

```text
optimization_config.m
Optimization_SC_2050.m
Optimization_SC_2040.m
Optimization_SA_2030.m
convert_h5_to_sel.m
run_full_pipeline.sh
```

必要时补充注释或调用共享函数：

```text
nonlcon2050.m
nonlcon2040.m
nonlcon2030.m
```

三个目录合计至少修改：

```text
18 个主要脚本
```

---

# 5. 实施顺序

按照以下顺序逐步修改和测试：

```text
1. 完成 landmask 语义测试
2. 根据测试结果修正或补充 landmask 注释
3. 增加调度诊断输出
4. 增加最终约束硬检查
5. 增加 GA_SEED = 42 配置
6. 增加贪心可行初始解和定向初始种群
7. 只运行三个 SSP 的 2050 年进行回归测试
8. 2050 年通过后，再运行 2040 和 2030
```

本计划不自动执行 Git 提交，也不要求脚本自动创建 commit。代码修改完成后，由人工检查 diff，再决定是否提交。

---

# 6. 最终验收标准

修改完成后，必须满足：

1. 已通过坐标点测试和全球图确认 `landmask == 1` 的语义。
2. 三个 SSP、三个年份均输出原始光伏发电量、原始风电发电量、原始风光发电占比和剩余负荷服务等价值。
3. 不可行结果无法生成 `Sel.mat`。
4. SSP5-6.0 2050 年若仍无法满足 VRE 上界，能够明确区分：
   - 约束本身不可行；
   - GA 尚未找到可行解。
5. 2040 和 2030 不会读取不可行的上游结果。
6. 保留现有整数约束：场站选择、储能功率、储能时长和输电容量均继续作为整数变量。
7. 三个 SSP 的 `optimization_config.m` 中均包含 `GA_SEED = 42`，九个优化脚本均读取该配置。
8. 不新增多随机种子运行脚本，不依赖多随机种子筛选最终解。
9. 2050 年结果能够证明相对于初始布局有明确改善，而不是仅凭选中格网比例接近 50% 就误判。
10. 三个 SSP 的结果汇总中同时展示：装机容量、原始发电量、调度后服务负荷、弃电、可行性和收敛情况。
11. 修改过程不自动创建 Git commit，由人工检查后决定是否提交。
