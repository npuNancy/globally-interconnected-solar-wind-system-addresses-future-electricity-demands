clear,clc
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
selindex=66;
sellayout=res_scale(selindex,:);

gens=all_gens;
grid_load=all_loads;
CGrid_Index=CGrid_Index(:,1:3);
scale=sellayout;
CGrid_Index(:,2)=round(scale(1:end-40-82));

grid_gens=zeros(20,8760);
grid_ids=unique(CGrid_Index(:,1));
grid_ids=grid_ids(grid_ids>0);
for g_ind=1:20
    index=find((CGrid_Index(:,1)==grid_ids(g_ind))&(CGrid_Index(:,2)==1));
    selgens=gens(index,:);   
    grid_gens(g_ind,:)=nansum(selgens,1);
end

daily_gens=zeros(20,365);
for ii=1:20
    tmp=grid_gens(ii,:);
    tmp=reshape(tmp,[24,365]);
    tmp=sum(tmp,1);
    daily_gens(ii,:)=tmp;
end
daily_gens=daily_gens';
tmp=sum(daily_gens,2);
daily_gens(:,21)=tmp;

daily_cvs=zeros(21,1);
for ii=1:21
    tmp=daily_gens(:,ii);
    daily_cvs(ii)=std(tmp)/mean(tmp);
    daily_gens(:,ii)=daily_gens(:,ii)/mean(tmp);
end


colors={"#e57fef","#b1fead","#09bd66","#e838a2","#fdd1b6"...
    ,"#cee974","#497804","#f3eb37","#a704bf","#ac8ff1"...
    ,"#1102ee","#8c012f","#550b84","#af2302","#066c6f"...
    ,"#f3047f","#9c9c3a","#57e7d3","#c5d1fb","#7a8cd5"};
h=figure;
set(h,'position',[100 100 800 200]);
daily_gens=daily_gens(:,[10,12,13,9,11,5,6,7,8,16,17,18,19,20,15,14,1,2,3,4,21]);
for ii=1:20
    hold on,plot(daily_gens(:,ii),'color',colors{ii})
end
hold on,plot(daily_gens(:,21),'k-','linewidth',2);
ylim([0 2])
xlim([0 365])
%legend()

daily_cvs=daily_cvs([10,12,13,9,11,5,6,7,8,16,17,18,19,20,15,14,1,2,3,4,21]);
figure,bar(daily_cvs)


