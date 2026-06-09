# `dev-SSPs-cost-only`：约束诊断、弃电率配置集中化、弃电率验收余量修改计划

**不管`区域扰动`!**
**不管`区域扰动`!**
**不管`区域扰动`!**


## 0. 修改目标

本轮针对以下三个 SSP 目录、三个年份统一修改：

```text
Optimization_ssp126/
Optimization_ssp245/
Optimization_ssp560/
```

年份：

```text
2050
2040
2030
```

共涉及：

```text
3 个 SSP × 3 个年份 = 9 组优化流程
```

本轮只修改四项内容：

1. 在 GA 完成后打印每一项约束值，用于明确是哪一项约束越界。
2. 弃电率上限只允许在 `Optimization_ssp*/optimization_config.m` 中设置。
~~修复 `utils/build_initial_population.m` 中的区域扰动 bug。~~
4. 仅针对弃电率放宽最终结果验收：  
   如果：

```text
弃电率 ≤ 弃电率上限 + 1%
```

则最终结果允许通过。

本计划将 `1%` 解释为：

```text
绝对增加 1 个百分点
```

即：

```text
0.15 + 0.01 = 0.16
0.16 + 0.01 = 0.17
```

不是：

```text
0.15 × 1.01 = 0.1515
```

---

# 1. 当前代码中的相关情况

## 1.1 弃电率上限存在两个配置来源

当前共享配置：

```text
utils/cost_model_config.m
```

中设置：

```matlab
cost_cfg.ENABLE_CURTAILMENT_CONSTRAINT = true;
cost_cfg.MAX_CURTAILMENT = 0.15;
```

同时三个 SSP 的：

```text
Optimization_ssp*/optimization_config.m
```

中也分别设置：

```matlab
MAX_CURTAILMENT = ...
```

优化主脚本会再次覆盖：

```matlab
cost_cfg = cost_model_config();
cost_cfg.MAX_CURTAILMENT = MAX_CURTAILMENT;
```

这会造成配置来源不够清晰。

本轮改为：

```text
弃电率上限唯一权威来源：
Optimization_ssp*/optimization_config.m
```

共享配置只负责：

```text
是否启用弃电率约束
弃电率定义
```

不再负责数值阈值。

---

## 1.2 当前非线性约束是严格弃电率约束

当前 9 个 `nonlcon*.m` 中，逻辑为：

```matlab
if cost_cfg.ENABLE_CURTAILMENT_CONSTRAINT
    c(end+1) = metrics.curtailment_rate ...
             - cost_cfg.MAX_CURTAILMENT;
end
```

MATLAB `ga` 要求：

```text
c <= 0
```

因此，GA 内部仍应保持：

```text
弃电率 <= MAX_CURTAILMENT
```

本轮不放宽 GA 内部约束。

---

## 1.3 放宽只应用于 GA 完成后的最终验收

新的规则为：

```text
GA 搜索阶段：
弃电率 <= MAX_CURTAILMENT

GA 完成后的最终结果验收：
弃电率 <= MAX_CURTAILMENT + CURTAILMENT_ACCEPTANCE_MARGIN
```

其中：

```matlab
CURTAILMENT_ACCEPTANCE_MARGIN = 0.01;
```

注意：

```text
VRE 上下界约束
既有光伏装机约束
既有风电装机约束
等式约束
```

仍然保持原来的严格判断，不允许使用这 1% 余量。

---

# 2. 配置文件修改

## 2.1 修改三个 `optimization_config.m`

修改：

```text
Optimization_ssp126/optimization_config.m
Optimization_ssp245/optimization_config.m
Optimization_ssp560/optimization_config.m
```

在现有：

```matlab
MAX_CURTAILMENT = ...;
```

后增加：

```matlab
% 最终结果验收时，仅针对弃电率允许额外 1 个百分点余量。
% 注意：GA 搜索阶段仍然使用严格的 MAX_CURTAILMENT。
CURTAILMENT_ACCEPTANCE_MARGIN = 0.01;
```

示例：

```matlab
%% 4. VRE 与弃电率配置

MAX_CURTAILMENT = 0.15;

% 最终结果验收余量：绝对增加 1 个百分点。
% 例如 MAX_CURTAILMENT = 0.15 时，
% 最终验收允许 curtailment_rate <= 0.16。
CURTAILMENT_ACCEPTANCE_MARGIN = 0.01;
```

如果某个 SSP 使用：

```matlab
MAX_CURTAILMENT = 0.15;
```

则最终验收允许：

```text
0.15 + 0.01 = 0.16
```

---

## 2.2 修改 `utils/cost_model_config.m`

删除：

```matlab
cost_cfg.MAX_CURTAILMENT = 0.15;
```

保留：

```matlab
cost_cfg.ENABLE_CURTAILMENT_CONSTRAINT = true;
```

修改注释：

```matlab
%% 8. 弃电率约束与弃电成本

% 弃电率定义：
%   curtailment_rate = 弃电量 / 调度前原始风光发电量
%
% 是否启用弃电率约束：
cost_cfg.ENABLE_CURTAILMENT_CONSTRAINT = true;
%
% MAX_CURTAILMENT 不在共享配置中赋值。
% 唯一权威来源：
%   Optimization_ssp*/optimization_config.m
%
% 优化主脚本、nonlcon 单参数模式和 convert_h5_to_sel.m
% 必须在加载 SSP 配置后注入：
%
%   cost_cfg.MAX_CURTAILMENT = MAX_CURTAILMENT;
```

---

## 2.3 增加防御性检查

建议新增共享函数：

```text
utils/validate_curtailment_config.m
```

内容：

```matlab
function validate_curtailment_config(cost_cfg, acceptance_margin)

    if cost_cfg.ENABLE_CURTAILMENT_CONSTRAINT
        if ~isfield(cost_cfg, 'MAX_CURTAILMENT') ...
                || isempty(cost_cfg.MAX_CURTAILMENT) ...
                || ~isscalar(cost_cfg.MAX_CURTAILMENT) ...
                || ~isfinite(cost_cfg.MAX_CURTAILMENT)
            error('Config:MissingMaxCurtailment', ...
                ['cost_cfg.MAX_CURTAILMENT 未设置。' ...
                 '请从 Optimization_ssp*/optimization_config.m 注入。']);
        end
    end

    if nargin >= 2
        if ~isscalar(acceptance_margin) ...
                || ~isfinite(acceptance_margin) ...
                || acceptance_margin < 0
            error('Config:InvalidCurtailmentAcceptanceMargin', ...
                'CURTAILMENT_ACCEPTANCE_MARGIN 必须为非负标量。');
        end
    end
end
```

在 9 个优化主脚本和 3 个 `convert_h5_to_sel.m` 中调用：

```matlab
validate_curtailment_config( ...
    cost_cfg, ...
    CURTAILMENT_ACCEPTANCE_MARGIN);
```

---

# 3. 打印每一项约束值

## 3.1 修改 9 个 `nonlcon*.m`

修改：

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

将函数签名从：

```matlab
function [c, ceq] = nonlcon2050(...)
```

改为：

```matlab
function [c, ceq, constraint_names] = nonlcon2050(...)
```

2040、2030 同理。

说明：

```text
MATLAB ga 仍然只读取前两个输出：
[c, ceq]

最终结果验收阶段额外读取第三个输出：
constraint_names
```

---

## 3.2 为每项约束添加名称

初始化：

```matlab
c = [];
constraint_names = {};
```

### 既有光伏装机约束

```matlab
c(end+1) = sum(tmp_e);
constraint_names{end+1} = ...
    'existing_solar_unmet_region_count';
```

含义：

```text
值 <= 0 表示满足
值 > 0 表示仍有多少个区域未满足既有光伏装机要求
```

### 既有风电装机约束

```matlab
c(end+1) = unmet_wind_count - allowed_unmet_wind;
constraint_names{end+1} = ...
    'existing_wind_unmet_region_count_minus_allowance';
```

### VRE 下界约束

SSP1-2.6、SSP2-4.5：

```matlab
if ~isnan(min_vre)
    c(end+1) = min_vre - vre_share;
    constraint_names{end+1} = ...
        'vre_lower_bound';
end
```

SSP5-6.0 的下界为 `NaN`，不添加该项。

### VRE 上界约束

```matlab
c(end+1) = vre_share - max_vre;
constraint_names{end+1} = ...
    'vre_upper_bound';
```

### 弃电率上界约束

```matlab
if cost_cfg.ENABLE_CURTAILMENT_CONSTRAINT
    c(end+1) = metrics.curtailment_rate ...
             - cost_cfg.MAX_CURTAILMENT;

    constraint_names{end+1} = ...
        'curtailment_upper_bound_strict';
end
```

---

## 3.3 新增统一打印函数

新增：

```text
utils/print_constraint_diagnostics.m
```

日志中每一项约束都同时打印：

```text
英文标识符
中文名称
约束值
是否严格通过
```

保留英文标识符，便于程序检索和自动汇总；增加中文名称，便于人工阅读日志。

建议在打印函数内部增加中文映射：

```matlab
function zh_name = get_constraint_name_zh(en_name)

    switch en_name
        case 'existing_solar_unmet_region_count'
            zh_name = '既有光伏装机未满足区域数量';

        case 'existing_wind_unmet_region_count_minus_allowance'
            zh_name = '既有风电装机未满足区域数量减允许违反区域数';

        case 'vre_lower_bound'
            zh_name = 'VRE 渗透率下界约束';

        case 'vre_upper_bound'
            zh_name = 'VRE 渗透率上界约束';

        case 'curtailment_upper_bound_strict'
            zh_name = '弃电率名义上限约束';

        otherwise
            zh_name = '未定义中文名称';
    end
end
```

逐项打印：

```matlab
for i = 1:length(c_strict)
    fprintf('[%d] %s\n', ...
        i, ...
        constraint_names{i});

    fprintf('    中文名称     = %s\n', ...
        get_constraint_name_zh( ...
            constraint_names{i}));

    fprintf('    strict_value = %.8e\n', ...
        c_strict(i));

    fprintf('    strict_pass  = %s\n', ...
        mat2str( ...
            c_strict(i) ...
            <= strict_tolerance));
end
```

如果存在等式约束，也要打印中文：

```matlab
for i = 1:length(ceq)
    fprintf('[eq-%d] equality_constraint_%d\n', ...
        i, i);

    fprintf('    中文名称     = 等式约束 %d\n', ...
        i);

    fprintf('    equality_value = %.8e\n', ...
        ceq(i));

    fprintf('    equality_pass  = %s\n', ...
        mat2str( ...
            abs(ceq(i)) ...
            <= strict_tolerance));
end
```

建议输出：

```text
=== 最终约束逐项诊断 ===

[1] existing_solar_unmet_region_count
    中文名称     = 既有光伏装机未满足区域数量
    strict_value = 0.00000000e+00
    strict_pass  = true

[2] existing_wind_unmet_region_count_minus_allowance
    中文名称     = 既有风电装机未满足区域数量减允许违反区域数
    strict_value = 0.00000000e+00
    strict_pass  = true

[3] vre_lower_bound
    中文名称     = VRE 渗透率下界约束
    strict_value = -1.24800000e-01
    strict_pass  = true

[4] vre_upper_bound
    中文名称     = VRE 渗透率上界约束
    strict_value = -3.18000000e-02
    strict_pass  = true

[5] curtailment_upper_bound_strict
    中文名称     = 弃电率名义上限约束
    strict_value = 2.89000000e-04
    strict_pass  = false

=== 弃电率最终验收 ===

actual_curtailment_rate
中文名称                      = 实际弃电率
value                         = 0.150289

configured_max_curtailment
中文名称                      = 配置中的名义弃电率上限
value                         = 0.150000

curtailment_acceptance_margin
中文名称                      = 最终验收允许的弃电率余量
value                         = 0.010000

final_acceptance_upper_bound
中文名称                      = 最终验收弃电率上限
value                         = 0.160000

final_acceptance_pass
中文名称                      = 是否通过最终弃电率验收
value                         = true
```


---

# 4. 仅针对弃电率放宽最终验收

## 4.1 保留通用严格检查函数

保留：

```text
utils/check_solution_feasibility.m
```

不修改原有含义：

```text
所有 c <= tolerance
所有 |ceq| <= tolerance
```

它继续用于：

```text
严格可行性诊断
```

---

## 4.2 新增最终验收函数

新增：

```text
utils/check_final_solution_acceptance.m
```

接口建议：

```matlab
function acceptance = check_final_solution_acceptance( ...
    c_strict, ...
    ceq, ...
    constraint_names, ...
    curtailment_rate, ...
    max_curtailment, ...
    curtailment_acceptance_margin, ...
    standard_tolerance)
```

逻辑：

```matlab
function acceptance = check_final_solution_acceptance( ...
    c_strict, ceq, constraint_names, ...
    curtailment_rate, max_curtailment, ...
    curtailment_acceptance_margin, standard_tolerance)

    if nargin < 7
        standard_tolerance = 1e-6;
    end

    c_accept = c_strict(:);

    idx = find(strcmp( ...
        constraint_names, ...
        'curtailment_upper_bound_strict'));

    if ~isempty(idx)
        c_accept(idx) = ...
            curtailment_rate ...
            - (max_curtailment ...
               + curtailment_acceptance_margin);
    end

    strict_feasibility = ...
        check_solution_feasibility( ...
            c_strict, ceq, standard_tolerance);

    acceptance_feasibility = ...
        check_solution_feasibility( ...
            c_accept, ceq, standard_tolerance);

    acceptance.strict_constraint_values = c_strict(:)';
    acceptance.acceptance_constraint_values = c_accept(:)';
    acceptance.strict_is_feasible = ...
        strict_feasibility.is_feasible;
    acceptance.is_accepted = ...
        acceptance_feasibility.is_feasible;
    acceptance.max_strict_violation = ...
        strict_feasibility.max_constraint_violation;
    acceptance.max_acceptance_violation = ...
        acceptance_feasibility.max_constraint_violation;
    acceptance.curtailment_rate = curtailment_rate;
    acceptance.max_curtailment = max_curtailment;
    acceptance.curtailment_acceptance_margin = ...
        curtailment_acceptance_margin;
    acceptance.final_acceptance_upper_bound = ...
        max_curtailment ...
        + curtailment_acceptance_margin;
end
```

---

## 4.3 修改 9 个优化主脚本

修改：

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

现有：

```matlab
[c_best, ceq_best] = nonlcon2050(...);

feasibility = check_solution_feasibility( ...
    c_best, ceq_best, 1e-6);

if ~feasibility.is_feasible
    ...
end
```

改为：

```matlab
[c_best, ceq_best, constraint_names] = ...
    nonlcon2050( ...
        best_scale, ...
        cost_cfg, ...
        scenario_cfg, ...
        model_data, ...
        persistent_data);

acceptance = check_final_solution_acceptance( ...
    c_best, ...
    ceq_best, ...
    constraint_names, ...
    best_metrics.curtailment_rate, ...
    cost_cfg.MAX_CURTAILMENT, ...
    CURTAILMENT_ACCEPTANCE_MARGIN, ...
    1e-6);

print_constraint_diagnostics( ...
    constraint_names, ...
    c_best, ...
    ceq_best, ...
    1e-6, ...
    best_metrics.curtailment_rate, ...
    cost_cfg.MAX_CURTAILMENT, ...
    CURTAILMENT_ACCEPTANCE_MARGIN);

fprintf('\n=== 最终解验收 ===\n');
fprintf('严格约束是否全部满足: %s\n', ...
    mat2str(acceptance.strict_is_feasible));

fprintf('最终结果是否接受:     %s\n', ...
    mat2str(acceptance.is_accepted));

fprintf('弃电率:               %.6f\n', ...
    best_metrics.curtailment_rate);

fprintf('名义弃电率上限:       %.6f\n', ...
    cost_cfg.MAX_CURTAILMENT);

fprintf('弃电率验收余量:       %.6f\n', ...
    CURTAILMENT_ACCEPTANCE_MARGIN);

fprintf('最终验收弃电率上限:   %.6f\n', ...
    acceptance.final_acceptance_upper_bound);

if ~acceptance.is_accepted
    fprintf('错误：最终解不满足验收规则，流水线终止。\n');
    ...
    error('Optimization:InfeasibleResult', ...);
end
```

2050、2040、2030 分别调用对应年份的：

```text
nonlcon2050
nonlcon2040
nonlcon2030
```

---

## 4.4 明确最终验收规则

最终结果只有在以下条件全部满足时才允许保存：

```text
既有光伏装机约束：严格满足
既有风电装机约束：严格满足
VRE 下界：严格满足
VRE 上界：严格满足
等式约束：严格满足
弃电率：允许 <= MAX_CURTAILMENT + CURTAILMENT_ACCEPTANCE_MARGIN
```

例如：

```text
MAX_CURTAILMENT = 0.15
CURTAILMENT_ACCEPTANCE_MARGIN = 0.01
```

则：

| 最终弃电率 | 是否接受 |
|---:|---|
| 0.1499 | 接受，严格满足 |
| 0.1503 | 接受，使用验收余量 |
| 0.1599 | 接受，使用验收余量 |
| 0.1600 | 接受 |
| 0.1601 | 拒绝 |

---

# 5. 保存结果时增加审计字段

## 5.1 修改 9 个优化主脚本

正式 HDF5 中新增：

```text
/is_strictly_feasible
/is_accepted
/curtailment_acceptance_margin
/final_acceptance_curtailment_upper_bound
/strict_constraint_values
/acceptance_constraint_values
```

写入示例：

```matlab
h5create(h5file, '/is_strictly_feasible', [1, 1]);
h5write(h5file, '/is_strictly_feasible', ...
    double(acceptance.strict_is_feasible));

h5create(h5file, '/is_accepted', [1, 1]);
h5write(h5file, '/is_accepted', ...
    double(acceptance.is_accepted));

h5create(h5file, '/curtailment_acceptance_margin', [1, 1]);
h5write(h5file, '/curtailment_acceptance_margin', ...
    CURTAILMENT_ACCEPTANCE_MARGIN);

h5create(h5file, ...
    '/final_acceptance_curtailment_upper_bound', ...
    [1, 1]);

h5write(h5file, ...
    '/final_acceptance_curtailment_upper_bound', ...
    acceptance.final_acceptance_upper_bound);

h5create(h5file, ...
    '/strict_constraint_values', ...
    size(acceptance.strict_constraint_values));

h5write(h5file, ...
    '/strict_constraint_values', ...
    acceptance.strict_constraint_values);

h5create(h5file, ...
    '/acceptance_constraint_values', ...
    size(acceptance.acceptance_constraint_values));

h5write(h5file, ...
    '/acceptance_constraint_values', ...
    acceptance.acceptance_constraint_values);
```

Sidecar MAT 同步保存：

```matlab
acceptance
constraint_names
CURTAILMENT_ACCEPTANCE_MARGIN
```

---

## 5.2 `/is_feasible` 兼容策略

当前后处理可能读取：

```text
/is_feasible
```

建议保留该字段，但将它解释为：

```text
最终结果是否通过验收规则
```

写入：

```matlab
is_feasible = double(acceptance.is_accepted);
```

同时新增更明确字段：

```text
/is_strictly_feasible
/is_accepted
```

避免以后混淆：

```text
严格满足所有 GA 约束
```

和：

```text
仅弃电率使用 1 个百分点验收余量后允许保存
```

---

# 6. 修改 3 个 `convert_h5_to_sel.m`

修改：

```text
Optimization_ssp126/convert_h5_to_sel.m
Optimization_ssp245/convert_h5_to_sel.m
Optimization_ssp560/convert_h5_to_sel.m
```

## 6.1 加载 SSP 配置

保持：

```matlab
run('optimization_config.m');
cost_cfg = cost_model_config();
cost_cfg.MAX_CURTAILMENT = MAX_CURTAILMENT;
```

增加：

```matlab
validate_curtailment_config( ...
    cost_cfg, ...
    CURTAILMENT_ACCEPTANCE_MARGIN);
```

---

## 6.2 修改弃电率二次校验

当前严格检查：

```matlab
if cost_cfg.ENABLE_CURTAILMENT_CONSTRAINT ...
        && curtailment_rate > cost_cfg.MAX_CURTAILMENT + 1e-6
    error(...)
end
```

改为：

```matlab
final_acceptance_curtailment_upper_bound = ...
    cost_cfg.MAX_CURTAILMENT ...
    + CURTAILMENT_ACCEPTANCE_MARGIN;

if cost_cfg.ENABLE_CURTAILMENT_CONSTRAINT ...
        && curtailment_rate ...
           > final_acceptance_curtailment_upper_bound ...
             + 1e-6
    error('Convert:CurtailmentUpperBoundViolation', ...
        ['弃电率 %.6f 高于最终验收上限 %.6f。' ...
         '名义上限 %.6f，验收余量 %.6f。终止后处理。'], ...
        curtailment_rate, ...
        final_acceptance_curtailment_upper_bound, ...
        cost_cfg.MAX_CURTAILMENT, ...
        CURTAILMENT_ACCEPTANCE_MARGIN);
end
```

---

## 6.3 输出完整说明

打印：

```matlab
fprintf('弃电率:                 %.6f\n', ...
    curtailment_rate);

fprintf('名义弃电率上限:         %.6f\n', ...
    cost_cfg.MAX_CURTAILMENT);

fprintf('弃电率验收余量:         %.6f\n', ...
    CURTAILMENT_ACCEPTANCE_MARGIN);

fprintf('最终验收弃电率上限:     %.6f\n', ...
    final_acceptance_curtailment_upper_bound);
```

---


# 8. 非线性约束单参数模式同步修改

9 个 `nonlcon*.m` 的单参数模式当前会：

```matlab
p_cost_cfg = cost_model_config();
run('optimization_config.m');
p_cost_cfg.MAX_CURTAILMENT = MAX_CURTAILMENT;
```

保留该注入逻辑。

增加：

```matlab
validate_curtailment_config( ...
    p_cost_cfg, ...
    CURTAILMENT_ACCEPTANCE_MARGIN);
```

说明：

```text
nonlcon 内部只需要严格 MAX_CURTAILMENT。
CURTAILMENT_ACCEPTANCE_MARGIN 不参与 GA 约束，
这里只做配置合法性检查和统一日志审计。
```

---

# 9. 日志输出建议

每组优化完成后，日志至少应包含：

```text
=== 最终约束逐项诊断 ===

existing_solar_unmet_region_count
strict_value = ...

existing_wind_unmet_region_count_minus_allowance
strict_value = ...

vre_lower_bound
strict_value = ...

vre_upper_bound
strict_value = ...

curtailment_upper_bound_strict
strict_value = ...

=== 最终解验收 ===

严格约束是否全部满足
最终结果是否接受
弃电率
名义弃电率上限
弃电率验收余量
最终验收弃电率上限
```

SSP5-6.0 没有 VRE 下界时，日志不应打印：

```text
vre_lower_bound
```

---

# 10. 修改文件清单

## 10.1 修改共享文件

```text
utils/cost_model_config.m
utils/build_initial_population.m
```

## 10.2 新增共享文件

```text
utils/validate_curtailment_config.m
utils/check_final_solution_acceptance.m
utils/print_constraint_diagnostics.m
```

## 10.3 修改三个 SSP 配置

```text
Optimization_ssp126/optimization_config.m
Optimization_ssp245/optimization_config.m
Optimization_ssp560/optimization_config.m
```

## 10.4 修改 9 个非线性约束文件

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

## 10.5 修改 9 个优化主脚本

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

## 10.6 修改 3 个后处理脚本

```text
Optimization_ssp126/convert_h5_to_sel.m
Optimization_ssp245/convert_h5_to_sel.m
Optimization_ssp560/convert_h5_to_sel.m
```

## 10.7 建议同步修改汇总脚本

```text
summarize_costmin_results.py
```

增加列：

```text
严格约束是否全部满足
最终结果是否接受
名义弃电率上限
弃电率验收余量
最终验收弃电率上限
```

---

# 11. 测试计划

## 11.1 单元测试：最终验收余量

新增：

```text
utils/test_check_final_solution_acceptance.m
```

测试：

```text
MAX_CURTAILMENT = 0.15
CURTAILMENT_ACCEPTANCE_MARGIN = 0.01
```

| 弃电率 | 其他约束 | 预期 |
|---:|---|---|
| 0.1499 | 满足 | 接受，严格可行 |
| 0.1503 | 满足 | 接受，使用余量 |
| 0.1599 | 满足 | 接受，使用余量 |
| 0.1600 | 满足 | 接受 |
| 0.1601 | 满足 | 拒绝 |
| 0.1503 | VRE 上界越界 | 拒绝 |
| 0.1503 | 既有装机约束越界 | 拒绝 |

---


## 11.3 冒烟测试

先使用：

```bash
export POPULATION_SIZE=10
export MAX_GENERATIONS=1
export PARPOOL_NUM_WORKERS=2
```

分别运行三个 SSP 的 2050：

```text
Optimization_ssp126/Optimization_SC_2050.m
Optimization_ssp245/Optimization_SC_2050.m
Optimization_ssp560/Optimization_SC_2050.m
```

检查日志：

```text
每一项约束均有名称和值
严格约束结果已打印
最终验收结果已打印
弃电率名义上限和验收上限已区分
```

---

## 11.4 回归测试：0.15 + 0.01

对于：

```text
MAX_CURTAILMENT = 0.15
CURTAILMENT_ACCEPTANCE_MARGIN = 0.01
```

如果最终弃电率：

```text
0.1503
```

则：

```text
严格约束是否全部满足 = false
最终结果是否接受     = true
```

并且：

```text
允许生成 HDF5
允许生成 Sel.mat
```

如果最终弃电率：

```text
0.1601
```

则：

```text
最终结果是否接受 = false
不得生成正式 HDF5
不得生成 Sel.mat
```

---

## 11.5 完整运行顺序

先运行：

```text
SSP1-2.6：2050
SSP2-4.5：2050
SSP5-6.0：2050
```

确认三组 2050 行为正确后，再运行：

```text
2040
2030
```

原因：

```text
2040 和 2030 会继承上游年份结果。
```

---

# 12. 验收标准

完成后必须满足：

1. 弃电率数值上限只在：

```text
Optimization_ssp*/optimization_config.m
```

中设置。

2. 共享配置中不再硬编码：

```matlab
cost_cfg.MAX_CURTAILMENT = 0.15;
```

3. 三个 SSP 的配置均包含：

```matlab
CURTAILMENT_ACCEPTANCE_MARGIN = 0.01;
```

4. GA 内部弃电率约束仍然严格使用：

```text
curtailment_rate <= MAX_CURTAILMENT
```

5. GA 完成后的最终验收仅对弃电率允许：

```text
curtailment_rate <= MAX_CURTAILMENT + 0.01
```

6. 其他约束仍严格执行，不使用 1% 余量。

7. 每次 GA 完成后，日志打印每一项约束名称、数值和是否通过。

8. SSP5-6.0 未设置 VRE 下界时，不打印虚假的下界约束项。

11. 正式 HDF5 中可以区分：

```text
严格可行
使用弃电率验收余量后允许保存
```

12. `convert_h5_to_sel.m` 使用与优化主脚本相同的弃电率验收规则。
