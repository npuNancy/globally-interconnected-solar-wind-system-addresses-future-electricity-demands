# dev-SSPs-cost-only：逐小时能源出力可视化代码修改计划（风光合并版）

**先只对`Optimization_ssp245`进行修改和测试。**
**先只对`Optimization_ssp245`进行修改和测试。**
**先只对`Optimization_ssp245`进行修改和测试。**
**先只对`Optimization_ssp245`进行修改和测试。**

## 0. 修改目标

当前分支：

```text
https://github.com/npuNancy/globally-interconnected-solar-wind-system-addresses-future-electricity-demands/tree/dev-SSPs-cost-only
```

当前分支已经从原来的多目标 / Pareto 流程转为**单目标成本最小化**流程。因此，逐小时能源出力可视化不再围绕 Pareto 解集合展开，而是围绕每个 SSP、每个年份最终保存的单个最优解：

```text
best_scale
```

进行一次确定性 dispatch replay，然后导出 8760 小时能源流数据，再绘图。

本次修改的核心要求：

```text
风电和光伏不再拆分。
```

统一使用：

```text
VRE = 风电 + 光伏
```

因此，两张图分别为：

```text
图 A：发电侧原始出力
原始风光发电量 + 负荷曲线

图 B：负荷侧实际供电结构
实际风光发电量 + 储能放电 + 基荷 + 灵活电源 + 负荷曲线
```

---

# 1. 图形定义

## 1.1 图 A：发电侧原始出力

图 A 展示：

```text
调度前，已选中的全部风电和光伏场站理论上能够产生多少电。
```

图 A 包含：

```text
原始风光发电量
负荷曲线
```

建议图形形式：

```text
area：原始风光发电量
line：负荷曲线
```

定义：

```text
原始风光发电量
= 所有选中风光格网逐小时发电量之和

负荷曲线
= 原始总负荷曲线，不扣除基荷
```

图 A 不考虑：

```text
弃电
输电
储能
基荷扣除
灵活电源
```

图 A 回答的问题：

```text
选中的风光场站每小时理论上可以发多少电？
原始风光出力相对于负荷是过剩还是不足？
```

---

## 1.2 图 B：负荷侧实际供电结构

图 B 展示：

```text
调度后，每个小时的负荷实际由哪些来源满足。
```

图 B 包含：

```text
实际风光发电量
储能放电
基荷
灵活电源
负荷曲线
```

建议图形形式：

```text
stacked area：
实际风光发电量
+ 储能放电
+ 基荷
+ 灵活电源

line：
负荷曲线
```

定义：

```text
实际风光发电量
= 实际进入负荷侧供电结构的 VRE 电量

储能放电
= 储能在该小时向负荷侧释放的电量

基荷
= base_load_ratio 对应的逐小时基荷供电量

灵活电源
= flexible_ele 对应的逐小时补足电量

负荷曲线
= 原始总负荷曲线，不扣除基荷
```

图 B 回答的问题：

```text
每个小时负荷由风光、储能、基荷和灵活电源分别承担多少？
储能和灵活电源在风光不足时如何补足缺口？
```

---

# 2. 与当前单目标优化流程的关系

当前分支是单目标成本最小化，不再需要：

```text
Pareto 解集合
preferred solution 选择
逐个 Pareto 解保存 dispatch 细节
```

新的可视化流程应当是：

```text
1. Optimization_SC_2050.m / Optimization_SC_2040.m / Optimization_SA_2030.m
   得到单个 best_scale

2. 保存 best_scale 到 HDF5 和 Sidecar MAT

3. convert_h5_to_sel.m 生成 Opt_*_Sel.mat

4. 新增 replay 脚本重新读取 best_scale

5. 调用 evaluate_dispatch_and_cost(...) 返回 detail

6. 导出 8760 小时能源流 CSV / MAT

7. 使用 Python 绘制图 A 和图 B
```

核心原则：

```text
优化阶段只保存最终解和年度诊断指标。
可视化阶段单独 replay。
不要在 GA 每次评估时写出 8760 小时文件。
```

原因：

```text
GA 会大量调用 dispatch 函数。
如果每个候选解都保存 8760 小时细节，会显著增加 I/O、内存和磁盘开销。
当前只需要最终 best_scale 的逐小时结果。
```

---

# 3. 当前代码需要补充什么

当前 dispatch 函数已经在内部计算了部分逐小时数组，例如：

```text
grid_gens
stored_ele
curtailed_ele
flexible_ele
shifted_ele
consumed_ele
```

但这些变量主要用于年度指标核算，默认不会完整返回给后处理。

本次需要新增：

```text
可选 detail 输出
逐小时能源流重建
逐小时 CSV / MAT 导出脚本
逐小时绘图脚本
```

不需要新增：

```text
实际风电拆分
实际光伏拆分
按比例分摊风电 / 光伏
双路风光 dispatch
```

---

# 4. 核心设计：为 dispatch 增加可选 detail 输出

## 4.1 修改文件

```text
utils/evaluate_dispatch_and_cost.m
utils/evaluate_dispatch_and_cost_cached.m
```

## 4.2 修改函数接口

保持原接口兼容：

```matlab
metrics = evaluate_dispatch_and_cost(...)
```

新增可选第二输出：

```matlab
[metrics, detail] = evaluate_dispatch_and_cost(...)
```

推荐写法：

```matlab
function [metrics, detail] = evaluate_dispatch_and_cost(...)

    want_detail = nargout >= 2;

    ...

    if want_detail
        detail = struct();
        ...
    end
end
```

这样可以避免优化过程中额外构建和返回大型逐小时 detail。

---

# 5. detail 中需要保存的逐小时变量

## 5.1 时间字段

统一输出 8760 小时：

```text
hour_index
month
day_of_year
hour_of_day
```

其中：

```text
hour_index = 1:8760
```

---

## 5.2 图 A 所需字段

图 A 只需要：

```text
raw_vre_generation_twh_hourly
load_twh_hourly
```

MATLAB 中建议变量名：

```matlab
detail.raw_vre_generation_twh_hourly
detail.load_twh_hourly
```

计算方式：

```matlab
raw_vre_generation_twh_hourly = ...
    sum(gens(selected_grid_mask, :), 1);

load_twh_hourly = ...
    sum(loads_original, 1);
```

注意：

```text
load_twh_hourly 必须使用扣除基荷前的原始负荷。
```

因此，需要在 `evaluate_dispatch_and_cost.m` 中，在修改负荷前保存：

```matlab
loads_original = loads;
```

---

## 5.3 图 B 所需字段

图 B 需要：

```text
actual_vre_generation_twh_hourly
storage_discharge_twh_hourly
base_generation_twh_hourly
flexible_generation_twh_hourly
load_twh_hourly
```

MATLAB 中建议变量名：

```matlab
detail.actual_vre_generation_twh_hourly
detail.storage_discharge_twh_hourly
detail.base_generation_twh_hourly
detail.flexible_generation_twh_hourly
detail.load_twh_hourly
```

---

## 5.4 可选诊断字段

为了定位问题，建议额外导出：

```text
curtailment_twh_hourly
storage_charge_twh_hourly
stored_energy_twh_hourly
```

MATLAB 中：

```matlab
detail.curtailment_twh_hourly
detail.storage_charge_twh_hourly
detail.stored_energy_twh_hourly
```

这些字段不一定进入最终图，但有助于解释：

```text
为什么某些时段弃电高？
为什么某些时段需要储能放电？
储能 SOC 如何变化？
```

---

# 6. 如何记录储能充放电

在 `evaluate_dispatch_and_cost.m` 中新增：

```matlab
storage_discharge_ele = zeros(size(grid_load));
storage_charge_ele = zeros(size(grid_load));
```

当储能充电时：

```matlab
storage_charge_ele(time_ind, gg_ind) = t_amount;
```

当储能放电时：

```matlab
storage_discharge_ele(time_ind, gg_ind) = discharge_amount;
```

其中：

```text
storage_discharge_ele
```

应记录储能向负荷侧实际释放的电量，而不是储能内部能量减少量。

若当前放电逻辑类似：

```matlab
available = stored_ele(time_ind, gg_ind) * fromStorageLoss;
discharge = min(deficit, available);

stored_ele(time_ind+1, gg_ind) = ...
    stored_ele(time_ind, gg_ind) ...
    - discharge / fromStorageLoss;
```

则记录：

```matlab
storage_discharge_ele(time_ind, gg_ind) = discharge;
```

---

# 7. 如何得到负荷侧实际风光发电量

本次不区分风电和光伏。

建议直接按照负荷侧逐小时能量平衡得到：

```text
actual_vre_generation
= load
- storage_discharge
- baseload
- flexible_generation
```

区域逐小时计算：

```matlab
actual_vre_by_region_twh = ...
    load_by_region_twh ...
    - storage_discharge_by_region_twh ...
    - base_by_region_twh ...
    - flexible_by_region_twh;
```

防御性处理：

```matlab
actual_vre_by_region_twh = ...
    max(actual_vre_by_region_twh, 0);
```

全球逐小时汇总：

```matlab
detail.actual_vre_generation_twh_hourly = ...
    sum(actual_vre_by_region_twh, 1);
```

说明：

```text
actual_vre_generation_twh_hourly
表示负荷侧实际由 VRE 直接承担的供电量。

它不包含储能放电。
储能放电单独作为图 B 的一层展示。
```

---

# 8. 需要在 dispatch 内部新增的区域级变量

为了构建图 B，建议保留以下区域逐小时数组：

```matlab
load_by_region_twh                 % 20 × 8760
base_by_region_twh                 % 20 × 8760
flexible_by_region_twh             % 20 × 8760
storage_discharge_by_region_twh    % 20 × 8760
actual_vre_by_region_twh           % 20 × 8760
```

可选增加：

```matlab
storage_charge_by_region_twh       % 20 × 8760
curtailment_by_region_twh          % 20 × 8760
stored_energy_by_region_twh        % 20 × 8761
```

不再需要：

```text
raw_pv_by_region_twh
raw_wind_by_region_twh
actual_pv_by_region_twh
actual_wind_by_region_twh
pv_ratio
wind_ratio
```

---

# 9. 新增 replay 导出脚本

## 9.1 新增 MATLAB 脚本

新增：

```text
utils/export_hourly_dispatch_detail.m
```

接口建议：

```matlab
export_hourly_dispatch_detail(year, scenario_dir)
```

示例：

```matlab
export_hourly_dispatch_detail(2050, 'Optimization_ssp245')
```

也可以在 SSP 目录内调用：

```matlab
year = 2050;
export_hourly_dispatch_detail
```

---

## 9.2 replay 脚本读取内容

根据年份读取：

```text
results/Optimization_SC_2050_Res.h5
results/Optimization_SC_2040_Res.h5
results/Optimization_SA_2030_Res.h5
```

从中读取：

```text
/res_scale
```

然后读取：

```text
optimization_config.m
utils/cost_model_config.m
```

重建：

```text
model_data
persistent_data
scenario_cfg
cost_cfg
```

调用：

```matlab
[metrics, detail] = evaluate_dispatch_and_cost(...);
```

---

## 9.3 replay 输出文件

建议输出到：

```text
Optimization_ssp*/results/hourly/
```

每个年份输出：

```text
hourly_dispatch_2050.mat
hourly_dispatch_2050.csv
hourly_dispatch_2040.mat
hourly_dispatch_2040.csv
hourly_dispatch_2030.mat
hourly_dispatch_2030.csv
```

CSV 字段：

```text
hour
month
day_of_year
hour_of_day
load_twh
raw_vre_twh
actual_vre_twh
storage_discharge_twh
base_twh
flexible_twh
curtailment_twh
storage_charge_twh
stored_energy_twh
```

---

# 10. 新增 Python 绘图脚本

新增：

```text
plot_hourly_energy_output.py
```

支持：

```bash
python plot_hourly_energy_output.py \
  --ssp ssp245 \
  --year 2050 \
  --input Optimization_ssp245/results/hourly/hourly_dispatch_2050.csv \
  --output-dir Optimization_ssp245/results/img/hourly
```

建议支持三个时间窗口：

```text
full_year
first_month
sample_week
```

默认输出：

```text
hourly_energy_A_generation_side_2050_full_year.png
hourly_energy_B_load_side_2050_full_year.png
hourly_energy_A_generation_side_2050_sample_week.png
hourly_energy_B_load_side_2050_sample_week.png
```

---

# 11. 图 A 绘图逻辑

Python：

```python
x = df['hour']

ax.fill_between(
    x,
    0,
    df['raw_vre_twh'],
    label='Raw VRE generation',
    alpha=0.8,
)

ax.plot(
    x,
    df['load_twh'],
    label='Load',
    linewidth=1.2,
)
```

标题：

```text
Figure A. Generation-side raw hourly VRE output
```

中文：

```text
图 A：发电侧原始逐小时风光出力
```

Y 轴：

```text
Electricity (TWh/hour)
```

如果每个时间步为 1 小时，则数值也可理解为：

```text
Power equivalent (TW)
```

---

# 12. 图 B 绘图逻辑

Python：

```python
x = df['hour']

stack = [
    df['actual_vre_twh'],
    df['storage_discharge_twh'],
    df['base_twh'],
    df['flexible_twh'],
]

labels = [
    'Actual VRE generation',
    'Storage discharge',
    'Baseload',
    'Flexible generation',
]

ax.stackplot(
    x,
    stack,
    labels=labels,
)

ax.plot(
    x,
    df['load_twh'],
    label='Load',
    linewidth=1.2,
)
```

标题：

```text
Figure B. Load-side actual hourly supply structure
```

中文：

```text
图 B：负荷侧实际逐小时供电结构
```

---

# 13. 图 B 能量平衡校验

绘图前必须检查：

```text
实际风光发电量
+ 储能放电
+ 基荷
+ 灵活电源
≈ 负荷
```

Python：

```python
supply = (
    df['actual_vre_twh']
    + df['storage_discharge_twh']
    + df['base_twh']
    + df['flexible_twh']
)

balance_error = (
    supply
    - df['load_twh']
)
```

输出：

```text
max_abs_balance_error
mean_abs_balance_error
```

若：

```text
max_abs_balance_error > 1e-6
```

则给出警告。

允许存在极小浮点误差，但不能出现系统性偏差。

---

# 14. 年度总量回归校验

CSV 按全年求和后，检查：

```text
sum(raw_vre_twh)
≈ metrics.gross_vre_generation_twh
```

```text
sum(curtailment_twh)
≈ metrics.curtailed_vre_twh
```

```text
sum(flexible_twh)
≈ metrics.flexible_generation_twh
```

```text
sum(base_twh)
≈ metrics.base_generation_twh
```

额外检查：

```text
sum(actual_vre_twh)
+ sum(storage_discharge_twh)
+ sum(base_twh)
+ sum(flexible_twh)
≈ sum(load_twh)
```

---

# 15. 与年度 VRE 指标的关系

需要明确区分：

```text
年度 actual_vre_generation_twh
```

和：

```text
图 B 中逐小时 actual_vre_twh 求和
```

图 B 中：

```text
actual_vre_twh
```

表示：

```text
逐小时直接进入负荷侧的 VRE 供电量
```

不包括：

```text
储能放电
```

而年度指标中：

```text
actual_vre_generation_twh
= gross_vre_generation_twh
- curtailed_vre_twh
```

表示：

```text
扣除弃电后进入系统的 VRE 发电量
```

其中包含：

```text
用于储能充电的 VRE 电量
```

因此，两者不要求严格相等。

建议在 replay 输出中同时保存：

```text
actual_vre_generation_twh_hourly_load_side
storage_charge_twh_hourly
storage_discharge_twh_hourly
```

并在文档中注明：

```text
负荷侧逐小时 VRE 供电量用于画图 B。
年度 VRE 渗透率仍按正式年度指标定义计算。
```

---

# 16. run_full_pipeline.sh 集成建议

建议第一版不直接修改完整优化流水线。

新增独立脚本：

```text
Optimization_ssp126/run_hourly_visualization.sh
Optimization_ssp245/run_hourly_visualization.sh
Optimization_ssp560/run_hourly_visualization.sh
```

示例：

```bash
#!/usr/bin/env bash
set -euo pipefail

YEAR="${1:-2050}"

matlab -batch "year=${YEAR}; export_hourly_dispatch_detail"

python ../plot_hourly_energy_output.py \
  --ssp ssp245 \
  --year "${YEAR}" \
  --input "results/hourly/hourly_dispatch_${YEAR}.csv" \
  --output-dir "results/img/hourly"
```

原因：

```text
逐小时可视化属于后处理。
不应增加完整优化流水线的失败点。
```

待独立脚本稳定后，再考虑接入：

```text
run_full_pipeline.sh
```

---

# 17. 建议新增文件

```text
utils/export_hourly_dispatch_detail.m
plot_hourly_energy_output.py
Optimization_ssp126/run_hourly_visualization.sh
Optimization_ssp245/run_hourly_visualization.sh
Optimization_ssp560/run_hourly_visualization.sh
```

可选新增：

```text
run_hourly_visualization_all.sh
```

用于统一处理：

```text
SSP1-2.6：2030 / 2040 / 2050
SSP2-4.5：2030 / 2040 / 2050
SSP5-6.0：2030 / 2040 / 2050
```

---

# 18. 需要修改的文件

## 18.1 必须修改

```text
utils/evaluate_dispatch_and_cost.m
utils/evaluate_dispatch_and_cost_cached.m
```

## 18.2 必须新增

```text
utils/export_hourly_dispatch_detail.m
plot_hourly_energy_output.py
Optimization_ssp126/run_hourly_visualization.sh
Optimization_ssp245/run_hourly_visualization.sh
Optimization_ssp560/run_hourly_visualization.sh
```

## 18.3 暂不修改

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

Optimization_ssp126/run_full_pipeline.sh
Optimization_ssp245/run_full_pipeline.sh
Optimization_ssp560/run_full_pipeline.sh
```

原因：

```text
逐小时可视化通过 replay 最终 best_scale 完成。
不需要在优化主脚本中保存逐小时数据。
第一版也不接入完整优化流水线。
```

---

# 19. 测试计划

## 19.1 单个年份测试

先测试：

```text
Optimization_ssp245 2050
```

设置种群数量=10，代数=1，快速得到 best_scale。
```bash
export POPULATION_SIZE=10    # 种群大小，默认 1000
export MAX_GENERATIONS=1     # 最大代数，默认 200
export PARPOOL_NUM_WORKERS=0  # 并行池工作者数量，默认 0（不使用并行）
```

执行：

```bash
cd Optimization_ssp245

matlab -batch "year=2050; export_hourly_dispatch_detail"

python ../plot_hourly_energy_output.py \
  --ssp ssp245 \
  --year 2050 \
  --input results/hourly/hourly_dispatch_2050.csv \
  --output-dir results/img/hourly
```

检查输出：

```text
results/hourly/hourly_dispatch_2050.csv
results/hourly/hourly_dispatch_2050.mat
results/img/hourly/hourly_energy_A_generation_side_2050_full_year.png
results/img/hourly/hourly_energy_B_load_side_2050_full_year.png
results/img/hourly/hourly_energy_A_generation_side_2050_sample_week.png
results/img/hourly/hourly_energy_B_load_side_2050_sample_week.png
```

---

## 19.2 CSV 字段检查

必须包含：

```text
hour
load_twh
raw_vre_twh
actual_vre_twh
storage_discharge_twh
base_twh
flexible_twh
curtailment_twh
storage_charge_twh
```

不得再要求：

```text
raw_pv_twh
raw_wind_twh
actual_pv_twh
actual_wind_twh
```

---

## 19.3 能量平衡测试

检查：

```text
load_twh
≈ actual_vre_twh
+ storage_discharge_twh
+ base_twh
+ flexible_twh
```

---

## 19.4 年度回归测试

检查：

```text
sum(raw_vre_twh)
≈ metrics.gross_vre_generation_twh
```

```text
sum(curtailment_twh)
≈ metrics.curtailed_vre_twh
```

```text
sum(base_twh)
≈ metrics.base_generation_twh
```

```text
sum(flexible_twh)
≈ metrics.flexible_generation_twh
```

---

## 19.5 图形人工检查

图 A 应表现出：

```text
原始风光出力的逐小时波动
原始风光出力可能超过负荷
```

图 B 应表现出：

```text
供电结构堆叠基本贴合负荷曲线
基荷形成稳定带
储能放电在风光不足时出现
灵活电源在缺口时出现
```

---

# 20. 与论文方法背景的关系

逐小时可视化服务于解释小时级供需平衡。相关论文强调，PV 和风电具有天气驱动的波动性，日周期和季节周期会造成发电与负荷不匹配，因此需要储能、灵活电源和跨区域互联来平衡供需。论文也明确其框架关注小时级数据、风光部署、储能容量和跨区域输电优化。

因此，本计划中的图 A 和图 B 分别对应：

```text
图 A：场站侧调度前的原始 VRE 波动
图 B：经过储能、基荷和灵活电源协调后的负荷侧供电结构
```

---

# 21. 最终验收标准

完成后应满足：

1. 不改变优化目标函数和约束逻辑。
2. 不在 GA 每次评估中写出 8760 小时文件。
3. 可以对任意 SSP、任意年份的最终 `best_scale` replay 得到逐小时能源流。
4. 图 A 包含：

```text
原始风光发电量
负荷曲线
```

5. 图 B 包含：

```text
实际风光发电量
储能放电
基荷
灵活电源
负荷曲线
```

6. 不再拆分：

```text
风电
光伏
```

7. CSV 年度总量与 `metrics` 中的年度诊断量一致。
8. 图 B 的供电堆叠与负荷曲线基本闭合。
9. 支持 full-year 和 sample-week 两种图形输出。
10. 输出目录统一为：

```text
Optimization_ssp*/results/hourly/
Optimization_ssp*/results/img/hourly/
```
