%% test_build_initial_population_region_swap — 区域扰动修复单元测试
%
% 验证 build_initial_population 的区域扰动逻辑：
%   1. 区域编号来自 CGrid_Index，而非 sol 值
%   2. 每次扰动后，同一区域同一技术类型的选中数量不变
%   3. 扰动只发生在同一区域、同一技术类型内部
%   4. 扰动后布局确实发生变化
%   5. 所有场站状态仍为 0/1

function tests = test_build_initial_population_region_swap
    tests = functiontests(localfunctions);
end

function setup(testCase)
    rng(42);
end

function teardown(testCase)
end

%% ---- 辅助函数：构造测试数据 ----
function [greedy_sol, lb, ub, scenario_cfg, CGrid_Index, nonlsol, nonlwin] = ...
    build_test_data(~)
    % 构造小型测试数据：
    %   区域 1：4 个光伏 + 4 个风电
    %   区域 2：4 个光伏 + 4 个风电
    %   储能：20 个区域 × 2（功率+时长）= 40
    %   输电：2 条线路

    nonlsol = 8;   % 8 个光伏候选格网
    nonlwin = 8;   % 8 个风电候选格网
    n_grid = nonlsol + nonlwin;
    n_storage = 40;  % 20 区域 × 2
    n_trans = 2;
    nvars = n_grid + n_storage + n_trans;

    % CGrid_Index：第1列 = 区域编号
    % 光伏：区域1(格网1-4)、区域2(格网5-8)
    % 风电：区域1(格网1-4)、区域2(格网5-8)
    CGrid_Index = zeros(nonlsol + nonlwin, 2);
    CGrid_Index(1:4, 1) = 1;   % 光伏 区域1
    CGrid_Index(5:8, 1) = 2;   % 光伏 区域2
    CGrid_Index(9:12, 1) = 1;  % 风电 区域1
    CGrid_Index(13:16, 1) = 2; % 风电 区域2

    % 贪心解：每个区域每种类型选 2 个
    greedy_sol = zeros(1, nvars);
    greedy_sol(1) = 1;  % 光伏区域1-格网1
    greedy_sol(2) = 1;  % 光伏区域1-格网2
    greedy_sol(5) = 1;  % 光伏区域2-格网5
    greedy_sol(6) = 1;  % 光伏区域2-格网6
    greedy_sol(9) = 1;  % 风电区域1-格网1
    greedy_sol(10) = 1; % 风电区域1-格网2
    greedy_sol(13) = 1; % 风电区域2-格网5
    greedy_sol(14) = 1; % 风电区域2-格网6

    % 储能和输电给非零值
    greedy_sol(n_grid+1:n_grid+n_storage) = 0.5;
    greedy_sol(n_grid+n_storage+1:end) = 0.3;

    % 上下界
    lb = zeros(1, nvars);
    ub = ones(1, nvars);
    lb(n_grid+1:n_grid+n_storage) = 0.1;
    ub(n_grid+1:n_grid+n_storage) = 1.0;
    lb(n_grid+n_storage+1:end) = 0.1;
    ub(n_grid+n_storage+1:end) = 1.0;

    % 情景配置
    scenario_cfg.min_vre_share = 0.5;
    scenario_cfg.max_vre_share = 0.9;
end

%% ---- 测试 1：区域内数量保持不变 ----
function test_region_count_preserved(testCase)
    [greedy_sol, lb, ub, scenario_cfg, CGrid_Index, nonlsol, nonlwin] = ...
        build_test_data();

    pv_regions = CGrid_Index(1:nonlsol, 1)';
    wind_regions = CGrid_Index(nonlsol+1:nonlsol+nonlwin, 1)';
    n_grid = nonlsol + nonlwin;

    pop_size = 200;
    population = build_initial_population(greedy_sol, lb, ub, ...
        pop_size, scenario_cfg, nonlsol, nonlwin, CGrid_Index);

    n_greedy = max(1, round(pop_size * 0.01));
    n_perturb = round(pop_size * 0.50);

    % 检查扰动解（跳过贪心解）
    for i = (n_greedy+1):(n_greedy+n_perturb)
        sol = population(i, :);
        for region = 1:2
            % 光伏区域数量不变
            pv_mask = (pv_regions == region);
            greedy_pv_count = sum(greedy_sol(1:nonlsol) .* pv_mask);
            sol_pv_count = sum(sol(1:nonlsol) .* pv_mask);
            verifyEqual(testCase, sol_pv_count, greedy_pv_count, ...
                sprintf('光伏区域 %d 数量变化: 期望 %d, 实际 %d (个体 %d)', ...
                region, greedy_pv_count, sol_pv_count, i));

            % 风电区域数量不变
            wind_mask = (wind_regions == region);
            greedy_wind_count = sum(greedy_sol(nonlsol+1:nonlsol+nonlwin) .* wind_mask);
            sol_wind_count = sum(sol(nonlsol+1:nonlsol+nonlwin) .* wind_mask);
            verifyEqual(testCase, sol_wind_count, greedy_wind_count, ...
                sprintf('风电区域 %d 数量变化: 期望 %d, 实际 %d (个体 %d)', ...
                region, greedy_wind_count, sol_wind_count, i));
        end
    end
end

%% ---- 测试 2：场站状态仍为 0/1 ----
function test_binary_states_valid(testCase)
    [greedy_sol, lb, ub, scenario_cfg, CGrid_Index, nonlsol, nonlwin] = ...
        build_test_data();

    pop_size = 200;
    population = build_initial_population(greedy_sol, lb, ub, ...
        pop_size, scenario_cfg, nonlsol, nonlwin, CGrid_Index);

    n_grid = nonlsol + nonlwin;

    % 所有场站选择变量必须为 0 或 1
    grid_values = population(:, 1:n_grid);
    verifyTrue(testCase, all(grid_values(:) == 0 | grid_values(:) == 1, 'all'), ...
        '存在非 0/1 的场站状态');
end

%% ---- 测试 3：扰动后布局确实发生变化 ----
function test_layout_changes(testCase)
    [greedy_sol, lb, ub, scenario_cfg, CGrid_Index, nonlsol, nonlwin] = ...
        build_test_data();

    pop_size = 200;
    population = build_initial_population(greedy_sol, lb, ub, ...
        pop_size, scenario_cfg, nonlsol, nonlwin, CGrid_Index);

    n_grid = nonlsol + nonlwin;

    n_greedy = max(1, round(pop_size * 0.01));
    n_perturb = round(pop_size * 0.50);

    changed_count = sum(population(n_greedy+1:n_greedy+n_perturb, 1:n_grid) ...
        ~= greedy_sol(1:n_grid), 2);

    % 至少有一个扰动解与贪心解不同
    verifyTrue(testCase, any(changed_count > 0), ...
        '所有扰动解与贪心解完全相同，扰动未生效');
end

%% ---- 测试 4：扰动只发生在同一区域同一技术类型内部 ----
function test_swap_within_same_region_and_type(testCase)
    [greedy_sol, lb, ub, scenario_cfg, CGrid_Index, nonlsol, nonlwin] = ...
        build_test_data();

    pv_regions = CGrid_Index(1:nonlsol, 1)';
    wind_regions = CGrid_Index(nonlsol+1:nonlsol+nonlwin, 1)';
    n_grid = nonlsol + nonlwin;

    pop_size = 200;
    population = build_initial_population(greedy_sol, lb, ub, ...
        pop_size, scenario_cfg, nonlsol, nonlwin, CGrid_Index);

    n_greedy = max(1, round(pop_size * 0.01));
    n_perturb = round(pop_size * 0.50);

    % 对比每个扰动解与贪心解的差异
    for i = (n_greedy+1):(n_greedy+n_perturb)
        sol = population(i, :);
        diff_mask = (sol(1:n_grid) ~= greedy_sol(1:n_grid));

        if any(diff_mask)
            % 找到所有变化的格网
            changed_indices = find(diff_mask);

            for k = 1:numel(changed_indices)
                idx = changed_indices(k);
                if idx <= nonlsol
                    % 光伏格网：检查该格网变到 1 时是否有同区域格网变到 0（或反之）
                    region = pv_regions(idx);
                    % 同区域光伏格网的变化
                    same_region_pv = find(pv_regions == region);
                    region_diff = diff_mask(same_region_pv);
                    % 同区域内光伏格网的变化必须成对出现（有增有减）
                    verifyTrue(testCase, sum(region_diff) >= 2, ...
                        sprintf('个体 %d: 光伏格网 %d (区域 %d) 变化但同区域无成对交换', ...
                        i, idx, region));
                else
                    % 风电格网
                    wind_idx = idx - nonlsol;
                    region = wind_regions(wind_idx);
                    same_region_wind = find(wind_regions == region);
                    region_diff = diff_mask(same_region_wind + nonlsol);
                    verifyTrue(testCase, sum(region_diff) >= 2, ...
                        sprintf('个体 %d: 风电格网 %d (区域 %d) 变化但同区域无成对交换', ...
                        i, idx, region));
                end
            end
        end
    end
end

%% ---- 测试 5：储能和输电变量不被扰动改变 ----
function test_storage_transmission_unchanged(testCase)
    [greedy_sol, lb, ub, scenario_cfg, CGrid_Index, nonlsol, nonlwin] = ...
        build_test_data();

    n_grid = nonlsol + nonlwin;

    pop_size = 200;
    population = build_initial_population(greedy_sol, lb, ub, ...
        pop_size, scenario_cfg, nonlsol, nonlwin, CGrid_Index);

    n_greedy = max(1, round(pop_size * 0.01));
    n_perturb = round(pop_size * 0.50);

    % 扰动解的储能和输电应与贪心解一致
    for i = (n_greedy+1):(n_greedy+n_perturb)
        verifyEqual(testCase, ...
            population(i, n_grid+1:end), ...
            greedy_sol(n_grid+1:end), ...
            sprintf('个体 %d 的储能或输电变量被意外修改', i));
    end
end
