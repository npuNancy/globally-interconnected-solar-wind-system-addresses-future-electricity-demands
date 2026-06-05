% convert_h5_to_sel.m — 将优化结果 h5 文件转换为 Sel.mat 空间布局文件
%
% 功能：读取 Optimization_*_Res.h5 中的 Pareto 解，将决策向量映射回
%       180×360 全球空间格网，并提取储能/输电配置，供下一阶段优化使用。
%
% 用法：matlab -batch "year=2050; sol_idx=0; convert_h5_to_sel"
%
% 参数：
%   year     - 优化年份（2050/2040/2030）
%   sol_idx  - Pareto 解编号（0=按照情景约束自动选择 preferred solution）
%
% 输出：Opt_*_Sel.mat（包含 opt_solar, opt_wind, opt_stoPow, opt_stoCap, opt_trans）

if ~exist('year', 'var'), year = 2050; end
if ~exist('sol_idx', 'var'), sol_idx = 0; end

%% 加载共享 MATLAB 工具
script_dir = fileparts(mfilename('fullpath'));
addpath(fullfile(script_dir, '..', 'utils'));

%% 加载当前 SSP 情景配置
run('optimization_config.m');
switch year
    case 2050
        base_load_ratio = BASE_LOAD_RATIO_2050;
        min_vre_share = MIN_VRE_SHARE_2050;
        max_vre_share = MAX_VRE_SHARE_2050;
    case 2040
        base_load_ratio = BASE_LOAD_RATIO_2040;
        min_vre_share = MIN_VRE_SHARE_2040;
        max_vre_share = MAX_VRE_SHARE_2040;
    case 2030
        base_load_ratio = BASE_LOAD_RATIO_2030;
        min_vre_share = MIN_VRE_SHARE_2030;
        max_vre_share = MAX_VRE_SHARE_2030;
    otherwise
        error('year 必须为 2030、2040 或 2050');
end

fprintf('=== h5 转 Sel：year=%d, sol_idx=%d, base_load_ratio=%.3f ===\n', year, sol_idx, base_load_ratio);

%% 1. 确定文件名和前缀
switch year
    case 2050
        h5file = 'results/Optimization_SC_2050_Res.h5';
        selprefix = 'Opt_SC_2050';
    case 2040
        h5file = 'results/Optimization_SC_2040_Res.h5';
        selprefix = 'Opt_SC_2040';
    case 2030
        h5file = 'results/Optimization_SA_2030_Res.h5';
        selprefix = 'Opt_SA_2030';
    otherwise
        error('year 必须为 2030、2040 或 2050');
end

%% 2. 读取 Pareto 结果
res_scale = h5read(h5file, '/res_scale');  % 决策向量矩阵
prs = h5read(h5file, '/prs');               % 目标函数值矩阵
n_solutions = size(res_scale, 1);
nvars_total = size(res_scale, 2);
fprintf('已加载 %d 个解（%d 个变量）\n', n_solutions, nvars_total);

%% 3. Pareto 前沿概览（先打印所有解信息，再选择 preferred solution）
fprintf('\n=== Pareto 前沿（%d 个解，基荷比例=%.1f%%） ===\n', n_solutions, base_load_ratio*100);
fprintf('%5s %10s %12s %12s %12s %12s\n', '编号', '弃电率', '风光渗透率', '总覆盖率', '灵活电源', '成本(十亿$)');
for i = 1:n_solutions
    flexible_ratio = prs(i, 2);
    total_coverage_ratio = 1 - flexible_ratio;
    solar_wind_penetration = 1 - base_load_ratio - flexible_ratio;
    fprintf('%5d %10.4f %12.4f %12.4f %12.4f %12.1f\n', ...
        i, prs(i,1), solar_wind_penetration, total_coverage_ratio, flexible_ratio, prs(i,3));
end

%% 4. 选择 preferred solution
if sol_idx == 0
    selection = select_preferred_solution( ...
        prs, ...
        base_load_ratio, ...
        min_vre_share, ...
        max_vre_share, ...
        MAX_CURTAILMENT, ...
        SELECTION_MODE ...
    );

    sol_idx = selection.sol_idx;
else
    % 手动指定解时仍然计算并保存对应指标
    flexible_ratio_manual = prs(sol_idx, 2);

    selection = struct();
    selection.status = 'manual';
    selection.sol_idx = sol_idx;
    selection.curtailment = prs(sol_idx, 1);
    selection.flexible_ratio = flexible_ratio_manual;
    selection.vre_share = 1 - base_load_ratio - flexible_ratio_manual;
    selection.cost = prs(sol_idx, 3);
    selection.min_vre_share = min_vre_share;
    selection.max_vre_share = max_vre_share;
    selection.max_curtailment = MAX_CURTAILMENT;
    selection.selection_mode = SELECTION_MODE;
end

% 若无合格解，直接报错退出（不保存 Sel.mat）
if strcmp(selection.status, 'no_qualified_solution')
    fprintf('\n⚠ 警告：当前 Pareto 前沿不存在合格 preferred solution，不保存 Sel.mat\n');
    error('当前 Pareto 前沿不存在合格 preferred solution，流水线停止');
end

scale = res_scale(sol_idx, :);

fprintf('解 %d：弃电率=%.4f, 风光渗透率=%.4f, 灵活电源比例=%.4f, 成本=%.1f 十亿美元\n', ...
    selection.sol_idx, ...
    selection.curtailment, ...
    selection.vre_share, ...
    selection.flexible_ratio, ...
    selection.cost ...
);

%% 4. 重建候选格网索引

% --- 光伏完整候选列表（与 Optimization_SC_2050.m 相同的筛选逻辑） ---
grids = geotiffread('Global_fishnet.tif');
solar_index_all = find(grids < 65536);

load Global_Solar_CFs
res_CF_scaled = res_CF / 10 / 1000;
clear res_CF

luccs = geotiffread('Global_Solar_Net_Area_Add_Egrid.tif');
luccs = luccs / 100;
fish_area = geotiffread('Global_Solar_Fishnet_Area.tif');
fish_area(fish_area < 0) = 0;
fish_area = double(fish_area);
areas = luccs(solar_index_all) .* fish_area(solar_index_all);
clear luccs fish_area

% 计算装机容量
pv_density = compute_pv_density(solar_index_all);
solar_ins = zeros(length(solar_index_all), 1);
for ii = 1:length(solar_index_all)
    solar_ins(ii) = (pv_density(ii) * areas(ii)) / 1e6;  % pv_density MW/km² → TWp
end

% 筛选：装机容量 > 0.001 TWp
tmp = solar_ins > 0.001;
tmp_idx = find(tmp);
solar_index_f = solar_index_all(tmp);
areas_solar_f = areas(tmp);

% 计算发电量并筛选：年发电量 < 90 TWh
pv_density_f = compute_pv_density(solar_index_f);
solar_gen_f = zeros(sum(tmp), 8760);
for ii = 1:sum(tmp)
    solar_gen_f(ii,:) = res_CF_scaled(tmp_idx(ii), :) * (pv_density_f(ii) * areas_solar_f(ii)) / 1e6;
end
clear pv_density_f
clear res_CF_scaled
annual_gen_solar = sum(solar_gen_f, 2);

tmp3 = annual_gen_solar < 90;
solar_index = solar_index_f(tmp3);
clear solar_gen_f annual_gen_solar areas_solar_f solar_ins solar_index_f solar_index_all areas pv_density
fprintf('2050年光伏候选格网：%d 个\n', length(solar_index));

% --- 风电完整候选列表 ---
luccs = geotiffread('Global_Wind_Net_Area_Add_Egrid.tif');
luccs = luccs / 100;
win_index_all = find(luccs > 0);
fish_area = geotiffread('Global_Wind_Fishnet_Area.tif');
fish_area = double(fish_area);
areas = luccs(win_index_all) .* fish_area(win_index_all);
landmask = readgeoraster('Global_LandMask.tif');
landmask(landmask < 100) = 0; landmask(landmask > 100) = 1;
landmask = landmask(win_index_all);

% 装机容量：陆上 3.68 MW/km²，海上 6.07 MW/km²
wind_ins = (3.68 * areas) / 1e6;
wind_ins(landmask == 1) = (6.07 * areas(landmask == 1)) / 1e6;

wind_gen_all = h5read('Global_Wind_CFs_Sel.h5', '/data');

% 筛选：装机容量 > 0.0001 TWp
tmp = wind_ins > 0.0001;
wind_ins_f = wind_ins(tmp);
wind_gen_f = wind_gen_all(tmp, :);
win_index_f = win_index_all(tmp);

for ii = 1:length(wind_ins_f)
    wind_gen_f(ii,:) = wind_gen_f(ii,:) * wind_ins_f(ii);
end
annual_gen_wind = sum(wind_gen_f, 2);

% 筛选：年发电量 < 10 TWh
tmp3 = annual_gen_wind < 10;
win_index = win_index_f(tmp3);
clear luccs fish_area areas landmask wind_ins wind_gen_all wind_gen_f wind_ins_f win_index_all win_index_f annual_gen_wind
fprintf('2050年风电候选格网：%d 个\n', length(win_index));

%% 5. 对于 2040/2030，应用上一阶段 Sel 进行预筛选
if year ~= 2050
    if year == 2040
        load('results/Opt_SC_2050_Sel.mat', 'opt_wind', 'opt_solar');  % 2050选中结果
    else
        load('results/Opt_SC_2040_Sel.mat', 'opt_wind', 'opt_solar');  % 2040选中结果
    end

    % 光伏：从完整2050候选中筛选上一阶段选中的格网
    [~, pos_s] = ismember(find(opt_solar == 1), solar_index);
    valid_s = pos_s > 0;
    solar_index = solar_index(pos_s(valid_s));
    N_solar = length(solar_index);

    % 风电：从完整2050候选中筛选上一阶段选中的格网
    [~, pos_w] = ismember(find(opt_wind == 1), win_index);
    valid_w = pos_w > 0;
    win_index = win_index(pos_w(valid_w));
    N_wind = length(win_index);

    fprintf('预筛选后：光伏=%d，风电=%d\n', N_solar, N_wind);
    clear opt_solar opt_wind pos_s pos_w valid_s valid_w
else
    N_solar = length(solar_index);
    N_wind = length(win_index);
end

N_grid = N_solar + N_wind;
fprintf('格网变量总数：%d，变量总数：%d\n', N_grid, nvars_total);

%% 6. 从决策向量提取各分量
solar_sel = round(scale(1:N_solar));           % 光伏选址（0/1）
wind_sel  = round(scale(N_solar+1:N_grid));    % 风电选址（0/1）
opt_stoPow = scale(N_grid+1:N_grid+20);        % 储能功率（GW）
opt_stoCap = scale(N_grid+21:N_grid+40);       % 储能时长（小时）

fprintf('光伏选中：%d / %d\n', sum(solar_sel), N_solar);
fprintf('风电选中：%d / %d\n', sum(wind_sel), N_wind);
fprintf('储能功率（GW）：[%s]\n', num2str(round(opt_stoPow)));
fprintf('储能时长（h）：[%s]\n', num2str(round(opt_stoCap)));

%% 7. 映射回 180×360 空间格网
opt_solar = zeros(180, 360);
opt_wind  = zeros(180, 360);
opt_solar(solar_index(solar_sel == 1)) = 1;  % 将选中格网标记为1
opt_wind(win_index(wind_sel == 1)) = 1;
fprintf('opt_solar 非零数=%d, opt_wind 非零数=%d\n', nnz(opt_solar), nnz(opt_wind));

%% 8. 提取传输容量（复制优化脚本的拓扑逻辑）
load Global_Init_State.mat cur_storage cur_trans
load Global_Trans trans_connections trans_loss

% 清零跨洲连接（大陆互联模式）
cur_trans(6,1)=0;cur_trans(7,1)=0;cur_trans(1,6)=0;cur_trans(1,7)=0;
cur_trans(17,4)=0;cur_trans(18,4)=0;cur_trans(4,17)=0;cur_trans(4,18)=0;

% 拓扑过滤：移除洲际连接（S-C 模式）
if year == 2050
    trans_connections(trans_connections==2)=0;
else
    trans_connections(trans_connections==2)=0;
end

tmp = cur_trans > 0;
cur_trans(cur_trans < 2) = 0;
trans_mask = tmp;
n_trans = sum(tmp(:));
fprintf('输电链路：%d 条有效连接，决策向量包含 %d 个输电变量\n', ...
    n_trans, length(scale)-N_grid-40);

% 将决策向量中的输电容量映射回 20×20 矩阵
trans_values = scale(N_grid+41:end);
opt_trans = zeros(20, 20);
opt_trans(trans_mask) = trans_values;
fprintf('opt_trans 非零数=%d\n', nnz(opt_trans));

%% 9. 保存
if ~exist('results', 'dir'), mkdir('results'); end; outfile = ['results/' selprefix '_Sel.mat'];
preferred_sol_idx = selection.sol_idx;
preferred_selection_status = selection.status;
preferred_curtailment = selection.curtailment;
preferred_vre_share = selection.vre_share;
preferred_flexible_ratio = selection.flexible_ratio;
preferred_cost = selection.cost;
preferred_min_vre_share = selection.min_vre_share;
preferred_max_vre_share = selection.max_vre_share;
preferred_max_curtailment = selection.max_curtailment;
preferred_selection_mode = selection.selection_mode;
preferred_scenario_name = SCENARIO_NAME;
preferred_base_load_ratio = base_load_ratio;

save(outfile, ...
    'opt_solar', ...
    'opt_wind', ...
    'opt_stoPow', ...
    'opt_stoCap', ...
    'opt_trans', ...
    'preferred_sol_idx', ...
    'preferred_selection_status', ...
    'preferred_curtailment', ...
    'preferred_vre_share', ...
    'preferred_flexible_ratio', ...
    'preferred_cost', ...
    'preferred_min_vre_share', ...
    'preferred_max_vre_share', ...
    'preferred_max_curtailment', ...
    'preferred_selection_mode', ...
    'preferred_scenario_name', ...
    'preferred_base_load_ratio' ...
);
fprintf('\n已保存 %s\n', outfile);
