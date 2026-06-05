%% Optimization_SA_2030.m — 2030年 SSP5-6.0 成本最小化优化（邻近互联 S-A）
%
% 功能：使用 GA（ga）单目标优化，求解2030年全球20个区域的光伏/风电场站
%       空间选址、储能配置和跨区输电容量的成本最小化方案。
%
% 与2040年的嵌套关系：
%   - 候选格网由2040年优化结果（results/Opt_SC_2040_Sel.mat）约束
%   - 储能功率/时长/输电容量的上界由2040年结果约束
%
% 情景假设（AR6 SSP5-6.0）：
%   - 全球电力需求：40,483 TWh
%   - 基荷发电占比：78.8%（非可再生能源调度份额）
%   - 互联模式：邻近互联（S-A），仅允许相邻区域间输电（maxNodes=2）
%
% 优化目标：
%   minimize: 风光扩张年度化增量系统成本（billion USD/year）
%
% 约束：
%   - MIN_VRE_SHARE <= 风光渗透率 <= MAX_VRE_SHARE
%   - 风电既有装机约束：允许 ALLOWED_UNMET_WIND_REGIONS_2030=8 个区域不满足
%   - 光伏既有装机约束：所有区域必须满足
%
% 输出：
%   results/Optimization_SA_2030_Res.h5
%   results/Optimization_SA_2030_metrics.mat

clear, clc
run('optimization_config.m');

% 加载共享工具和成本配置
script_dir = fileparts(mfilename('fullpath'));
addpath(fullfile(script_dir, '..', 'utils'));
addpath(script_dir);
cost_cfg = cost_model_config();

%% ======================== 1. 启动并行计算池 ========================
try
    pool = parpool('local');
    fprintf('并行池已启动：%d 个工作节点\n', pool.NumWorkers);
catch ME
    if contains(ME.identifier, 'parallel:pool:alreadyopen')
        pool = gcp('nocreate');
        fprintf('并行池已在运行：%d 个工作节点\n', pool.NumWorkers);
    else
        warning('并行池启动失败：%s', ME.message);
    end
end

%% ======================== 2. 加载2040年优化结果（约束候选格网） ========================
load results/Opt_SC_2040_Sel opt_trans opt_stoCap opt_stoPow opt_wind opt_solar

%% ======================== 3. 构建风电候选格网（受2040约束） ========================
luccs = geotiffread('Global_Wind_Net_Area_Add_Egrid.tif');
luccs = luccs / 100;
win_index = find(luccs > 0);
fish_area = geotiffread('Global_Wind_Fishnet_Area.tif');
fish_area = double(fish_area);
areas = luccs(win_index) .* fish_area(win_index);
landmask = readgeoraster('Global_LandMask.tif');
landmask(landmask<100) = 0; landmask(landmask>100) = 1;
landmask = landmask(win_index);
wind_ins = (3.68 * areas) / 1000 / 1000;
wind_ins(landmask==1) = (6.07 * areas(landmask==1)) / 1000 / 1000;
wind_gen = h5read('Global_Wind_CFs_Sel.h5', '/data');
for ii = 1:8477
    wind_gen(ii,:) = wind_gen(ii,:) * wind_ins(ii);
end
clear areas fish_area luccs

% 预筛选：仅保留2040年选中的风电格网
win_index2 = find(opt_wind == 1);
[~, loc] = ismember(win_index2, win_index);
wind_ins = wind_ins(loc); wind_gen = wind_gen(loc,:); win_index = win_index(loc);
clear win_index2

%% ======================== 4. 构建光伏候选格网（受2040约束） ========================
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

% 预筛选：仅保留2040年选中的光伏格网
solar_index2 = find(opt_solar == 1);
[~, loc] = ismember(solar_index2, solar_index);
solar_ins = solar_ins(loc); solar_gen = solar_gen(loc,:); solar_index = solar_index(loc);
clear areas fish_area luccs grids solar_index2 loc

%% ======================== 5. 合并光伏/风电数据 ========================
all_gens = [solar_gen; wind_gen];
all_ins  = [solar_ins; wind_ins];
clear solar_gen wind_gen
clear solar_ins wind_ins

%% ======================== 6. 加载2030年负荷数据 ========================
% SSP5-6.0 对应第2个情景维度（索引=2）
load Global_Load_22region.mat
all_loads = squeeze(all_loads(2,:,:)) / 1000 / 1000;
global_load = sum(all_loads, 1);
all_loads = all_loads / (sum(global_load(:)) / DEMAND_2030);
clear global_load

%% ======================== 7. 构建区域索引和约束数据 ========================
[grid_ind, R] = readgeoraster('Global_Grid_Division.tif');
CGrid_Index = [grid_ind(solar_index); grid_ind(win_index)];
nonlcon_sel = CGrid_Index; nonlcon_ins = all_ins;
nonlsol = length(solar_index); nonlwin = length(win_index);
save NonlConData2030 nonlcon_sel nonlcon_ins nonlsol nonlwin
clear nonlcon_sel nonlcon_ins nonlsol nonlwin
landmask = readgeoraster('Global_LandMask.tif');
landmask(landmask<100) = 0; landmask(landmask>100) = 1;
landmask = landmask(win_index);
CGrid_Index(length(solar_index)+1 : length(solar_index)+length(win_index), 3) = landmask;
clear grid_ind R landmask

%% ======================== 8. 设置优化变量与约束 ========================
rng default
nvars = length(CGrid_Index);
load Global_Init_State.mat cur_storage cur_trans

lb = zeros(1, nvars);
ub = ones(1, nvars);

% 储能功率：下界=当前已有，上界=2040年配置（受约束）
lb(nvars+1:nvars+20) = cur_storage / 1000;
ub(nvars+1:nvars+20) = opt_stoPow;   % GW
clear cur_storage

% 储能时长：下界=2h，上界=2040年配置（受约束）
lb(nvars+21:nvars+40) = 2;
ub(nvars+21:nvars+40) = opt_stoCap;  % 小时

% 输电容量：清零跨洲链路下界
cur_trans(6,1)=0; cur_trans(7,1)=0; cur_trans(1,6)=0; cur_trans(1,7)=0;
cur_trans(17,4)=0; cur_trans(18,4)=0; cur_trans(4,17)=0; cur_trans(4,18)=0;
tmp = cur_trans > 0;
cur_trans(cur_trans < 2) = 0;
lb(nvars+41:nvars+40+sum(tmp(:))) = cur_trans(tmp) / 1000;
ub(nvars+41:nvars+40+sum(tmp(:))) = opt_trans(tmp);   % 上界=2040年输电配置（GW）
clear cur_trans
nvars = length(lb);
intcon = 1:1:length(lb);

%% ======================== 9. 构建成本与情景配置 ========================
scenario_cfg = struct( ...
    'base_load_ratio',            BASE_LOAD_RATIO_2030, ...
    'interconnection_mode',       'S-A', ...
    'min_vre_share',              MIN_VRE_SHARE_2030, ...
    'max_vre_share',              MAX_VRE_SHARE_2030, ...
    'allowed_unmet_wind_regions', ALLOWED_UNMET_WIND_REGIONS_2030 ...
);

% 预加载非线性约束所需的持久数据
load NonlConData2030.mat nonlcon_sel nonlcon_ins nonlsol nonlwin
load Global_Init_State cur_solar cur_wind
cur_solar = cur_solar / 1e6;  % MWp → TWp
cur_wind  = cur_wind  / 1e6;

% 封装为 struct
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

% 保存模型数据供独立使用
if ~exist('results', 'dir'), mkdir('results'); end
save('results/model_data_2030.mat', 'model_data', 'persistent_data');

%% ======================== 10. 运行 GA 单目标优化 ========================
T = datetime('now');
disp(T);
fprintf('开始2030年成本最小化优化（邻近互联，种群=%d，代数=%d）...\n', ...
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
    'Display',           'iter');

[best_scale, best_cost, exitflag, output] = ga( ...
    @(scale) objective_total_cost(scale, all_ins, all_gens, all_loads, ...
        CGrid_Index, scenario_cfg.base_load_ratio, ...
        scenario_cfg.interconnection_mode, cost_cfg, nonlsol), ...
    nvars, ...
    [], [], [], [], ...
    lb, ub, ...
    @nonlcon2030, ...
    intcon, ...
    options);

T = datetime('now');
disp(T);
fprintf('优化完成，exitflag=%d，最优成本=%.2f\n', exitflag, best_cost);

%% ======================== 11. 评估最优解指标 ========================
best_metrics = evaluate_dispatch_and_cost(all_ins, all_gens, all_loads, ...
    CGrid_Index, best_scale, scenario_cfg.base_load_ratio, ...
    scenario_cfg.interconnection_mode, cost_cfg, nonlsol);

fprintf('\n=== 最优解指标 ===\n');
fprintf('弃电率:        %.4f\n', best_metrics.curtailment_rate);
fprintf('灵活电源比例:  %.4f\n', best_metrics.flexible_ratio);
fprintf('风光渗透率:    %.4f\n', best_metrics.vre_share);
fprintf('VRE 约束区间:  [%.4f, %.4f]\n', scenario_cfg.min_vre_share, scenario_cfg.max_vre_share);
fprintf('年度总成本:    %.2f billion USD/year\n', best_metrics.total_annual_cost);
fprintf('输电容量:      %.4f TW\n', best_metrics.transmission_capacity_TW);

cb = best_metrics.cost_breakdown;
fprintf('\n=== 成本分解 ===\n');
if strcmp(cost_cfg.COST_MODE, 'annualized_incremental')
    fprintf('VRE CAPEX (总):           %.2f billion USD\n', cb.vre_capex_billion);
    fprintf('VRE CAPEX (增量):         %.2f billion USD\n', cb.incremental_vre_capex_billion);
    fprintf('VRE CAPEX (年度化):       %.2f billion USD/year\n', cb.annualized_vre_capex_billion);
    fprintf('储能 CAPEX (总):          %.2f billion USD\n', cb.storage_capex_billion);
    fprintf('储能 CAPEX (增量):        %.2f billion USD\n', cb.incremental_storage_capex_billion);
    fprintf('储能 CAPEX (年度化):      %.2f billion USD/year\n', cb.annualized_storage_capex_billion);
    fprintf('输电 CAPEX (总):          %.2f billion USD\n', cb.tx_capex_billion);
    fprintf('输电 CAPEX (增量):        %.2f billion USD\n', cb.incremental_tx_capex_billion);
    fprintf('输电 CAPEX (年度化):      %.2f billion USD/year\n', cb.annualized_tx_capex_billion);
    fprintf('VRE O&M:                  %.2f billion USD/year\n', cb.vre_om_billion);
    fprintf('储能 O&M:                 %.2f billion USD/year\n', cb.storage_om_billion);
    fprintf('输电 O&M:                 %.2f billion USD/year\n', cb.tx_om_billion);
    fprintf('灵活电源 OPEX:            %.2f billion USD/year\n', cb.flexible_opex_billion);
else
    fprintf('VRE + 储能 + 输电总成本:  %.2f billion USD\n', best_metrics.total_annual_cost);
end

%% ======================== 12. 保存结果 ========================
if ~exist('results', 'dir'), mkdir('results'); end

res_scale = best_scale(:)';
prs = [best_metrics.curtailment_rate, best_metrics.flexible_ratio, best_metrics.total_annual_cost];

h5file = 'results/Optimization_SA_2030_Res.h5';
if exist(h5file, 'file'), delete(h5file); end

h5create(h5file, '/res_scale', size(res_scale));
h5write(h5file, '/res_scale', res_scale);
h5create(h5file, '/prs', size(prs));
h5write(h5file, '/prs', prs);

metrics_vec = [best_metrics.curtailment_rate, best_metrics.flexible_ratio, ...
               best_metrics.vre_share, best_metrics.total_annual_cost];
h5create(h5file, '/metrics', size(metrics_vec));
h5write(h5file, '/metrics', metrics_vec);

if strcmp(cost_cfg.COST_MODE, 'annualized_incremental')
    cost_bd_vec = [cb.vre_capex_billion, cb.incremental_vre_capex_billion, ...
                   cb.annualized_vre_capex_billion, cb.storage_capex_billion, ...
                   cb.incremental_storage_capex_billion, cb.annualized_storage_capex_billion, ...
                   cb.tx_capex_billion, cb.incremental_tx_capex_billion, ...
                   cb.annualized_tx_capex_billion, cb.vre_om_billion, ...
                   cb.storage_om_billion, cb.tx_om_billion, cb.flexible_opex_billion];
else
    cost_bd_vec = [best_metrics.total_annual_cost];
end
h5create(h5file, '/cost_breakdown', size(cost_bd_vec));
h5write(h5file, '/cost_breakdown', cost_bd_vec);

fprintf('结果已保存至 %s\n', h5file);

matfile = 'results/Optimization_SA_2030_metrics.mat';
save(matfile, ...
    'best_metrics', 'cost_cfg', 'scenario_cfg', ...
    'best_scale', 'best_cost', 'exitflag', ...
    'res_scale', 'prs', 'metrics_vec', 'cost_bd_vec' ...
);
fprintf('指标已保存至 %s\n', matfile);

%% ======================== 13. 关闭并行池 ========================
pool = gcp('nocreate');
if ~isempty(pool)
    delete(pool);
    fprintf('并行池已关闭\n');
end
