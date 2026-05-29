clear,clc

% Start parallel pool for gamultiobj acceleration
try
    pool = parpool('local');
    fprintf('Parallel pool started: %d workers\n', pool.NumWorkers);
catch ME
    if contains(ME.identifier, 'parallel:pool:alreadyopen')
        pool = gcp('nocreate');
        fprintf('Parallel pool already running: %d workers\n', pool.NumWorkers);
    else
        warning('Failed to start parallel pool: %s', ME.message);
    end
end

%wind generation curves
luccs=geotiffread('Global_Wind_Net_Area_Add_Egrid.tif');
luccs=luccs/100;% percentage
win_index=find(luccs>0);
fish_area=geotiffread('Global_Wind_Fishnet_Area.tif');
fish_area=double(fish_area);%km2
areas=luccs(win_index).*fish_area(win_index);
landmask=readgeoraster('Global_LandMask.tif');
landmask(landmask<100)=0;landmask(landmask>100)=1;
landmask=landmask(win_index);
wind_ins=(2.7*areas)/1000/1000;%Uint TWp
wind_ins(landmask==1)=(4.6*areas(landmask==1))/1000/1000;%Uint TWp
wind_gen=h5read('Global_Wind_CFs_Sel.h5','/data');
for ii=1:8477
    wind_gen(ii,:)=wind_gen(ii,:)*wind_ins(ii);%unit TWh
end
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

%Solar generation curves
grids=geotiffread('Global_fishnet.tif');
solar_index=find(grids<65536);
grids(solar_index)=0;
load  Global_Solar_CFs
res_CF=res_CF/10/1000;
luccs=geotiffread('Global_Solar_Net_Area_Add_Egrid.tif');
luccs=luccs/100;% percentage
fish_area=geotiffread('Global_Solar_Fishnet_Area.tif');
fish_area(fish_area<0)=0;
fish_area=double(fish_area);%km2
areas=luccs(solar_index).*fish_area(solar_index);
solar_gen=res_CF;clear res_CF
solar_ins=zeros([13296,1]);
for ii=1:13296
    solar_ins(ii)=(74*areas(ii))/1000/1000;%unit TWp
    solar_gen(ii,:)=solar_gen(ii,:)*(74*areas(ii))/1000/1000;%unit TWh
end
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

all_gens=[solar_gen;wind_gen];
all_ins=[solar_ins;wind_ins];
clear solar_gen wind_gen
clear solar_ins wind_ins 

%global load profiles in 2050
load Global_Load_22region.mat
all_loads=squeeze(all_loads(4,:,:))/1000/1000;%TW;
global_load=sum(all_loads,1);
all_loads=all_loads/(sum(global_load(:))/71164);
% Figure 1f
% global_gen=sum(all_gens,1);
% global_load=sum(all_loads,1);
% sum(global_gen(:))/sum(global_load(:))
% global_gen=reshape(global_gen,[24,365]);
% global_gen=mean(global_gen,2);
% global_load=reshape(global_load,[24,365]);
% global_load=mean(global_load,2);
% figure,plot(global_load);
% hold on,plot(global_gen)
% ylim([0 50])
clear global_load

[grid_ind,R]=readgeoraster('Global_Grid_Division.tif');
CGrid_Index=[grid_ind(solar_index);grid_ind(win_index)];
nonlcon_sel=CGrid_Index; nonlcon_ins=all_ins;
nonlsol=length(solar_index); nonlwin=length(win_index);
save NonlConData nonlcon_sel nonlcon_ins nonlsol nonlwin
clear nonlcon_sel nonlcon_ins nonlsol nonlwin
landmask=readgeoraster('Global_LandMask.tif');
landmask(landmask<100)=0;landmask(landmask>100)=1;
landmask=landmask(win_index);
CGrid_Index(length(solar_index)+1:length(solar_index)+length(win_index),3)=landmask;
clear grid_ind R landmask


%optimization 2050
% find the optimal layout
rng default
nvars=length(CGrid_Index);
load Global_Init_State.mat cur_storage cur_trans
% lb<= X <= ub
lb=zeros(1,nvars);
ub=ones(1,nvars);
al=max(all_loads,[],2);% Unit TW
lb(nvars+1:nvars+20)=cur_storage/1000;ub(nvars+1:nvars+20)=al*1000;%storage power (GW)
clear cur_storage al
lb(nvars+21:nvars+40)=2;ub(nvars+21:nvars+40)=72;%storage duration (hours)
tmp=cur_trans>0;cur_trans(cur_trans<2)=0;
lb(nvars+41:nvars+40+sum(tmp(:)))=cur_trans(tmp)/1000;ub(nvars+41:nvars+40+sum(tmp(:)))=10*1000;% Transmission power (GW)
clear cur_trans
nvars=length(lb);
intcon=1:1:length(lb);
% population_size = 500; 
% initial_population = [rand(population_size, length(all_gens)) < 0.3, rand(population_size, 20) * 2000,rand(population_size, 20) * 72,rand(population_size, sum(tmp(:))) * 10000];
% options = optimoptions('gamultiobj', ...
%     'InitialPopulationMatrix', initial_population, ...
%     'PopulationSize', population_size, ...
%     'MaxGenerations', 100,'PlotFcn',@gaplotpareto);
% gens=all_gens;
% loads=all_loads;
% ins_cap=all_ins;
% scale=rand(nvars,1);
T = datetime('now');
disp(T)
options = optimoptions('gamultiobj','UseParallel',true,'PlotFcn',[]);
[res_scale,prs]=gamultiobj(@(scale)  OptFun_SG_Dispatch_2050(all_ins,all_gens,all_loads,CGrid_Index,scale),...
    nvars,[],[],[],[],lb,ub,@nonlcon2050,intcon,options);
% [res_scale,prs]=gamultiobj(@(scale)  OptFun_SG_Dispatch(all_ins,all_gens,all_loads,CGrid_Index,scale),...
%     nvars,[],[],[],[],lb,ub,[],intcon,options);
T = datetime('now');
disp(T)
mkdir -p results;  % 确保结果目录存在
h5create('results/Optimization_SG_2050_Res.h5','/res_scale',size(res_scale));
h5write('results/Optimization_SG_2050_Res.h5','/res_scale',res_scale);
h5create('results/Optimization_SG_2050_Res.h5','/prs',size(prs));
h5write('results/Optimization_SG_2050_Res.h5','/prs',prs);

% Shutdown parallel pool
pool = gcp('nocreate');
if ~isempty(pool)
    delete(pool);
    fprintf('Parallel pool shut down.\n');
end







