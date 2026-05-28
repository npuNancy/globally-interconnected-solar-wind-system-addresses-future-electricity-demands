%% Optimization_SC_2050.m — 2050年 SSP2-4.5 情景下的空间布局优化（大陆互联 S-C）
%
% 功能：使用 NSGA-II（gamultiobj）多目标优化，求解2050年全球20个区域的光伏/风电场站
%       空间选址、储能配置和跨区输电容量的 Pareto 最优方案。
%
% 情景假设（AR6 SSP2-4.5）：
%   - 全球电力需求：51,940 TWh
%   - 基荷发电占比：71.3%（非可再生能源调度份额）
%   - 互联模式：大陆互联（S-C），仅保留洲内输电通道，跨洲海底电缆不启用
%
% 优化目标：
%   f(1) = 弃电率（curtailment rate, 最小化）
%   f(2) = 1 - 可再生渗透率（flexible generation ratio, 最小化）
%   f(3) = 系统总成本（USD billion, 最小化）
%
% 决策变量：
%   [光伏选址(0/1) | 风电选址(0/1) | 储能功率(20区域) | 储能时长(20区域) | 输电容量(n_trans条链路)]
%
% 输出：Optimization_SC_2050_Res.h5（Pareto 前沿 + 决策向量）

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

%% ======================== 2. 构建风电候选格网 ========================
% 读取风电可用面积比例（占网格面积百分比）
luccs=geotiffread('Global_Wind_Net_Area_Add_Egrid.tif');
luccs=luccs/100;% 百分比 → 小数
win_index=find(luccs>0);
% 读取网格面积（km²）
fish_area=geotiffread('Global_Wind_Fishnet_Area.tif');
fish_area=double(fish_area);%km2
areas=luccs(win_index).*fish_area(win_index);
% 读取陆地掩膜，区分陆上/海上风电（安装密度不同）
landmask=readgeoraster('Global_LandMask.tif');
landmask(landmask<100)=0;landmask(landmask>100)=1;
landmask=landmask(win_index);
% 计算风电装机容量（TWp）：陆上 2.7 MW/km²，海上 4.6 MW/km²
wind_ins=(2.7*areas)/1000/1000;%单位 TWp
wind_ins(landmask==1)=(4.6*areas(landmask==1))/1000/1000;%海上风电密度更高
% 读取风电容量因子时序数据，计算发电量（TWh）
wind_gen=h5read('Global_Wind_CFs_Sel.h5','/data');
for ii=1:8477
    wind_gen(ii,:)=wind_gen(ii,:)*wind_ins(ii);%单位 TWh
end
% 候选格网筛选：
%   ind1: 装机容量 ≤ 0.0001 TWp（过小，排除）
%   ind2: 年发电量 ≥ 10 TWh（过大，排除）
%   ind3: 最终候选（0.0001 < ins 且 gen < 10 TWh）
wind_ind1=win_index((wind_ins<=0.0001)&(wind_ins>0));
tmp=wind_ins>0.0001;
wind_ins=wind_ins(tmp);wind_gen=wind_gen(tmp,:);win_index=win_index(tmp);
tmp=sum(wind_gen,2);
wind_ind2=win_index(tmp>=10);
tmp=tmp<10;
wind_ins=wind_ins(tmp);wind_gen=wind_gen(tmp,:);win_index=win_index(tmp);
wind_ind3=win_index;
save WindInd2050 wind_ind3 wind_ind2 wind_ind1
clear areas fish_area luccs tmp wind_ind1 wind_ind2 wind_ind3

%% ======================== 3. 构建光伏候选格网 ========================
% 读取全球渔网网格（180×360），筛选有效光伏格网（编号 < 65536）
grids=geotiffread('Global_fishnet.tif');
solar_index=find(grids<65536);
grids(solar_index)=0;
% 读取光伏容量因子时序数据
load  Global_Solar_CFs
res_CF=res_CF/10/1000;
% 读取光伏可用面积
luccs=geotiffread('Global_Solar_Net_Area_Add_Egrid.tif');
luccs=luccs/100;% 百分比 → 小数
fish_area=geotiffread('Global_Solar_Fishnet_Area.tif');
fish_area(fish_area<0)=0;
fish_area=double(fish_area);%km2
areas=luccs(solar_index).*fish_area(solar_index);
solar_gen=res_CF;clear res_CF
% 计算光伏装机容量和发电量：安装密度 74 MW/km²
solar_ins=zeros([13296,1]);
for ii=1:13296
    solar_ins(ii)=(74*areas(ii))/1000/1000;%单位 TWp
    solar_gen(ii,:)=solar_gen(ii,:)*(74*areas(ii))/1000/1000;%单位 TWh
end
% 候选格网筛选：
%   ind1: 装机容量 ≤ 0.001 TWp（过小，排除）
%   ind2: 年发电量 ≥ 90 TWh（过大，排除）
%   ind3: 最终候选（0.001 < ins 且 gen < 90 TWh）
solar_ind1=solar_index((solar_ins<=0.001)&(solar_ins>0));
tmp=solar_ins>0.001;
solar_ins=solar_ins(tmp);solar_gen=solar_gen(tmp,:);solar_index=solar_index(tmp);
tmp=sum(solar_gen,2);
solar_ind2=solar_index(tmp>=90);
tmp=tmp<90;
solar_ins=solar_ins(tmp);solar_gen=solar_gen(tmp,:);solar_index=solar_index(tmp);
solar_ind3=solar_index;
save SolarInd2050 solar_ind1 solar_ind2 solar_ind3
clear areas fish_area luccs grids tmp solar_ind3 solar_ind2 solar_ind1

%% ======================== 4. 合并光伏/风电数据 ========================
all_gens=[solar_gen;wind_gen];  % 所有候选格网的发电时序（TWh, 8760h）
all_ins=[solar_ins;wind_ins];   % 所有候选格网的装机容量（TWp）
clear solar_gen wind_gen
clear solar_ins wind_ins

%% ======================== 5. 加载2050年负荷数据 ========================
% Global_Load_22region.mat: (9个情景 × 20区域 × 8760h)
% SSP2-4.5 对应第4个情景维度（索引=4）
load Global_Load_22region.mat
all_loads=squeeze(all_loads(4,:,:))/1000/1000;%单位 TW
global_load=sum(all_loads,1);
% 将负荷总量缩放至 AR6 SSP2-4.5 的 51,940 TWh，保持小时形状和区域分布不变
all_loads=all_loads/(sum(global_load(:))/51940);
clear global_load

%% ======================== 6. 构建区域索引和约束数据 ========================
% 读取全球20区域划分图，为每个候选格网标记所属区域编号（1-20）
[grid_ind,R]=readgeoraster('Global_Grid_Division.tif');
CGrid_Index=[grid_ind(solar_index);grid_ind(win_index)]; % [区域编号, 选中状态, 陆海标记]
% 保存非线性约束所需数据（供 nonlcon2050.m 使用）
nonlcon_sel=CGrid_Index; nonlcon_ins=all_ins;
nonlsol=length(solar_index); nonlwin=length(win_index);
save NonlConData nonlcon_sel nonlcon_ins nonlsol nonlwin
clear nonlcon_sel nonlcon_ins nonlsol nonlwin
% 为风电候选格网添加陆海标记（第3列），用于成本计算区分陆上/海上
landmask=readgeoraster('Global_LandMask.tif');
landmask(landmask<100)=0;landmask(landmask>100)=1;
landmask=landmask(win_index);
CGrid_Index(length(solar_index)+1:length(solar_index)+length(win_index),3)=landmask;
clear grid_ind R landmask

%% ======================== 7. 设置优化变量与约束 ========================
rng default
nvars=length(CGrid_Index);
load Global_Init_State.mat cur_storage cur_trans

% --- 决策变量上下界 ---
% 变量结构: [光伏选址(N_solar) | 风电选址(N_wind) | 储能功率(20) | 储能时长(20) | 输电容量(n_trans)]
lb=zeros(1,nvars);   % 选址变量下界=0（不选）
ub=ones(1,nvars);    % 选址变量上界=1（选中）

% 储能功率（TW）：下界=当前已有储能，上界=区域峰值负荷×1000（GW）
al=max(all_loads,[],2);% 各区域峰值负荷（TW）
lb(nvars+1:nvars+20)=cur_storage/1000;ub(nvars+1:nvars+20)=al*1000;%单位 GW
clear cur_storage al

% 储能时长（小时）：下界=2h，上界=72h
lb(nvars+21:nvars+40)=2;ub(nvars+21:nvars+40)=72;

% 输电容量（GW）：清零跨洲链路的下界（大陆互联模式下不启用跨洲输电）
% 跨洲链路：北美↔欧洲（6-1, 7-1, 1-6, 1-7）、欧洲↔北美（17-4, 18-4, 4-17, 4-18）
cur_trans(6,1)=0;cur_trans(7,1)=0;cur_trans(1,6)=0;cur_trans(1,7)=0;
cur_trans(17,4)=0;cur_trans(18,4)=0;cur_trans(4,17)=0;cur_trans(4,18)=0;
tmp=cur_trans>0;cur_trans(cur_trans<2)=0;  % 仅保留已有 ≥2 GW 的链路
lb(nvars+41:nvars+40+sum(tmp(:)))=cur_trans(tmp)/1000;ub(nvars+41:nvars+40+sum(tmp(:)))=10*1000;%输电容量上界 10 TW（GW）
clear cur_trans
nvars=length(lb);
intcon=1:1:length(lb);  % 所有变量均为整数约束

%% ======================== 8. 运行 NSGA-II 优化 ========================
T = datetime('now');
disp(T)
fprintf('开始2050年优化（大陆互联，种群=1000，代数=200）...\n');
options = optimoptions('gamultiobj','UseParallel',true,'PlotFcn',[],'PopulationSize',1000,'MaxGenerations',200);
[res_scale,prs]=gamultiobj(@(scale)  OptFun_SC_Dispatch_2050(all_ins,all_gens,all_loads,CGrid_Index,scale),...
    nvars,[],[],[],[],lb,ub,@nonlcon2050,intcon,options);
T = datetime('now');
disp(T)
fprintf('优化完成，共 %d 个 Pareto 解\n', size(prs,1));

%% ======================== 9. 保存结果 ========================
if exist('Optimization_SC_2050_Res.h5','file'), delete('Optimization_SC_2050_Res.h5'); end
h5create('Optimization_SC_2050_Res.h5','/res_scale',size(res_scale));
h5write('Optimization_SC_2050_Res.h5','/res_scale',res_scale);
h5create('Optimization_SC_2050_Res.h5','/prs',size(prs));
h5write('Optimization_SC_2050_Res.h5','/prs',prs);
fprintf('结果已保存至 Optimization_SC_2050_Res.h5\n');

%% ======================== 10. 关闭并行池 ========================
pool = gcp('nocreate');
if ~isempty(pool)
    delete(pool);
    fprintf('并行池已关闭\n');
end
