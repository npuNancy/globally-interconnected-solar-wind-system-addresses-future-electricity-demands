function population = build_initial_population(greedy_sol, lb, ub, pop_size, ...
    scenario_cfg, nonlsol, nonlwin)
% BUILD_INITIAL_POPULATION — 构造初始种群矩阵
%
% 种群组成：
%   - 至少 1 个贪心可行解
%   - 50% 贪心解附近的小扰动解
%   - 30% 根据 VRE 上下界定向增删场站的解
%   - 20% 完全随机解
%
% 输入：
%   greedy_sol   — 贪心初始解向量
%   lb, ub       — 变量下界和上界
%   pop_size     — 种群大小
%   scenario_cfg — 情景配置
%   nonlsol      — 光伏候选格网数量
%   nonlwin      — 风电候选格网数量
%
% 输出：
%   population   — pop_size × nvars 矩阵

    nvars = length(lb);
    n_grid = nonlsol + nonlwin;  % 场站选择变量数

    % 计算各类解的数量
    n_greedy = max(1, round(pop_size * 0.01));  % 至少 1 个
    n_perturb = round(pop_size * 0.50);
    n_directed = round(pop_size * 0.30);
    n_random = pop_size - n_greedy - n_perturb - n_directed;

    population = zeros(pop_size, nvars);
    idx = 1;

    %% 1. 贪心可行解（至少 1 个）
    for i = 1:n_greedy
        population(idx, :) = greedy_sol;
        idx = idx + 1;
    end

    %% 2. 小扰动解（50%）
    % 在同一区域内交换格网，避免破坏装机约束
    for i = 1:n_perturb
        sol = greedy_sol;

        % 随机选择 5-15% 的场站进行扰动
        n_swap = randi([round(n_grid * 0.05), round(n_grid * 0.15)]);

        for j = 1:n_swap
            % 随机选择一个区域
            region = randi(20);

            % 在该区域内随机交换一个场站
            % 优先选择同类型（光伏或风电）
            if rand() < 0.5
                % 光伏
                region_grids = find(sol(1:nonlsol) == region | ...
                    (sol(1:nonlsol) == 0 & region == 1));  % 简化：只考虑区域1
            else
                % 风电
                region_grids = find(sol(nonlsol+1:nonlsol+nonlwin) == region);
                if ~isempty(region_grids)
                    region_grids = region_grids + nonlsol;
                end
            end

            if ~isempty(region_grids) && length(region_grids) > 1
                % 随机选择两个格网交换状态
                swap_idx = randperm(length(region_grids), 2);
                g1 = region_grids(swap_idx(1));
                g2 = region_grids(swap_idx(2));
                sol(g1) = 1 - sol(g1);
                sol(g2) = 1 - sol(g2);
            end
        end

        % 储能和输电保持贪心解的值（避免破坏约束）
        population(idx, :) = sol;
        idx = idx + 1;
    end

    %% 3. 定向增删解（30%）
    % 根据 VRE 上下界定向调整场站数量
    min_vre = scenario_cfg.min_vre_share;
    max_vre = scenario_cfg.max_vre_share;

    for i = 1:n_directed
        sol = greedy_sol;

        if isnan(min_vre)
            % SSP5-6.0：只有上界，主要执行删减
            % 随机删除 10-30% 的选中场站
            selected = find(sol(1:n_grid) == 1);
            n_remove = randi([round(length(selected) * 0.10), ...
                              round(length(selected) * 0.30)]);
            if n_remove > 0 && n_remove < length(selected)
                remove_idx = randperm(length(selected), n_remove);
                sol(selected(remove_idx)) = 0;
            end
        else
            % SSP1-2.6 或 SSP2-4.5：有下界
            % 50% 概率增加场站，50% 概率在保持可行的前提下减少
            if rand() < 0.5
                % 增加：随机加入 5-20% 的未选中场站
                unselected = find(sol(1:n_grid) == 0);
                n_add = randi([round(length(unselected) * 0.05), ...
                               round(length(unselected) * 0.20)]);
                if n_add > 0 && n_add < length(unselected)
                    add_idx = randperm(length(unselected), n_add);
                    sol(unselected(add_idx)) = 1;
                end
            else
                % 减少：随机删除 5-15% 的选中场站
                selected = find(sol(1:n_grid) == 1);
                n_remove = randi([round(length(selected) * 0.05), ...
                                  round(length(selected) * 0.15)]);
                if n_remove > 0 && n_remove < length(selected)
                    remove_idx = randperm(length(selected), n_remove);
                    sol(selected(remove_idx)) = 0;
                end
            end
        end

        % 储能和输电保持不变
        population(idx, :) = sol;
        idx = idx + 1;
    end

    %% 4. 完全随机解（20%）
    for i = 1:n_random
        sol = zeros(1, nvars);

        % 场站选择：随机 0/1
        sol(1:n_grid) = randi([0, 1], 1, n_grid);

        % 储能功率：在下界和上界之间随机
        sol(n_grid+1:n_grid+20) = lb(n_grid+1:n_grid+20) + ...
            rand(1, 20) .* (ub(n_grid+1:n_grid+20) - lb(n_grid+1:n_grid+20));

        % 储能时长：在下界和上界之间随机
        sol(n_grid+21:n_grid+40) = lb(n_grid+21:n_grid+40) + ...
            rand(1, 20) .* (ub(n_grid+21:n_grid+40) - lb(n_grid+21:n_grid+40));

        % 输电容量：在下界和上界之间随机
        if nvars > n_grid + 40
            sol(n_grid+41:end) = lb(n_grid+41:end) + ...
                rand(1, nvars-n_grid-40) .* (ub(n_grid+41:end) - lb(n_grid+41:end));
        end

        % 确保整数变量取整
        sol(1:n_grid+40) = round(sol(1:n_grid+40));

        population(idx, :) = sol;
        idx = idx + 1;
    end

    fprintf('初始种群构造完成：%d 个个体（贪心 %d，扰动 %d，定向 %d，随机 %d）\n', ...
        pop_size, n_greedy, n_perturb, n_directed, n_random);
end
