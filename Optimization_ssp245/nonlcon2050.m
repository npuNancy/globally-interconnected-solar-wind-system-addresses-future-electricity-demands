function [c, ceq, constraint_names] = nonlcon2050(x, cost_cfg, scenario_cfg, model_data, persistent_data)
% nonlcon2050 — 2050年成本最小化非线性约束
%
% 约束逻辑：
%   1. 既有装机容量约束（光伏每区域不低于当前装机；风电允许若干区域不满足）
%   2. VRE 渗透率上下界约束
%   3. 可选弃电率约束
%
% 用法：
%   nonlcon2050(x)                          — 由 ga 调用，从持久变量加载配置
%   nonlcon2050(x, cost_cfg, scenario_cfg, model_data, persistent_data)
%                                           — 直接传参（用于测试）
%
% 注意：单参数模式需要先运行 Optimization_SC_2050.m 保存模型数据
%       至 results/model_data_2050.mat。

    if nargin == 1
        persistent p_cost_cfg p_scenario_cfg p_model_data p_persistent_data

        if isempty(p_cost_cfg)
            p_cost_cfg = cost_model_config();

            run('optimization_config.m');
            p_cost_cfg.MAX_CURTAILMENT = MAX_CURTAILMENT;
            validate_curtailment_config(p_cost_cfg, CURTAILMENT_ACCEPTANCE_MARGIN);
            p_scenario_cfg = struct( ...
                'base_load_ratio',            BASE_LOAD_RATIO_2050, ...
                'interconnection_mode',       'S-C', ...
                'min_vre_share',              MIN_VRE_SHARE_2050, ...
                'max_vre_share',              MAX_VRE_SHARE_2050, ...
                'allowed_unmet_wind_regions', ALLOWED_UNMET_WIND_REGIONS_2050, ...
                'allowed_unmet_solar_regions', ALLOWED_UNMET_SOLAR_REGIONS_2050 ...
            );

            data = load('results/model_data_2050.mat', 'model_data', 'persistent_data');
            p_model_data = data.model_data;
            p_persistent_data = data.persistent_data;
        end

        cost_cfg        = p_cost_cfg;
        scenario_cfg    = p_scenario_cfg;
        model_data      = p_model_data;
        persistent_data = p_persistent_data;
    end

    % 默认值
    if ~isfield(scenario_cfg, 'allowed_unmet_wind_regions')
        scenario_cfg.allowed_unmet_wind_regions = 0;
    end
    if ~isfield(scenario_cfg, 'allowed_unmet_solar_regions')
        scenario_cfg.allowed_unmet_solar_regions = 0;
    end

    min_vre = scenario_cfg.min_vre_share;
    max_vre = scenario_cfg.max_vre_share;
    allowed_unmet_wind = scenario_cfg.allowed_unmet_wind_regions;
    allowed_unmet_solar = scenario_cfg.allowed_unmet_solar_regions;

    nonlcon_sel = persistent_data.nonlcon_sel;
    nonlcon_ins = persistent_data.nonlcon_ins;
    nonlsol_n   = persistent_data.nonlsol;
    nonlwin_n   = persistent_data.nonlwin;
    cur_solar   = persistent_data.cur_solar;
    cur_wind    = persistent_data.cur_wind;

    ins_cap     = model_data.ins_cap;
    gens        = model_data.gens;
    loads       = model_data.loads;
    CGrid_Index = model_data.CGrid_Index;
    nonlsol     = model_data.nonlsol;

    c = [];
    constraint_names = {};

    %% ======== 1. 既有装机容量约束 ========

    % --- 光伏约束（所有区域必须满足） ---
    tmp_a = x(1:nonlsol_n);
    tmp_b = nonlcon_ins(1:nonlsol_n);
    tmp_c = tmp_a(:) .* tmp_b(:);
    tmp_d = nonlcon_sel(1:nonlsol_n);
    tmp_solar = zeros(20, 1);
    for i = 1:20
        idx = find(tmp_d == i);
        tmp_solar(i) = sum(tmp_c(idx));
    end
    tmp_e = tmp_solar < cur_solar;
    c(end+1) = sum(tmp_e) - allowed_unmet_solar;
    constraint_names{end+1} = 'existing_solar_unmet_region_count_minus_allowance';

    % --- 风电约束（允许若干区域不满足） ---
    tmp_a2 = x(nonlsol_n+1 : nonlsol_n+nonlwin_n);
    tmp_b2 = nonlcon_ins(nonlsol_n+1 : nonlsol_n+nonlwin_n);
    tmp_c2 = tmp_a2(:) .* tmp_b2(:);
    tmp_d2 = nonlcon_sel(nonlsol_n+1 : nonlsol_n+nonlwin_n);
    tmp_wind = zeros(20, 1);
    for i = 1:20
        idx = find(tmp_d2 == i);
        tmp_wind(i) = sum(tmp_c2(idx));
    end
    tmp_e2 = tmp_wind < cur_wind;
    unmet_wind_count = sum(tmp_e2);
    c(end+1) = unmet_wind_count - allowed_unmet_wind;
    constraint_names{end+1} = 'existing_wind_unmet_region_count_minus_allowance';

    %% ======== 2. VRE 渗透率约束 ========
    % VRE 渗透率严格定义：
    %   vre_share = actual_vre_generation_twh / total_generation_twh
    % 其中：
    %   actual_vre_generation_twh = gross_vre_generation_twh - curtailed_vre_twh
    %   total_generation_twh = actual_vre + base_generation + flexible_generation

    metrics = evaluate_dispatch_and_cost_cached(x, ins_cap, gens, loads, ...
        CGrid_Index, scenario_cfg.base_load_ratio, scenario_cfg.interconnection_mode, ...
        cost_cfg, nonlsol);

    vre_share = metrics.vre_share;
    if ~isnan(min_vre)
        c(end+1) = min_vre - vre_share;
        constraint_names{end+1} = 'vre_lower_bound';
    end
    c(end+1) = vre_share - max_vre;
    constraint_names{end+1} = 'vre_upper_bound';

    %% ======== 3. 弃电率上限约束 ========
    if cost_cfg.ENABLE_CURTAILMENT_CONSTRAINT
        c(end+1) = metrics.curtailment_rate - cost_cfg.MAX_CURTAILMENT;
        constraint_names{end+1} = 'curtailment_upper_bound_strict';
    end

    ceq = [];
end
