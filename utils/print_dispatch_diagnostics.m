function print_dispatch_diagnostics(metrics, scenario_cfg, cost_cfg)
% PRINT_DISPATCH_DIAGNOSTICS — 打印调度与成本诊断信息
%
% 输入：
%   metrics      — evaluate_dispatch_and_cost 返回的结构体
%   scenario_cfg — 情景配置结构体
%   cost_cfg     — 成本模型配置结构体

    fprintf('\n=== 容量诊断 ===\n');
    fprintf('光伏装机容量:          %.2f GW\n', metrics.pv_capacity_gw);
    fprintf('风电装机容量:          %.2f GW\n', metrics.wind_capacity_gw);
    fprintf('  陆上风电:            %.2f GW\n', metrics.onshore_wind_capacity_gw);
    fprintf('  海上风电:            %.2f GW\n', metrics.offshore_wind_capacity_gw);
    fprintf('VRE 总装机:            %.2f GW\n', metrics.total_vre_capacity_gw);
    fprintf('选中光伏格网数:        %d\n',     metrics.selected_pv_grid_count);
    fprintf('选中风电格网数:        %d\n',     metrics.selected_wind_grid_count);

    fprintf('\n=== 原始发电量诊断 ===\n');
    fprintf('光伏原始发电量:        %.4f TWh\n', metrics.gross_pv_generation_twh);
    fprintf('风电原始发电量:        %.4f TWh\n', metrics.gross_wind_generation_twh);
    fprintf('原始风光发电量:        %.4f TWh\n', metrics.gross_vre_generation_twh);
    fprintf('原始风光发电占比:      %.4f\n',     metrics.gross_vre_share);

    fprintf('\n=== 负荷服务与调度诊断 ===\n');
    fprintf('总负荷:                %.4f TWh\n', metrics.total_load_twh);
    fprintf('基荷发电量:            %.4f TWh\n', metrics.base_load_twh);
    fprintf('灵活电源发电量:        %.4f TWh\n', metrics.flexible_generation_twh);
    fprintf('VRE 剩余负荷服务等价值:%.4f TWh\n', metrics.residual_vre_service_twh);
    fprintf('弃电量:                %.4f TWh\n', metrics.curtailed_vre_twh);
    fprintf('弃电率:                %.4f\n',     metrics.curtailment_rate);
    fprintf('输电容量:              %.4f TW\n',  metrics.transmission_capacity_TW);

    fprintf('\n=== 渗透率与约束 ===\n');
    fprintf('vre_share (残差定义):  %.4f\n', metrics.vre_share);
    fprintf('VRE 约束区间:          [%.4f, %.4f]\n', ...
        scenario_cfg.min_vre_share, scenario_cfg.max_vre_share);

    fprintf('\n=== 成本 ===\n');
    fprintf('年度总成本:            %.2f billion USD/year\n', metrics.total_annual_cost);

    cb = metrics.cost_breakdown;
    if strcmp(cost_cfg.COST_MODE, 'annualized_incremental')
        fprintf('VRE CAPEX (总):        %.2f billion USD\n', cb.vre_capex_billion);
        fprintf('VRE CAPEX (增量):      %.2f billion USD\n', cb.incremental_vre_capex_billion);
        fprintf('VRE CAPEX (年度化):    %.2f billion USD/year\n', cb.annualized_vre_capex_billion);
        fprintf('储能 CAPEX (总):       %.2f billion USD\n', cb.storage_capex_billion);
        fprintf('储能 CAPEX (增量):     %.2f billion USD\n', cb.incremental_storage_capex_billion);
        fprintf('储能 CAPEX (年度化):   %.2f billion USD/year\n', cb.annualized_storage_capex_billion);
        fprintf('输电 CAPEX (总):       %.2f billion USD\n', cb.tx_capex_billion);
        fprintf('输电 CAPEX (增量):     %.2f billion USD\n', cb.incremental_tx_capex_billion);
        fprintf('输电 CAPEX (年度化):   %.2f billion USD/year\n', cb.annualized_tx_capex_billion);
        fprintf('VRE O&M:               %.2f billion USD/year\n', cb.vre_om_billion);
        fprintf('储能 O&M:              %.2f billion USD/year\n', cb.storage_om_billion);
        fprintf('输电 O&M:              %.2f billion USD/year\n', cb.tx_om_billion);
        fprintf('灵活电源 OPEX:         %.2f billion USD/year\n', cb.flexible_opex_billion);
    end
end
