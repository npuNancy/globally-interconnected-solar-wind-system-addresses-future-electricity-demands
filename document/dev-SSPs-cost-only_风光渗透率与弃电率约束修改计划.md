# `dev-SSPs-cost-only`：风光渗透率重定义与弃电率约束启用修改计划

## 0. 目标

本轮修改包含两部分：

1. 将风光渗透率严格定义为：

```text
VRE 渗透率
= 实际风光发电量 / 总发电量
= （调度前原始风光发电量 - 弃电量） / 总发电量
```

2. 启用弃电率硬约束：

```matlab
cost_cfg.ENABLE_CURTAILMENT_CONSTRAINT = true;
```

弃电率上限继续使用：

```matlab
cost_cfg.MAX_CURTAILMENT = 0.15;
```

本轮不修改：

```text
整数约束范围
GA_SEED = 42
储能初始 SOC = 50%
输电成本逻辑
储能成本逻辑
场站 0/1 选择逻辑
```

---

# 1. 指标定义

## 1.1 调度前原始风光发电量

定义：

```text
gross_vre_generation_twh
= gross_pv_generation_twh
+ gross_wind_generation_twh
```

其中：

```text
gross_pv_generation_twh
= 所有选中光伏格网的逐小时发电量总和

gross_wind_generation_twh
= 所有选中风电格网的逐小时发电量总和
```

它表示：

```text
风光场站在不考虑弃电时，理论上能够产生的全年电量
```

---

## 1.2 弃电量

定义：

```text
curtailed_vre_twh
= sum(curtailed_ele(:))
```

它表示：

```text
调度过程中无法被负荷、跨区输电或储能吸收的风光电量
```

---

## 1.3 实际风光发电量

定义：

```text
actual_vre_generation_twh
= gross_vre_generation_twh
- curtailed_vre_twh
```

代码中建议写为：

```matlab
actual_vre_generation_twh = max( ...
    gross_vre_generation_twh - curtailed_vre_twh, ...
    0);
```

使用 `max(..., 0)` 是为了防止浮点误差造成极小负值。

---

## 1.4 基荷发电量

定义：

```text
base_generation_twh
= base_load_ratio
× total_load_twh
```

代码：

```matlab
base_generation_twh = base_load_ratio * total_load_twh;
```

---

## 1.5 灵活电源发电量

定义：

```text
flexible_generation_twh
= sum(flexible_ele(:))
```

代码：

```matlab
flexible_generation_twh = sum(flexible_ele(:));
```

---

## 1.6 总发电量

定义：

```text
total_generation_twh
= actual_vre_generation_twh
+ base_generation_twh
+ flexible_generation_twh
```

代码：

```matlab
total_generation_twh = ...
    actual_vre_generation_twh ...
    + base_generation_twh ...
    + flexible_generation_twh;
```

注意：

```text
储能放电不能再次计入总发电量
```

原因：

```text
储能不是一次能源发电来源。
储能充入的电量已经来源于风光发电。
若再次加入储能放电，会重复计算。
```

---

## 1.7 新的 VRE 渗透率

定义：

```text
vre_share
= actual_vre_generation_twh
/ total_generation_twh
```

代码：

```matlab
if total_generation_twh <= 0
    error('Dispatch:InvalidTotalGeneration', ...
        '总发电量必须大于 0，当前值为 %.6f TWh', ...
        total_generation_twh);
end

vre_share = ...
    actual_vre_generation_twh ...
    / total_generation_twh;
```

---

## 1.8 弃电率

弃电率继续独立定义为：

```text
curtailment_rate
= curtailed_vre_twh
/ gross_vre_generation_twh
```

代码：

```matlab
if gross_vre_generation_twh <= 0
    curtailment_rate = 0;
else
    curtailment_rate = ...
        curtailed_vre_twh ...
        / gross_vre_generation_twh;
end
```

说明：

```text
VRE 渗透率和弃电率是两个独立指标。

VRE 渗透率：
实际风光发电量 / 总发电量

弃电率：
弃电量 / 调度前原始风光发电量
```

不得再通过：

```text
1 - base_load_ratio - flexible_ratio
```

计算 VRE 渗透率。

---

# 2. 修改范围概览

## 2.1 必须修改的共享文件

```text
utils/evaluate_dispatch_and_cost.m
utils/build_diagnostics_vector.m
utils/print_dispatch_diagnostics.m
utils/cost_model_config.m
utils/build_greedy_initial_solution.m
summarize_costmin_results.py
```

## 2.2 必须更新注释或兼容逻辑的共享文件

```text
utils/evaluate_dispatch_and_cost_cached.m
utils/build_initial_population.m
```

## 2.3 必须修改的非线性约束文件

```text
Optimization_ssp126/nonlcon2050.m
Optimization_ssp126/nonlcon2040.m
Optimization_ssp126/nonlcon2030.m

Optimization_ssp245/nonlcon2050.m
Optimization_ssp245/nonlcon2040.m
Optimization_ssp245/nonlcon2030.m

Optimization_ssp560/nonlcon2050.m
Optimization_ssp560/nonlcon2040.m
Optimization_ssp560/nonlcon2030.m
```

## 2.4 必须修改的优化主脚本

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

## 2.5 必须修改的后处理脚本

```text
Optimization_ssp126/convert_h5_to_sel.m
Optimization_ssp245/convert_h5_to_sel.m
Optimization_ssp560/convert_h5_to_sel.m
```

## 2.6 建议更新的文档

```text
document/SSPs_Analysis_Report.md
document/SSP风光场站_单目标成本最小化_代码修改计划_输电成本保持原逻辑.md
```

---

# 3. 修改 `utils/evaluate_dispatch_and_cost.m`

这是本轮修改的核心文件。

## 3.1 删除旧的 VRE 渗透率定义

删除：

```matlab
vre_share = 1 - base_load_ratio - flexible_ratio;
```

不得保留该表达式作为正式 `vre_share`。

---

## 3.2 重排第 7 节指标计算顺序

建议将第 7 节改为以下结构。

```matlab
%% ======================== 7. 计算诊断指标 ========================

% ---- 基础统计 ----
total_load_twh = sum(loads(:));

% ---- 容量统计 ----
sel_mask = CGrid_Index(:,2) == 1;
grid_idx = (1:length(CGrid_Index))';

pv_sel   = sel_mask & (grid_idx <= nonlsol);
wind_sel = sel_mask & (grid_idx > nonlsol);

pv_capacity_gw   = sum(ins_cap(pv_sel)) * 1000;
wind_capacity_gw = sum(ins_cap(wind_sel)) * 1000;
total_vre_capacity_gw = pv_capacity_gw + wind_capacity_gw;

selected_pv_grid_count   = sum(pv_sel);
selected_wind_grid_count = sum(wind_sel);

% 陆上/海上风电拆分
onshore_wind_sel  = wind_sel & (CGrid_Index(:,3) == 0);
offshore_wind_sel = wind_sel & (CGrid_Index(:,3) == 1);

onshore_wind_capacity_gw  = sum(ins_cap(onshore_wind_sel)) * 1000;
offshore_wind_capacity_gw = sum(ins_cap(offshore_wind_sel)) * 1000;

% ---- 调度前原始风光发电量 ----
gross_pv_generation_twh   = sum(gens(pv_sel, :), 'all');
gross_wind_generation_twh = sum(gens(wind_sel, :), 'all');

gross_vre_generation_twh = ...
    gross_pv_generation_twh ...
    + gross_wind_generation_twh;

% 原始风光发电量 / 总负荷，仅用于诊断超配程度
gross_vre_to_load_ratio = ...
    gross_vre_generation_twh ...
    / total_load_twh;

% ---- 弃电量与弃电率 ----
curtailed_vre_twh = sum(curtailed_ele(:));

if gross_vre_generation_twh <= 0
    curtailment_rate = 0;
else
    curtailment_rate = ...
        curtailed_vre_twh ...
        / gross_vre_generation_twh;
end

% ---- 实际风光发电量 ----
actual_vre_generation_twh = max( ...
    gross_vre_generation_twh ...
    - curtailed_vre_twh, ...
    0);

% ---- 其他电源 ----
base_generation_twh = ...
    base_load_ratio ...
    * total_load_twh;

flexible_generation_twh = ...
    sum(flexible_ele(:));

flexible_ratio = ...
    flexible_generation_twh ...
    / total_load_twh;

% ---- 总发电量 ----
total_generation_twh = ...
    actual_vre_generation_twh ...
    + base_generation_twh ...
    + flexible_generation_twh;

if total_generation_twh <= 0
    error('Dispatch:InvalidTotalGeneration', ...
        '总发电量必须大于 0，当前值为 %.6f TWh', ...
        total_generation_twh);
end

% ---- 严格定义的 VRE 渗透率 ----
vre_share = ...
    actual_vre_generation_twh ...
    / total_generation_twh;
```

---

## 3.3 更新函数头部注释

将旧注释：

```matlab
%   .vre_share - 风光渗透率 = 1 - base_load_ratio - flexible_ratio
```

改为：

```matlab
%   .vre_share
%       - 风光渗透率
%       - 定义：实际风光发电量 / 总发电量
%
%   .gross_vre_generation_twh
%       - 调度前原始风光发电量
%
%   .curtailed_vre_twh
%       - 弃电量
%
%   .actual_vre_generation_twh
%       - 实际风光发电量
%       - 定义：调度前原始风光发电量 - 弃电量
%
%   .total_generation_twh
%       - 总发电量
%       - 定义：实际风光发电量 + 基荷发电量 + 灵活电源发电量
```

---

## 3.4 更新 `metrics` 输出字段

保留已有字段，并新增：

```matlab
metrics.gross_vre_to_load_ratio   = gross_vre_to_load_ratio;
metrics.actual_vre_generation_twh = actual_vre_generation_twh;
metrics.base_generation_twh       = base_generation_twh;
metrics.total_generation_twh      = total_generation_twh;
```

保留：

```matlab
metrics.gross_pv_generation_twh
metrics.gross_wind_generation_twh
metrics.gross_vre_generation_twh
metrics.curtailed_vre_twh
metrics.curtailment_rate
metrics.flexible_generation_twh
metrics.flexible_ratio
metrics.vre_share
```

---

## 3.5 删除或弃用旧字段

旧字段：

```matlab
residual_vre_service_twh
```

不再作为正式指标输出。

原因：

```text
它基于旧的残差定义。
新的 vre_share 已经改为实际风光发电量 / 总发电量。
继续保留会造成概念混淆。
```

若确实需要回归对比，可以改名为：

```matlab
legacy_residual_vre_service_share
legacy_residual_vre_service_twh
```

并添加注释：

```matlab
% 仅用于历史结果回归。
% 不得用于 VRE 约束。
```

默认不加入最终汇总表。

---

# 4. 修改 `utils/cost_model_config.m`

## 4.1 启用弃电率约束

将：

```matlab
cost_cfg.ENABLE_CURTAILMENT_CONSTRAINT = false;
```

改为：

```matlab
cost_cfg.ENABLE_CURTAILMENT_CONSTRAINT = true;
```

保留：

```matlab
cost_cfg.MAX_CURTAILMENT = 0.15;
```

---

## 4.2 更新注释

建议改为：

```matlab
%% 8. 弃电率约束与弃电成本

% 弃电率定义：
%   curtailment_rate
%   = 弃电量 / 调度前原始风光发电量
%
% 弃电率约束：
%   curtailment_rate <= MAX_CURTAILMENT
%
% 该约束与 VRE 渗透率约束相互独立。
%
% VRE 渗透率定义：
%   vre_share
%   = 实际风光发电量 / 总发电量
%
% 实际风光发电量：
%   actual_vre_generation_twh
%   = gross_vre_generation_twh - curtailed_vre_twh

cost_cfg.ENABLE_CURTAILMENT_CONSTRAINT = true;
cost_cfg.MAX_CURTAILMENT = 0.15;

% 暂不启用弃电成本
cost_cfg.ENABLE_CURTAILMENT_COST = false;
cost_cfg.CURTAILMENT_COST_USD_PER_MWH = 0;
```

---

# 5. 修改 `utils/build_diagnostics_vector.m`

## 5.1 删除旧字段

删除：

```text
gross_vre_share
residual_vre_service_twh
```

---

## 5.2 新增字段

建议顺序：

```matlab
names = { ...
    'pv_capacity_gw', ...
    'wind_capacity_gw', ...
    'onshore_wind_capacity_gw', ...
    'offshore_wind_capacity_gw', ...
    'total_vre_capacity_gw', ...
    'selected_pv_grid_count', ...
    'selected_wind_grid_count', ...
    'gross_pv_generation_twh', ...
    'gross_wind_generation_twh', ...
    'gross_vre_generation_twh', ...
    'gross_vre_to_load_ratio', ...
    'curtailed_vre_twh', ...
    'curtailment_rate', ...
    'actual_vre_generation_twh', ...
    'base_generation_twh', ...
    'flexible_generation_twh', ...
    'total_generation_twh', ...
    'vre_share', ...
    'flexible_ratio', ...
    'total_load_twh', ...
    'transmission_capacity_tw', ...
    'total_annual_cost' ...
};
```

对应 `values` 顺序同步修改。

---

# 6. 修改 `utils/print_dispatch_diagnostics.m`

## 6.1 删除旧输出

删除：

```matlab
fprintf('VRE 剩余负荷服务等价值:%.4f TWh\n', ...
    metrics.residual_vre_service_twh);

fprintf('vre_share (残差定义):  %.4f\n', ...
    metrics.vre_share);
```

---

## 6.2 增加新输出

建议打印：

```matlab
fprintf('\n=== 原始发电量诊断 ===\n');
fprintf('光伏原始发电量:          %.4f TWh\n', ...
    metrics.gross_pv_generation_twh);

fprintf('风电原始发电量:          %.4f TWh\n', ...
    metrics.gross_wind_generation_twh);

fprintf('原始风光发电量:          %.4f TWh\n', ...
    metrics.gross_vre_generation_twh);

fprintf('原始风光发电量 / 总负荷: %.4f\n', ...
    metrics.gross_vre_to_load_ratio);

fprintf('\n=== 调度后实际发电量 ===\n');
fprintf('弃电量:                  %.4f TWh\n', ...
    metrics.curtailed_vre_twh);

fprintf('弃电率:                  %.4f\n', ...
    metrics.curtailment_rate);

fprintf('实际风光发电量:          %.4f TWh\n', ...
    metrics.actual_vre_generation_twh);

fprintf('基荷发电量:              %.4f TWh\n', ...
    metrics.base_generation_twh);

fprintf('灵活电源发电量:          %.4f TWh\n', ...
    metrics.flexible_generation_twh);

fprintf('总发电量:                %.4f TWh\n', ...
    metrics.total_generation_twh);

fprintf('\n=== 渗透率与约束 ===\n');
fprintf('VRE 渗透率:              %.4f\n', ...
    metrics.vre_share);

fprintf('VRE 定义:                实际风光发电量 / 总发电量\n');

fprintf('VRE 约束区间:            [%.4f, %.4f]\n', ...
    scenario_cfg.min_vre_share, ...
    scenario_cfg.max_vre_share);

fprintf('弃电率上限:              %.4f\n', ...
    cost_cfg.MAX_CURTAILMENT);

fprintf('弃电率约束是否启用:      %s\n', ...
    mat2str(cost_cfg.ENABLE_CURTAILMENT_CONSTRAINT));
```

---

# 7. 修改 9 个 `nonlcon*.m`

需要同步修改：

```text
Optimization_ssp126/nonlcon2050.m
Optimization_ssp126/nonlcon2040.m
Optimization_ssp126/nonlcon2030.m

Optimization_ssp245/nonlcon2050.m
Optimization_ssp245/nonlcon2040.m
Optimization_ssp245/nonlcon2030.m

Optimization_ssp560/nonlcon2050.m
Optimization_ssp560/nonlcon2040.m
Optimization_ssp560/nonlcon2030.m
```

## 7.1 VRE 约束逻辑保持使用 `metrics.vre_share`

保留：

```matlab
vre_share = metrics.vre_share;
c(end+1) = min_vre - vre_share;
c(end+1) = vre_share - max_vre;
```

因为 `metrics.vre_share` 已经在共享函数中改为严格定义。

---

## 7.2 更新注释

改为：

```matlab
%% ======== 2. VRE 渗透率约束 ========

% VRE 渗透率严格定义：
%
%   vre_share
%   = actual_vre_generation_twh
%     / total_generation_twh
%
% 其中：
%
%   actual_vre_generation_twh
%   = gross_vre_generation_twh
%     - curtailed_vre_twh
%
%   total_generation_twh
%   = actual_vre_generation_twh
%     + base_generation_twh
%     + flexible_generation_twh

metrics = evaluate_dispatch_and_cost_cached(...);

vre_share = metrics.vre_share;

c(end+1) = min_vre - vre_share;
c(end+1) = vre_share - max_vre;
```

对于 SSP5-6.0 的 `NaN` 下界，继续保留现有 `isnan` 处理。

---

## 7.3 保留并启用弃电率约束

保留：

```matlab
%% ======== 3. 弃电率上限约束 ========

if cost_cfg.ENABLE_CURTAILMENT_CONSTRAINT
    c(end+1) = metrics.curtailment_rate ...
             - cost_cfg.MAX_CURTAILMENT;
end
```

由于共享配置已设置：

```matlab
cost_cfg.ENABLE_CURTAILMENT_CONSTRAINT = true;
```

该约束会自动生效。

---

# 8. 修改 `utils/build_greedy_initial_solution.m`

本轮不重构贪心算法，但必须修正口径。

## 8.1 修改近似指标命名

当前：

```matlab
approx_vre = sum(gens(selected_grids, :), 'all') / total_load;
```

实际不是新的 VRE 渗透率。

改为：

```matlab
approx_gross_vre_to_load_ratio = ...
    sum(gens(selected_grids, :), 'all') ...
    / total_load;
```

注释：

```matlab
% 仅用于快速估计场站超配程度。
% 不属于严格定义的 VRE 渗透率。
% 不得直接用于判断最终 VRE 上下界。
```

---

## 8.2 最终 VRE 判断使用完整调度

保留完整调度：

```matlab
temp_metrics = evaluate_dispatch_and_cost(...);
actual_vre_share = temp_metrics.vre_share;
```

根据：

```matlab
actual_vre_share
```

判断 VRE 上下界。

---

## 8.3 同时检查弃电率

在完整调度后增加：

```matlab
actual_curtailment_rate = ...
    temp_metrics.curtailment_rate;

fprintf('  实际 VRE 渗透率 = %.4f\n', ...
    actual_vre_share);

fprintf('  实际弃电率 = %.4f\n', ...
    actual_curtailment_rate);
```

对于需要满足全部约束的情况，使用：

```matlab
vre_ok = ...
    (isnan(min_vre) || actual_vre_share >= min_vre - 1e-6) ...
    && actual_vre_share <= max_vre + 1e-6;

curtailment_ok = ...
    ~cost_cfg.ENABLE_CURTAILMENT_CONSTRAINT ...
    || actual_curtailment_rate <= cost_cfg.MAX_CURTAILMENT + 1e-6;
```

然后：

```matlab
if vre_ok && curtailment_ok
    fprintf('  ✓ 当前贪心解满足 VRE 与弃电率约束\n');
    break;
end
```

---

# 9. 修改 9 个优化主脚本

需要同步修改：

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

## 9.1 更新日志说明

增加：

```matlab
fprintf('VRE 渗透率定义: 实际风光发电量 / 总发电量\n');

fprintf('弃电率约束: %s\n', ...
    mat2str(cost_cfg.ENABLE_CURTAILMENT_CONSTRAINT));

fprintf('弃电率上限: %.4f\n', ...
    cost_cfg.MAX_CURTAILMENT);
```

---

## 9.2 保持 `/metrics` 四元组兼容

继续保存：

```matlab
metrics_vec = [ ...
    best_metrics.curtailment_rate, ...
    best_metrics.flexible_ratio, ...
    best_metrics.vre_share, ...
    best_metrics.total_annual_cost ...
];
```

但更新注释：

```matlab
% 指标向量：
% [
%   curtailment_rate,
%   flexible_ratio,
%   vre_share,
%   total_annual_cost
% ]
%
% vre_share 严格定义：
%   实际风光发电量 / 总发电量
```

---

## 9.3 增加指标版本

新增：

```matlab
metrics_schema_version = 2;
vre_share_definition = ...
    'actual_vre_generation_twh / total_generation_twh';
```

写入 HDF5：

```matlab
h5create(h5file, '/metrics_schema_version', [1, 1]);
h5write(h5file, '/metrics_schema_version', metrics_schema_version);
```

Sidecar MAT 中保存：

```matlab
save(matfile, ...
    ...
    'metrics_schema_version', ...
    'vre_share_definition' ...
);
```

目的：

```text
防止旧版 residual vre_share 结果
被误当作新版 actual-generation-based vre_share 结果。
```

---

# 10. 修改 3 个 `convert_h5_to_sel.m`

需要同步修改：

```text
Optimization_ssp126/convert_h5_to_sel.m
Optimization_ssp245/convert_h5_to_sel.m
Optimization_ssp560/convert_h5_to_sel.m
```

## 10.1 增加版本检查

读取：

```matlab
try
    metrics_schema_version = ...
        h5read(h5file, '/metrics_schema_version');
catch ME
    error('Convert:MissingMetricsSchemaVersion', ...
        'HDF5 中缺少 /metrics_schema_version。请重新运行优化。');
end

if metrics_schema_version ~= 2
    error('Convert:UnsupportedMetricsSchema', ...
        '当前 HDF5 指标版本为 %.0f，要求版本为 2。请重新运行优化。', ...
        metrics_schema_version);
end
```

---

## 10.2 更新日志文本

打印：

```matlab
fprintf('VRE 渗透率:    %.4f\n', vre_share);
fprintf('VRE 定义:      实际风光发电量 / 总发电量\n');
fprintf('弃电率:        %.4f\n', curtailment_rate);
fprintf('弃电率上限:    %.4f\n', cost_cfg.MAX_CURTAILMENT);
```

---

## 10.3 增加弃电率二次校验

即使优化阶段已经检查过，也建议在后处理中增加防御性校验：

```matlab
if cost_cfg.ENABLE_CURTAILMENT_CONSTRAINT ...
        && curtailment_rate > cost_cfg.MAX_CURTAILMENT + 1e-6
    error('Convert:CurtailmentUpperBoundViolation', ...
        '弃电率 %.4f 高于上限 %.4f，终止后处理。', ...
        curtailment_rate, ...
        cost_cfg.MAX_CURTAILMENT);
end
```

---

# 11. 修改 `summarize_costmin_results.py`

## 11.1 更新标签

替换为：

```python
DIAG_LABELS = {
    'pv_capacity_gw': '光伏装机容量 (GW)',
    'wind_capacity_gw': '风电装机容量 (GW)',
    'onshore_wind_capacity_gw': '陆上风电装机容量 (GW)',
    'offshore_wind_capacity_gw': '海上风电装机容量 (GW)',
    'total_vre_capacity_gw': 'VRE 总装机容量 (GW)',
    'selected_pv_grid_count': '选中光伏格网数',
    'selected_wind_grid_count': '选中风电格网数',
    'gross_pv_generation_twh': '光伏原始发电量 (TWh)',
    'gross_wind_generation_twh': '风电原始发电量 (TWh)',
    'gross_vre_generation_twh': '原始风光发电量 (TWh)',
    'gross_vre_to_load_ratio': '原始风光发电量 / 总负荷',
    'curtailed_vre_twh': '弃电量 (TWh)',
    'curtailment_rate': '弃电率',
    'actual_vre_generation_twh': '实际风光发电量 (TWh)',
    'base_generation_twh': '基荷发电量 (TWh)',
    'flexible_generation_twh': '灵活电源发电量 (TWh)',
    'total_generation_twh': '总发电量 (TWh)',
    'vre_share': 'VRE 渗透率：实际风光发电量 / 总发电量',
    'flexible_ratio': '灵活电源比例',
    'total_load_twh': '总负荷 (TWh)',
    'transmission_capacity_tw': '输电容量 (TW)',
    'total_annual_cost': '年度总成本 (billion USD/year)',
}
```

---

## 11.2 更新全年度汇总表

建议列：

```text
SSP
年份
光伏装机容量
风电装机容量
原始风光发电量
原始风光发电量 / 总负荷
弃电量
弃电率
实际风光发电量
总发电量
VRE 渗透率
年度成本
exitflag
```

---

# 12. 修改 `utils/evaluate_dispatch_and_cost_cached.m`

核心逻辑不需要修改。

建议：

```text
保持当前缓存键
```

并在 9 个优化主脚本开头增加：

```matlab
clear evaluate_dispatch_and_cost_cached
```

避免同一 MATLAB 会话中复用旧指标定义产生的缓存。

---

# 13. 修改 `utils/build_initial_population.m`

不修改核心构造逻辑。

只更新注释：

```matlab
% 定向增删场站仅用于构造候选初始个体。
%
% 最终是否满足约束，由 nonlcon*.m 调用完整调度判断：
%
%   VRE 渗透率
%   = 实际风光发电量 / 总发电量
%
%   弃电率
%   = 弃电量 / 调度前原始风光发电量
```

---

# 14. 测试计划

## 14.1 单元测试：新 VRE 定义

新增：

```text
utils/test_vre_share_definition.m
```

检查：

```matlab
assert(abs( ...
    metrics.actual_vre_generation_twh ...
    - (metrics.gross_vre_generation_twh ...
       - metrics.curtailed_vre_twh)) ...
    < 1e-6);

assert(abs( ...
    metrics.total_generation_twh ...
    - (metrics.actual_vre_generation_twh ...
       + metrics.base_generation_twh ...
       + metrics.flexible_generation_twh)) ...
    < 1e-6);

assert(abs( ...
    metrics.vre_share ...
    - metrics.actual_vre_generation_twh ...
      / metrics.total_generation_twh) ...
    < 1e-10);
```

---

## 14.2 单元测试：弃电率约束

新增：

```text
utils/test_curtailment_constraint.m
```

检查：

```matlab
cost_cfg.ENABLE_CURTAILMENT_CONSTRAINT = true;
cost_cfg.MAX_CURTAILMENT = 0.15;
```

构造：

```text
curtailment_rate = 0.10
```

预期：

```text
约束满足
```

构造：

```text
curtailment_rate = 0.20
```

预期：

```text
c(end) = 0.05
最终解不可行
```


---

## 14.4 2050 年冒烟测试

先运行：

```bash
export POPULATION_SIZE=10
export MAX_GENERATIONS=1
```

分别运行：

```text
Optimization_ssp126/Optimization_SC_2050.m
Optimization_ssp245/Optimization_SC_2050.m
Optimization_ssp560/Optimization_SC_2050.m
```

目的：

```text
验证新字段存在
验证 VRE 定义正确
验证弃电率约束生效
验证不可行解会被阻断
```

---


# 15. 验收标准

修改完成后，必须满足：

1. `vre_share` 不再使用：

```text
1 - base_load_ratio - flexible_ratio
```

2. `vre_share` 严格等于：

```text
actual_vre_generation_twh
/ total_generation_twh
```

3. `actual_vre_generation_twh` 严格等于：

```text
gross_vre_generation_twh
- curtailed_vre_twh
```

4. `total_generation_twh` 严格等于：

```text
actual_vre_generation_twh
+ base_generation_twh
+ flexible_generation_twh
```

5. `cost_cfg.ENABLE_CURTAILMENT_CONSTRAINT` 已改为：

```matlab
true
```

6. 弃电率约束生效：

```text
curtailment_rate <= 0.15
```

7. 不可行结果不能生成 `Sel.mat`。

8. 日志中必须打印：

```text
原始风光发电量
弃电量
实际风光发电量
基荷发电量
灵活电源发电量
总发电量
VRE 渗透率
VRE 定义
弃电率
弃电率上限
弃电率约束是否启用
```

9. 旧版 HDF5 不得被新版后处理误读。

10. 旧版 2050、2040、2030 结果全部作废，必须重新运行。

---

# 16. 最终输出示例

修改后日志建议包含：

```text
=== 原始发电量诊断 ===
光伏原始发电量:          48838.0200 TWh
风电原始发电量:           9215.0800 TWh
原始风光发电量:          58053.1000 TWh
原始风光发电量 / 总负荷:     1.1177

=== 调度后实际发电量 ===
弃电量:                  38459.5500 TWh
弃电率:                      0.6625
实际风光发电量:          19593.5500 TWh
基荷发电量:              26902.9200 TWh
灵活电源发电量:           7714.0000 TWh
总发电量:                54210.4700 TWh

=== 渗透率与约束 ===
VRE 渗透率:                  0.3614
VRE 定义:                    实际风光发电量 / 总发电量
VRE 约束区间:                [0.2871, 0.4646]
弃电率上限:                  0.1500
弃电率约束是否启用:          true
```

该示例中的弃电率为：

```text
0.6625
```

因此，修改后应被判定为：

```text
不可行
```

不会继续生成：

```text
Sel.mat
```
