function test_vre_share_definition()
% TEST_VRE_SHARE_DEFINITION — 验证 VRE 渗透率严格定义
%
% 检查：
%   actual_vre_generation_twh = gross_vre_generation_twh - curtailed_vre_twh
%   total_generation_twh = actual_vre + base_generation + flexible_generation
%   vre_share = actual_vre_generation_twh / total_generation_twh

    fprintf('=== test_vre_share_definition ===\n');

    % 构造最小测试数据
    n_grids = 10;
    nonlsol = 5;
    n_hours = 24;

    ins_cap = ones(n_grids, 1) * 0.01;  % TWp each
    gens = rand(n_grids, n_hours) * 0.001;  % TWh
    loads = ones(20, n_hours) * 0.005;  % TW

    CGrid_Index = zeros(n_grids, 3);
    CGrid_Index(:,1) = repmat((1:5)', 2, 1);  % 5 regions
    CGrid_Index(:,2) = [1;1;0;0;1; 1;0;1;0;0];  % select some
    CGrid_Index(:,3) = [0;0;0;0;1; 0;0;1;0;0];  % offshore flags

    scale = zeros(n_grids + 40 + 10, 1);
    scale(1:n_grids) = CGrid_Index(:,2);
    % storage power (20 regions)
    scale(n_grids+1:n_grids+20) = 1;
    % storage duration (20 regions)
    scale(n_grids+21:n_grids+40) = 4;
    % transmission
    scale(n_grids+41:end) = 10;

    base_load_ratio = 0.1;
    interconnection_mode = 'S-A';

    cost_cfg = cost_model_config();
    cost_cfg.COST_MODE = 'legacy_capex';

    metrics = evaluate_dispatch_and_cost(ins_cap, gens, loads, ...
        CGrid_Index, scale, base_load_ratio, interconnection_mode, ...
        cost_cfg, nonlsol);

    % 检查 1: actual_vre = gross_vre - curtailed
    expected_actual = max(metrics.gross_vre_generation_twh - metrics.curtailed_vre_twh, 0);
    assert(abs(metrics.actual_vre_generation_twh - expected_actual) < 1e-6, ...
        'actual_vre_generation_twh != gross - curtailed');

    % 检查 2: total_generation = actual_vre + base + flexible
    expected_total = metrics.actual_vre_generation_twh ...
        + metrics.base_generation_twh ...
        + metrics.flexible_generation_twh;
    assert(abs(metrics.total_generation_twh - expected_total) < 1e-6, ...
        'total_generation_twh != actual_vre + base + flexible');

    % 检查 3: vre_share = actual_vre / total_generation
    expected_share = metrics.actual_vre_generation_twh / metrics.total_generation_twh;
    assert(abs(metrics.vre_share - expected_share) < 1e-10, ...
        'vre_share != actual_vre / total_generation');

    % 检查 4: base_generation = base_load_ratio * total_load
    expected_base = base_load_ratio * metrics.total_load_twh;
    assert(abs(metrics.base_generation_twh - expected_base) < 1e-6, ...
        'base_generation_twh != base_load_ratio * total_load');

    % 检查 5: gross_vre_to_load_ratio
    expected_ratio = metrics.gross_vre_generation_twh / metrics.total_load_twh;
    assert(abs(metrics.gross_vre_to_load_ratio - expected_ratio) < 1e-10, ...
        'gross_vre_to_load_ratio mismatch');

    % 检查 6: curtailment_rate = curtailed / gross_vre
    if metrics.gross_vre_generation_twh > 0
        expected_cr = metrics.curtailed_vre_twh / metrics.gross_vre_generation_twh;
        assert(abs(metrics.curtailment_rate - expected_cr) < 1e-10, ...
            'curtailment_rate != curtailed / gross_vre');
    end

    fprintf('  全部断言通过。\n');
end
