%% Optimization_SC_2050.m — 2050年 SSP2-4.5 成本最小化优化（大陆互联 S-C）
%
% 功能：使用 GA（ga）单目标优化，求解2050年全球20个区域的光伏/风电场站
%       空间选址、储能配置和跨区输电容量的成本最小化方案。
%
% 情景假设（AR6 SSP2-4.5）：
%   - 全球电力需求：51,940 TWh
%   - 基荷发电占比：51.8%（非可再生能源调度份额）
%   - 互联模式：大陆互联（S-C），仅保留洲内输电通道
%
% 优化目标：
%   minimize: 风光扩张年度化增量系统成本（billion USD/year）
%
% 约束：
%   - MIN_VRE_SHARE <= 风光渗透率 <= MAX_VRE_SHARE
%   - 逐小时供需调度逻辑
%   - 已有装机容量约束
%   - 储能与输电容量约束
%
% 决策变量：
%   [光伏选址(0/1) | 风电选址(0/1) | 储能功率(20区域) | 储能时长(20区域) | 输电容量(n_trans条链路)]
%
% 输出：
%   results/Optimization_SC_2050_Res.h5
%   results/Optimization_SC_2050_metrics.mat

clear, clc
run('optimization_config.m');

% 加载共享工具和成本配置
script_dir = fileparts(mfilename('fullpath'));
addpath(fullfile(script_dir, '..', 'utils'));
addpath(script_dir);   % 确保 helper 函数（calculatePathCapacity 等）可被 utils/ 调用
RESULTS_DIR = setup_results_dir(RESULTS_SUBDIR);
cost_cfg = cost_model_config();
cost_cfg.MAX_CURTAILMENT = MAX_CURTAILMENT;
validate_curtailment_config(cost_cfg, CURTAILMENT_ACCEPTANCE_MARGIN);

%% ======================== 1. 启动并行计算池 ========================
% PARPOOL_NUM_WORKERS 在 optimization_config.m 中定义（默认 64，可通过环境变量覆盖）
fprintf('请求并行池 worker 数: %d\n', PARPOOL_NUM_WORKERS);
try
    pool = parpool('local', PARPOOL_NUM_WORKERS);
    fprintf('并行池已启动：%d 个工作节点\n', pool.NumWorkers);
catch ME
    if contains(ME.identifier, 'parallel:pool:alreadyopen')
        pool = gcp('nocreate');
        fprintf('并行池已在运行：%d 个工作节点\n', pool.NumWorkers);
    else
        error('并行池启动失败，终止运行：%s', ME.message);
    end
end

%% ======================== 2. 构建风电候选格网 ========================
luccs = geotiffread('Global_Wind_Net_Area_Add_Egrid.tif');
luccs = luccs / 100;
win_index = find(luccs > 0);
fish_area = geotiffread('Global_Wind_Fishnet_Area.tif');
fish_area = double(fish_area);
areas = luccs(win_index) .* fish_area(win_index);
% Global_LandMask.tif 经测试确认：
%   landmask == 1 表示海洋格网（offshore）
%   landmask == 0 表示陆地格网（onshore）
landmask = readgeoraster('Global_LandMask.tif');
landmask(landmask<100) = 0; landmask(landmask>100) = 1;
landmask = landmask(win_index);
wind_ins = (3.68 * areas) / 1000 / 1000;
wind_ins(landmask==1) = (6.07 * areas(landmask==1)) / 1000 / 1000;
wind_gen = h5read('Global_Wind_CFs_Sel.h5', '/data');
for ii = 1:8477
    wind_gen(ii,:) = wind_gen(ii,:) * wind_ins(ii);
end
wind_ind1 = win_index((wind_ins<=0.0001) & (wind_ins>0));
tmp = wind_ins > 0.0001;
wind_ins = wind_ins(tmp); wind_gen = wind_gen(tmp,:); win_index = win_index(tmp);
tmp = sum(wind_gen, 2);
wind_ind2 = win_index(tmp >= 10);
tmp = tmp < 10;
wind_ins = wind_ins(tmp); wind_gen = wind_gen(tmp,:); win_index = win_index(tmp);
wind_ind3 = win_index;
save WindInd2050 wind_ind3 wind_ind2 wind_ind1
clear areas fish_area luccs tmp wind_ind1 wind_ind2 wind_ind3

%% ======================== 3. 构建光伏候选格网 ========================
grids = geotiffread('Global_fishnet.tif');
solar_index = find(grids < 65536);
grids(solar_index) = 0;
load Global_Solar_CFs
res_CF = res_CF / 10 / 1000;
luccs = geotiffread('Global_Solar_Net_Area_Add_Egrid.tif');
luccs = luccs / 100;
fish_area = geotiffread('Global_Solar_Fishnet_Area.tif');
fish_area(fish_area < 0) = 0;
fish_area = double(fish_area);
areas = luccs(solar_index) .* fish_area(solar_index);
solar_gen = res_CF; clear res_CF
pv_density = compute_pv_density(solar_index);
solar_ins = zeros([13296, 1]);
for ii = 1:13296
    solar_ins(ii) = (pv_density(ii) * areas(ii)) / 1000 / 1000;
    solar_gen(ii,:) = solar_gen(ii,:) * (pv_density(ii) * areas(ii)) / 1000 / 1000;
end
clear pv_density
solar_ind1 = solar_index((solar_ins<=0.001) & (solar_ins>0));
tmp = solar_ins > 0.001;
solar_ins = solar_ins(tmp); solar_gen = solar_gen(tmp,:); solar_index = solar_index(tmp);
tmp = sum(solar_gen, 2);
solar_ind2 = solar_index(tmp >= 90);
tmp = tmp < 90;
solar_ins = solar_ins(tmp); solar_gen = solar_gen(tmp,:); solar_index = solar_index(tmp);
solar_ind3 = solar_index;
save SolarInd2050 solar_ind1 solar_ind2 solar_ind3
clear areas fish_area luccs grids tmp solar_ind3 solar_ind2 solar_ind1

%% ======================== 4. 合并光伏/风电数据 ========================
all_gens = [solar_gen; wind_gen];
all_ins  = [solar_ins; wind_ins];
clear solar_gen wind_gen
clear solar_ins wind_ins

%% ======================== 5. 加载2050年负荷数据 ========================
load Global_Load_22region.mat
all_loads = squeeze(all_loads(4,:,:)) / 1000 / 1000;
global_load = sum(all_loads, 1);
all_loads = all_loads / (sum(global_load(:)) / DEMAND_2050);
clear global_load

%% ======================== 6. 构建区域索引和约束数据 ========================
[grid_ind, R] = readgeoraster('Global_Grid_Division.tif');
CGrid_Index = [grid_ind(solar_index); grid_ind(win_index)];
nonlcon_sel = CGrid_Index; nonlcon_ins = all_ins;
nonlsol = length(solar_index); nonlwin = length(win_index);
save NonlConData nonlcon_sel nonlcon_ins nonlsol nonlwin
clear nonlcon_sel nonlcon_ins nonlsol nonlwin
landmask = readgeoraster('Global_LandMask.tif');
landmask(landmask<100) = 0; landmask(landmask>100) = 1;
landmask = landmask(win_index);
CGrid_Index(length(solar_index)+1 : length(solar_index)+length(win_index), 3) = landmask;
clear grid_ind R landmask

%% ======================== 7. 设置优化变量与约束 ========================
rng(GA_SEED, 'twister');
fprintf('GA 随机种子: %d\n', GA_SEED);
nvars = length(CGrid_Index);
load Global_Init_State.mat cur_storage cur_trans

lb = zeros(1, nvars);
ub = ones(1, nvars);

al = max(all_loads, [], 2);
lb(nvars+1:nvars+20) = cur_storage / 1000;
ub(nvars+1:nvars+20) = al * 1000;
clear cur_storage al

lb(nvars+21:nvars+40) = 2;
ub(nvars+21:nvars+40) = 72;

cur_trans(6,1)=0; cur_trans(7,1)=0; cur_trans(1,6)=0; cur_trans(1,7)=0;
cur_trans(17,4)=0; cur_trans(18,4)=0; cur_trans(4,17)=0; cur_trans(4,18)=0;
tmp = cur_trans > 0;
cur_trans(cur_trans < 2) = 0;
lb(nvars+41:nvars+40+sum(tmp(:))) = cur_trans(tmp) / 1000;
ub(nvars+41:nvars+40+sum(tmp(:))) = 10 * 1000;
clear cur_trans
nvars = length(lb);
intcon = 1:1:length(lb);

%% ======================== 8. 构建成本与情景配置 ========================
scenario_cfg = struct( ...
    'base_load_ratio',            BASE_LOAD_RATIO_2050, ...
    'interconnection_mode',       'S-C', ...
    'min_vre_share',              MIN_VRE_SHARE_2050, ...
    'max_vre_share',              MAX_VRE_SHARE_2050, ...
    'allowed_unmet_wind_regions', ALLOWED_UNMET_WIND_REGIONS_2050 ...
);

% 预加载非线性约束所需的持久数据
load NonlConData.mat nonlcon_sel nonlcon_ins nonlsol nonlwin
load Global_Init_State cur_solar cur_wind
cur_solar = cur_solar / 1e6;  % MWp → TWp
cur_wind  = cur_wind  / 1e6;

% 封装为 struct，保存供 nonlcon2050.m 加载
model_data = struct( ...
    'ins_cap', all_ins, ...
    'gens',    all_gens, ...
    'loads',   all_loads, ...
    'CGrid_Index', CGrid_Index, ...
    'nonlsol', nonlsol ...
);

persistent_data = struct( ...
    'nonlcon_sel', nonlcon_sel, ...
    'nonlcon_ins', nonlcon_ins, ...
    'nonlsol',     nonlsol, ...
    'nonlwin',     nonlwin, ...
    'cur_solar',   cur_solar, ...
    'cur_wind',    cur_wind ...
);

% 保存模型数据供 nonlcon2050.m 独立使用
if ~exist('results', 'dir'), mkdir('results'); end
save('results/model_data_2050.mat', 'model_data', 'persistent_data');

% 清除旧指标缓存，避免复用旧定义产生的 metrics
clear evaluate_dispatch_and_cost_cached;

fprintf('VRE 渗透率定义: 实际风光发电量/总发电量\n');
fprintf('弃电率约束: %s\n', mat2str(cost_cfg.ENABLE_CURTAILMENT_CONSTRAINT));
fprintf('弃电率上限: %.4f\n', cost_cfg.MAX_CURTAILMENT);

%% ======================== 7.5 构造贪心初始解和初始种群 ========================
fprintf('\n=== 构造贪心初始解 ===\n');
[greedy_sol, greedy_metrics, greedy_status] = build_greedy_initial_solution(...
    all_ins, all_gens, all_loads, CGrid_Index, lb, ub, ...
    cost_cfg, scenario_cfg, nonlsol, nonlwin, persistent_data);
fprintf('%s\n', greedy_status);

if greedy_metrics.total_annual_cost > 0
    fprintf('贪心初始解成本: %.2f billion USD/year\n', greedy_metrics.total_annual_cost);
    fprintf('贪心初始解 VRE: %.4f\n', greedy_metrics.vre_share);
end

% 记录初始解统计
initial_selected_pv = sum(greedy_sol(1:nonlsol));
initial_selected_wind = sum(greedy_sol(nonlsol+1:nonlsol+nonlwin));
initial_pv_ratio = initial_selected_pv / nonlsol;
initial_wind_ratio = initial_selected_wind / nonlwin;
initial_cost = greedy_metrics.total_annual_cost;

[c_init, ceq_init] = nonlcon2050(greedy_sol, cost_cfg, scenario_cfg, model_data, persistent_data);
init_feasibility = check_solution_feasibility(c_init, ceq_init, 1e-6);
initial_max_violation = init_feasibility.max_constraint_violation;

fprintf('\n=== 构造初始种群 ===\n');
initial_population = build_initial_population(greedy_sol, lb, ub, ...
    POPULATION_SIZE, scenario_cfg, nonlsol, nonlwin);

%% ======================== 9. 运行 GA 单目标优化 ========================
T = datetime('now');
disp(T);
fprintf('开始2050年成本最小化优化（大陆互联，种群=%d，代数=%d）...\n', ...
    POPULATION_SIZE, MAX_GENERATIONS);
fprintf('成本模式: %s\n', cost_cfg.COST_MODE);
fprintf('VRE 渗透率约束: [%.4f, %.4f]\n', scenario_cfg.min_vre_share, scenario_cfg.max_vre_share);
fprintf('允许违反风电约束的区域数: %d\n', scenario_cfg.allowed_unmet_wind_regions);

options = optimoptions('ga', ...
    'UseParallel',       true, ...
    'PlotFcn',           [], ...
    'PopulationSize',    POPULATION_SIZE, ...
    'MaxGenerations',    MAX_GENERATIONS, ...
    'ConstraintTolerance', 1e-6, ...
    'MaxStallGenerations', MAX_STALL_GENERATIONS, ...
    'InitialPopulationMatrix', initial_population, ...
    'Display',           'iter');

fprintf('\n GA 迭代输出说明：Generation=代数 | Func-count=目标函数累计调用次数 | Best Penalty=当代最优惩罚值 | Mean Penalty=当代平均惩罚值 | Stall Generations=连续无改善代数\n\n');

[best_scale, best_cost, exitflag, output] = ga( ...
    @(scale) objective_total_cost(scale, all_ins, all_gens, all_loads, ...
        CGrid_Index, scenario_cfg.base_load_ratio, ...
        scenario_cfg.interconnection_mode, cost_cfg, nonlsol), ...
    nvars, ...
    [], [], [], [], ...
    lb, ub, ...
    @nonlcon2050, ...
    intcon, ...
    options);

T = datetime('now');
disp(T);
fprintf('优化完成，exitflag=%d，最优成本=%.2f\n', exitflag, best_cost);

%% ======================== 9.2 初始-最终对比诊断 ========================
final_selected_pv = sum(best_scale(1:nonlsol));
final_selected_wind = sum(best_scale(nonlsol+1:nonlsol+nonlwin));
final_pv_ratio = final_selected_pv / nonlsol;
final_wind_ratio = final_selected_wind / nonlwin;

% Hamming 距离
hamming_dist = sum(greedy_sol(1:nonlsol+nonlwin) ~= best_scale(1:nonlsol+nonlwin));
jaccard_sim = sum(greedy_sol(1:nonlsol+nonlwin) & best_scale(1:nonlsol+nonlwin)) / ...
              sum(greedy_sol(1:nonlsol+nonlwin) | best_scale(1:nonlsol+nonlwin));

fprintf('\n=== 初始-最终对比诊断 ===\n');
fprintf('初始选中光伏比例: %.4f (%d/%d)\n', initial_pv_ratio, initial_selected_pv, nonlsol);
fprintf('初始选中风电比例: %.4f (%d/%d)\n', initial_wind_ratio, initial_selected_wind, nonlwin);
fprintf('最终选中光伏比例: %.4f (%d/%d)\n', final_pv_ratio, final_selected_pv, nonlsol);
fprintf('最终选中风电比例: %.4f (%d/%d)\n', final_wind_ratio, final_selected_wind, nonlwin);
fprintf('Hamming 距离: %d\n', hamming_dist);
fprintf('Jaccard 相似度: %.4f\n', jaccard_sim);
fprintf('初始成本: %.2f billion USD/year\n', initial_cost);
fprintf('最终成本: %.2f billion USD/year\n', best_cost);
fprintf('初始最大约束违反: %.2e\n', initial_max_violation);

%% ======================== 10. 评估最优解指标（始终执行）========================
best_metrics = evaluate_dispatch_and_cost(all_ins, all_gens, all_loads, ...
    CGrid_Index, best_scale, scenario_cfg.base_load_ratio, ...
    scenario_cfg.interconnection_mode, cost_cfg, nonlsol);

print_dispatch_diagnostics(best_metrics, scenario_cfg, cost_cfg);
cb = best_metrics.cost_breakdown;

%% ======================== 9.5 最终解验收 ========================
[c_best, ceq_best, constraint_names] = nonlcon2050( ...
    best_scale, cost_cfg, scenario_cfg, model_data, persistent_data);

acceptance = check_final_solution_acceptance( ...
    c_best, ceq_best, constraint_names, ...
    best_metrics.curtailment_rate, cost_cfg.MAX_CURTAILMENT, ...
    CURTAILMENT_ACCEPTANCE_MARGIN, 1e-6);

print_constraint_diagnostics( ...
    constraint_names, c_best, ceq_best, 1e-6, ...
    best_metrics.curtailment_rate, cost_cfg.MAX_CURTAILMENT, ...
    CURTAILMENT_ACCEPTANCE_MARGIN);

fprintf('\n=== 最终解验收 ===\n');
fprintf('严格约束是否全部满足: %s\n', mat2str(acceptance.strict_is_feasible));
fprintf('最终结果是否接受:     %s\n', mat2str(acceptance.is_accepted));
fprintf('弃电率:               %.6f\n', best_metrics.curtailment_rate);
fprintf('名义弃电率上限:       %.6f\n', cost_cfg.MAX_CURTAILMENT);
fprintf('弃电率验收余量:       %.6f\n', CURTAILMENT_ACCEPTANCE_MARGIN);
fprintf('最终验收弃电率上限:   %.6f\n', acceptance.final_acceptance_upper_bound);

feasibility = check_solution_feasibility(c_best, ceq_best, 1e-6);

if ~acceptance.is_accepted
    fprintf('错误：最终解不满足验收规则，流水线终止。\n');
    failed_dir = fullfile('results', 'failed');
    if ~exist(failed_dir, 'dir'), mkdir(failed_dir); end
    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    fail_file = fullfile(failed_dir, sprintf('Optimization_SC_2050_failed_%s.mat', timestamp));
    save(fail_file, 'best_scale', 'best_cost', 'best_metrics', 'exitflag', ...
        'scenario_cfg', 'acceptance', 'feasibility', 'constraint_names');
    error('Optimization:InfeasibleResult', ...
        '最终解不可行 (max_violation=%.2e)，结果已保存至 %s', ...
        acceptance.max_acceptance_violation, fail_file);
end

if exitflag <= 0
    fprintf('提示：当前解满足验收规则，但 GA 未完全收敛，exitflag=%d\n', exitflag);
end

%% ======================== 11. 保存结果 ========================
% 构建兼容旧格式的输出
res_scale = best_scale(:)';    % 1 × nvars
prs = [best_metrics.curtailment_rate, best_metrics.flexible_ratio, best_metrics.total_annual_cost];

% HDF5 结果文件
h5file = fullfile(RESULTS_DIR, 'Optimization_SC_2050_Res.h5');
if exist(h5file, 'file'), delete(h5file); end

h5create(h5file, '/res_scale', size(res_scale));
h5write(h5file, '/res_scale', res_scale);
h5create(h5file, '/prs', size(prs));
h5write(h5file, '/prs', prs);

% 指标向量: [curtailment_rate, flexible_ratio, vre_share, total_annual_cost]
% vre_share 严格定义：实际风光发电量 / 总发电量
metrics_vec = [best_metrics.curtailment_rate, best_metrics.flexible_ratio, ...
               best_metrics.vre_share, best_metrics.total_annual_cost];
h5create(h5file, '/metrics', size(metrics_vec));
h5write(h5file, '/metrics', metrics_vec);

% 成本分解向量
if strcmp(cost_cfg.COST_MODE, 'annualized_incremental')
    cost_bd_vec = [cb.vre_capex_billion, cb.incremental_vre_capex_billion, ...
                   cb.annualized_vre_capex_billion, cb.storage_capex_billion, ...
                   cb.incremental_storage_capex_billion, cb.annualized_storage_capex_billion, ...
                   cb.tx_capex_billion, cb.incremental_tx_capex_billion, ...
                   cb.annualized_tx_capex_billion, cb.vre_om_billion, ...
                   cb.storage_om_billion, cb.tx_om_billion, cb.flexible_opex_billion];
    cost_bd_names = {'vre_capex', 'incr_vre_capex', 'ann_vre_capex', ...
                     'storage_capex', 'incr_storage_capex', 'ann_storage_capex', ...
                     'tx_capex', 'incr_tx_capex', 'ann_tx_capex', ...
                     'vre_om', 'storage_om', 'tx_om', 'flexible_opex'};
else
    cost_bd_vec = [best_metrics.total_annual_cost];
    cost_bd_names = {'legacy_total'};
end
h5create(h5file, '/cost_breakdown', size(cost_bd_vec));
h5write(h5file, '/cost_breakdown', cost_bd_vec);

% 诊断向量
[diag_names, diag_values] = build_diagnostics_vector(best_metrics);
h5create(h5file, '/diagnostics', size(diag_values));
h5write(h5file, '/diagnostics', diag_values);

% exitflag
h5create(h5file, '/exitflag', [1, 1]);
h5write(h5file, '/exitflag', double(exitflag));

% 约束信息
h5create(h5file, '/constraint_values', size(acceptance.strict_constraint_values));
h5write(h5file, '/constraint_values', acceptance.strict_constraint_values);
h5create(h5file, '/max_constraint_violation', [1, 1]);
h5write(h5file, '/max_constraint_violation', acceptance.max_strict_violation);
h5create(h5file, '/is_feasible', [1, 1]);
h5write(h5file, '/is_feasible', double(acceptance.is_accepted));

h5create(h5file, '/is_strictly_feasible', [1, 1]);
h5write(h5file, '/is_strictly_feasible', double(acceptance.strict_is_feasible));
h5create(h5file, '/is_accepted', [1, 1]);
h5write(h5file, '/is_accepted', double(acceptance.is_accepted));
h5create(h5file, '/curtailment_acceptance_margin', [1, 1]);
h5write(h5file, '/curtailment_acceptance_margin', CURTAILMENT_ACCEPTANCE_MARGIN);
h5create(h5file, '/final_acceptance_curtailment_upper_bound', [1, 1]);
h5write(h5file, '/final_acceptance_curtailment_upper_bound', acceptance.final_acceptance_upper_bound);
h5create(h5file, '/strict_constraint_values', size(acceptance.strict_constraint_values));
h5write(h5file, '/strict_constraint_values', acceptance.strict_constraint_values);
h5create(h5file, '/acceptance_constraint_values', size(acceptance.acceptance_constraint_values));
h5write(h5file, '/acceptance_constraint_values', acceptance.acceptance_constraint_values);

% 指标版本标记
metrics_schema_version = 2;
vre_share_definition = 'actual_vre_generation_twh / total_generation_twh';
h5create(h5file, '/metrics_schema_version', [1, 1]);
h5write(h5file, '/metrics_schema_version', metrics_schema_version);

fprintf('结果已保存至 %s\n', h5file);

% Sidecar MAT 文件
matfile = fullfile(RESULTS_DIR, 'Optimization_SC_2050_metrics.mat');
save(matfile, ...
    'best_metrics', ...
    'cost_cfg', ...
    'scenario_cfg', ...
    'best_scale', ...
    'best_cost', ...
    'exitflag', ...
    'res_scale', ...
    'prs', ...
    'metrics_vec', ...
    'cost_bd_vec', ...
    'cost_bd_names', ...
    'diag_names', 'diag_values', ...
    'acceptance', ...
    'constraint_names', ...
    'CURTAILMENT_ACCEPTANCE_MARGIN', ...
    'feasibility', ...
    'metrics_schema_version', 'vre_share_definition' ...
);
fprintf('指标已保存至 %s\n', matfile);

%% ======================== 12. 关闭并行池 ========================
pool = gcp('nocreate');
if ~isempty(pool)
    delete(pool);
    fprintf('并行池已关闭\n');
end
