%% binary_search_driver.m — AR6 SSP1-2.6 校准二分搜索驱动脚本
%
% 功能：自动化两阶段二分搜索，调整光伏成本倍率和容量惩罚，
%       使2050年优化结果与 AR6 SSP1-2.6 参考值基本一致。
%
% Phase 1：固定 cap_penalty=0，搜索 solar_mult → 匹配光伏/风电占比
% Phase 2：固定 solar_mult，搜索 cap_penalty → 匹配总装机容量
% Phase 3（可选）：联合微调
%
% 用法：matlab -batch "binary_search_driver"
% 输出：每次迭代保存为 Optimization_SC_2050_Res_sm{sm}_cp{cp}.h5
%       日志文件：binary_search_log.txt

clear, clc

%% ======================== 配置参数 ========================
AR6_SOLAR_GW   = 5799;     % AR6 SSP1-2.6 2050 光伏装机
AR6_WIND_GW    = 6418;     % AR6 SSP1-2.6 2050 风电装机
AR6_TOTAL_GW   = 12217;    % AR6 总装机
AR6_SOLAR_PCT  = 47.5;     % AR6 光伏占比 %
AR6_WIND_PCT   = 52.5;     % AR6 风电占比 %

% 验收范围
SOLAR_SHARE_LO = 42.5;     SOLAR_SHARE_HI = 52.5;
TOTAL_CAP_LO   = 10384;    TOTAL_CAP_HI   = 14050;

% 二分搜索参数
MAX_ITER_PHASE1 = 6;       % Phase 1 最大迭代
MAX_ITER_PHASE2 = 6;       % Phase 2 最大迭代
N_WORKERS = 64;            % 并行工作节点数（集群上限64）

% 日志文件
LOG_FILE = 'binary_search_log.txt';
if exist(LOG_FILE, 'file'), delete(LOG_FILE); end

%% ======================== 启动并行池 ========================
try
    pool = parpool('local', N_WORKERS);
    fprintf('并行池已启动：%d 个工作节点\n', pool.NumWorkers);
catch ME
    if contains(ME.identifier, 'parallel:pool:alreadyopen')
        pool = gcp('nocreate');
        fprintf('并行池已在运行：%d 个工作节点\n', pool.NumWorkers);
    else
        error('并行池启动失败：%s', ME.message);
    end
end

%% ======================== 加载数据（一次性） ========================
fprintf('正在加载优化数据...\n');

% --- 风电候选格网 ---
luccs=geotiffread('Global_Wind_Net_Area_Add_Egrid.tif');
luccs=luccs/100;
win_index=find(luccs>0);
fish_area=geotiffread('Global_Wind_Fishnet_Area.tif');
fish_area=double(fish_area);
areas=luccs(win_index).*fish_area(win_index);
landmask=readgeoraster('Global_LandMask.tif');
landmask(landmask<100)=0;landmask(landmask>100)=1;
landmask=landmask(win_index);
wind_ins=(2.7*areas)/1000/1000;
wind_ins(landmask==1)=(4.6*areas(landmask==1))/1000/1000;
wind_gen=h5read('Global_Wind_CFs_Sel.h5','/data');
for ii=1:8477
    wind_gen(ii,:)=wind_gen(ii,:)*wind_ins(ii);
end
wind_ind1=win_index((wind_ins<=0.0001)&(wind_ins>0));
tmp=wind_ins>0.0001;
wind_ins=wind_ins(tmp);wind_gen=wind_gen(tmp,:);win_index=win_index(tmp);
tmp=sum(wind_gen,2);
wind_ind2=win_index(tmp>=10);
tmp=tmp<10;
wind_ins=wind_ins(tmp);wind_gen=wind_gen(tmp,:);win_index=win_index(tmp);
wind_ind3=win_index;
clear areas fish_area luccs tmp wind_ind1 wind_ind2 wind_ind3

% --- 光伏候选格网 ---
grids=geotiffread('Global_fishnet.tif');
solar_index=find(grids<65536);
grids(solar_index)=0;
load Global_Solar_CFs
res_CF=res_CF/10/1000;
luccs=geotiffread('Global_Solar_Net_Area_Add_Egrid.tif');
luccs=luccs/100;
fish_area=geotiffread('Global_Solar_Fishnet_Area.tif');
fish_area(fish_area<0)=0;
fish_area=double(fish_area);
areas=luccs(solar_index).*fish_area(solar_index);
solar_gen=res_CF;clear res_CF
solar_ins=zeros([13296,1]);
for ii=1:13296
    solar_ins(ii)=(74*areas(ii))/1000/1000;
    solar_gen(ii,:)=solar_gen(ii,:)*(74*areas(ii))/1000/1000;
end
solar_ind1=solar_index((solar_ins<=0.001)&(solar_ins>0));
tmp=solar_ins>0.001;
solar_ins=solar_ins(tmp);solar_gen=solar_gen(tmp,:);solar_index=solar_index(tmp);
tmp=sum(solar_gen,2);
solar_ind2=solar_index(tmp>=90);
tmp=tmp<90;
solar_ins=solar_ins(tmp);solar_gen=solar_gen(tmp,:);solar_index=solar_index(tmp);
solar_ind3=solar_index;
clear areas fish_area luccs grids tmp solar_ind3 solar_ind2 solar_ind1

% --- 合并 ---
all_gens=[solar_gen;wind_gen];
all_ins=[solar_ins;wind_ins];
clear solar_gen wind_gen solar_ins wind_ins

% --- 负荷 ---
load Global_Load_22region.mat
all_loads=squeeze(all_loads(4,:,:))/1000/1000;
global_load=sum(all_loads,1);
all_loads=all_loads/(sum(global_load(:))/54767);
clear global_load

% --- 区域索引 ---
[grid_ind,R]=readgeoraster('Global_Grid_Division.tif');
CGrid_Index=[grid_ind(solar_index);grid_ind(win_index)];
nonlcon_sel=CGrid_Index; nonlcon_ins=all_ins;
nonlsol=length(solar_index); nonlwin=length(win_index);
save NonlConData nonlcon_sel nonlcon_ins nonlsol nonlwin
clear nonlcon_sel nonlcon_ins
landmask=readgeoraster('Global_LandMask.tif');
landmask(landmask<100)=0;landmask(landmask>100)=1;
landmask=landmask(win_index);
CGrid_Index(length(solar_index)+1:length(solar_index)+length(win_index),3)=landmask;
clear grid_ind R landmask

% --- 优化变量 ---
rng default
nvars=length(CGrid_Index);
load Global_Init_State.mat cur_storage cur_trans
lb=zeros(1,nvars);
ub=ones(1,nvars);
al=max(all_loads,[],2);
lb(nvars+1:nvars+20)=cur_storage/1000;ub(nvars+1:nvars+20)=al*1000;
clear cur_storage al
lb(nvars+21:nvars+40)=2;ub(nvars+21:nvars+40)=72;
cur_trans(6,1)=0;cur_trans(7,1)=0;cur_trans(1,6)=0;cur_trans(1,7)=0;
cur_trans(17,4)=0;cur_trans(18,4)=0;cur_trans(4,17)=0;cur_trans(4,18)=0;
tmp=cur_trans>0;cur_trans(cur_trans<2)=0;
lb(nvars+41:nvars+40+sum(tmp(:)))=cur_trans(tmp)/1000;ub(nvars+41:nvars+40+sum(tmp(:)))=10*1000;
clear cur_trans
nvars=length(lb);
intcon=1:1:length(lb);

fprintf('数据加载完成。候选格网：光伏 %d，风电 %d，总变量 %d\n', ...
    length(solar_index), length(win_index), nvars);

%% ======================== Phase 1：搜索 solar_mult ========================
fprintf('\n========================================\n');
fprintf('  Phase 1：搜索光伏成本倍率 solar_mult\n');
fprintf('  目标：光伏占比 %.1f%% - %.1f%%\n', SOLAR_SHARE_LO, SOLAR_SHARE_HI);
fprintf('========================================\n');

sm_lo = 1.0;  sm_hi = 4.0;  cap_penalty = 0;
best_sm = 1.0;

log_write(LOG_FILE, '=== Phase 1: solar_mult search ===');
log_write(LOG_FILE, sprintf('%-6s %-12s %-12s %-12s %-12s %-10s', ...
    'Iter', 'solar_mult', 'Solar_GW', 'Wind_GW', 'Total_GW', 'Solar%'));

for iter = 1:MAX_ITER_PHASE1
    solar_mult = (sm_lo + sm_hi) / 2;
    rng default;

    fprintf('\n--- Phase 1, 迭代 %d: solar_mult = %.4f ---\n', iter, solar_mult);

    options = optimoptions('gamultiobj','UseParallel',true,...
        'PlotFcn',[],'PopulationSize',500,'MaxGenerations',200);
    [res_scale, prs] = gamultiobj(...
        @(scale) OptFun_SC_Dispatch_2050(all_ins,all_gens,all_loads,...
            CGrid_Index,scale,solar_mult,cap_penalty),...
        nvars,[],[],[],[],lb,ub,@nonlcon2050,intcon,options);

    % 分析结果
    [solar_gw, wind_gw, total_gw, solar_pct, wind_pct] = ...
        analyze_result(res_scale, all_ins, nonlsol, length(solar_index)+length(win_index));

    fprintf('  结果: 光伏=%.0f GW (%.1f%%), 风电=%.0f GW (%.1f%%), 合计=%.0f GW\n',...
        solar_gw, solar_pct, wind_gw, wind_pct, total_gw);

    log_write(LOG_FILE, sprintf('%-6d %-12.4f %-12.0f %-12.0f %-12.0f %-10.1f', ...
        iter, solar_mult, solar_gw, wind_gw, total_gw, solar_pct));

    % 检查验收
    if solar_pct >= SOLAR_SHARE_LO && solar_pct <= SOLAR_SHARE_HI
        fprintf('  *** 光伏占比在验收范围内！***\n');
        best_sm = solar_mult;
        break;
    end

    % 更新搜索范围
    if solar_pct > AR6_SOLAR_PCT
        sm_lo = solar_mult;
    else
        sm_hi = solar_mult;
    end
    best_sm = solar_mult;
end

solar_mult = best_sm;
fprintf('\nPhase 1 完成: solar_mult = %.4f\n', solar_mult);
log_write(LOG_FILE, sprintf('Phase 1 结果: solar_mult = %.4f', solar_mult));

%% ======================== Phase 2：搜索 cap_penalty ========================
fprintf('\n========================================\n');
fprintf('  Phase 2：搜索容量惩罚 cap_penalty\n');
fprintf('  目标：总装机 %d - %d GW\n', TOTAL_CAP_LO, TOTAL_CAP_HI);
fprintf('  固定: solar_mult = %.4f\n', solar_mult);
fprintf('========================================\n');

cp_lo = 0;  cp_hi = 50;
best_cp = 0;

log_write(LOG_FILE, '');
log_write(LOG_FILE, '=== Phase 2: cap_penalty search ===');
log_write(LOG_FILE, sprintf('%-6s %-14s %-12s %-12s %-12s %-10s', ...
    'Iter', 'cap_penalty', 'Solar_GW', 'Wind_GW', 'Total_GW', 'Solar%'));

for iter = 1:MAX_ITER_PHASE2
    cap_penalty = (cp_lo + cp_hi) / 2;
    rng default;

    fprintf('\n--- Phase 2, 迭代 %d: cap_penalty = %.2f ---\n', iter, cap_penalty);

    options = optimoptions('gamultiobj','UseParallel',true,...
        'PlotFcn',[],'PopulationSize',500,'MaxGenerations',200);
    [res_scale, prs] = gamultiobj(...
        @(scale) OptFun_SC_Dispatch_2050(all_ins,all_gens,all_loads,...
            CGrid_Index,scale,solar_mult,cap_penalty),...
        nvars,[],[],[],[],lb,ub,@nonlcon2050,intcon,options);

    [solar_gw, wind_gw, total_gw, solar_pct, wind_pct] = ...
        analyze_result(res_scale, all_ins, nonlsol, length(solar_index)+length(win_index));

    fprintf('  结果: 光伏=%.0f GW (%.1f%%), 风电=%.0f GW (%.1f%%), 合计=%.0f GW\n',...
        solar_gw, solar_pct, wind_gw, wind_pct, total_gw);

    log_write(LOG_FILE, sprintf('%-6d %-14.2f %-12.0f %-12.0f %-12.0f %-10.1f', ...
        iter, cap_penalty, solar_gw, wind_gw, total_gw, solar_pct));

    if total_gw >= TOTAL_CAP_LO && total_gw <= TOTAL_CAP_HI
        fprintf('  *** 总装机在验收范围内！***\n');
        best_cp = cap_penalty;
        break;
    end

    if total_gw > AR6_TOTAL_GW
        cp_lo = cap_penalty;
    else
        cp_hi = cap_penalty;
    end
    best_cp = cap_penalty;
end

cap_penalty = best_cp;
fprintf('\nPhase 2 完成: cap_penalty = %.2f\n', cap_penalty);
log_write(LOG_FILE, sprintf('Phase 2 结果: cap_penalty = %.2f', cap_penalty));

%% ======================== 最终验证 ========================
fprintf('\n========================================\n');
fprintf('  最终验证运行\n');
fprintf('  solar_mult = %.4f, cap_penalty = %.2f\n', solar_mult, cap_penalty);
fprintf('========================================\n');

rng default;
options = optimoptions('gamultiobj','UseParallel',true,...
    'PlotFcn',[],'PopulationSize',500,'MaxGenerations',200);
[res_scale, prs] = gamultiobj(...
    @(scale) OptFun_SC_Dispatch_2050(all_ins,all_gens,all_loads,...
        CGrid_Index,scale,solar_mult,cap_penalty),...
    nvars,[],[],[],[],lb,ub,@nonlcon2050,intcon,options);

[solar_gw, wind_gw, total_gw, solar_pct, wind_pct] = ...
    analyze_result(res_scale, all_ins, nonlsol, length(solar_index)+length(win_index));

fprintf('\n最终结果:\n');
fprintf('  光伏: %.0f GW (%.1f%%)  [AR6: %d GW, %.1f%%]\n', solar_gw, solar_pct, AR6_SOLAR_GW, AR6_SOLAR_PCT);
fprintf('  风电: %.0f GW (%.1f%%)  [AR6: %d GW, %.1f%%]\n', wind_gw, wind_pct, AR6_WIND_GW, AR6_WIND_PCT);
fprintf('  合计: %.0f GW          [AR6: %d GW]\n', total_gw, AR6_TOTAL_GW);
fprintf('  Pareto 解数: %d\n', size(prs, 1));

% 验收判断
pass_solar = solar_pct >= SOLAR_SHARE_LO && solar_pct <= SOLAR_SHARE_HI;
pass_total = total_gw >= TOTAL_CAP_LO && total_gw <= TOTAL_CAP_HI;
fprintf('\n验收结果:\n');
fprintf('  光伏占比: %s (%.1f%% in [%.1f%%, %.1f%%])\n', ...
    ternary(pass_solar, 'PASS', 'FAIL'), solar_pct, SOLAR_SHARE_LO, SOLAR_SHARE_HI);
fprintf('  总装机:   %s (%.0f GW in [%d, %d])\n', ...
    ternary(pass_total, 'PASS', 'FAIL'), total_gw, TOTAL_CAP_LO, TOTAL_CAP_HI);

log_write(LOG_FILE, '');
log_write(LOG_FILE, '=== Final Result ===');
log_write(LOG_FILE, sprintf('solar_mult=%.4f, cap_penalty=%.2f', solar_mult, cap_penalty));
log_write(LOG_FILE, sprintf('Solar=%.0f GW (%.1f%%), Wind=%.0f GW (%.1f%%), Total=%.0f GW', ...
    solar_gw, solar_pct, wind_gw, wind_pct, total_gw));
log_write(LOG_FILE, sprintf('Solar%% PASS: %s, Total PASS: %s', ...
    ternary(pass_solar, 'YES', 'NO'), ternary(pass_total, 'YES', 'NO')));

%% ======================== 关闭并行池 ========================
pool = gcp('nocreate');
if ~isempty(pool)
    delete(pool);
    fprintf('并行池已关闭\n');
end

fprintf('\n二分搜索完成。日志文件: %s\n', LOG_FILE);

%% ======================== 辅助函数 ========================

function [solar_gw, wind_gw, total_gw, solar_pct, wind_pct] = ...
    analyze_result(res_scale, all_ins, nonlsol, N)
    % 从 Pareto 前沿中位成本解计算装机容量
    % res_scale: (n_pareto, nvars)，all_ins: (N,1) 列向量
    n_pareto = size(res_scale, 1);
    solar_caps = zeros(n_pareto, 1);
    wind_caps = zeros(n_pareto, 1);
    for i = 1:n_pareto
        site_sel = round(res_scale(i, 1:N))';  % 转置为列向量，与 all_ins 对齐
        solar_caps(i) = sum(all_ins(1:nonlsol) .* site_sel(1:nonlsol)) * 1000;
        wind_caps(i) = sum(all_ins(nonlsol+1:N) .* site_sel(nonlsol+1:N)) * 1000;
    end
    solar_gw = median(solar_caps);
    wind_gw = median(wind_caps);
    total_gw = solar_gw + wind_gw;
    solar_pct = solar_gw / total_gw * 100;
    wind_pct = wind_gw / total_gw * 100;
end

function log_write(filename, msg)
    fid = fopen(filename, 'a');
    fprintf(fid, '%s\n', msg);
    fclose(fid);
end

function s = ternary(cond, t, f)
    if cond, s = t; else, s = f; end
end
