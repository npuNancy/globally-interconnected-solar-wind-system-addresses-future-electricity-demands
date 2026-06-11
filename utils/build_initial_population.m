function population = build_initial_population(greedy_sol, lb, ub, pop_size, ...
    scenario_cfg, nonlsol, nonlwin, CGrid_Index)
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
%   CGrid_Index  — 候选格网索引矩阵，第1列为区域编号
%
% 输出：
%   population   — pop_size × nvars 矩阵

    nvars = length(lb);
    n_grid = nonlsol + nonlwin;  % 场站选择变量数

    % 提取每个候选格网所属区域
    pv_regions = CGrid_Index(1:nonlsol, 1);
    wind_regions = CGrid_Index(nonlsol+1:nonlsol+nonlwin, 1);

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
    % 在同一区域、同一种技术类型内部：
    %   删除一个已选格网，增加一个未选格网
    % 保持区域内场站数量不变，只改变空间位置
    for i = 1:n_perturb
        sol = greedy_sol;

        % 随机选择 5%-15% 的场站进行扰动
        n_swap = randi([round(n_grid * 0.05), round(n_grid * 0.15)]);

        for j = 1:n_swap
            % 随机选择区域
            region = randi(20);

            % 50% 概率扰动光伏，50% 概率扰动风电
            if rand() < 0.5
                % 光伏候选格网
                region_grids = find(pv_regions == region);
            else
                % 风电候选格网
                region_grids = find(wind_regions == region);
                region_grids = region_grids + nonlsol;
            end

            selected_grids = ...
                region_grids(sol(region_grids) == 1);
            unselected_grids = ...
                region_grids(sol(region_grids) == 0);

            if ~isempty(selected_grids) ...
                    && ~isempty(unselected_grids)
                g_selected = ...
                    selected_grids(randi(length(selected_grids)));
                g_unselected = ...
                    unselected_grids(randi(length(unselected_grids)));
                sol(g_selected) = 0;
                sol(g_unselected) = 1;
            end
        end

        % 储能和输电保持贪心解的值
        population(idx, :) = sol;
        idx = idx + 1;
    end

    %% 3. 定向增删解（30%）
    % 定向增删场站仅用于构造候选初始个体。
    %
    % 最终是否满足约束，由 nonlcon*.m 调用完整调度判断：
    %   VRE 渗透率 = 实际风光发电量 / 总发电量
    %   弃电率 = 弃电量 / 调度前原始风光发电量
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
