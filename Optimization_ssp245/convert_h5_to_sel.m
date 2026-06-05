% convert_h5_to_sel.m — 将成本最小化优化结果转换为 Sel.mat 空间布局文件
%
% 功能：读取 Optimization_*_Res.h5 中的唯一最优解，校验 VRE 约束，
%       将决策向量映射回 180×360 全球空间格网，并提取储能/输电配置。
%
% 用法：matlab -batch "year=2050; convert_h5_to_sel"
%
% 参数：
%   year - 优化年份（2050/2040/2030）
%
% 输出：Opt_*_Sel.mat（包含 opt_solar, opt_wind, opt_stoPow, opt_stoCap, opt_trans）

if ~exist('year', 'var'), year = 2050; end

%% 加载共享工具和成本配置
script_dir = fileparts(mfilename('fullpath'));
addpath(fullfile(script_dir, '..', 'utils'));

%% 加载当前 SSP 情景配置
run('optimization_config.m');
cost_cfg = cost_model_config();

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

fprintf('=== costmin h5 转 Sel：year=%d, base_load_ratio=%.3f ===\n', year, base_load_ratio);

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

%% 2. 读取最优解
scale = h5read(h5file, '/res_scale');    % 1 × nvars
nvars_total = length(scale);
fprintf('已加载最优解（%d 个变量）\n', nvars_total);

% 读取指标
metrics_vec = h5read(h5file, '/metrics');
curtailment_rate = metrics_vec(1);
flexible_ratio   = metrics_vec(2);
vre_share        = metrics_vec(3);
total_annual_cost = metrics_vec(4);

% 读取成本分解
cost_bd = h5read(h5file, '/cost_breakdown');

%% 3. 校验 VRE 约束
fprintf('\n=== 最优解指标 ===\n');
fprintf('弃电率:        %.4f\n', curtailment_rate);
fprintf('灵活电源比例:  %.4f\n', flexible_ratio);
fprintf('风光渗透率:    %.4f\n', vre_share);
fprintf('VRE 约束区间:  [%.4f, %.4f]\n', min_vre_share, max_vre_share);
fprintf('年度总成本:    %.2f billion USD/year\n', total_annual_cost);

if vre_share < min_vre_share - 1e-6
    fprintf('⚠ 警告：VRE 渗透率 %.4f 低于下界 %.4f\n', vre_share, min_vre_share);
end
if vre_share > max_vre_share + 1e-6
    fprintf('⚠ 警告：VRE 渗透率 %.4f 高于上界 %.4f\n', vre_share, max_vre_share);
end

%% 4. 重建候选格网索引

% --- 光伏完整候选列表 ---
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

pv_density = compute_pv_density(solar_index_all);
solar_ins = zeros(length(solar_index_all), 1);
for ii = 1:length(solar_index_all)
    solar_ins(ii) = (pv_density(ii) * areas(ii)) / 1e6;
end

tmp = solar_ins > 0.001;
tmp_idx = find(tmp);
solar_index_f = solar_index_all(tmp);
areas_solar_f = areas(tmp);

pv_density_f = compute_pv_density(solar_index_f);
solar_gen_f = zeros(sum(tmp), 8760);
for ii = 1:sum(tmp)
    solar_gen_f(ii,:) = res_CF_scaled(tmp_idx(ii), :) * (pv_density_f(ii) * areas_solar_f(ii)) / 1e6;
end
clear pv_density_f res_CF_scaled
annual_gen_solar = sum(solar_gen_f, 2);

tmp3 = annual_gen_solar < 90;
solar_index = solar_index_f(tmp3);
clear solar_gen_f annual_gen_solar areas_solar_f solar_ins solar_index_f solar_index_all areas pv_density
fprintf('光伏候选格网：%d 个\n', length(solar_index));

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

wind_ins = (3.68 * areas) / 1e6;
wind_ins(landmask == 1) = (6.07 * areas(landmask == 1)) / 1e6;

wind_gen_all = h5read('Global_Wind_CFs_Sel.h5', '/data');

tmp = wind_ins > 0.0001;
wind_ins_f = wind_ins(tmp);
wind_gen_f = wind_gen_all(tmp, :);
win_index_f = win_index_all(tmp);

for ii = 1:length(wind_ins_f)
    wind_gen_f(ii,:) = wind_gen_f(ii,:) * wind_ins_f(ii);
end
annual_gen_wind = sum(wind_gen_f, 2);

tmp3 = annual_gen_wind < 10;
win_index = win_index_f(tmp3);
clear luccs fish_area areas landmask wind_ins wind_gen_all wind_gen_f wind_ins_f win_index_all win_index_f annual_gen_wind
fprintf('风电候选格网：%d 个\n', length(win_index));

%% 5. 对于 2040/2030，应用上一阶段 Sel 进行预筛选
if year ~= 2050
    if year == 2040
        load('results/Opt_SC_2050_Sel.mat', 'opt_wind', 'opt_solar');
    else
        load('results/Opt_SC_2040_Sel.mat', 'opt_wind', 'opt_solar');
    end

    [~, pos_s] = ismember(find(opt_solar == 1), solar_index);
    valid_s = pos_s > 0;
    solar_index = solar_index(pos_s(valid_s));
    N_solar = length(solar_index);

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
solar_sel = round(scale(1:N_solar));
wind_sel  = round(scale(N_solar+1:N_grid));
opt_stoPow = scale(N_grid+1:N_grid+20);        % 储能功率（GW）
opt_stoCap = scale(N_grid+21:N_grid+40);       % 储能时长（小时）

fprintf('光伏选中：%d / %d\n', sum(solar_sel), N_solar);
fprintf('风电选中：%d / %d\n', sum(wind_sel), N_wind);
fprintf('储能功率（GW）：[%s]\n', num2str(round(opt_stoPow)));
fprintf('储能时长（h）：[%s]\n', num2str(round(opt_stoCap)));

%% 7. 映射回 180×360 空间格网
opt_solar = zeros(180, 360);
opt_wind  = zeros(180, 360);
opt_solar(solar_index(solar_sel == 1)) = 1;
opt_wind(win_index(wind_sel == 1)) = 1;
fprintf('opt_solar 非零数=%d, opt_wind 非零数=%d\n', nnz(opt_solar), nnz(opt_wind));

%% 8. 提取传输容量
load Global_Init_State.mat cur_storage cur_trans
load Global_Trans trans_connections trans_loss

% 清零跨洲连接（大陆互联模式）
cur_trans(6,1)=0; cur_trans(7,1)=0; cur_trans(1,6)=0; cur_trans(1,7)=0;
cur_trans(17,4)=0; cur_trans(18,4)=0; cur_trans(4,17)=0; cur_trans(4,18)=0;

% 拓扑过滤
trans_connections(trans_connections==2)=0;

tmp = cur_trans > 0;
cur_trans(cur_trans < 2) = 0;
trans_mask = tmp;
n_trans = sum(tmp(:));
fprintf('输电链路：%d 条有效连接，决策向量包含 %d 个输电变量\n', ...
    n_trans, length(scale)-N_grid-40);

trans_values = scale(N_grid+41:end);
opt_trans = zeros(20, 20);
opt_trans(trans_mask) = trans_values;
fprintf('opt_trans 非零数=%d\n', nnz(opt_trans));
fprintf('输电总容量: %.4f TW\n', sum(opt_trans(:)) / 1000);

%% 9. 保存
if ~exist('results', 'dir'), mkdir('results'); end;
outfile = ['results/' selprefix '_Sel.mat'];

% costmin 专用元数据
preferred_sol_idx = 1;
preferred_selection_status = 'costmin_optimal';
preferred_curtailment = curtailment_rate;
preferred_vre_share = vre_share;
preferred_flexible_ratio = flexible_ratio;
preferred_cost = total_annual_cost;
preferred_min_vre_share = min_vre_share;
preferred_max_vre_share = max_vre_share;
preferred_max_curtailment = cost_cfg.MAX_CURTAILMENT;
preferred_selection_mode = 'costmin';
preferred_scenario_name = SCENARIO_NAME;
preferred_base_load_ratio = base_load_ratio;
preferred_cost_mode = cost_cfg.COST_MODE;
preferred_cost_breakdown = cost_bd;

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
    'preferred_base_load_ratio', ...
    'preferred_cost_mode', ...
    'preferred_cost_breakdown' ...
);
fprintf('\n已保存 %s\n', outfile);
