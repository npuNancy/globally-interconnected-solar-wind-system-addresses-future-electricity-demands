clear,clc
res_supply=zeros(20,3);
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
% tmp=(wind_ins<=0.0001)&(wind_ins>0);
% tmp2=wind_gen(tmp,:);
% rng(1);
% tmp = [zeros(799, 1); ones(900, 1)];
% tmp = tmp(randperm(length(tmp)));tmp = tmp==1;
% sum(tmp2(tmp,:)) sum(ans(:))
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

% S-G
res_scale=h5read('Optimization_SG_2050_Res.h5','/res_scale');
prs=h5read('Optimization_SG_2050_Res.h5','/prs');
scale=res_scale(66,:);%66 
load Global_Trans trans_connections
trans=trans_connections;trans(trans>0)=1;
[f,con,flex,curtail,storage,shifted,grid_gens]=Fun_Dispatch_2050_Sen_flex_Corrected(all_ins,all_gens,all_loads,CGrid_Index,scale,0.09,trans,6);
f(1) 
1-f(2)-0.09

res=zeros(20,2); 
for ii=1:20
    ii 
    trans_power=zeros(20,20);
    trans_power(trans_connections>0)=scale(length(CGrid_Index)+41:end);
    %transmission power GW 
    trans_power(ii,:)=0;trans_power(:,ii)=0;
    tmp=trans_power(trans_connections>0); 
    tmpscale=scale;
    tmpscale(length(CGrid_Index)+41:end)=[];
    tmpscale=[tmpscale(:);tmp(:)];
    tmpscale=tmpscale';
    trans=trans_connections;trans(trans>0)=1;
    [f,con,flex,curtail,storage,shifted,grid_gens]=Fun_Dispatch_2050_Sen_flex_Corrected(all_ins,all_gens,all_loads,CGrid_Index,tmpscale,0.09,trans,6);
    res(ii,1)=f(1); res(ii,2)=1-f(2)-0.09;
end 
res(:,1)=abs(res(:,1)-0.0609); 
res(:,2)=-1*abs(res(:,2)-0.7661);
figure,bar(res([10,12,13,9,11,5,6,7,8,16,17,18,19,20,15,14,1,2,3,4],1))
figure,bar(res([10,12,13,9,11,5,6,7,8,16,17,18,19,20,15,14,1,2,3,4],2))

trans_power=zeros(20,20);
trans_power(trans_connections>0)=scale(length(CGrid_Index)+41:end);
res_power=zeros(20,2);
res_power(:,1)=sum(trans_power,1);
res_power(:,2)=sum(trans_power,2);
res_power(:,3)=res_power(:,1)+res_power(:,2);
res_power=res_power/1000/1000;
figure,scatter(res_power(:,3),res(:,1))

