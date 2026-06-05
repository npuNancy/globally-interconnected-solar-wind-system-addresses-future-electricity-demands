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

新增了运维成本和可选的灵活电源运行成本，它们都是年度费用；现有风光、储能和输电成本则是一次性投资。如果直接相加，单位不一致。因此，推荐使用"风光扩张年度化增量系统成本"，单位统一为 `billion USD / year`：

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

继续使用当前代码已经存在的区域差异化 CAPEX：

- 光伏：按洲使用已有 `USD/kW` 系数；
- 陆上风电：按洲使用已有 `USD/kW` 系数；
- 海上风电：继续使用 `3461 USD/kW`。

### 2.2 储能建设成本

继续使用当前代码：`350 USD/kWh`。

### 2.3 跨区域输电建设成本

沿用原代码逻辑：`跨区域输电建设成本 = 98 × Σ 每条线路的输电容量`。

在年度化增量成本模式下，将该一次性建设成本年度化。

### 2.4 运维成本

第一版增加风光固定 O&M：

```text
annual_pv_om      = pv_capex      * 0.01
annual_onwind_om  = onwind_capex  * 0.03
annual_offwind_om = offwind_capex * 0.03
```

储能和跨区域输电 O&M 暂时保留配置接口（默认关闭）。

### 2.5 灵活电源运行成本

默认关闭，保留接口。启用后按区域边际成本计算。

### 2.6 年度化

使用统一的资本回收系数 CRF：

```text
CRF(r,n) = r * (1+r)^n / ((1+r)^n - 1)
annualized_capex = upfront_capex * CRF
```

参数：`WACC=0.074`, `LIFETIME_PV=25`, `LIFETIME_ONWIND=25`, `LIFETIME_OFFWIND=25`, `LIFETIME_STORAGE=15`, `LIFETIME_TX=40`。

---

## 3. 代码修改实录

> 以下记录对比 git 旧版（fdb4a90，NSGA-II 三目标）与当前代码（单目标成本最小化）的实际差异。
> 修改直接在 `Optimization_ssp245/` 原文件上进行，不创建平行 `_costmin` 文件。

### 3.1 新增共享文件（`utils/`）

以下文件在旧版中不存在，全部新增：

| 文件 | 用途 |
|------|------|
| `utils/cost_model_config.m` | 集中存放成本配置：CAPEX、WACC/寿命、CRF、O&M 比例、灵活电源开关、弃电约束开关、旧版兼容开关 |
| `utils/evaluate_dispatch_and_cost.m` | 逐小时调度与成本核算共享函数，返回结构体（弃电率、VRE 渗透率、成本分解等）。调度逻辑从原 `OptFun_*_Dispatch_*.m` 平移，成本核算拆为 legacy/annualized 两种模式 |
| `utils/evaluate_dispatch_and_cost_cached.m` | 在 `evaluate_dispatch_and_cost` 基础上增加 `persistent` 缓存，避免目标函数和非线性约束对同一 `scale` 重复计算调度 |
| `utils/objective_total_cost.m` | 目标函数封装：调用 `evaluate_dispatch_and_cost`，返回标量 `total_annual_cost` |
| `utils/select_preferred_solution.m` | Pareto 解筛选（仍保留用于旧流程兼容） |
| `utils/test_select_preferred_solution.m` | 筛选函数的单元测试 |

### 3.2 `Optimization_ssp245/Optimization_SC_2050.m`（原文件直接修改）

| 项目 | 旧版（NSGA-II） | 新版（单目标成本最小化） |
|------|-----------------|------------------------|
| 优化器 | `gamultiobj`（NSGA-II 多目标） | `ga`（单目标） |
| 目标函数 | `OptFun_SC_Dispatch_2050(all_ins,all_gens,...)` | `objective_total_cost(scale, all_ins,...)` |
| 非线性约束 | `@nonlcon2050`（仅装机约束） | `@nonlcon2050`（装机约束 + VRE 上下界 + 可选弃电率约束） |
| ConstraintTolerance | 未显式设置（默认） | `1e-6` |
| 成本配置 | 无 | `cost_model_config()` + `addpath('../utils')` |
| 情景配置 | 无 | `scenario_cfg` struct（base_load_ratio, min/max_vre_share, allowed_unmet_wind_regions） |
| 模型数据 | 不保存 | 保存 `results/model_data.mat` 供 `nonlcon2050.m` 独立加载 |
| 结果输出 | `res_scale` + `prs`（三目标值） | `res_scale` + `prs` + `metrics` + `cost_breakdown` + sidecar MAT |
| 结果评估 | 无（目标函数已计算） | 调用 `evaluate_dispatch_and_cost` 评估最优解指标 |

### 3.3 `Optimization_ssp245/Optimization_SC_2040.m`（原文件直接修改）

与 2050 年修改相同，额外：
- 候选格网受 2050 年结果约束（加载 `results/Opt_SC_2050_Sel.mat`）；
- 保存 `results/model_data_2040.mat`；
- `ALLOWED_UNMET_WIND_REGIONS_2040 = 4`。

### 3.4 `Optimization_ssp245/Optimization_SA_2030.m`（原文件直接修改）

与 2050 年修改相同，额外：
- 候选格网受 2040 年结果约束（加载 `results/Opt_SC_2040_Sel.mat`）；
- 互联模式 `S-A`（maxNodes=2）；
- 保存 `results/model_data_2030.mat`；
- `ALLOWED_UNMET_WIND_REGIONS_2030 = 8`。

### 3.5 `Optimization_ssp245/OptFun_SC_Dispatch_2050.m`（原文件直接修改）

| 项目 | 旧版 | 新版 |
|------|------|------|
| 签名 | `f = OptFun_SC_Dispatch_2050(ins_cap, gens, loads, CGrid_Index, scale, base_load_ratio)` | 不变 |
| 返回值 | `f(1)=弃电率, f(2)=灵活电源比例, f(3)=成本` | `f = objective_total_cost(...)` 标量 |
| 调度逻辑 | 内联 8760h 调度 | 委托给 `objective_total_cost` → `evaluate_dispatch_and_cost` |
| 成本核算 | 内联（风光按洲差异化 + 储能 350 + 输电 98） | 委托给共享函数（支持 legacy/annualized 两种模式） |
| 持久化 | 无 | `persistent cost_cfg nonlsol`，首次调用时加载 |

同理修改 `OptFun_SC_Dispatch_2040.m`（S-C 模式）和 `OptFun_SA_Dispatch_2030.m`（S-A 模式）。

### 3.6 `Optimization_ssp245/nonlcon2050.m`（原文件直接修改）

| 项目 | 旧版 | 新版 |
|------|------|------|
| 签名 | `[c,ceq] = nonlcon2050(x)` | `[c,ceq] = nonlcon2050(x, cost_cfg, scenario_cfg, model_data, persistent_data)` |
| 约束数量 | 2 个（光伏装机 + 风电装机） | 4~5 个（光伏装机 + 风电装机 + VRE 下界 + VRE 上界 + 可选弃电率） |
| 数据加载 | 每次 `load` NonlConData.mat | 单参数时 `persistent` 缓存（加载 `results/model_data.mat`）；多参数时直接使用传入参数 |
| VRE 约束 | 无 | `c(end+1) = min_vre - vre_share`，`c(end+1) = vre_share - max_vre` |
| 弃电率约束 | 无 | 可选：`c(end+1) = curtailment_rate - MAX_CURTAILMENT` |
| 风电容忍 | 全部区域必须满足 | `c(end+1) = unmet_wind_count - ALLOWED_UNMET_WIND_REGIONS` |
| 调度计算 | 无 | 调用 `evaluate_dispatch_and_cost_cached` 计算 VRE 渗透率 |

同理修改 `nonlcon2040.m`（加载 `model_data_2040.mat`，S-C 模式）和 `nonlcon2030.m`（加载 `model_data_2030.mat`，S-A 模式）。

三个文件的约束逻辑完全相同，差异仅在于：
- 单参数模式加载的 `.mat` 文件名不同（`model_data.mat` / `model_data_2040.mat` / `model_data_2030.mat`）；
- 情景参数不同（base_load_ratio、min/max_vre_share、allowed_unmet_wind_regions、interconnection_mode）。

### 3.7 `Optimization_ssp245/optimization_config.m`（原文件直接修改）

新增内容：

```matlab
%% 4. Pareto preferred solution 筛选配置
SCENARIO_NAME = 'SSP2-4.5';
SELECTION_MODE = 'bounded_transition';
MAX_CURTAILMENT = 0.15;

MIN_VRE_SHARE_2030 = 0.1417;
MIN_VRE_SHARE_2040 = 0.2091;
MIN_VRE_SHARE_2050 = 0.2871;

MAX_VRE_SHARE_2030 = 0.2579;
MAX_VRE_SHARE_2040 = 0.3572;
MAX_VRE_SHARE_2050 = 0.4646;

%% 5. 既有装机约束的允许违反区域数量
ALLOWED_UNMET_WIND_REGIONS_2050 = 0;
ALLOWED_UNMET_WIND_REGIONS_2040 = 4;
ALLOWED_UNMET_WIND_REGIONS_2030 = 8;
```

### 3.8 `Optimization_ssp245/convert_h5_to_sel.m`（原文件直接修改）

旧版从 Pareto 前沿中筛选 preferred solution（调用 `select_preferred_solution`）。
新版直接读取 `ga` 唯一最优解：

- 不再调用 `select_preferred_solution`；
- 直接读取 `/res_scale`、`/metrics`、`/cost_breakdown`；
- 校验 VRE 约束是否满足；
- 保留 costmin 专用元数据（`preferred_selection_mode='costmin'`）。

### 3.9 新增辅助文件

以下辅助文件同时用于 NSGA-II 和成本最小化模式，非本次修改新增但随优化脚本一起出现在 diff 中：

| 文件 | 用途 |
|------|------|
| `calculatePathCapacity.m` | 输电路径瓶颈容量计算 |
| `compute_pv_density.m` | 纬度依赖光伏装机密度计算 |
| `findAllPathsFromStart.m` | DFS 搜索可行输电路径 |
| `geotiffread.m` | Mapping Toolbox 替代：优先读 `.mat`，回退读 `.tif` |
| `readgeoraster.m` | Mapping Toolbox 替代 |
| `readtif_custom.m` | 纯 MATLAB TIFF 读取器 |
| `nansum.m` | Statistics Toolbox 替代 |
| `convert_tif_to_mat.py` | Python 脚本：批量 `.tif` → `.mat` 预转换 |
| `run_full_pipeline.sh` | 三阶段优化自动化流水线 |
| `run_2050_pipeline.sh` | 仅 2050 阶段的流水线 |

### 3.10 测试文件

新增 `Optimization_ssp245/test_costmin.m`，覆盖 12 组共 45 项测试：

1. `cost_model_config` 基础正确性（CRF 值、默认开关）
2. 候选格网与测试解向量构建
3. legacy 模式回归（与旧版 `OptFun_SC_Dispatch_2050` 数值完全一致）
4. 年度化增量成本模式基本运行
5. O&M 开关测试
6. 灵活电源 OPEX 测试
7. VRE 约束测试（区间内不违反、宽松不违反、严格被违反）
8. 缓存一致性测试
9. `objective_total_cost` 封装测试
10. S-A 模式测试
11. 2040/2030 配置项加载测试
12. `allowed_unmet_wind_regions` 约束容忍测试

---

## 4. 推广至 SSP126 和 SSP560

SSP126 和 SSP560 的修改直接在原代码上进行，与 SSP245 相同的策略：

1. 新增 `utils/` 下的共享函数（已存在，直接复用）
2. 修改对应 SSP 目录下的优化脚本、目标函数、约束函数、`convert_h5_to_sel.m`、`optimization_config.m`
3. 不创建平行 `_costmin` 文件

仅替换情景配置：

```text
DEMAND_YEAR
BASE_LOAD_RATIO_YEAR
MIN_VRE_SHARE_YEAR
MAX_VRE_SHARE_YEAR
ALLOWED_UNMET_WIND_REGIONS_YEAR
interconnection_mode
```

避免维护多份重复成本函数。

---

## 5. 结果文件格式

为兼容旧流程，继续保存：

```text
/res_scale    1 × nvars
/prs          1 × 3  (curtailment_rate, flexible_ratio, total_annual_cost)
```

新增：

```text
/metrics      [curtailment_rate, flexible_ratio, vre_share, total_annual_cost]
/cost_breakdown  年度化模式：13 项分解；legacy 模式：1 项总成本
```

Sidecar MAT 文件保存完整结构体和配置。

---

## 6. 缓存与性能

目标函数和非线性约束都会调用 8,760 小时调度。`evaluate_dispatch_and_cost_cached.m` 使用 `persistent` 缓存最近一次 `scale` 及其 `metrics`，避免对同一候选解重复计算两次。

---

## 7. 已完成状态

- [x] `utils/cost_model_config.m`
- [x] `utils/evaluate_dispatch_and_cost.m`
- [x] `utils/evaluate_dispatch_and_cost_cached.m`
- [x] `utils/objective_total_cost.m`
- [x] `Optimization_ssp245/Optimization_SC_2050.m`
- [x] `Optimization_ssp245/Optimization_SC_2040.m`
- [x] `Optimization_ssp245/Optimization_SA_2030.m`
- [x] `Optimization_ssp245/OptFun_SC_Dispatch_2050.m`
- [x] `Optimization_ssp245/OptFun_SC_Dispatch_2040.m`
- [x] `Optimization_ssp245/OptFun_SA_Dispatch_2030.m`
- [x] `Optimization_ssp245/nonlcon2050.m`
- [x] `Optimization_ssp245/nonlcon2040.m`
- [x] `Optimization_ssp245/nonlcon2030.m`
- [x] `Optimization_ssp245/optimization_config.m`
- [x] `Optimization_ssp245/convert_h5_to_sel.m`
- [x] `Optimization_ssp245/test_costmin.m`（45/45 测试通过）
- [ ] SSP126 同步修改
- [ ] SSP560 同步修改
