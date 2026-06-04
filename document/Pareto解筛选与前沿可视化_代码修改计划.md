# Pareto 解筛选与前沿可视化：代码修改计划

## 1. 修改目标
修改三个 SSP 情景目录：

```text
Optimization_ssp126/
Optimization_ssp245/
Optimization_ssp560/
```

目标是：

1. 删除当前 `convert_h5_to_sel.m` 中“默认选择 Pareto 解列表中间编号”的逻辑；
2. 根据 SSP 情景叙事和 AR6 五模型结果，自动筛选 preferred solution；
3. 将弃电率上限统一设定为 **15%**（原论文为5%）；
4. 增加 Pareto 前沿可视化脚本 `plot_pareto_front.py`；
5. 在三套 `run_full_pipeline.sh` 中自动调用绘图脚本；
6. 对不存在合格解的情况显式报错，禁止静默回退到任意中间编号。

本计划只涉及 Pareto 解筛选与可视化，不修改优化目标函数，不修改基荷计算逻辑，不增加额外实验分支。

---

## 2. 当前代码存在的问题

三个 SSP 目录中的 `convert_h5_to_sel.m` 目前均使用：

```matlab
if sol_idx == 0
    sol_idx = round(n_solutions / 2);
    fprintf('自动选择第 %d 个解（共 %d 个的中间位置）\n', sol_idx, n_solutions);
end
```

这意味着：

- 未根据弃电率筛选；
- 未根据风光渗透率区间筛选；
- 未根据成本比较；
- NSGA-II 输出列表中的“中间编号”没有明确物理含义；
- 下游 2040 和 2030 的候选场址集合会继承一个任意的父阶段方案。

必须改为：

```text
先按照情景约束筛选可行解
        ↓
再在可行解中选择成本最低解
        ↓
将该解保存为 preferred solution
        ↓
将该解传递给下一阶段
```

---

## 3. 统一指标定义

现有 `convert_h5_to_sel.m` 已经从 `/prs` 中读取三目标值：

```matlab
prs = h5read(h5file, '/prs');
```

并使用：

```matlab
flexible_ratio = prs(:, 2);
solar_wind_penetration = 1 - base_load_ratio - flexible_ratio;
```

本次修改继续沿用这一口径。

统一定义：

```matlab
curtailment = prs(:, 1);
flexible_ratio = prs(:, 2);
cost = prs(:, 3);
vre_share = 1 - base_load_ratio - flexible_ratio;
```

其中：

| 变量 | 含义 |
|---|---|
| `curtailment` | 弃电率 |
| `flexible_ratio` | 灵活电源比例 |
| `cost` | 系统成本 |
| `vre_share` | 风光渗透率 |

统一弃电率上限：

```matlab
MAX_CURTAILMENT = 0.15;
```

即：

\[
R_c \le 15\%
\]

---

## 4. 各 SSP 情景的筛选规则

## 4.1 SSP1-2.6：积极转型路径

约束：

\[
R_{p,\mathrm{mean}}^{\mathrm{AR6}}
\le
R_p
\le
R_{p,\max}^{\mathrm{AR6}}
\]

\[
R_c \le 15\%
\]

在满足条件的解中，选择成本最低解：

\[
i^\star
=
\arg\min_{i\in\mathcal{S}} C_i
\]

参数：

| 年份 | 风光渗透率下界：五模型均值 | 风光渗透率上界：五模型最大值 |
|---:|---:|---:|
| 2030 | 26.35% | 57.89% |
| 2040 | 43.08% | 68.23% |
| 2050 | 55.44% | 71.11% |

配置值：

```matlab
MIN_VRE_SHARE_2030 = 0.2635;
MIN_VRE_SHARE_2040 = 0.4308;
MIN_VRE_SHARE_2050 = 0.5544;

MAX_VRE_SHARE_2030 = 0.5789;
MAX_VRE_SHARE_2040 = 0.6823;
MAX_VRE_SHARE_2050 = 0.7111;
```

---

## 4.2 SSP2-4.5：中等转型路径

约束：

\[
R_{p,\mathrm{mean}}^{\mathrm{AR6}}
\le
R_p
\le
R_{p,\max}^{\mathrm{AR6}}
\]

\[
R_c \le 15\%
\]

在满足条件的解中，选择成本最低解。

参数：

| 年份 | 风光渗透率下界：五模型均值 | 风光渗透率上界：五模型最大值 |
|---:|---:|---:|
| 2030 | 14.17% | 25.79% |
| 2040 | 20.91% | 35.72% |
| 2050 | 28.71% | 46.46% |

配置值：

```matlab
MIN_VRE_SHARE_2030 = 0.1417;
MIN_VRE_SHARE_2040 = 0.2091;
MIN_VRE_SHARE_2050 = 0.2871;

MAX_VRE_SHARE_2030 = 0.2579;
MAX_VRE_SHARE_2040 = 0.3572;
MAX_VRE_SHARE_2050 = 0.4646;
```

---

## 4.3 SSP5-6.0：化石能源主导路径

SSP5-6.0 不设置积极转型路径的风光渗透率下界，只设置上限。

约束：

\[
R_p
\le
R_{p,\mathrm{second-highest}}^{\mathrm{AR6}}
\]

\[
R_c \le 15\%
\]

在满足条件的解中，选择成本最低解。

参数：

| 年份 | 风光渗透率上界：五模型中的第二高值 |
|---:|---:|
| 2030 | 8.90% |
| 2040 | 11.73% |
| 2050 | 14.20% |

配置值：

```matlab
MIN_VRE_SHARE_2030 = [];
MIN_VRE_SHARE_2040 = [];
MIN_VRE_SHARE_2050 = [];

MAX_VRE_SHARE_2030 = 0.0890;
MAX_VRE_SHARE_2040 = 0.1173;
MAX_VRE_SHARE_2050 = 0.1420;
```

说明：

- `SSP5-6.0` 的筛选逻辑不应强制风光占比达到某个积极转型目标；
- 只需要阻止优化算法选出超过 AR6 合理范围的高风光方案；
- 为保持代码接口统一，可以将无下界表示为 `NaN`，不要使用空数组参与布尔比较。

推荐实际配置：

```matlab
MIN_VRE_SHARE_2030 = NaN;
MIN_VRE_SHARE_2040 = NaN;
MIN_VRE_SHARE_2050 = NaN;
```

---

## 5. 需要修改和新增的文件清单

## 5.1 修改文件

三个情景目录均需要修改：

```text
Optimization_ssp126/optimization_config.m
Optimization_ssp126/convert_h5_to_sel.m
Optimization_ssp126/run_full_pipeline.sh

Optimization_ssp245/optimization_config.m
Optimization_ssp245/convert_h5_to_sel.m
Optimization_ssp245/run_full_pipeline.sh

Optimization_ssp560/optimization_config.m
Optimization_ssp560/convert_h5_to_sel.m
Optimization_ssp560/run_full_pipeline.sh
```

## 5.2 新增文件

仓库根目录新增：

```text
utils/select_preferred_solution.m
plot_pareto_front.py
```

测试文件新增：

```text
utils/test_select_preferred_solution.m
```
---

## 6. 修改 `optimization_config.m`

三个目录均在现有配置文件末尾增加 Pareto 筛选配置。

## 6.1 `Optimization_ssp126/optimization_config.m`

追加：

```matlab
%% 4. Pareto preferred solution 筛选配置
SCENARIO_NAME = 'SSP1-2.6';
SELECTION_MODE = 'bounded_transition';

MAX_CURTAILMENT = 0.15;

MIN_VRE_SHARE_2030 = 0.2635;
MIN_VRE_SHARE_2040 = 0.4308;
MIN_VRE_SHARE_2050 = 0.5544;

MAX_VRE_SHARE_2030 = 0.5789;
MAX_VRE_SHARE_2040 = 0.6823;
MAX_VRE_SHARE_2050 = 0.7111;
```

## 6.2 `Optimization_ssp245/optimization_config.m`

追加：

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
```

## 6.3 `Optimization_ssp560/optimization_config.m`

追加：

```matlab
%% 4. Pareto preferred solution 筛选配置
SCENARIO_NAME = 'SSP5-6.0';
SELECTION_MODE = 'fossil_upper_bound';

MAX_CURTAILMENT = 0.15;

% SSP5-6.0 不设置风光渗透率下界
MIN_VRE_SHARE_2030 = NaN;
MIN_VRE_SHARE_2040 = NaN;
MIN_VRE_SHARE_2050 = NaN;

% 五模型中的第二高值
MAX_VRE_SHARE_2030 = 0.0890;
MAX_VRE_SHARE_2040 = 0.1173;
MAX_VRE_SHARE_2050 = 0.1420;
```

## 6.4 添加对这些参数的中文注释

---

## 7. 新增 MATLAB 筛选函数

新增：

```text
utils/select_preferred_solution.m
```

建议实现：

```matlab
function result = select_preferred_solution( ...
    prs, ...
    base_load_ratio, ...
    min_vre_share, ...
    max_vre_share, ...
    max_curtailment, ...
    selection_mode)
% select_preferred_solution
%
% 从 NSGA-II Pareto 解中筛选 preferred solution。
%
% 输入：
%   prs(:,1)            弃电率
%   prs(:,2)            灵活电源比例
%   prs(:,3)            成本
%   base_load_ratio     基荷比例
%   min_vre_share       风光渗透率下界；SSP5-6.0 使用 NaN
%   max_vre_share       风光渗透率上界
%   max_curtailment     弃电率上限，本项目固定为 0.15
%   selection_mode      bounded_transition / fossil_upper_bound
%
% 输出：
%   result.sol_idx
%   result.status
%   result.curtailment
%   result.flexible_ratio
%   result.vre_share
%   result.cost
%   result.n_total
%   result.n_curtailment_ok
%   result.n_vre_ok
%   result.n_qualified

curtailment = prs(:, 1);
flexible_ratio = prs(:, 2);
cost = prs(:, 3);

vre_share = 1 - base_load_ratio - flexible_ratio;

curtailment_ok = curtailment <= max_curtailment;

switch selection_mode
    case 'bounded_transition'
        if isnan(min_vre_share)
            error('bounded_transition 模式必须提供 min_vre_share');
        end

        vre_ok = ...
            vre_share >= min_vre_share & ...
            vre_share <= max_vre_share;

    case 'fossil_upper_bound'
        vre_ok = vre_share <= max_vre_share;

    otherwise
        error('未知 selection_mode: %s', selection_mode);
end

qualified = find(curtailment_ok & vre_ok);

result = struct();
result.status = 'qualified';
result.n_total = length(curtailment);
result.n_curtailment_ok = nnz(curtailment_ok);
result.n_vre_ok = nnz(vre_ok);
result.n_qualified = length(qualified);
result.min_vre_share = min_vre_share;
result.max_vre_share = max_vre_share;
result.max_curtailment = max_curtailment;
result.selection_mode = selection_mode;

if isempty(qualified)
    result.status = 'no_qualified_solution';

    fprintf('\n=== Pareto 筛选失败：没有合格解 ===\n');
    fprintf('模式：%s\n', selection_mode);
    fprintf('Pareto 解总数：%d\n', result.n_total);
    fprintf('满足弃电率上限的解数量：%d\n', result.n_curtailment_ok);
    fprintf('满足风光约束的解数量：%d\n', result.n_vre_ok);
    fprintf('同时满足全部约束的解数量：%d\n', result.n_qualified);
    fprintf('最低弃电率：%.4f\n', min(curtailment));
    fprintf('风光渗透率范围：[%.4f, %.4f]\n', min(vre_share), max(vre_share));

    error('当前 Pareto 前沿不存在合格 preferred solution');
end

% 在合格解中选择成本最低方案
[~, local_idx] = min(cost(qualified));
sol_idx = qualified(local_idx);

result.sol_idx = sol_idx;
result.curtailment = curtailment(sol_idx);
result.flexible_ratio = flexible_ratio(sol_idx);
result.vre_share = vre_share(sol_idx);
result.cost = cost(sol_idx);

fprintf('\n=== Preferred solution ===\n');
fprintf('模式：%s\n', selection_mode);
fprintf('Pareto 解总数：%d\n', result.n_total);
fprintf('满足弃电率上限的解数量：%d\n', result.n_curtailment_ok);
fprintf('满足风光约束的解数量：%d\n', result.n_vre_ok);
fprintf('同时满足全部约束的解数量：%d\n', result.n_qualified);
fprintf('选中解编号：%d\n', result.sol_idx);
fprintf('弃电率：%.4f\n', result.curtailment);
fprintf('风光渗透率：%.4f\n', result.vre_share);
fprintf('灵活电源比例：%.4f\n', result.flexible_ratio);
fprintf('成本：%.1f 十亿美元\n', result.cost);
end
```

设计原则：

- 不允许自动选择中间解；
- 没有合格解时直接停止流水线；
- 所有计数、阈值和选中结果必须写入日志；
- SSP1-2.6 和 SSP2-4.5 使用上下界；
- SSP5-6.0 只使用上界；
- 所有场景统一使用 15% 弃电率上限；
- 所有场景均在合格解中选择成本最低方案。

---

## 8. 修改三个 `convert_h5_to_sel.m`

三个文件采用同样的修改方式。

文件：

```text
Optimization_ssp126/convert_h5_to_sel.m
Optimization_ssp245/convert_h5_to_sel.m
Optimization_ssp560/convert_h5_to_sel.m
```

## 8.1 修改注释

原注释：

```matlab
%   sol_idx  - Pareto 解编号（0=自动选中间解）
```

改为：

```matlab
%   sol_idx  - Pareto 解编号（0=按照情景约束自动选择 preferred solution）
```

## 8.2 加载共享 MATLAB 工具

在脚本开头增加：

```matlab
script_dir = fileparts(mfilename('fullpath'));
addpath(fullfile(script_dir, '..', 'utils'));
```

## 8.3 按年份读取筛选参数

在现有：

```matlab
switch year
```

中，同时读取上下界：

```matlab
switch year
    case 2050
        base_load_ratio = BASE_LOAD_RATIO_2050;
        min_vre_share = MIN_VRE_SHARE_2050;
        max_vre_share = MAX_VRE_SHARE_2050;
    case 2040
        base_load_ratio = BASE_LOAD_RATIO_2040;
        min_vre_share = MIN_VRE_SHARE_2040;
        max_vre_share = MAX_VRE_SHARE_2040;
    case 2030
        base_load_ratio = BASE_LOAD_RATIO_2030;
        min_vre_share = MIN_VRE_SHARE_2030;
        max_vre_share = MAX_VRE_SHARE_2030;
    otherwise
        error('year 必须为 2030、2040 或 2050');
end
```

## 8.4 替换中间编号逻辑

删除：

```matlab
%% 3. 选择解（sol_idx=0 时自动选中间解）
if sol_idx == 0
    sol_idx = round(n_solutions / 2);
    fprintf('自动选择第 %d 个解（共 %d 个的中间位置）\n', sol_idx, n_solutions);
end
```

替换为：

```matlab
%% 3. 选择 preferred solution
if sol_idx == 0
    selection = select_preferred_solution( ...
        prs, ...
        base_load_ratio, ...
        min_vre_share, ...
        max_vre_share, ...
        MAX_CURTAILMENT, ...
        SELECTION_MODE ...
    );

    sol_idx = selection.sol_idx;
else
    % 手动指定解时仍然计算并保存对应指标
    flexible_ratio_manual = prs(sol_idx, 2);

    selection = struct();
    selection.status = 'manual';
    selection.sol_idx = sol_idx;
    selection.curtailment = prs(sol_idx, 1);
    selection.flexible_ratio = flexible_ratio_manual;
    selection.vre_share = 1 - base_load_ratio - flexible_ratio_manual;
    selection.cost = prs(sol_idx, 3);
    selection.min_vre_share = min_vre_share;
    selection.max_vre_share = max_vre_share;
    selection.max_curtailment = MAX_CURTAILMENT;
    selection.selection_mode = SELECTION_MODE;
end
```

## 8.5 使用筛选结果输出指标

将原有单解输出替换为：

```matlab
scale = res_scale(sol_idx, :);

fprintf(['解 %d：弃电率=%.4f, 风光渗透率=%.4f, ', ...
         '灵活电源比例=%.4f, 成本=%.1f 十亿美元\n'], ...
    selection.sol_idx, ...
    selection.curtailment, ...
    selection.vre_share, ...
    selection.flexible_ratio, ...
    selection.cost ...
);
```

## 8.6 扩展 Sel.mat 输出内容

当前输出仅保存：

```matlab
save(outfile, 'opt_solar', 'opt_wind', 'opt_stoPow', 'opt_stoCap', 'opt_trans');
```

改为：

```matlab
preferred_sol_idx = selection.sol_idx;
preferred_selection_status = selection.status;
preferred_curtailment = selection.curtailment;
preferred_vre_share = selection.vre_share;
preferred_flexible_ratio = selection.flexible_ratio;
preferred_cost = selection.cost;
preferred_min_vre_share = selection.min_vre_share;
preferred_max_vre_share = selection.max_vre_share;
preferred_max_curtailment = selection.max_curtailment;
preferred_selection_mode = selection.selection_mode;
preferred_scenario_name = SCENARIO_NAME;

save(outfile, ...
    'opt_solar', ...
    'opt_wind', ...
    'opt_stoPow', ...
    'opt_stoCap', ...
    'opt_trans', ...
    'preferred_sol_idx', ...
    'preferred_selection_status', ...
    'preferred_curtailment', ...
    'preferred_vre_share', ...
    'preferred_flexible_ratio', ...
    'preferred_cost', ...
    'preferred_min_vre_share', ...
    'preferred_max_vre_share', ...
    'preferred_max_curtailment', ...
    'preferred_selection_mode', ...
    'preferred_scenario_name' ...
);
```

目的：

- Python 绘图脚本可以直接读取 Sel.mat；
- 后续审计可以明确知道选择了哪个解；
- 不依赖日志文本解析；
- 2040 和 2030 的输入布局仍可保持现有读取方式。

---

## 9. 新增 Python 可视化脚本

新增仓库根目录文件：

```text
plot_pareto_front.py
```

## 9.1 功能要求

脚本必须：

1. 读取指定年份 H5 中的 `/prs`；
2. 读取对应 `Sel.mat` 中的 preferred solution 元数据；
3. 计算所有 Pareto 解的风光渗透率；
4. 绘制所有 Pareto 解；
5. 高亮 preferred solution；
6. 标出风光渗透率上下界；
7. 标出弃电率上限 15%；
8. 将图保存到对应目录：

```text
Optimization_ssp*/results/img/
```

一个 SSP 的一个年份对应一张图。

输出文件名：

```text
pareto_front_2030.png
pareto_front_2040.png
pareto_front_2050.png
```

## 9.2 命令行接口

建议：

```bash
python ../plot_pareto_front.py \
  --scenario SSP1-2.6 \
  --year 2050 \
  --h5 results/Optimization_SC_2050_Res.h5 \
  --sel-mat results/Opt_SC_2050_Sel.mat \
  --output results/img/pareto_front_2050.png
```

## 9.3 绘图要求

散点图：

```text
x = 风光渗透率
y = 弃电率
颜色 = 成本
```

图中元素：

| 元素 | 要求 |
|---|---|
| 全部 Pareto 解 | 散点 |
| Preferred solution | 高亮星形点或明显描边点 |
| 风光渗透率下界 | x 轴竖线；SSP5-6.0 不绘制下界线 |
| 风光渗透率上界 | x 轴竖线 |
| 弃电率上限 | y 轴横线，固定为 15% |
| 成本 | Colorbar |
| 坐标轴 | 百分比显示 |
| 标题 | 包含 SSP 情景和年份 |
| 图例 | 说明 preferred solution 和约束线 |

## 9.4 推荐实现骨架

```python
#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

import h5py
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.ticker import PercentFormatter
from scipy.io import loadmat


def load_prs(h5_path: Path) -> np.ndarray:
    with h5py.File(h5_path, "r") as f:
        prs = np.asarray(f["prs"])

    # 兼容 MATLAB HDF5 维度方向差异
    if prs.ndim != 2:
        raise ValueError(f"/prs 必须是二维矩阵，实际 shape={prs.shape}")

    if prs.shape[1] == 3:
        return prs

    if prs.shape[0] == 3:
        return prs.T

    raise ValueError(f"无法识别 /prs 的形状：{prs.shape}")


def scalar_from_mat(mat: dict, key: str) -> float:
    if key not in mat:
        raise KeyError(f"Sel.mat 缺少字段：{key}")
    return float(np.asarray(mat[key]).squeeze())


def optional_scalar_from_mat(mat: dict, key: str) -> float | None:
    value = scalar_from_mat(mat, key)
    if np.isnan(value):
        return None
    return value


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scenario", required=True)
    parser.add_argument("--year", type=int, required=True)
    parser.add_argument("--h5", type=Path, required=True)
    parser.add_argument("--sel-mat", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    prs = load_prs(args.h5)
    mat = loadmat(args.sel_mat)

    sol_idx_matlab = int(round(scalar_from_mat(mat, "preferred_sol_idx")))
    sol_idx_python = sol_idx_matlab - 1

    base_load_ratio = scalar_from_mat(mat, "preferred_base_load_ratio")
    min_vre_share = optional_scalar_from_mat(mat, "preferred_min_vre_share")
    max_vre_share = scalar_from_mat(mat, "preferred_max_vre_share")
    max_curtailment = scalar_from_mat(mat, "preferred_max_curtailment")

    curtailment = prs[:, 0]
    flexible_ratio = prs[:, 1]
    cost = prs[:, 2]
    vre_share = 1.0 - base_load_ratio - flexible_ratio

    args.output.parent.mkdir(parents=True, exist_ok=True)

    fig, ax = plt.subplots(figsize=(8, 6))

    scatter = ax.scatter(
        vre_share,
        curtailment,
        c=cost,
        s=28,
        alpha=0.8,
    )

    ax.scatter(
        [vre_share[sol_idx_python]],
        [curtailment[sol_idx_python]],
        marker="*",
        s=260,
        edgecolors="black",
        linewidths=1.2,
        label=f"Preferred solution #{sol_idx_matlab}",
        zorder=5,
    )

    if min_vre_share is not None:
        ax.axvline(
            min_vre_share,
            linestyle="--",
            linewidth=1.2,
            label=f"VRE lower bound: {min_vre_share:.1%}",
        )

    ax.axvline(
        max_vre_share,
        linestyle="--",
        linewidth=1.2,
        label=f"VRE upper bound: {max_vre_share:.1%}",
    )

    ax.axhline(
        max_curtailment,
        linestyle="--",
        linewidth=1.2,
        label=f"Curtailment upper bound: {max_curtailment:.1%}",
    )

    ax.set_title(f"{args.scenario} Pareto Front ({args.year})")
    ax.set_xlabel("Solar-wind penetration")
    ax.set_ylabel("Curtailment rate")
    ax.xaxis.set_major_formatter(PercentFormatter(1.0))
    ax.yaxis.set_major_formatter(PercentFormatter(1.0))
    ax.grid(True, alpha=0.25)
    ax.legend(loc="best")

    colorbar = fig.colorbar(scatter, ax=ax)
    colorbar.set_label("System cost (billion USD)")

    fig.tight_layout()
    fig.savefig(args.output, dpi=220)
    plt.close(fig)


if __name__ == "__main__":
    main()
```

## 9.5 注意：补充保存字段

上面的 Python 骨架依赖：

```matlab
preferred_base_load_ratio
```

因此，`convert_h5_to_sel.m` 保存 Sel.mat 时，还需要增加：

```matlab
preferred_base_load_ratio = base_load_ratio;
```

并写入：

```matlab
save(outfile, ..., 'preferred_base_load_ratio', ...);
```

---

## 10. 修改三个 `run_full_pipeline.sh`

每个情景目录的脚本都需要：

1. 创建绘图输出目录；
2. 每个年份完成 `convert_h5_to_sel` 后调用绘图；
3. 绘图失败时停止流水线。

## 10.1 增加 Python 与图像目录配置

在脚本开头增加：

```bash
PYTHON=${PYTHON:-python}
IMGDIR=$(pwd)/results/img
mkdir -p "$IMGDIR"
```

## 10.2 增加绘图函数

增加：

```bash
plot_pareto() {
    local scenario=$1
    local year=$2
    local h5file=$3
    local selfile=$4
    local outfile=$5

    echo "[$(date)] 正在绘制 Pareto 前沿：$scenario $year"

    $PYTHON ../plot_pareto_front.py \
      --scenario "$scenario" \
      --year "$year" \
      --h5 "$h5file" \
      --sel-mat "$selfile" \
      --output "$outfile"

    if [ $? -ne 0 ]; then
        echo "[$(date)] Pareto 前沿绘图失败：$scenario $year"
        return 1
    fi

    echo "[$(date)] Pareto 前沿已保存：$outfile"
}
```

## 10.3 在每次 `convert_h5_to_sel` 后调用绘图

### 2050

```bash
plot_pareto \
  "SSP1-2.6" \
  2050 \
  "results/Optimization_SC_2050_Res.h5" \
  "results/Opt_SC_2050_Sel.mat" \
  "results/img/pareto_front_2050.png"
```

### 2040

```bash
plot_pareto \
  "SSP1-2.6" \
  2040 \
  "results/Optimization_SC_2040_Res.h5" \
  "results/Opt_SC_2040_Sel.mat" \
  "results/img/pareto_front_2040.png"
```

### 2030

```bash
plot_pareto \
  "SSP1-2.6" \
  2030 \
  "results/Optimization_SA_2030_Res.h5" \
  "results/Opt_SA_2030_Sel.mat" \
  "results/img/pareto_front_2030.png"
```

在：

```text
Optimization_ssp245/run_full_pipeline.sh
Optimization_ssp560/run_full_pipeline.sh
```

中分别将情景名称改为：

```text
SSP2-4.5
SSP5-6.0
```

---

## 11. 运行顺序与父子阶段关系

三个情景流水线保持原有顺序：

```text
2050 优化
    ↓
2050 preferred solution 筛选
    ↓
2050 Pareto 前沿绘图
    ↓
2050 Sel.mat 保存
    ↓
2040 优化
    ↓
2040 preferred solution 筛选
    ↓
2040 Pareto 前沿绘图
    ↓
2040 Sel.mat 保存
    ↓
2030 优化
    ↓
2030 preferred solution 筛选
    ↓
2030 Pareto 前沿绘图
    ↓
2030 Sel.mat 保存
```

注意：

- 2040 的候选场址依赖 2050 的 preferred solution；
- 2030 的候选场址依赖 2040 的 preferred solution；
- 修改筛选逻辑后，必须从 2050 开始完整重跑；
- 不应复用旧的 2040 和 2030 H5 结果；
- 建议运行前清理旧输出。

清理命令：

```bash
rm -rf results
rm -rf logs
mkdir -p results/img
mkdir -p logs
```

---

## 12. 增加 MATLAB 单元测试

新增：

```text
utils/test_select_preferred_solution.m
```

## 12.1 测试 SSP1-2.6 / SSP2-4.5 模式

构造：

```matlab
prs = [
    0.10, 0.40, 100;  % vre = 1 - 0.20 - 0.40 = 0.40，低于下界
    0.14, 0.30, 120;  % vre = 0.50，合格
    0.12, 0.28, 130;  % vre = 0.52，合格但成本更高
    0.16, 0.25,  80;  % 弃电率超过 15%
    0.11, 0.05,  60;  % vre = 0.75，超过上界
];

result = select_preferred_solution( ...
    prs, ...
    0.20, ...
    0.45, ...
    0.60, ...
    0.15, ...
    'bounded_transition' ...
);

assert(result.sol_idx == 2);
```

验证：

- 低于下界的解被排除；
- 高于上界的解被排除；
- 弃电率超过 15% 的解被排除；
- 合格解中选择成本最低解。

## 12.2 测试 SSP5-6.0 模式

构造：

```matlab
prs = [
    0.10, 0.72, 100;  % vre = 0.08，合格
    0.14, 0.70,  80;  % vre = 0.10，合格且成本最低
    0.12, 0.65,  60;  % vre = 0.15，超过上限
    0.16, 0.73,  50;  % 弃电率超过 15%
];

result = select_preferred_solution( ...
    prs, ...
    0.18, ...
    NaN, ...
    0.12, ...
    0.15, ...
    'fossil_upper_bound' ...
);

assert(result.sol_idx == 2);
```

验证：

- 不要求风光渗透率达到下界；
- 超过第二高值上限的解被排除；
- 合格解中选择成本最低方案。

## 12.3 测试无合格解

构造全部违反约束的解，验证函数明确报错：

```matlab
try
    result = select_preferred_solution(...);
    error('测试失败：应当抛出异常');
catch ME
    assert(contains(ME.message, '不存在合格 preferred solution'));
end
```

---

## 13. 静态检查

完成修改后运行：

```bash
grep -RIn "round(n_solutions / 2)" \
  Optimization_ssp126 \
  Optimization_ssp245 \
  Optimization_ssp560
```

预期：

```text
无结果
```

检查三个配置目录是否均包含 15%：

```bash
grep -RIn "MAX_CURTAILMENT = 0.15" \
  Optimization_ssp126 \
  Optimization_ssp245 \
  Optimization_ssp560
```

预期：

```text
三个结果
```

检查绘图调用：

```bash
grep -RIn "plot_pareto_front.py" \
  Optimization_ssp126/run_full_pipeline.sh \
  Optimization_ssp245/run_full_pipeline.sh \
  Optimization_ssp560/run_full_pipeline.sh
```

---

## 14. 测试流程

## 14.1 MATLAB 单元测试

在仓库根目录运行：

```bash
/data6/yanxiaokai/MATLAB/R2024b/bin/matlab \
  -batch "addpath('utils'); test_select_preferred_solution"
```

要求：

```text
所有测试通过
```

## 14.2 Python 脚本语法检查

```bash
python -m py_compile plot_pareto_front.py
```

## 14.3 依赖检查

```bash
python - <<'PY'
import h5py
import matplotlib
import numpy
import scipy
print("plot dependencies OK")
PY
```

如需安装，默认使用阿里云镜像：

```bash
pip install -i https://mirrors.aliyun.com/pypi/simple \
  numpy h5py scipy matplotlib
```

## 14.4 SSP1-2.6 小规模流水线测试

```bash
cd Optimization_ssp126

rm -rf results logs
mkdir -p results/img logs

export POPULATION_SIZE=30
export MAX_GENERATIONS=3

bash run_full_pipeline.sh
```

说明：

- 小规模 NSGA-II 仅用于检查代码链路；
- 由于搜索不足，可能找不到满足约束的 preferred solution；
- 如果函数明确报错并打印诊断信息，说明失败保护机制工作正常；
- 正式判断方案是否存在，需要使用正式优化参数。

## 14.5 正式运行

注意！只正式运行`Optimization_ssp126`, 并且 2050年的优化已经完成，`Optimization_ssp126/results/Optimization_SC_2050_Res.h5`，因此2050年只需要运行筛选和绘图阶段。2040年和2030年需要完整运行优化、筛选和绘图阶段。

注意！只正式运行`Optimization_ssp126`, 并且 2050年的优化已经完成，`Optimization_ssp126/results/Optimization_SC_2050_Res.h5`，因此2050年只需要运行筛选和绘图阶段。2040年和2030年需要完整运行优化、筛选和绘图阶段。

注意！只正式运行`Optimization_ssp126`, 并且 2050年的优化已经完成，`Optimization_ssp126/results/Optimization_SC_2050_Res.h5`，因此2050年只需要运行筛选和绘图阶段。2040年和2030年需要完整运行优化、筛选和绘图阶段。


```bash
unset POPULATION_SIZE
unset MAX_GENERATIONS

cd Optimization_ssp126
bash run_full_pipeline.sh

# cd ../Optimization_ssp245
# bash run_full_pipeline.sh

# cd ../Optimization_ssp560
# bash run_full_pipeline.sh
```

---

## 15. 可视化验收标准


正式运行完成后，应存在 9 张图：

```text
Optimization_ssp126/results/img/pareto_front_2030.png
Optimization_ssp126/results/img/pareto_front_2040.png
Optimization_ssp126/results/img/pareto_front_2050.png

Optimization_ssp245/results/img/pareto_front_2030.png
Optimization_ssp245/results/img/pareto_front_2040.png
Optimization_ssp245/results/img/pareto_front_2050.png

Optimization_ssp560/results/img/pareto_front_2030.png
Optimization_ssp560/results/img/pareto_front_2040.png
Optimization_ssp560/results/img/pareto_front_2050.png
```

只需要验收 `Optimization_ssp126/results/img/pareto_front_2050.png` 即可！
只需要验收 `Optimization_ssp126/results/img/pareto_front_2050.png` 即可！
只需要验收 `Optimization_ssp126/results/img/pareto_front_2050.png` 即可！

每张图必须满足：

- [ ] 全部 Pareto 解均已绘制；
- [ ] x 轴为风光渗透率；
- [ ] y 轴为弃电率；
- [ ] 点颜色为成本；
- [ ] Preferred solution 被高亮；
- [ ] SSP1-2.6 和 SSP2-4.5 显示风光渗透率上下界；
- [ ] SSP5-6.0 显示风光渗透率上界；
- [ ] y 轴显示 15% 弃电率上限；
- [ ] 图像保存在对应 `results/img/` 下；
- [ ] 图标题包含 SSP 情景和年份。

---

## 16. 日志验收标准

每次 `convert_h5_to_sel.m` 应输出：

```text
情景名称
年份
筛选模式
基荷比例
弃电率上限
风光渗透率下界
风光渗透率上界
Pareto 解总数
满足弃电率上限的解数量
满足风光约束的解数量
同时满足全部约束的解数量
选中解编号
选中解弃电率
选中解风光渗透率
选中解灵活电源比例
选中解成本
```

SSP5-6.0 的日志中：

```text
风光渗透率下界
```

应明确打印为：

```text
未设置
```

---

## 17. 最终验收标准

- [ ] 三个 SSP 的 `optimization_config.m` 已增加正确筛选参数；
- [ ] 弃电率上限统一为 15%；
- [ ] SSP1-2.6 使用五模型均值作为下界、五模型最大值作为上界；
- [ ] SSP2-4.5 使用五模型均值作为下界、五模型最大值作为上界；
- [ ] SSP5-6.0 使用五模型第二高值作为上界，不设置积极转型下界；
- [ ] `convert_h5_to_sel.m` 不再选择中间编号；
- [ ] 新增 `utils/select_preferred_solution.m`；
- [ ] `Sel.mat` 保存 preferred solution 元数据；
- [ ] 新增 `plot_pareto_front.py`；
- [ ] 三套流水线均自动绘图；
- [ ] 9 张 Pareto 前沿图均生成；
- [ ] 无合格解时流水线明确停止；
- [ ] MATLAB 单元测试通过；
- [ ] Python 脚本语法检查通过；
- [ ] 静态检查通过。
