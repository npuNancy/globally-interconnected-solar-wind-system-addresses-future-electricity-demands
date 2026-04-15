clear,clc
final_res=zeros(720,1440);
%wind Potential
luccs=geotiffread('LUCC_Suitability_Add_Egrid_wind.tif');
luccs=luccs/100;% percentage
index=find(luccs>0);
fish_area=geotiffread('fishnet_area_global.tif');
fish_area=double(fish_area);%km2
fish_area=imresize(fish_area,[720,1440],'nearest');
fish_area=fish_area/16;
areas=luccs(index).*fish_area(index);
CFs=geotiffread('Wind_Annual_CF.tif');
CFs=CFs(index);
landmask=readgeoraster('Global_LandMask.tif');
landmask(landmask<100)=0;landmask(landmask>100)=1;
landmask=imresize(landmask,[720 1440],'nearest');
landmask=landmask(index);
gen_wind=(2.7*areas).*(8760*CFs)/1000/1000;%TW
gen_wind(landmask==1)=(4.6*areas(landmask==1)).*(8760*CFs(landmask==1))/1000/1000;%TW
final_res(index)=gen_wind;
% figure,imshow(final_res,[])

%Solar Potential
filename='Global_fishnet.tif';
grids=geotiffread(filename);
index=find(grids<65536);
grids(index)=0;
load  Global_land_CF
res_CF=res_CF/10/1000;
res_CF=nansum(res_CF,2);
CFs=zeros(180,360);
CFs(index)=res_CF;
CFs=imresize(CFs,[720,1440],'nearest');
% figure,imshow(grids,[])
luccs=geotiffread('LUCC_Suitability_Add_Egrid_solar.tif');
luccs=luccs/100;% percentage
% figure,imshow(luccs,[])
fish_area=geotiffread('fishnet_area_global.tif');
fish_area=double(fish_area);%km2
fish_area=imresize(fish_area,[720,1440],'nearest');
fish_area=fish_area/16;
index=find(luccs>0);
areas=luccs(index).*fish_area(index);
% figure,imshow(areas,[])
gen_solar=(74*areas).*(CFs(index))/1000/1000;%TW
final_res(index)=final_res(index)+gen_solar;
% figure,imshow(final_res,[])


% output
R = georasterref('RasterSize', size(final_res), 'LatitudeLimits', [-90 90], 'LongitudeLimits', [-180 180],'ColumnsStartFrom','north');
filename = 'Wind_Solar_AnnualPotential_025.tif';
geotiffwrite(filename, final_res, R);







