clear,clc
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
clearvars -except solar_index win_index
solar_index2=solar_index;
win_index2=win_index;

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
tmp=wind_ins>0.0;
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
tmp=solar_ins>0.0;
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
nonlcon_sel=CGrid_Index; nonlcon_ins=all_ins;
nonlsol=length(solar_index); nonlwin=length(win_index);
save NonlConDataSac nonlcon_sel nonlcon_ins nonlsol nonlwin
clear nonlcon_sel nonlcon_ins nonlsol nonlwin
landmask=readgeoraster('Global_LandMask.tif');
landmask(landmask<100)=0;landmask(landmask>100)=1;
landmask=landmask(win_index);
CGrid_Index(length(solar_index)+1:length(solar_index)+length(win_index),3)=landmask;
clear grid_ind R landmask

%S-G
res_scale=h5read('Optimization_SG_2050_Res.h5','/res_scale');
prs=h5read('Optimization_SG_2050_Res.h5','/prs');
tmp1=res_scale(66,1:length(solar_index2));
isInMatrix2 = ismember(solar_index, solar_index2);
scale1=zeros(length(solar_index),1);
scale1(~isInMatrix2)=0;scale1(isInMatrix2)=tmp1;
tmp1=res_scale(66,length(solar_index2)+1:length(solar_index2)+length(win_index2));
isInMatrix2 = ismember(win_index, win_index2);
scale2=zeros(length(win_index),1);
scale2(~isInMatrix2)=0;scale2(isInMatrix2)=tmp1;
tmp1=res_scale(66,length(solar_index2)+length(win_index2)+1:end);
scale=[scale1',scale2',tmp1];
load Global_Trans trans_connections
trans=trans_connections;trans(trans>0)=1;
priceWeights=ones(20,1);
[f,con,flex,curtail,storage,shifted,grid_gens]=Fun_Dispatch_2050_Sen_flex_Corrected_CompletingPrice(all_ins,all_gens,all_loads,CGrid_Index,scale,0.09,trans,6,priceWeights);
% f(1)
% 1-f(2)-0.09
tmp1=sum(flex,1);
tmp2=sum(all_loads,2);
tmp1=tmp1(:)./tmp2(:);
tmp1=1-tmp1-0.09;
res_pr_base=tmp1;

res=zeros(20,20);
for ii=1:20
    ii
    %transmission power GW
    trans_power=zeros(20,20);
    trans_power(trans_connections>0)=scale(length(CGrid_Index)+41:end);
    tmp=trans_power(trans_connections>0);
    tmpscale=scale;
    tmpscale(length(CGrid_Index)+41:end)=[];
    tmpscale=[tmpscale(:);tmp(:)];
    tmpscale=tmpscale';
    trans=trans_connections;trans(trans>0)=1;
    for jj=1:20
        jj
        priceWeights=ones(20,1)*(1+jj*0.1);priceWeights(ii)=1;
        [f,con,flex,curtail,storage,shifted,grid_gens]=Fun_Dispatch_2050_Sen_flex_Corrected_CompletingPrice(all_ins,all_gens,all_loads,CGrid_Index,tmpscale,0.09,trans,6,priceWeights);
        tmp1=sum(flex,1);
        tmp2=sum(all_loads,2);
        tmp1=tmp1(:)./tmp2(:);
        tmp1=1-tmp1-0.09;
        res(ii,jj)=tmp1(ii)-res_pr_base(ii);
    end
end

tmp=abs(res);
for ii=20:-1:2
    tmp(:,ii)=tmp(:,ii)-tmp(:,ii-1);
end

tmp=max(tmp,[],2);
figure,bar(tmp([10,12,13,9,11,5,6,7,8,16,17,18,19,20,15,14,1,2,3,4]))

res=abs(res);
res=res*100;
llist=[10,12,13,9,11,5,6,7,8,16,17,18,19,20,15,14,1,2,3,4];
figure,hold on
for ii=1:20
    for jj=1:20
        if res(llist(ii),llist(jj))~=0
        scatter(ii,res(llist(ii),llist(jj)),'o','filled')
        end
    end
end
figure,bar(res([10,12,13,9,11,5,6,7,8,16,17,18,19,20,15,14,1,2,3,4],21))


