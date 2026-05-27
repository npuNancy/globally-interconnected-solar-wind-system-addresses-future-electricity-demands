%% test_optimization_speedup.m
%  对比 gamultiobj 在不同 optimoptions 配置下的运行速度
%
%  测试方案（通过 flag 控制是否运行）：
%    1. Baseline:   PlotFcn=@gaplotpareto, UseParallel=false
%    2. 方案 1:     UseParallel=true（并行评估）
%    3. 方案 3:     PlotFcn=[]（关闭绘图）
%    4. 方案 1+3:   UseParallel=true + PlotFcn=[]
%
%  使用 20 代、种群 200，仅对比速度，不关心优化质量。
%  运行前确保当前目录为 Optimization/。
clear; clc;

% --- 控制哪些测试运行 ---
RUN_TEST_1 = false;   % Baseline
RUN_TEST_2 = true;    % UseParallel=true
RUN_TEST_3 = false;   % PlotFcn=[]
RUN_TEST_4 = true;    % UseParallel=true + PlotFcn=[]

MaxGen  = 20;
PopSize = 200;

%% ==================== Data Preparation ====================
fprintf('[1/5] Data preparation ...\n');
tic;

% --- Wind ---
luccs = geotiffread('Global_Wind_Net_Area_Add_Egrid.tif');
luccs = luccs/100;
win_index = find(luccs>0);
fish_area = geotiffread('Global_Wind_Fishnet_Area.tif');
fish_area = double(fish_area);
areas = luccs(win_index).*fish_area(win_index);
landmask = readgeoraster('Global_LandMask.tif');
landmask(landmask<100)=0; landmask(landmask>100)=1;
landmask = landmask(win_index);
wind_ins = (2.7*areas)/1000/1000;
wind_ins(landmask==1) = (4.6*areas(landmask==1))/1000/1000;
wind_gen = h5read('Global_Wind_CFs_Sel.h5','/data');
for ii = 1:8477
    wind_gen(ii,:) = wind_gen(ii,:)*wind_ins(ii);
end
tmp = wind_ins>0.0001;
wind_ins = wind_ins(tmp); wind_gen = wind_gen(tmp,:); win_index = win_index(tmp);
tmp = sum(wind_gen,2);
tmp = tmp<10;
wind_ins = wind_ins(tmp); wind_gen = wind_gen(tmp,:); win_index = win_index(tmp);
clear areas fish_area luccs tmp landmask

% --- Solar ---
grids = geotiffread('Global_fishnet.tif');
solar_index = find(grids<65536);
grids(solar_index) = 0;
load Global_Solar_CFs
res_CF = res_CF/10/1000;
luccs = geotiffread('Global_Solar_Net_Area_Add_Egrid.tif');
luccs = luccs/100;
fish_area = geotiffread('Global_Solar_Fishnet_Area.tif');
fish_area(fish_area<0) = 0;
fish_area = double(fish_area);
areas = luccs(solar_index).*fish_area(solar_index);
solar_gen = res_CF; clear res_CF
solar_ins = zeros(13296,1);
for ii = 1:13296
    solar_ins(ii) = (74*areas(ii))/1000/1000;
    solar_gen(ii,:) = solar_gen(ii,:)*(74*areas(ii))/1000/1000;
end
tmp = solar_ins>0.001;
solar_ins = solar_ins(tmp); solar_gen = solar_gen(tmp,:); solar_index = solar_index(tmp);
tmp = sum(solar_gen,2);
tmp = tmp<90;
solar_ins = solar_ins(tmp); solar_gen = solar_gen(tmp,:); solar_index = solar_index(tmp);
clear areas fish_area luccs grids tmp

all_gens = [solar_gen; wind_gen];
all_ins  = [solar_ins; wind_ins];
clear solar_gen wind_gen solar_ins wind_ins

% --- Load ---
load Global_Load_22region.mat
all_loads = squeeze(all_loads(4,:,:))/1000/1000;
global_load = sum(all_loads,1);
all_loads = all_loads/(sum(global_load(:))/71164);
clear global_load

% --- Grid index ---
[grid_ind, ~] = readgeoraster('Global_Grid_Division.tif');
CGrid_Index = [grid_ind(solar_index); grid_ind(win_index)];
landmask = readgeoraster('Global_LandMask.tif');
landmask(landmask<100)=0; landmask(landmask>100)=1;
landmask = landmask(win_index);
CGrid_Index(length(solar_index)+1:length(solar_index)+length(win_index),3) = landmask;
clear grid_ind landmask

t_prep = toc;
fprintf('  Done. %.1f s  |  nvars = %d  (solar=%d, wind=%d)\n\n', ...
    t_prep, length(CGrid_Index)+40+60, length(solar_index), length(win_index));

%% ==================== Setup optimization variables ====================
rng default
nvars = length(CGrid_Index);
load Global_Init_State.mat cur_storage cur_trans
lb = zeros(1,nvars);
ub = ones(1,nvars);
al = max(all_loads,[],2);
lb(nvars+1:nvars+20)  = cur_storage/1000;
ub(nvars+1:nvars+20)  = al*1000;
clear cur_storage al
lb(nvars+21:nvars+40) = 2;
ub(nvars+21:nvars+40) = 72;
tmp = cur_trans>0; cur_trans(cur_trans<2)=0;
lb(nvars+41:nvars+40+sum(tmp(:))) = cur_trans(tmp)/1000;
ub(nvars+41:nvars+40+sum(tmp(:))) = 10*1000;
clear cur_trans tmp
nvars = length(lb);
intcon = 1:1:length(lb);

fprintf('  Total nvars = %d\n', nvars);
fprintf('  MaxGenerations = %d, PopulationSize = %d\n\n', MaxGen, PopSize);

%% ==================== Initialize result variables ====================
t1 = NaN; t2 = NaN; t3 = NaN; t4 = NaN;
n_workers = 0;

%% ==================== Setup parallel pool ====================
if RUN_TEST_2 || RUN_TEST_4
    has_parallel = false;
    try
        has_parallel = license('test', 'Distrib_Computing_Toolbox');
        if has_parallel
            pool = gcp('nocreate');
            if isempty(pool)
                pool = parpool('local');
            end
            n_workers = pool.NumWorkers;
            fprintf('Parallel pool: %d workers\n\n', n_workers);
        end
    catch ME
        fprintf('Parallel pool setup failed: %s\n\n', ME.message);
        has_parallel = false;
    end
else
    has_parallel = false;
end

%% ==================== Test 1: Baseline ====================
if RUN_TEST_1
    fprintf('[Test 1] Baseline (PlotFcn=gaplotpareto, no parallel) ...\n');
    rng default
    opts1 = optimoptions('gamultiobj', ...
        'PlotFcn', @gaplotpareto, ...
        'MaxGenerations', MaxGen, ...
        'PopulationSize', PopSize);
    tic;
    [res1, prs1] = gamultiobj(@(scale) OptFun_SG_Dispatch_2050(all_ins,all_gens,all_loads,CGrid_Index,scale), ...
        nvars, [],[],[],[], lb, ub, @nonlcon2050, intcon, opts1);
    t1 = toc;
    fprintf('  %.1f s (%.1f min)  |  Pareto fronts: %d\n\n', t1, t1/60, size(res1,1));
else
    fprintf('[Test 1] SKIPPED\n\n');
end

%% ==================== Test 2: UseParallel ====================
if RUN_TEST_2
    fprintf('[Test 2] UseParallel=true ...\n');
    if has_parallel
        rng default
        opts2 = optimoptions('gamultiobj', ...
            'PlotFcn', @gaplotpareto, ...
            'MaxGenerations', MaxGen, ...
            'PopulationSize', PopSize, ...
            'UseParallel', true);
        tic;
        [res2, prs2] = gamultiobj(@(scale) OptFun_SG_Dispatch_2050(all_ins,all_gens,all_loads,CGrid_Index,scale), ...
            nvars, [],[],[],[], lb, ub, @nonlcon2050, intcon, opts2);
        t2 = toc;
        fprintf('  %.1f s (%.1f min)  |  Pareto fronts: %d\n\n', t2, t2/60, size(res2,1));
    else
        fprintf('  SKIPPED: Parallel Computing Toolbox not available.\n\n');
    end
else
    fprintf('[Test 2] SKIPPED\n\n');
end

%% ==================== Test 3: PlotFcn=[] ====================
if RUN_TEST_3
    fprintf('[Test 3] PlotFcn=[] ...\n');
    rng default
    opts3 = optimoptions('gamultiobj', ...
        'PlotFcn', [], ...
        'MaxGenerations', MaxGen, ...
        'PopulationSize', PopSize);
    tic;
    [res3, prs3] = gamultiobj(@(scale) OptFun_SG_Dispatch_2050(all_ins,all_gens,all_loads,CGrid_Index,scale), ...
        nvars, [],[],[],[], lb, ub, @nonlcon2050, intcon, opts3);
    t3 = toc;
    fprintf('  %.1f s (%.1f min)  |  Pareto fronts: %d\n\n', t3, t3/60, size(res3,1));
else
    fprintf('[Test 3] SKIPPED\n\n');
end

%% ==================== Test 4: UseParallel + PlotFcn=[] ====================
if RUN_TEST_4
    fprintf('[Test 4] UseParallel=true + PlotFcn=[] ...\n');
    if has_parallel
        rng default
        opts4 = optimoptions('gamultiobj', ...
            'PlotFcn', [], ...
            'MaxGenerations', MaxGen, ...
            'PopulationSize', PopSize, ...
            'UseParallel', true);
        tic;
        [res4, prs4] = gamultiobj(@(scale) OptFun_SG_Dispatch_2050(all_ins,all_gens,all_loads,CGrid_Index,scale), ...
            nvars, [],[],[],[], lb, ub, @nonlcon2050, intcon, opts4);
        t4 = toc;
        fprintf('  %.1f s (%.1f min)  |  Pareto fronts: %d\n\n', t4, t4/60, size(res4,1));
    else
        fprintf('  SKIPPED: Parallel Computing Toolbox not available.\n\n');
    end
else
    fprintf('[Test 4] SKIPPED\n\n');
end

%% ==================== Summary ====================
fprintf('============================================================\n');
fprintf('  gamultiobj Speedup Comparison (MaxGen=%d, PopSize=%d, nvars=%d)\n', MaxGen, PopSize, nvars);
fprintf('============================================================\n');
fprintf('  #   Configuration              Time (min)   Speedup\n');
fprintf('  --------------------------------------------------------\n');
if ~isnan(t1)
    fprintf('  1.  Baseline                   %8.1f      1.0x\n', t1/60);
else
    fprintf('  1.  Baseline                   SKIPPED\n');
end
if ~isnan(t2)
    ref = t1; if isnan(ref), ref = t2; end
    fprintf('  2.  UseParallel (%d workers)   %8.1f      %.1fx (vs baseline)\n', n_workers, t2/60, ref/t2);
else
    fprintf('  2.  UseParallel                  SKIPPED\n');
end
if ~isnan(t3)
    ref = t1; if isnan(ref), ref = t3; end
    fprintf('  3.  PlotFcn=[]                %8.1f      %.1fx (vs baseline)\n', t3/60, ref/t3);
else
    fprintf('  3.  PlotFcn=[]                   SKIPPED\n');
end
if ~isnan(t4)
    ref = t1; if isnan(ref), ref = t4; end
    fprintf('  4.  Parallel + PlotFcn=[]     %8.1f      %.1fx (vs baseline)\n', t4/60, ref/t4);
else
    fprintf('  4.  Parallel + PlotFcn=[]        SKIPPED\n');
end
fprintf('  --------------------------------------------------------\n');
fprintf('  Data preparation: %.1f s\n', t_prep);
fprintf('============================================================\n');
