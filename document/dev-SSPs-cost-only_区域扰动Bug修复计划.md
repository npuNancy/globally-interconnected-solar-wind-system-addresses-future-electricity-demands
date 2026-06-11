# `dev-SSPs-cost-only`：区域扰动 Bug 修复计划

## 0. 目标

本计划只处理：

```text
utils/build_initial_population.m
```

中的“区域扰动”逻辑。

区域扰动用于构造 GA 初始种群中的“小扰动解”：

```text
以贪心初始解为基础，
在同一区域、同一种技术类型内部，
替换少量场站格网，
生成空间布局略有差异的候选解。
```

本轮不修改：

```text
弃电率约束
VRE 渗透率定义
成本函数
整数约束
GA 种群比例
贪心初始解逻辑
储能与输电扰动逻辑
```

---

# 1. 区域扰动是什么？

当前初始种群包含：

```text
贪心解
小扰动解
定向增删解
完全随机解
```

其中，“小扰动解”的目标是：

```text
保留贪心解的大体规模
+
在局部替换少量格网
+
增加初始种群空间多样性
```

正确的区域扰动应满足：

```text
同一区域
同一种技术类型
删除一个已选场站
增加一个未选场站
区域内选中场站数量不变
```

例如，区域 1 中有 5 个光伏格网：

| 格网 | 原始状态 |
|---|---:|
| A | 1 |
| B | 1 |
| C | 0 |
| D | 0 |
| E | 0 |

扰动前选中：

```text
A、B
```

扰动后可以替换为：

```text
B、C
```

区域 1 的光伏选中数量仍然为：

```text
2
```

但空间位置发生变化。

---

# 2. 当前代码中的 Bug

文件：

```text
utils/build_initial_population.m
```

当前函数接口：

```matlab
function population = build_initial_population( ...
    greedy_sol, lb, ub, pop_size, ...
    scenario_cfg, nonlsol, nonlwin)
```

当前光伏扰动：

```matlab
region_grids = find(sol(1:nonlsol) == region | ...
    (sol(1:nonlsol) == 0 & region == 1));
```

当前风电扰动：

```matlab
region_grids = ...
    find(sol(nonlsol+1:nonlsol+nonlwin) == region);
```

问题是：

```text
sol(...)
```

表示：

```text
0 / 1 场站选择状态
```

不是区域编号。

因此：

```matlab
sol(...) == region
```

不能正确筛选区域。

正确的区域编号来自：

```text
CGrid_Index(:, 1)
```

---

# 3. 当前“交换”逻辑也需要修复

当前代码：

```matlab
swap_idx = randperm(length(region_grids), 2);

g1 = region_grids(swap_idx(1));
g2 = region_grids(swap_idx(2));

sol(g1) = 1 - sol(g1);
sol(g2) = 1 - sol(g2);
```

这实际上是：

```text
同时翻转两个格网状态
```

不是真正的场站替换。

如果两个格网状态分别为：

```text
1, 0
```

翻转后：

```text
0, 1
```

效果等价于交换。

但如果两个格网状态相同：

```text
1, 1
```

翻转后会变成：

```text
0, 0
```

区域内场站数量减少 2 个。

如果两个格网状态为：

```text
0, 0
```

翻转后会变成：

```text
1, 1
```

区域内场站数量增加 2 个。

这会破坏区域内装机结构，也可能破坏既有装机约束。

正确逻辑应当显式选择：

```text
一个已选格网
一个未选格网
```

然后执行：

```text
已选格网：1 → 0
未选格网：0 → 1
```

---

# 4. 修改方案

## 4.1 修改函数接口

修改：

```text
utils/build_initial_population.m
```

将：

```matlab
function population = build_initial_population( ...
    greedy_sol, lb, ub, pop_size, ...
    scenario_cfg, nonlsol, nonlwin)
```

改为：

```matlab
function population = build_initial_population( ...
    greedy_sol, lb, ub, pop_size, ...
    scenario_cfg, nonlsol, nonlwin, ...
    CGrid_Index)
```

新增输入：

```text
CGrid_Index
```

用于获取每个候选格网所属区域。

---

## 4.2 提前提取区域索引

在函数开头增加：

```matlab
pv_regions = ...
    CGrid_Index(1:nonlsol, 1);

wind_regions = ...
    CGrid_Index( ...
        nonlsol+1 : nonlsol+nonlwin, ...
        1);
```

说明：

```text
pv_regions
```

长度为：

```text
nonlsol
```

保存全部光伏候选格网所属区域。

```text
wind_regions
```

长度为：

```text
nonlwin
```

保存全部风电候选格网所属区域。

---

## 4.3 修复光伏区域扰动

删除：

```matlab
region_grids = find(sol(1:nonlsol) == region | ...
    (sol(1:nonlsol) == 0 & region == 1));
```

改为：

```matlab
region_grids = ...
    find(pv_regions == region);
```

然后分别筛选：

```matlab
selected_grids = ...
    region_grids( ...
        sol(region_grids) == 1);

unselected_grids = ...
    region_grids( ...
        sol(region_grids) == 0);
```

若同时存在已选和未选格网：

```matlab
if ~isempty(selected_grids) ...
        && ~isempty(unselected_grids)

    g_selected = ...
        selected_grids( ...
            randi(length(selected_grids)));

    g_unselected = ...
        unselected_grids( ...
            randi(length(unselected_grids)));

    sol(g_selected) = 0;
    sol(g_unselected) = 1;
end
```

---

## 4.4 修复风电区域扰动

删除：

```matlab
region_grids = ...
    find(sol(nonlsol+1:nonlsol+nonlwin) == region);

if ~isempty(region_grids)
    region_grids = ...
        region_grids ...
        + nonlsol;
end
```

改为：

```matlab
region_grids = ...
    find(wind_regions == region);

region_grids = ...
    region_grids ...
    + nonlsol;
```

然后与光伏逻辑一致：

```matlab
selected_grids = ...
    region_grids( ...
        sol(region_grids) == 1);

unselected_grids = ...
    region_grids( ...
        sol(region_grids) == 0);

if ~isempty(selected_grids) ...
        && ~isempty(unselected_grids)

    g_selected = ...
        selected_grids( ...
            randi(length(selected_grids)));

    g_unselected = ...
        unselected_grids( ...
            randi(length(unselected_grids)));

    sol(g_selected) = 0;
    sol(g_unselected) = 1;
end
```

---

## 4.5 建议替换后的完整扰动代码

将原来的“小扰动解”章节替换为：

```matlab
%% 2. 小扰动解（50%）
% 在同一区域、同一种技术类型内部：
%   删除一个已选格网
%   增加一个未选格网
%
% 目的：
%   保持区域内场站数量不变，
%   只改变空间位置，
%   避免明显破坏区域装机约束。

for i = 1:n_perturb
    sol = greedy_sol;

    % 随机选择 5%-15% 的场站进行扰动
    n_swap = randi([ ...
        round(n_grid * 0.05), ...
        round(n_grid * 0.15) ...
    ]);

    for j = 1:n_swap
        % 随机选择区域
        region = randi(20);

        % 50% 概率扰动光伏，50% 概率扰动风电
        if rand() < 0.5
            % 光伏候选格网
            region_grids = ...
                find(pv_regions == region);
        else
            % 风电候选格网
            region_grids = ...
                find(wind_regions == region);

            region_grids = ...
                region_grids ...
                + nonlsol;
        end

        selected_grids = ...
            region_grids( ...
                sol(region_grids) == 1);

        unselected_grids = ...
            region_grids( ...
                sol(region_grids) == 0);

        if ~isempty(selected_grids) ...
                && ~isempty(unselected_grids)

            g_selected = ...
                selected_grids( ...
                    randi(length(selected_grids)));

            g_unselected = ...
                unselected_grids( ...
                    randi(length(unselected_grids)));

            sol(g_selected) = 0;
            sol(g_unselected) = 1;
        end
    end

    % 储能和输电保持贪心解的值
    population(idx, :) = sol;
    idx = idx + 1;
end
```

---

# 5. 修改 9 个优化主脚本调用

需要修改：

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

将：

```matlab
initial_population = build_initial_population( ...
    greedy_sol, lb, ub, ...
    POPULATION_SIZE, ...
    scenario_cfg, ...
    nonlsol, ...
    nonlwin);
```

改为：

```matlab
initial_population = build_initial_population( ...
    greedy_sol, lb, ub, ...
    POPULATION_SIZE, ...
    scenario_cfg, ...
    nonlsol, ...
    nonlwin, ...
    CGrid_Index);
```

---

# 6. 文件修改清单

## 必须修改

```text
utils/build_initial_population.m
```

## 必须同步修改调用位置

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

---

# 7. 测试计划

## 7.1 新增单元测试

新增：

```text
utils/test_build_initial_population_region_swap.m
```

人工构造：

```text
区域 1：4 个光伏格网
区域 2：4 个光伏格网
区域 1：4 个风电格网
区域 2：4 个风电格网
```

每个区域内同时存在：

```text
已选格网
未选格网
```

---

## 7.2 检查区域内数量保持不变

对于每一个扰动解，检查：

```text
每个区域的光伏选中数量
每个区域的风电选中数量
```

必须与贪心解一致。

示例：

```matlab
for region = 1:20
    pv_mask = ...
        pv_regions == region;

    wind_mask = ...
        wind_regions == region;

    assert( ...
        sum(sol(1:nonlsol) .* pv_mask) ...
        == ...
        sum(greedy_sol(1:nonlsol) .* pv_mask) ...
    );

    assert( ...
        sum(sol(nonlsol+1:nonlsol+nonlwin) .* wind_mask) ...
        == ...
        sum(greedy_sol(nonlsol+1:nonlsol+nonlwin) .* wind_mask) ...
    );
end
```

---

## 7.3 检查扰动只发生在同一区域

对于每次交换，记录：

```text
技术类型
区域编号
被删除格网
被新增格网
```

检查：

```text
被删除格网和被新增格网：
属于同一区域
属于同一技术类型
```

---

## 7.4 检查布局确实发生变化

至少部分扰动解应满足：

```text
扰动解 != 贪心解
```

可以检查：

```matlab
changed_count = ...
    sum(population(:, 1:n_grid) ...
        ~= greedy_sol(1:n_grid), ...
        2);

assert(any(changed_count > 0));
```

---

## 7.5 检查 0 / 1 状态合法

检查：

```matlab
assert(all( ...
    population(:, 1:n_grid) == 0 ...
    | population(:, 1:n_grid) == 1, ...
    'all'));
```

---

# 8. 验收标准

完成后必须满足：

1. 区域编号来自：

```text
CGrid_Index(:, 1)
```

2. 不再使用：

```matlab
sol(...) == region
```

判断区域。

3. 光伏只与同一区域的光伏格网交换。

4. 风电只与同一区域的风电格网交换。

5. 每次扰动显式选择：

```text
一个已选格网
一个未选格网
```

6. 每次扰动后：

```text
同一区域
同一种技术类型
选中场站数量不变
```

7. 不再使用：

```matlab
sol(g1) = 1 - sol(g1);
sol(g2) = 1 - sol(g2);
```

作为区域交换。

8. 9 个优化主脚本均将：

```text
CGrid_Index
```

传入：

```text
build_initial_population(...)
```

9. 单元测试能够验证：

```text
区域内数量保持不变
技术类型保持不变
扰动后布局确实发生变化
所有场站状态仍为 0 / 1
```

---

# 9. 最终效果

修复后，区域扰动会实现：

```text
在不明显破坏既有装机结构的前提下，
对场站空间位置做局部替换，
为 GA 提供更多可探索的初始布局。
```

它只影响：

```text
GA 从哪些初始候选布局开始搜索
```

不会直接改变：

```text
VRE 渗透率定义
弃电率公式
成本函数
储能约束
输电约束
```
