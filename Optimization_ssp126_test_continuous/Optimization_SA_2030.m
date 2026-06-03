%% Optimization_SA_2030.m — 2030年 SSP1-2.6 情景下的空间布局优化（邻近互联 S-A）
%
% 功能：使用 NSGA-II（gamultiobj）多目标优化，求解2030年全球20个区域的光伏/风电场站
%       空间选址、储能配置和跨区输电容量的 Pareto 最优方案。
%
% 与2040年的嵌套关系：
%   - 候选格网由2040年优化结果（results/Opt_SC_2040_Sel.mat）约束
%   - 储能/输电上界由2040年结果约束
%
% 情景假设（AR6 SSP1-2.6）：
%   - 全球电力需求：34,633 TWh
%   - 基荷发电占比：73.7%（非可再生能源调度份额）
%   - 互联模式：邻近互联（S-A），仅允许相邻区域间输电（maxNodes=2）
%
% 优化目标：
%   f(1) = 弃电率（最小化）
%   f(2) = 1 - 可再生渗透率（最小化）
%   f(3) = 系统总成本（USD billion, 最小化）
%
% 输出：results/Optimization_SA_2030_Res.h5

clear,clc

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
cfg = continuous_config();
load results/Opt_SC_2040_Sel opt_trans opt_stoCap opt_stoPow opt_wind opt_solar

%% ======================== 3. 构建风电候选格网（受2040约束） ========================
luccs=geotiffread('Global_Wind_Net_Area_Add_Egrid.tif');
luccs=luccs/100;% 百分比 → 小数
win_index=find(luccs>0);
fish_area=geotiffread('Global_Wind_Fishnet_Area.tif');
fish_area=double(fish_area);%km2
areas=luccs(win_index).*fish_area(win_index);
landmask=readgeoraster('Global_LandMask.tif');
landmask(landmask<100)=0;landmask(landmask>100)=1;
landmask=landmask(win_index);
% 装机容量：陆上 3.68 MW/km²，海上 6.07 MW/km²
wind_ins=(3.68*areas)/1000/1000;%单位 TWp
wind_ins(landmask==1)=(6.07*areas(landmask==1))/1000/1000;%海上
wind_gen=h5read('Global_Wind_CFs_Sel.h5','/data');
for ii=1:8477
    wind_gen(ii,:)=wind_gen(ii,:)*wind_ins(ii);%单位 TWh
end
clear areas fish_area luccs
% 预筛选：仅保留2040年有效开发的风电格网（比例 > EPS_ACTIVE）
win_index2 = find(opt_wind > cfg.EPS_ACTIVE);
wind_ub = opt_wind(win_index2);
[is_found, loc] = ismember(win_index2, win_index);
wind_ub = wind_ub(is_found);
loc = loc(is_found);
wind_ins = wind_ins(loc); wind_gen = wind_gen(loc,:); win_index = win_index(loc);
clear win_index2 is_found loc

%% ======================== 4. 构建光伏候选格网（受2040约束） ========================
grids=geotiffread('Global_fishnet.tif');
solar_index=find(grids<65536);
grids(solar_index)=0;
load  Global_Solar_CFs
res_CF=res_CF/10/1000;
luccs=geotiffread('Global_Solar_Net_Area_Add_Egrid.tif');
luccs=luccs/100;% 百分比 → 小数
fish_area=geotiffread('Global_Solar_Fishnet_Area.tif');
fish_area(fish_area<0)=0;
fish_area=double(fish_area);%km2
areas=luccs(solar_index).*fish_area(solar_index);
solar_gen=res_CF;clear res_CF
% 装机容量：纬度依赖安装密度 161.9×Ω(lat)×FR MW/km²
pv_density = compute_pv_density(solar_index);
solar_ins=zeros([13296,1]);
for ii=1:13296
    solar_ins(ii)=(pv_density(ii)*areas(ii))/1000/1000;%单位 TWp
    solar_gen(ii,:)=solar_gen(ii,:)*(pv_density(ii)*areas(ii))/1000/1000;%单位 TWh
end
clear pv_density
% 预筛选：仅保留2040年有效开发的光伏格网（比例 > EPS_ACTIVE）
solar_index2 = find(opt_solar > cfg.EPS_ACTIVE);
solar_ub = opt_solar(solar_index2);
[is_found, loc] = ismember(solar_index2, solar_index);
solar_ub = solar_ub(is_found);
loc = loc(is_found);
solar_ins = solar_ins(loc); solar_gen = solar_gen(loc,:); solar_index = solar_index(loc);
clear areas fish_area luccs grids solar_index2 is_found loc

%% ======================== 5. 合并光伏/风电数据 ========================
all_gens=[solar_gen;wind_gen];
all_ins=[solar_ins;wind_ins];
clear solar_gen wind_gen
clear solar_ins wind_ins

%% ======================== 6. 加载2030年负荷数据 ========================
% SSP1-2.6 对应第2个情景维度（索引=2）
load Global_Load_22region.mat
all_loads=squeeze(all_loads(2,:,:))/1000/1000;%单位 TW
global_load=sum(all_loads,1);
% 缩放至 AR6 SSP1-2.6 的 34,633 TWh
all_loads=all_loads/(sum(global_load(:))/34633);
clear global_load

%% ======================== 7. 构建区域索引和约束数据 ========================
[grid_ind,R]=readgeoraster('Global_Grid_Division.tif');
CGrid_Index=[grid_ind(solar_index);grid_ind(win_index)];
nonlcon_sel=CGrid_Index; nonlcon_ins=all_ins;
nonlcon_ub=[solar_ub(:); wind_ub(:)];  % 2030年格网比例上限 = 2040年开发比例
nonlsol=length(solar_index); nonlwin=length(win_index);
save NonlConData2030 nonlcon_sel nonlcon_ins nonlcon_ub nonlsol nonlwin
clear nonlcon_sel nonlcon_ins nonlcon_ub nonlsol nonlwin
% 为风电候选添加陆海标记
landmask=readgeoraster('Global_LandMask.tif');
landmask(landmask<100)=0;landmask(landmask>100)=1;
landmask=landmask(win_index);
CGrid_Index(length(solar_index)+1:length(solar_index)+length(win_index),3)=landmask;
clear grid_ind R landmask

%% ======================== 8. 设置优化变量与约束 ========================
rng default
n_grid = length(CGrid_Index);
load Global_Init_State.mat cur_storage cur_trans

% 变量结构: [光伏开发比例 | 风电开发比例 | 储能功率(20) | 储能时长(20) | 输电容量(n_trans)]
lb=zeros(1,n_grid);

% 2030 年格网开发比例不得超过 2040 年的比例
ub=[solar_ub(:); wind_ub(:)].';

% 储能功率：下界=当前已有，上界=2040年配置
lb(n_grid+1:n_grid+20)=cur_storage/1000;
ub(n_grid+1:n_grid+20)=opt_stoPow;%单位 GW
clear cur_storage

% 储能时长：下界=2h，上界=2040年配置
lb(n_grid+21:n_grid+40)=2;
ub(n_grid+21:n_grid+40)=opt_stoCap;%单位 小时

% 输电容量：清零跨洲链路下界（邻近互联模式同样不启用跨洲输电）
cur_trans(6,1)=0;cur_trans(7,1)=0;cur_trans(1,6)=0;cur_trans(1,7)=0;
cur_trans(17,4)=0;cur_trans(18,4)=0;cur_trans(4,17)=0;cur_trans(4,18)=0;
tmp=cur_trans>0;cur_trans(cur_trans<2)=0;
lb(n_grid+41:n_grid+40+sum(tmp(:)))=cur_trans(tmp)/1000;
ub(n_grid+41:n_grid+40+sum(tmp(:)))=opt_trans(tmp);% 上界=2040年输电配置（GW）
clear cur_trans
nvars=length(lb);

% 风光比例变量保持连续；储能功率、储能时长和输电容量继续保持整数粒度
intcon = (n_grid + 1):nvars;

%% ======================== 9. 约束可行性检查 ========================
load Global_Init_State.mat cur_solar cur_wind
cur_solar_tw = cur_solar / 1e6;
cur_wind_tw  = cur_wind  / 1e6;

load NonlConData2030.mat nonlcon_sel nonlcon_ins nonlcon_ub nonlsol nonlwin

solar_max = accumarray( ...
    nonlcon_sel(1:nonlsol, 1), ...
    nonlcon_ins(1:nonlsol) .* nonlcon_ub(1:nonlsol), ...
    [20, 1], @sum, 0);

wind_max = accumarray( ...
    nonlcon_sel(nonlsol+1:end, 1), ...
    nonlcon_ins(nonlsol+1:end) .* nonlcon_ub(nonlsol+1:end), ...
    [20, 1], @sum, 0);

if any(solar_max + 1e-12 < cur_solar_tw) || any(wind_max + 1e-12 < cur_wind_tw)
    solar_deficit = find(solar_max + 1e-12 < cur_solar_tw);
    wind_deficit  = find(wind_max + 1e-12 < cur_wind_tw);
    fprintf('警告：以下区域最大可用容量不足以覆盖已有装机：\n');
    if ~isempty(solar_deficit)
        fprintf('  光伏缺口区域：%s\n', num2str(solar_deficit'));
    end
    if ~isempty(wind_deficit)
        fprintf('  风电缺口区域：%s\n', num2str(wind_deficit'));
    end
    error('存在无法覆盖已有装机容量的区域，请检查候选格网或父阶段比例上限');
end
clear cur_solar cur_wind cur_solar_tw cur_wind_tw solar_max wind_max

%% ======================== 10. 运行 NSGA-II 优化 ========================
T = datetime('now');
disp(T)
fprintf('开始2030年连续容量优化（邻近互联，种群=%d，代数=%d）...\n', ...
    cfg.POPULATION_SIZE, cfg.MAX_GENERATIONS);
options = optimoptions('gamultiobj', ...
    'UseParallel', true, ...
    'PlotFcn', [], ...
    'PopulationSize', cfg.POPULATION_SIZE, ...
    'MaxGenerations', cfg.MAX_GENERATIONS, ...
    'ConstraintTolerance', cfg.CONSTRAINT_TOL);
[res_scale,prs]=gamultiobj(@(scale)  OptFun_SA_Dispatch_2030(all_ins,all_gens,all_loads,CGrid_Index,scale),...
    nvars,[],[],[],[],lb,ub,@nonlcon2030,intcon,options);
T = datetime('now');
disp(T)
fprintf('优化完成，共 %d 个 Pareto 解\n', size(prs,1));

%% ======================== 11. 保存结果 ========================
if ~exist('results', 'dir'), mkdir('results'); end  % 确保结果目录存在
if exist('results/Optimization_SA_2030_Res.h5','file'), delete('results/Optimization_SA_2030_Res.h5'); end
h5create('results/Optimization_SA_2030_Res.h5','/res_scale',size(res_scale));
h5write('results/Optimization_SA_2030_Res.h5','/res_scale',res_scale);
h5create('results/Optimization_SA_2030_Res.h5','/prs',size(prs));
h5write('results/Optimization_SA_2030_Res.h5','/prs',prs);
fprintf('结果已保存至 results/Optimization_SA_2030_Res.h5\n');

%% ======================== 12. 关闭并行池 ========================
pool = gcp('nocreate');
if ~isempty(pool)
    delete(pool);
    fprintf('并行池已关闭\n');
end
