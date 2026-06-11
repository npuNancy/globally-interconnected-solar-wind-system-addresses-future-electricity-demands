%% repair_vre_2050.m — 后处理修复 SSP5-6.0 2050年 VRE 渗透率上界约束
%
% 功能：
%   加载 GA 优化结果，逐步移除成本效率最低的冗余场站，
%   直到 VRE 渗透率 ≤ MAX_VRE_SHARE，同时保持既有装机约束。
%
% 原理：
%   对每个区域，计算当前装机容量与最低要求的差值（余量）。
%   在余量内的场站按"年发电量/装机容量"排序，
%   优先移除效率最低（对 VRE 贡献小、成本高）的场站。
%   使用完整 8760h 调度模拟验证 VRE，确保修复精度。
%
% 用法：
%   在 Optimization_ssp560/ 目录下运行：
%     matlab -batch "run('repair_vre_2050.m')"
%   或修改 RESULT_DIR 指向其他结果目录。

clear, clc

%% ========== 参数配置 ==========
RESULT_DIR = 'results/results_20260610_1046';

BATCH_LARGE  = 200;    % VRE 远超目标时每轮移除数
BATCH_SMALL  = 20;     % VRE 接近目标时每轮移除数
COARSE_GAP   = 0.03;   % VRE 与目标差距超过此值用大批量
MAX_ITER     = 50;     % 最大迭代轮数

%% ========== 加载配置 ==========
script_dir = fileparts(mfilename('fullpath'));
addpath(fullfile(script_dir, '..', 'utils'));
addpath(script_dir);
run('optimization_config.m');

cost_cfg = cost_model_config();
cost_cfg.MAX_CURTAILMENT = MAX_CURTAILMENT;

%% ========== 加载数据 ==========
fprintf('========================================\n');
fprintf('  VRE 后处理修复 — SSP5-6.0 2050\n');
fprintf('========================================\n\n');

h5file     = fullfile(RESULT_DIR, 'Optimization_SC_2050_Res.h5');
matfile_in = fullfile(RESULT_DIR, 'Optimization_SC_2050_metrics.mat');

res_scale = h5read(h5file, '/res_scale')';
mat_data  = load(matfile_in, 'scenario_cfg');
scenario_cfg = mat_data.scenario_cfg;

md = load('results/model_data_2050.mat');
ins_cap     = md.model_data.ins_cap;
gens        = md.model_data.gens;
loads       = md.model_data.loads;
CGrid_Index = md.model_data.CGrid_Index;
nonlsol     = md.model_data.nonlsol;
nonlwin     = md.persistent_data.nonlwin;
cur_solar   = md.persistent_data.cur_solar;
cur_wind    = md.persistent_data.cur_wind;
nonlcon_sel = md.persistent_data.nonlcon_sel;

scale   = res_scale;
n_grids = nonlsol + nonlwin;
MAX_VRE = scenario_cfg.max_vre_share;

%% ========== 修复前评估 ==========
metrics0 = evaluate_dispatch_and_cost(ins_cap, gens, loads, CGrid_Index, scale, ...
    scenario_cfg.base_load_ratio, scenario_cfg.interconnection_mode, cost_cfg, nonlsol);

fprintf('修复前: VRE=%.4f, 弃电率=%.4f, 成本=%.2f B USD/yr, 选中=%d\n', ...
    metrics0.vre_share, metrics0.curtailment_rate, metrics0.total_annual_cost, ...
    sum(scale(1:n_grids)));

if metrics0.vre_share <= MAX_VRE + 1e-6
    fprintf('VRE 已满足约束，无需修复。\n');
    return;
end

%% ========== 预计算每个场站的发电效率 ==========
annual_gen = sum(gens, 2);
cost_eff = annual_gen ./ max(ins_cap, 1e-10);

%% ========== 迭代移除 ==========
fprintf('\n开始修复 (目标 VRE <= %.4f)...\n\n', MAX_VRE);

total_removed = 0;
for iter = 1:MAX_ITER
    metrics = evaluate_dispatch_and_cost(ins_cap, gens, loads, CGrid_Index, scale, ...
        scenario_cfg.base_load_ratio, scenario_cfg.interconnection_mode, cost_cfg, nonlsol);

    vre_gap = metrics.vre_share - MAX_VRE;
    fprintf('迭代 %2d: VRE=%.4f (超 %.4f), 成本=%.2f B, 选中=%d\n', ...
        iter, metrics.vre_share, vre_gap, metrics.total_annual_cost, ...
        sum(scale(1:n_grids)));

    if vre_gap <= 1e-6
        fprintf('  VRE 约束已满足\n');
        break;
    end

    batch_size = select_batch_size(vre_gap, COARSE_GAP, BATCH_LARGE, BATCH_SMALL);

    candidates = build_removal_candidates(scale, ins_cap, cost_eff, ...
        nonlcon_sel, nonlsol, n_grids, cur_solar, cur_wind);

    if isempty(candidates)
        fprintf('  无可移除场站，VRE 仍为 %.4f\n', metrics.vre_share);
        break;
    end

    [~, order] = sort(cost_eff(candidates), 'ascend');
    n_remove = min(batch_size, length(order));
    to_remove = candidates(order(1:n_remove));

    scale(to_remove) = 0;
    total_removed = total_removed + n_remove;
    fprintf('  移除 %d 个场站 (累计 %d), 剩余候选 %d\n', ...
        n_remove, total_removed, length(candidates) - n_remove);
end

%% ========== 最终评估 ==========
fprintf('\n========================================\n');
fprintf('  修复完成\n');
fprintf('========================================\n\n');

metrics_final = evaluate_dispatch_and_cost(ins_cap, gens, loads, CGrid_Index, scale, ...
    scenario_cfg.base_load_ratio, scenario_cfg.interconnection_mode, cost_cfg, nonlsol);

fprintf('         修复前        修复后\n');
fprintf('VRE:     %.4f     %.4f  (目标 <= %.4f)\n', ...
    metrics0.vre_share, metrics_final.vre_share, MAX_VRE);
fprintf('弃电率:  %.4f     %.4f\n', ...
    metrics0.curtailment_rate, metrics_final.curtailment_rate);
fprintf('成本:    %.2f    %.2f  B USD/yr\n', ...
    metrics0.total_annual_cost, metrics_final.total_annual_cost);
fprintf('选中数:  %d        %d\n', ...
    sum(res_scale(1:n_grids)), sum(scale(1:n_grids)));
fprintf('累计移除: %d 个场站\n', total_removed);

%% ========== 约束检查 ==========
fprintf('\n--- 约束逐项检查 ---\n');
[c_final, ~, cnames] = nonlcon2050(scale, cost_cfg, scenario_cfg, ...
    md.model_data, md.persistent_data);

all_pass = true;
for i = 1:length(cnames)
    pass = c_final(i) <= 1e-6;
    if ~pass, all_pass = false; end
    tag = 'PASS';
    if ~pass, tag = 'FAIL'; end
    fprintf('  %-45s  %+.4e  %s\n', cnames{i}, c_final(i), tag);
end
fprintf('全部通过: %s\n', mat2str(all_pass));

%% ========== 保存结果 ==========
repaired_h5 = fullfile(RESULT_DIR, 'Optimization_SC_2050_Res_repaired.h5');
if exist(repaired_h5, 'file'), delete(repaired_h5); end

res_scale_out = scale(:)';
h5create(repaired_h5, '/res_scale', size(res_scale_out));
h5write(repaired_h5, '/res_scale', res_scale_out);

metrics_vec = [metrics_final.curtailment_rate, metrics_final.flexible_ratio, ...
               metrics_final.vre_share, metrics_final.total_annual_cost];
h5create(repaired_h5, '/metrics', size(metrics_vec));
h5write(repaired_h5, '/metrics', metrics_vec);

cb = metrics_final.cost_breakdown;
cost_bd_vec = [cb.vre_capex_billion, cb.incremental_vre_capex_billion, ...
               cb.annualized_vre_capex_billion, cb.storage_capex_billion, ...
               cb.incremental_storage_capex_billion, cb.annualized_storage_capex_billion, ...
               cb.tx_capex_billion, cb.incremental_tx_capex_billion, ...
               cb.annualized_tx_capex_billion, cb.vre_om_billion, ...
               cb.storage_om_billion, cb.tx_om_billion, cb.flexible_opex_billion];
h5create(repaired_h5, '/cost_breakdown', size(cost_bd_vec));
h5write(repaired_h5, '/cost_breakdown', cost_bd_vec);

h5create(repaired_h5, '/metrics_schema_version', [1, 1]);
h5write(repaired_h5, '/metrics_schema_version', 2);
h5create(repaired_h5, '/is_feasible', [1, 1]);
h5write(repaired_h5, '/is_feasible', double(all_pass));
h5create(repaired_h5, '/is_repaired', [1, 1]);
h5write(repaired_h5, '/is_repaired', double(true));
h5create(repaired_h5, '/repair_removed_count', [1, 1]);
h5write(repaired_h5, '/repair_removed_count', double(total_removed));
h5create(repaired_h5, '/vre_before_repair', [1, 1]);
h5write(repaired_h5, '/vre_before_repair', metrics0.vre_share);
h5create(repaired_h5, '/vre_after_repair', [1, 1]);
h5write(repaired_h5, '/vre_after_repair', metrics_final.vre_share);

repaired_mat = fullfile(RESULT_DIR, 'Optimization_SC_2050_repaired_metrics.mat');
save(repaired_mat, 'metrics0', 'metrics_final', 'total_removed', ...
     'scale', 'scenario_cfg', 'cost_cfg', 'c_final', 'cnames', 'all_pass');

fprintf('\n修复结果已保存至:\n  %s\n  %s\n', repaired_h5, repaired_mat);

%% ==================== 辅助函数 ====================

function batch_size = select_batch_size(vre_gap, coarse_gap, batch_large, batch_small)
    if vre_gap > coarse_gap
        batch_size = batch_large;
    else
        batch_size = batch_small;
    end
end

function candidates = build_removal_candidates(scale, ins_cap, cost_eff, ...
    nonlcon_sel, nonlsol, n_grids, cur_solar, cur_wind)
% 找出所有可安全移除的场站（移除后不违反既有装机约束）。
% 返回全局索引（可直接用于 scale(idx) = 0）。
%
% 注意：scale 是行向量，nonlcon_sel 是列向量。
%       必须用 (:) 强制统一形状后再做逻辑运算。

    sel = (scale(1:n_grids) == 1);
    sel = sel(:);
    reg = nonlcon_sel(:);

    candidates = [];
    for region = 1:20
        % --- 光伏 (全局索引 1:nonlsol) ---
        mask_s = (reg(1:nonlsol) == region) & sel(1:nonlsol);
        idx_s = find(mask_s);
        candidates = [candidates; ...
            pick_removable(idx_s, ins_cap, cost_eff, cur_solar(region))];

        % --- 风电 (全局索引 nonlsol+1:n_grids) ---
        mask_w = (reg(nonlsol+1:n_grids) == region) & sel(nonlsol+1:n_grids);
        idx_w = find(mask_w) + nonlsol;
        candidates = [candidates; ...
            pick_removable(idx_w, ins_cap, cost_eff, cur_wind(region))];
    end
end

function removable = pick_removable(idx, ins_cap, cost_eff, min_cap)
% 在给定全局索引列表中，按成本效率从差到好排序，
% 选出可移除的子集（累计移除容量不超过余量）。

    removable = [];
    if isempty(idx), return; end

    total_cap = sum(ins_cap(idx));
    excess = total_cap - min_cap;
    if excess <= 0, return; end

    [~, order] = sort(cost_eff(idx), 'ascend');
    cum = 0;
    for i = 1:length(order)
        g = idx(order(i));
        if cum + ins_cap(g) <= excess
            removable = [removable; g];
            cum = cum + ins_cap(g);
        end
    end
end
