function [init_sol, init_metrics, status_msg] = build_greedy_initial_solution(...
    ins_cap, gens, loads, CGrid_Index, lb, ub, ...
    cost_cfg, scenario_cfg, nonlsol, nonlwin, persistent_data)
% BUILD_GREEDY_INITIAL_SOLUTION — 构造贪心可行初始解
%
% 策略：
%   1. 场站变量全部初始化为 0
%   2. 储能功率、储能时长、输电容量取下界
%   3. 对 20 个区域分别处理光伏最低装机要求
%   4. 对 20 个区域分别处理风电最低装机要求
%   5. 在每个区域内，按 annual_generation_twh / annualized_capex 排序
%   6. SSP1-2.6 和 SSP2-4.5：继续加入场站直到 vre_share >= MIN_VRE_SHARE
%   7. SSP5-6.0：检查最低装机是否已超过 MAX_VRE_SHARE
%
% 输入：
%   ins_cap          — 候选格网装机容量向量（TWp）
%   gens             — 候选格网发电时序矩阵（TWh, 8760h）
%   loads            — 20区域负荷时序矩阵（TW, 8760h）
%   CGrid_Index      — 候选格网区域索引矩阵 [区域编号, 选中状态, 陆海标记]
%   lb, ub           — 变量下界和上界
%   cost_cfg         — 成本模型配置
%   scenario_cfg     — 情景配置
%   nonlsol          — 光伏候选格网数量
%   nonlwin          — 风电候选格网数量
%   persistent_data  — 包含 cur_solar, cur_wind, nonlcon_sel, nonlcon_ins
%
% 输出：
%   init_sol    — 初始解向量
%   init_metrics— 初始解的调度指标（如果可行）
%   status_msg  — 状态消息

    nvars = length(lb);
    init_sol = lb(:)';  % 从下界开始

    % 场站变量全部初始化为 0（已在 lb 中）
    % init_sol(1:nonlsol+nonlwin) = 0;  % 默认就是 0

    status_msg = '贪心初始解构造成功';

    nonlcon_sel = persistent_data.nonlcon_sel;
    nonlcon_ins = persistent_data.nonlcon_ins;
    cur_solar   = persistent_data.cur_solar;
    cur_wind    = persistent_data.cur_wind;

    %% ======== 1. 满足光伏既有装机约束 ========
    for region = 1:20
        % 找到该区域的光伏格网
        idx = find(nonlcon_sel(1:nonlsol) == region);
        if isempty(idx), continue; end

        % 计算每个格网的年发电量
        annual_gen = sum(gens(idx, :), 2) * 1000;  % TWh → GWh

        % 简化的成本效率指标（越高越好）
        % 使用 ins_cap 作为代理，因为成本与容量正相关
        cap = nonlcon_ins(idx) * 1e6;  % TWp → MWp

        % 成本效率 = 年发电量 / 容量（相当于容量因子）
        efficiency = annual_gen ./ max(cap, 1);

        % 按效率降序排序
        [~, sort_idx] = sort(efficiency, 'descend');

        % 逐步加入格网直到满足约束
        current_cap = 0;
        target_cap = cur_solar(region);

        for i = 1:length(sort_idx)
            if current_cap >= target_cap
                break;
            end
            grid_idx = idx(sort_idx(i));
            init_sol(grid_idx) = 1;
            current_cap = current_cap + nonlcon_ins(grid_idx);
        end
    end

    %% ======== 2. 满足风电既有装机约束 ========
    for region = 1:20
        % 找到该区域的风电格网
        idx = find(nonlcon_sel(nonlsol+1:nonlsol+nonlwin) == region);
        if isempty(idx), continue; end

        % 计算每个格网的年发电量
        annual_gen = sum(gens(nonlsol+idx, :), 2) * 1000;  % TWh → GWh

        % 容量
        cap = nonlcon_ins(nonlsol+idx) * 1e6;  % TWp → MWp

        % 成本效率
        efficiency = annual_gen ./ max(cap, 1);

        % 按效率降序排序
        [~, sort_idx] = sort(efficiency, 'descend');

        % 逐步加入格网直到满足约束
        current_cap = 0;
        target_cap = cur_wind(region);

        for i = 1:length(sort_idx)
            if current_cap >= target_cap
                break;
            end
            grid_idx = nonlsol + idx(sort_idx(i));
            init_sol(grid_idx) = 1;
            current_cap = current_cap + nonlcon_ins(grid_idx);
        end
    end

    %% ======== 3. 评估当前 VRE 渗透率（使用近似值，快速） ========
    % 仅用于快速估计场站超配程度。不属于严格定义的 VRE 渗透率。
    % 不得直接用于判断最终 VRE 上下界。
    total_load = sum(loads(:));
    selected_grids = find(init_sol(1:nonlsol+nonlwin) == 1);
    approx_gross_vre_to_load_ratio = sum(gens(selected_grids, :), 'all') / total_load;

    min_vre = scenario_cfg.min_vre_share;
    max_vre = scenario_cfg.max_vre_share;

    fprintf('贪心初始解：满足装机约束后 近似 gross_vre/load = %.4f（已选中 %d 个场站）\n', ...
        approx_gross_vre_to_load_ratio, length(selected_grids));

    %% ======== 4. 根据情景处理 VRE 约束 ========
    if isnan(min_vre)
        % SSP5-6.0：只有上界，检查是否已超过
        if approx_gross_vre_to_load_ratio > max_vre + 1e-6
            status_msg = sprintf('警告：当前既有装机约束下最低 gross_vre/load ≈ %.4f，已超过 SSP5-6.0 上界 %.4f。继续运行 GA 没有意义，请检查约束可行性。', ...
                approx_gross_vre_to_load_ratio, max_vre);
            fprintf('%s\n', status_msg);
        else
            fprintf('SSP5-6.0：最低 gross_vre/load ≈ %.4f 满足上界 %.4f，使用当前解。\n', ...
                approx_gross_vre_to_load_ratio, max_vre);
        end
    else
        % SSP1-2.6 或 SSP2-4.5：有下界，需要继续加入场站
        if approx_gross_vre_to_load_ratio < min_vre - 1e-6
            fprintf('继续加入场站以达到 VRE 下界 %.4f ...\n', min_vre);

            % 收集所有未选中的场站
            all_grids = find(init_sol(1:nonlsol+nonlwin) == 0);

            % 计算成本效率（年发电量 / 容量）
            annual_gen_all = sum(gens(all_grids, :), 2);
            cap_all = ins_cap(all_grids) * 1e6;  % TWp → MWp
            efficiency_all = annual_gen_all ./ max(cap_all, 1);

            [~, sort_idx] = sort(efficiency_all, 'descend');

            % 维护已选中格网的发电总量，用于快速更新近似比例
            running_gen = sum(gens(selected_grids, :), 'all');

            % 逐步加入（使用近似比例，不做完整调度模拟）
            for i = 1:length(sort_idx)
                if approx_gross_vre_to_load_ratio >= min_vre - 1e-6
                    break;
                end

                grid_idx = all_grids(sort_idx(i));
                init_sol(grid_idx) = 1;
                running_gen = running_gen + sum(gens(grid_idx, :));
                approx_gross_vre_to_load_ratio = running_gen / total_load;

                if mod(i, 500) == 0
                    fprintf('  已加入 %d 个场站，近似 gross_vre/load = %.4f\n', i, approx_gross_vre_to_load_ratio);
                end
            end

            if approx_gross_vre_to_load_ratio >= min_vre - 1e-6
                fprintf('✓ 达到 VRE 下界 %.4f（近似 gross_vre/load = %.4f，共加入 %d 个额外场站）\n', ...
                    min_vre, approx_gross_vre_to_load_ratio, min(i, length(sort_idx)));
            else
                status_msg = sprintf('警告：已加入所有可行场站，近似 gross_vre/load 仍为 %.4f，未达到下界 %.4f', ...
                    approx_gross_vre_to_load_ratio, min_vre);
                fprintf('%s\n', status_msg);
            end

            %% ======== 4.1 迭代校正：用完整调度评估实际 VRE ========
            max_iterations = 5;
            for iter = 1:max_iterations
                fprintf('迭代校正 %d/%d：执行完整调度评估...\n', iter, max_iterations);
                temp_metrics = evaluate_dispatch_and_cost(ins_cap, gens, loads, ...
                    CGrid_Index, init_sol, scenario_cfg.base_load_ratio, ...
                    scenario_cfg.interconnection_mode, cost_cfg, nonlsol);
                actual_vre_share = temp_metrics.vre_share;
                actual_curtailment_rate = temp_metrics.curtailment_rate;
                fprintf('  实际 VRE 渗透率 = %.4f\n', actual_vre_share);
                fprintf('  实际弃电率 = %.4f\n', actual_curtailment_rate);

                vre_ok = (isnan(min_vre) || actual_vre_share >= min_vre - 1e-6) ...
                    && actual_vre_share <= max_vre + 1e-6;
                curtailment_ok = ~cost_cfg.ENABLE_CURTAILMENT_CONSTRAINT ...
                    || actual_curtailment_rate <= cost_cfg.MAX_CURTAILMENT + 1e-6;

                if vre_ok && curtailment_ok
                    fprintf('  ✓ 当前贪心解满足 VRE 与弃电率约束\n');
                    break;
                end

                if actual_vre_share >= min_vre - 1e-6
                    fprintf('  ✓ 实际 VRE 已满足下界 %.4f\n', min_vre);
                    break;
                end

                % 继续添加更多场站
                remaining_grids = find(init_sol(1:nonlsol+nonlwin) == 0);
                if isempty(remaining_grids)
                    fprintf('  ⚠ 无更多可添加的场站\n');
                    break;
                end

                % 重新计算剩余场站的效率
                annual_gen_rem = sum(gens(remaining_grids, :), 2);
                cap_rem = ins_cap(remaining_grids) * 1e6;
                efficiency_rem = annual_gen_rem ./ max(cap_rem, 1);
                [~, sort_idx_rem] = sort(efficiency_rem, 'descend');

                % 添加一批场站（数量为剩余场站的 20%）
                batch_size = max(1, round(length(remaining_grids) * 0.2));
                for j = 1:batch_size
                    grid_idx = remaining_grids(sort_idx_rem(j));
                    init_sol(grid_idx) = 1;
                end
                fprintf('  继续添加 %d 个场站\n', batch_size);
            end
        else
            fprintf('✓ 当前近似 gross_vre/load %.4f 已满足下界 %.4f\n', approx_gross_vre_to_load_ratio, min_vre);
        end
    end

    %% ======== 5. 最终完整调度评估（仅一次） ========
    fprintf('执行最终完整调度评估...\n');
    init_metrics = evaluate_dispatch_and_cost(ins_cap, gens, loads, ...
        CGrid_Index, init_sol, scenario_cfg.base_load_ratio, ...
        scenario_cfg.interconnection_mode, cost_cfg, nonlsol);
    fprintf('最终调度 VRE = %.4f，弃电率 = %.4f，成本 = %.2f billion USD/year\n', ...
        init_metrics.vre_share, init_metrics.curtailment_rate, init_metrics.total_annual_cost);
end
