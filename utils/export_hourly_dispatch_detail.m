function export_hourly_dispatch_detail(year, scenario_dir)
% EXPORT_HOURLY_DISPATCH_DETAIL — 从 best_scale replay 得到逐小时能源流并导出
%
% 用法：
%   export_hourly_dispatch_detail(2050, 'Optimization_ssp245')
%
% 也可在 SSP 目录内调用（scenario_dir 缺省为当前目录）：
%   year = 2050; export_hourly_dispatch_detail
%
% 输入：
%   year         - 年份（2050 / 2040 / 2030）
%   scenario_dir - SSP 场景目录（相对于项目根目录）
%
% 输出：
%   <scenario_dir>/results/hourly/hourly_dispatch_<year>.mat
%   <scenario_dir>/results/hourly/hourly_dispatch_<year>.csv

if nargin < 1
    if ~exist('year', 'var')
        error('必须提供 year 参数');
    end
end
if nargin < 2
    scenario_dir = pwd;
end

fprintf('=== export_hourly_dispatch_detail: year=%d, dir=%s ===\n', year, scenario_dir);

%% ======================== 1. 确定文件路径 ========================
if strncmp(scenario_dir, '/', 1) || strncmp(scenario_dir, '~', 1)
    base_dir = scenario_dir;
else
    % 相对于项目根目录
    this_dir = fileparts(mfilename('fullpath'));
    proj_root = fullfile(this_dir, '..');
    base_dir = fullfile(proj_root, scenario_dir);
end

% 查找包含该年份 HDF5 的 results 子目录
results_root = fullfile(base_dir, 'results');

% 年份对应的文件名模板
if year == 2050
    h5_name = 'Optimization_SC_2050_Res.h5';
    md_name = 'model_data_2050.mat';
elseif year == 2040
    h5_name = 'Optimization_SC_2040_Res.h5';
    md_name = 'model_data_2040.mat';
elseif year == 2030
    h5_name = 'Optimization_SA_2030_Res.h5';
    md_name = 'model_data_2030.mat';
else
    error('不支持的年份: %d', year);
end

% 在 results_root 及其子目录中搜索 HDF5 和 model_data
h5file = '';
matfile = '';

% 先检查 results_root 本身
if exist(fullfile(results_root, h5_name), 'file')
    h5file = fullfile(results_root, h5_name);
end
if exist(fullfile(results_root, md_name), 'file')
    matfile = fullfile(results_root, md_name);
end

% 再检查 results_* 子目录（按名称倒序）
if isempty(h5file) || isempty(matfile)
    subdirs = dir(fullfile(results_root, 'results_*'));
    subdirs = subdirs([subdirs.isdir]);
    names = {subdirs.name};
    [sorted_names, idx] = sort(names);
    idx = flipud(idx);
    for ii = 1:length(idx)
        sd = fullfile(results_root, subdirs(idx(ii)).name);
        if isempty(h5file) && exist(fullfile(sd, h5_name), 'file')
            h5file = fullfile(sd, h5_name);
        end
        if isempty(matfile) && exist(fullfile(sd, md_name), 'file')
            matfile = fullfile(sd, md_name);
        end
        if ~isempty(h5file) && ~isempty(matfile)
            break
        end
    end
end

% 也检查 failed 子目录
if isempty(h5file) || isempty(matfile)
    failed_dir = fullfile(results_root, 'failed');
    if exist(failed_dir, 'dir')
        if isempty(h5file) && exist(fullfile(failed_dir, h5_name), 'file')
            h5file = fullfile(failed_dir, h5_name);
        end
        if isempty(matfile) && exist(fullfile(failed_dir, md_name), 'file')
            matfile = fullfile(failed_dir, md_name);
        end
    end
end

if isempty(h5file)
    error('找不到 HDF5 结果文件: %s (在 %s 及其子目录中)', h5_name, results_root);
end
if isempty(matfile)
    error('找不到 model_data 文件: %s (在 %s 及其子目录中)', md_name, results_root);
end

fprintf('HDF5: %s\n', h5file);
fprintf('model_data: %s\n', matfile);

%% ======================== 2. 加载数据 ========================
% 读取 best_scale
best_scale = h5read(h5file, '/res_scale');
fprintf('best_scale 长度: %d\n', length(best_scale));

% 加载 model_data
md = load(matfile, 'model_data');
model_data = md.model_data;

ins_cap     = model_data.ins_cap;
gens        = model_data.gens;
loads       = model_data.loads;
CGrid_Index = model_data.CGrid_Index;
nonlsol     = model_data.nonlsol;

fprintf('候选格网数: %d (PV=%d, Wind=%d)\n', ...
    length(ins_cap), nonlsol, length(ins_cap) - nonlsol);

% 加载场景配置（从 metrics MAT 文件）
if year == 2050
    metrics_mat = fullfile(results_dir, 'Optimization_SC_2050_metrics.mat');
elseif year == 2040
    metrics_mat = fullfile(results_dir, 'Optimization_SC_2040_metrics.mat');
else
    metrics_mat = fullfile(results_dir, 'Optimization_SA_2030_metrics.mat');
end

if exist(metrics_mat, 'file')
    m = load(metrics_mat, 'scenario_cfg');
    scenario_cfg = m.scenario_cfg;
    fprintf('从 metrics 文件加载 scenario_cfg\n');
else
    % 从 optimization_config 重建
    fprintf('未找到 metrics 文件，尝试从 optimization_config 重建\n');
    orig_dir = pwd;
    cd(base_dir);
    run('optimization_config.m');
    cd(orig_dir);
    if year == 2050
        scenario_cfg = struct( ...
            'base_load_ratio', BASE_LOAD_RATIO_2050, ...
            'interconnection_mode', 'S-C');
    elseif year == 2040
        scenario_cfg = struct( ...
            'base_load_ratio', BASE_LOAD_RATIO_2040, ...
            'interconnection_mode', 'S-C');
    else
        scenario_cfg = struct( ...
            'base_load_ratio', BASE_LOAD_RATIO_2030, ...
            'interconnection_mode', 'S-A');
    end
end

base_load_ratio = scenario_cfg.base_load_ratio;
interconnection_mode = scenario_cfg.interconnection_mode;

fprintf('base_load_ratio: %.4f\n', base_load_ratio);
fprintf('interconnection_mode: %s\n', interconnection_mode);

% 成本配置
cost_cfg = cost_model_config();

% 确保 base workspace 有 trans_connections / trans_loss
% evaluate_dispatch_and_cost 内部执行 load Global_Trans trans_connections trans_loss
% 需要当前目录或 base workspace 能找到这些变量
trans_file = fullfile(base_dir, 'Global_Trans.mat');
if exist(trans_file, 'file')
    trans_data = load(trans_file);
    assignin('base', 'trans_connections', trans_data.trans_connections);
    assignin('base', 'trans_loss', trans_data.trans_loss);
    % 也在当前函数 workspace 可用
    trans_connections = trans_data.trans_connections;
    trans_loss = trans_data.trans_loss;
    fprintf('已加载 Global_Trans 变量\n');
else
    error('找不到 Global_Trans.mat: %s', trans_file);
end

% 添加路径以确保 findAllPathsFromStart 等可用
addpath(fullfile(fileparts(mfilename('fullpath'))));  % utils/
addpath(base_dir);  % SSP 目录

% 保存当前目录并切换到 SSP 目录（evaluate_dispatch_and_cost 内部 load Global_Trans 需要）
orig_pwd = pwd;
cd(base_dir);

%% ======================== 3. 调用 dispatch 获取 detail ========================
fprintf('\n正在 replay dispatch...\n');
[metrics, detail] = evaluate_dispatch_and_cost(ins_cap, gens, loads, ...
    CGrid_Index, best_scale, base_load_ratio, ...
    interconnection_mode, cost_cfg, nonlsol);

fprintf('VRE 渗透率: %.4f\n', metrics.vre_share);
fprintf('弃电率: %.4f\n', metrics.curtailment_rate);
fprintf('总成本: %.2f billion USD/year\n', metrics.total_annual_cost);

%% ======================== 4. 年度总量回归校验 ========================
fprintf('\n=== 年度总量回归校验 ===\n');

raw_vre_sum = sum(detail.raw_vre_generation_twh_hourly);
fprintf('sum(raw_vre_twh) = %.6f, metrics.gross_vre = %.6f, diff = %.2e\n', ...
    raw_vre_sum, metrics.gross_vre_generation_twh, ...
    raw_vre_sum - metrics.gross_vre_generation_twh);

curt_sum = sum(detail.curtailment_twh_hourly);
fprintf('sum(curtailment_twh) = %.6f, metrics.curtailed = %.6f, diff = %.2e\n', ...
    curt_sum, metrics.curtailed_vre_twh, curt_sum - metrics.curtailed_vre_twh);

flex_sum = sum(detail.flexible_generation_twh_hourly);
fprintf('sum(flexible_twh) = %.6f, metrics.flexible = %.6f, diff = %.2e\n', ...
    flex_sum, metrics.flexible_generation_twh, flex_sum - metrics.flexible_generation_twh);

base_sum = sum(detail.base_generation_twh_hourly);
fprintf('sum(base_twh) = %.6f, metrics.base = %.6f, diff = %.2e\n', ...
    base_sum, metrics.base_generation_twh, base_sum - metrics.base_generation_twh);

load_sum = sum(detail.load_twh_hourly);
fprintf('sum(load_twh) = %.6f, metrics.total_load = %.6f, diff = %.2e\n', ...
    load_sum, metrics.total_load_twh, load_sum - metrics.total_load_twh);

% 供电平衡校验
supply_sum = sum(detail.actual_vre_generation_twh_hourly) ...
    + sum(detail.storage_discharge_twh_hourly) ...
    + base_sum + flex_sum;
fprintf('supply_total = %.6f, load_total = %.6f, diff = %.2e\n', ...
    supply_sum, load_sum, supply_sum - load_sum);

%% ======================== 5. 构建输出表格 ========================
% 时间字段
hour_index = (1:8760)';
month = zeros(8760, 1);
day_of_year = zeros(8760, 1);
hour_of_day = zeros(8760, 1);
for h = 1:8760
    % 假设从1月1日0时开始
    day_of_year(h) = floor((h - 1) / 24) + 1;
    hour_of_day(h) = mod(h - 1, 24);
end
% 简化月份计算（每月按实际天数）
days_in_month = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
cum_days = cumsum([0, days_in_month]);
for h = 1:8760
    d = day_of_year(h);
    for m = 12:-1:1
        if d > cum_days(m)
            month(h) = m;
            break;
        end
    end
end

T = table( ...
    hour_index, ...
    month, ...
    day_of_year, ...
    hour_of_day, ...
    detail.load_twh_hourly', ...
    detail.raw_vre_generation_twh_hourly', ...
    detail.actual_vre_generation_twh_hourly', ...
    detail.storage_discharge_twh_hourly', ...
    detail.base_generation_twh_hourly', ...
    detail.flexible_generation_twh_hourly', ...
    detail.curtailment_twh_hourly', ...
    detail.storage_charge_twh_hourly', ...
    'VariableNames', {'hour', 'month', 'day_of_year', 'hour_of_day', ...
        'load_twh', 'raw_vre_twh', 'actual_vre_twh', 'storage_discharge_twh', ...
        'base_twh', 'flexible_twh', 'curtailment_twh', 'storage_charge_twh'});

%% ======================== 6. 导出文件 ========================
out_dir = fullfile(results_dir, 'hourly');
if ~exist(out_dir, 'dir'), mkdir(out_dir); end

% MAT 文件
mat_out = fullfile(out_dir, sprintf('hourly_dispatch_%d.mat', year));
detail_with_meta = detail;
detail_with_meta.year = year;
detail_with_meta.base_load_ratio = base_load_ratio;
detail_with_meta.interconnection_mode = interconnection_mode;
detail_with_meta.annual_metrics = metrics;
save(mat_out, 'detail_with_meta', 'T');
fprintf('\nMAT 已保存: %s\n', mat_out);

% CSV 文件
csv_out = fullfile(out_dir, sprintf('hourly_dispatch_%d.csv', year));
writetable(T, csv_out);
fprintf('CSV 已保存: %s\n', csv_out);

fprintf('\n=== export_hourly_dispatch_detail 完成 ===\n');

% 恢复原始工作目录
cd(orig_pwd);

end
