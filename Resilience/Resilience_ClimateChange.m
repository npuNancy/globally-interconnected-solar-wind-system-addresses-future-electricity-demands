clear,clc
load Opt_SC_2040_Sel opt_trans opt_stoCap opt_stoPow opt_wind opt_solar
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
clear areas fish_area luccs
win_index2=find(opt_wind==1);
[~, loc] = ismember(win_index2, win_index);
wind_ins=wind_ins(loc);wind_gen=wind_gen(loc,:);win_index=win_index(loc);
clear win_index2
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
solar_index2=find(opt_solar==1);
[~, loc] = ismember(solar_index2, solar_index);
solar_ins=solar_ins(loc);solar_gen=solar_gen(loc,:);solar_index=solar_index(loc);
clear areas fish_area luccs grids solar_index2 loc
all_gens=[solar_gen;wind_gen];
all_ins=[solar_ins;wind_ins];
clear solar_gen wind_gen
clear solar_ins wind_ins 
%global load profiles in 2030
load Global_Load_22region.mat
all_loads=squeeze(all_loads(2,:,:))/1000/1000;%TW;
global_load=sum(all_loads,1);
all_loads=all_loads/(sum(global_load(:))/37316);
clear global_load
[grid_ind,R]=readgeoraster('Global_Grid_Division.tif');
CGrid_Index=[grid_ind(solar_index);grid_ind(win_index)];
nonlcon_sel=CGrid_Index; nonlcon_ins=all_ins;
nonlsol=length(solar_index); nonlwin=length(win_index);
clear nonlcon_sel nonlcon_ins nonlsol nonlwin
landmask=readgeoraster('Global_LandMask.tif');
landmask(landmask<100)=0;landmask(landmask>100)=1;
landmask=landmask(win_index);
CGrid_Index(length(solar_index)+1:length(solar_index)+length(win_index),3)=landmask;
clear grid_ind R landmask
%Dispatch 2030
prs=h5read('Optimization_SA_2030_Res.h5','/prs');
res_scale=h5read('Optimization_SA_2030_Res.h5','/res_scale');
scale=res_scale(5,:);
CGrid_Index(1:2334,2)=1;CGrid_Index(2335:2334+2312,2)=0;
sens_climate=zeros(200,1);
for ii=1:200
    ii
    gens=all_gens;
    tmpindex=CGrid_Index(:,2)==1;
    X = (rand([sum(tmpindex),8760])*10-5)/100;       
    gens(tmpindex,:)=all_gens(tmpindex,:).*(1+X);
    tmpindex=CGrid_Index(:,2)==0;
    X = (rand([sum(tmpindex),8760])*2-1)/100;   
    gens(tmpindex,:)=all_gens(tmpindex,:).*(1+X);
    X = (rand(size(all_loads))*20-10)/100;   
    grid_load=all_loads.*(1+X);
    [f,con,flex,curtail,storage,shifted]=Fun_SA_Dispatch_2030(all_ins,gens,grid_load,CGrid_Index,scale);
    sens_climate(ii,1)=f(2);
end
[f,con,flex,curtail,storage,shifted]=Fun_SA_Dispatch_2030(all_ins,all_gens,all_loads,CGrid_Index,scale);
sens_climate=sens_climate-f(2);
sens_climate=sens_climate*100;
max(sens_climate)
prctile(sens_climate, 90)
prctile(sens_climate, 50)
% h5create('Senstivity_2050_Res.h5','/data2',size(sens_climate));
% h5write('Senstivity_2050_Res.h5','/data2',sens_climate);
% clearvars -except res_consumption res_supply res_gens res_loads

%optimal configuration in 2040 under S-C
load Opt_SG_2050_Sel opt_trans opt_stoCap opt_stoPow opt_wind opt_solar
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
clear areas fish_area luccs
win_index2=find(opt_wind==1);
[~, loc] = ismember(win_index2, win_index);
wind_ins=wind_ins(loc);wind_gen=wind_gen(loc,:);win_index=win_index(loc);
clear win_index2
clear landmask
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
solar_index2=find(opt_solar==1);
[~, loc] = ismember(solar_index2, solar_index);
solar_ins=solar_ins(loc);solar_gen=solar_gen(loc,:);solar_index=solar_index(loc);
clear areas fish_area luccs grids solar_index2 loc
all_gens=[solar_gen;wind_gen];
all_ins=[solar_ins;wind_ins];
clear solar_gen wind_gen
clear solar_ins wind_ins 
%global load profiles in 2040
load Global_Load_22region.mat
all_loads=squeeze(all_loads(3,:,:))/1000/1000;%TW;
global_load=sum(all_loads,1);
all_loads=all_loads/(sum(global_load(:))/56553);
clear global_load
[grid_ind,R]=readgeoraster('Global_Grid_Division.tif');
CGrid_Index=[grid_ind(solar_index);grid_ind(win_index)];
nonlcon_sel=CGrid_Index; nonlcon_ins=all_ins;
nonlsol=length(solar_index); nonlwin=length(win_index);
clear nonlcon_sel nonlcon_ins nonlsol nonlwin
landmask=readgeoraster('Global_LandMask.tif');
landmask(landmask<100)=0;landmask(landmask>100)=1;
landmask=landmask(win_index);
CGrid_Index(length(solar_index)+1:length(solar_index)+length(win_index),3)=landmask;
clear grid_ind R landmask
clear opt_solar opt_stoCap opt_stoPow opt_trans opt_wind
%Dispatch 2040
prs=h5read('Optimization_SC_2040_Res.h5','/prs');
res_scale=h5read('Optimization_SC_2040_Res.h5','/res_scale');
scale=res_scale(15,:);

CGrid_Index(1:4324,2)=1;CGrid_Index(4325:4324+4294,2)=0;
sens_climate=zeros(200,1);
for ii=1:200
    ii
    gens=all_gens;
    tmpindex=CGrid_Index(:,2)==1;
    X = (rand([sum(tmpindex),8760])*10-5)/100;       
    gens(tmpindex,:)=all_gens(tmpindex,:).*(1+X);
    tmpindex=CGrid_Index(:,2)==0;
    X = (rand([sum(tmpindex),8760])*2-1)/100;   
    gens(tmpindex,:)=all_gens(tmpindex,:).*(1+X);
    X = (rand(size(all_loads))*20-10)/100;   
    grid_load=all_loads.*(1+X);
    [f,con,flex,curtail,storage,shifted]=Fun_SC_Dispatch_2040(all_ins,gens,grid_load,CGrid_Index,scale);
    sens_climate(ii,1)=f(2);
end
[f,con,flex,curtail,storage,shifted]=Fun_SC_Dispatch_2040(all_ins,all_gens,all_loads,CGrid_Index,scale);
sens_climate=sens_climate-f(2);
sens_climate=sens_climate*100;
max(sens_climate)
prctile(sens_climate, 90)
prctile(sens_climate, 50)


%optimal configuration in 2050 under S-G
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
tmp=wind_ins>0.0001;
wind_ins=wind_ins(tmp);wind_gen=wind_gen(tmp,:);win_index=win_index(tmp);
tmp=sum(wind_gen,2);
tmp=tmp<10;
wind_ins=wind_ins(tmp);wind_gen=wind_gen(tmp,:);win_index=win_index(tmp);
clear areas fish_area luccs tmp
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
tmp=solar_ins>0.001;
solar_ins=solar_ins(tmp);solar_gen=solar_gen(tmp,:);solar_index=solar_index(tmp);
tmp=sum(solar_gen,2);
tmp=tmp<90;
solar_ins=solar_ins(tmp);solar_gen=solar_gen(tmp,:);solar_index=solar_index(tmp);
clear areas fish_area luccs grids tmp
all_gens=[solar_gen;wind_gen];
all_ins=[solar_ins;wind_ins];
clear solar_gen wind_gen
clear solar_ins wind_ins 
%global load profiles in 2050
load Global_Load_22region.mat
all_loads=squeeze(all_loads(4,:,:))/1000/1000;%TW;
global_load=sum(all_loads,1);
all_loads=all_loads/(sum(global_load(:))/71164);
clear global_load
[grid_ind,R]=readgeoraster('Global_Grid_Division.tif');
CGrid_Index=[grid_ind(solar_index);grid_ind(win_index)];
landmask=readgeoraster('Global_LandMask.tif');
landmask(landmask<100)=0;landmask(landmask>100)=1;
landmask=landmask(win_index);
CGrid_Index(length(solar_index)+1:length(solar_index)+length(win_index),3)=landmask;
clear grid_ind R landmask
prs=h5read('Optimization_SG_2050_Res.h5','/prs');
res_scale=h5read('Optimization_SG_2050_Res.h5','/res_scale');
scale=res_scale(66,:);

CGrid_Index(1:5918,2)=1;CGrid_Index(5919:5918+6743,2)=0;
sens_climate=zeros(200,1);
for ii=1:200
    ii
    gens=all_gens;
    tmpindex=CGrid_Index(:,2)==1;
    X = (rand([sum(tmpindex),8760])*10-5)/100;       
    gens(tmpindex,:)=all_gens(tmpindex,:).*(1+X);
    tmpindex=CGrid_Index(:,2)==0;
    X = (rand([sum(tmpindex),8760])*2-1)/100;   
    gens(tmpindex,:)=all_gens(tmpindex,:).*(1+X);
    X = (rand(size(all_loads))*20-10)/100;   
    grid_load=all_loads.*(1+X);
    [f,con,flex,curtail,storage,shifted]=Fun_SG_Dispatch_2050(all_ins,gens,grid_load,CGrid_Index,scale);
    sens_climate(ii,1)=f(2);
end
[f,con,flex,curtail,storage,shifted]=Fun_SG_Dispatch_2050(all_ins,all_gens,all_loads,CGrid_Index,scale);
sens_climate=sens_climate-f(2);
sens_climate=abs(sens_climate)*100;
max(sens_climate)
prctile(sens_climate, 90)
prctile(sens_climate, 50)





