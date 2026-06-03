% convert_h5_to_sel.m — 将优化结果 h5 文件转换为 Sel.mat 空间布局文件
%
% 功能：读取 Optimization_*_Res.h5 中的 Pareto 解，将决策向量映射回
%       180×360 全球空间格网，并提取储能/输电配置，供下一阶段优化使用。
%
% 用法：matlab -batch "year=2050; sol_idx=0; convert_h5_to_sel"
%
% 参数：
%   year     - 优化年份（2050/2040/2030）
%   sol_idx  - Pareto 解编号（0=自动选中间解）
%
% 输出：Opt_*_Sel.mat（包含 opt_solar, opt_wind, opt_stoPow, opt_stoCap, opt_trans）

if ~exist('year', 'var'), year = 2050; end
if ~exist('sol_idx', 'var'), sol_idx = 0; end

fprintf('=== h5 转 Sel：year=%d, sol_idx=%d ===\n', year, sol_idx);

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

%% 3. 选择解（sol_idx=0 时自动选中间解）
if sol_idx == 0
    sol_idx = round(n_solutions / 2);
    fprintf('自动选择第 %d 个解（共 %d 个的中间位置）\n', sol_idx, n_solutions);
end
scale = res_scale(sol_idx, :);
fprintf('解 %d：弃电率=%.4f, 渗透率=%.4f, 成本=%.0f 十亿美元\n', ...
    sol_idx, prs(sol_idx,1), 1-prs(sol_idx,2), prs(sol_idx,3));

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

% 计算装机容量：纬度依赖安装密度 161.9×Ω(lat)×FR MW/km²
pv_density = compute_pv_density(solar_index_all);
solar_ins = zeros(length(solar_index_all), 1);
for ii = 1:length(solar_index_all)
    solar_ins(ii) = (pv_density(ii) * areas(ii)) / 1e6;  % MW/km² × km² / 1e6 → TWp
end
clear pv_density

% 筛选：装机容量 > 0.001 TWp
tmp = solar_ins > 0.001;
tmp_idx = find(tmp);
solar_index_f = solar_index_all(tmp);
areas_solar_f = areas(tmp);

% 计算发电量并筛选：年发电量 < 90 TWh
pv_density_f = compute_pv_density(solar_index_f);
solar_gen_f = zeros(sum(tmp), 8760);
solar_ins_f = zeros(sum(tmp), 1);
for ii = 1:sum(tmp)
    solar_gen_f(ii,:) = res_CF_scaled(tmp_idx(ii), :) * (pv_density_f(ii) * areas_solar_f(ii)) / 1e6;
    solar_ins_f(ii) = (pv_density_f(ii) * areas_solar_f(ii)) / 1e6;  % TWp
end
clear res_CF_scaled pv_density_f
annual_gen_solar = sum(solar_gen_f, 2);

tmp3 = annual_gen_solar < 90;
solar_index = solar_index_f(tmp3);
solar_ins_selected = solar_ins_f(tmp3);  % 保留候选格网装机容量（TWp）
clear solar_gen_f annual_gen_solar areas_solar_f solar_ins solar_ins_f solar_index_f solar_index_all areas
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
wind_ins_selected = wind_ins_f(tmp3);  % 保留候选格网装机容量（TWp）
clear luccs fish_area areas landmask wind_ins wind_gen_all wind_gen_f wind_ins_f win_index_all win_index_f annual_gen_wind
fprintf('2050年风电候选格网：%d 个\n', length(win_index));

%% 5. 对于 2040/2030，应用上一阶段 Sel 进行预筛选
cfg = continuous_config();

if year ~= 2050
    if year == 2040
        load('results/Opt_SC_2050_Sel.mat', 'opt_wind', 'opt_solar');  % 2050选中结果
    else
        load('results/Opt_SC_2040_Sel.mat', 'opt_wind', 'opt_solar');  % 2040选中结果
    end

    % 光伏：从完整候选中筛选上一阶段有效开发的格网（比例 > EPS_ACTIVE）
    solar_frac_parent = opt_solar(opt_solar > cfg.EPS_ACTIVE);
    solar_idx_parent = find(opt_solar > cfg.EPS_ACTIVE);
    [~, pos_s] = ismember(solar_idx_parent, solar_index);
    valid_s = pos_s > 0;
    solar_index = solar_index(pos_s(valid_s));
    solar_ins_selected = solar_ins_selected(pos_s(valid_s));
    solar_ub = solar_frac_parent(valid_s);  % 父阶段比例作为上限
    N_solar = length(solar_index);

    % 风电：从完整候选中筛选上一阶段有效开发的格网
    wind_frac_parent = opt_wind(opt_wind > cfg.EPS_ACTIVE);
    wind_idx_parent = find(opt_wind > cfg.EPS_ACTIVE);
    [~, pos_w] = ismember(wind_idx_parent, win_index);
    valid_w = pos_w > 0;
    win_index = win_index(pos_w(valid_w));
    wind_ins_selected = wind_ins_selected(pos_w(valid_w));
    wind_ub = wind_frac_parent(valid_w);  % 父阶段比例作为上限
    N_wind = length(win_index);

    fprintf('预筛选后：光伏=%d，风电=%d\n', N_solar, N_wind);
    clear opt_solar opt_wind pos_s pos_w valid_s valid_w
    clear solar_frac_parent wind_frac_parent solar_idx_parent wind_idx_parent
else
    N_solar = length(solar_index);
    N_wind = length(win_index);
end

N_grid = N_solar + N_wind;
fprintf('格网变量总数：%d，变量总数：%d\n', N_grid, nvars_total);

%% 6. 从决策向量提取各分量
solar_frac = scale(1:N_solar);              % 光伏开发比例（0~1）
wind_frac  = scale(N_solar+1:N_grid);       % 风电开发比例（0~1）

% 裁剪到 [0, 1] 并清理数值噪声
solar_frac = max(0, min(1, solar_frac));
wind_frac  = max(0, min(1, wind_frac));
solar_frac(abs(solar_frac) < cfg.EPS_ACTIVE) = 0;
wind_frac(abs(wind_frac) < cfg.EPS_ACTIVE) = 0;

opt_stoPow = scale(N_grid+1:N_grid+20);        % 储能功率（GW）
opt_stoCap = scale(N_grid+21:N_grid+40);       % 储能时长（小时）

n_solar_active = sum(solar_frac > cfg.EPS_ACTIVE);
n_wind_active  = sum(wind_frac > cfg.EPS_ACTIVE);
n_solar_partial = sum((solar_frac > cfg.EPS_ACTIVE) & (solar_frac < 1 - cfg.EPS_ACTIVE));
n_wind_partial  = sum((wind_frac > cfg.EPS_ACTIVE) & (wind_frac < 1 - cfg.EPS_ACTIVE));

fprintf('光伏有效开发：%d / %d（部分开发：%d）\n', n_solar_active, N_solar, n_solar_partial);
fprintf('风电有效开发：%d / %d（部分开发：%d）\n', n_wind_active, N_wind, n_wind_partial);
fprintf('储能功率（GW）：[%s]\n', num2str(round(opt_stoPow)));
fprintf('储能时长（h）：[%s]\n', num2str(round(opt_stoCap)));

%% 7. 映射回 180×360 空间格网
opt_solar_frac = zeros(180, 360);
opt_wind_frac  = zeros(180, 360);

opt_solar_frac(solar_index) = solar_frac(:);
opt_wind_frac(win_index) = wind_frac(:);

% 兼容旧接口：opt_solar / opt_wind 继续存在，但含义已变为开发比例
opt_solar = opt_solar_frac;
opt_wind = opt_wind_frac;

fprintf('opt_solar 非零数=%d, opt_wind 非零数=%d\n', nnz(opt_solar), nnz(opt_wind));

%% 8. 提取传输容量（复制优化脚本的拓扑逻辑）
load Global_Init_State.mat cur_storage cur_trans
load Global_Trans trans_connections trans_loss

% 清零跨洲连接（大陆互联模式）
cur_trans(6,1)=0;cur_trans(7,1)=0;cur_trans(1,6)=0;cur_trans(1,7)=0;
cur_trans(17,4)=0;cur_trans(18,4)=0;cur_trans(4,17)=0;cur_trans(4,18)=0;

% 拓扑过滤
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

%% 9. 计算实际容量栅格并保存
% 实际装机容量 = 最大技术潜力 × 开发比例
opt_solar_cap_twp = zeros(180, 360);
opt_wind_cap_twp  = zeros(180, 360);

opt_solar_cap_twp(solar_index) = solar_ins_selected(:) .* solar_frac(:);
opt_wind_cap_twp(win_index)  = wind_ins_selected(:) .* wind_frac(:);

% 元数据
selection_mode = 'continuous_fraction';
eps_active = cfg.EPS_ACTIVE;

if ~exist('results', 'dir'), mkdir('results'); end; outfile = ['results/' selprefix '_Sel.mat'];
save(outfile, ...
    'opt_solar', 'opt_wind', ...
    'opt_solar_frac', 'opt_wind_frac', ...
    'opt_solar_cap_twp', 'opt_wind_cap_twp', ...
    'opt_stoPow', 'opt_stoCap', 'opt_trans', ...
    'selection_mode', 'eps_active', ...
    'year', 'sol_idx');
fprintf('\n已保存 %s\n', outfile);

%% 10. Pareto 前沿概览
fprintf('\n=== Pareto 前沿（%d 个解） ===\n', n_solutions);
fprintf('%5s %10s %10s %12s\n', '编号', '弃电率', '渗透率', '成本(十亿$)');
for i = 1:min(n_solutions, 20)
    fprintf('%5d %10.4f %10.4f %12.1f\n', i, prs(i,1), 1-prs(i,2), prs(i,3));
end
if n_solutions > 20
    fprintf('  ... （共 %d 个解，此处省略）\n', n_solutions - 20);
    fprintf('%5d %10.4f %10.4f %12.1f\n', n_solutions, prs(n_solutions,1), 1-prs(n_solutions,2), prs(n_solutions,3));
end
