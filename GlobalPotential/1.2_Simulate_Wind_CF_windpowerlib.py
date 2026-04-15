# -*- coding: utf-8 -*-
"""
Created on Fri Feb 24 11:21:04 2023

@author: JIANGHOU
"""

import numpy as np
import pandas as pd
import h5py,os
from windpowerlib import ModelChain, WindTurbine, create_power_curve
from windpowerlib import WindFarm
from windpowerlib import TurbineClusterModelChain


os.chdir(r'F:\GlobalSolarNet\WindTurbinePotential')

filename='Onshore_Offshore_Indicator.h5'
f=h5py.File(filename,'r')
indicator=f['/data'][:]
indicator=np.transpose(indicator,[1,0])


year=1
for year in range(1,23):   
    print(year)
    filename='F:\GlobalSolarNet\WindTurbinePotential\Wind_S'+str(year)+'.h5'
    f=h5py.File(filename,'r')
    data=f['/data'][:]
    data=np.transpose(data,[2,1,0])
    #month day lat lon pressure,temperature,10 wind_speed,roughness_length, 100 wind_speed
    hnum=8760    
    f.close()
    #latlons=pd.read_csv(r'F:\Offshore_Solar_Wind\Data_Analysis\Wind_Lat_Lon.csv',header=None)    
    # Convert utc-time to local time
    ind=indicator[30000*(year-1):min(30000*year,len(indicator))]
    
    evalRes=np.zeros((len(data),hnum))
    ii=100
    for ii in range(0,len(data)):    
        print(ii)
        lat=data[ii,1,2]
        lon=data[ii,1,3]  
        tzs=np.round(lon/15)
        if tzs>=0:
            timezone='Etc/GMT-'+str(int(tzs)) 
        else:
            timezone='Etc/GMT+'+str(int(np.abs(tzs)))
        
        startstr=str(int(tzs))
        if (np.abs(tzs)<10)&(tzs>=0):
            startstr='0'+startstr
        if (np.abs(tzs)<10)&(tzs<0):
            startstr='-0'+str(int(np.abs(tzs)))
            
        startstr=str(2021)+'-01-01  '+startstr
        timeindex=pd.date_range(start=startstr, periods=hnum, freq='H')      
        timeindex=timeindex.tz_localize(timezone)  
        
        tmpdata=np.squeeze(data[ii,0:hnum,4:9])
        tmpdata=tmpdata.copy()
        tmpdata=np.array(tmpdata)
        weather=pd.DataFrame(tmpdata,index=timeindex)
       
        #aa=pd.DataFrame(data[1,:,:])
       
        #df_combine = pd.concat([df_basic1,df_basic2])
        #Pressure kPa; 2m temperature K; 10 wind m/s; roughness m; 100 wind m/s
        array2 = [['pressure','temperature','wind_speed','roughness_length','wind_speed'],[0,2,10,0,100]]
        m2 = pd.MultiIndex.from_arrays(array2, names= ['variable_name','height'])       
        weather.columns = m2
        weather['pressure']=weather['pressure']*1000
        #initialize_wind_turbines():
        # **** Data is provided in the oedb turbine library **********************
       
        if ind[ii]==1:
            my_power = pd.Series(
                [25,89,171,269,389,533,704,906,1136,1400,1674,1934,2160,2316,2416,2477,\
                 2514,2528,2530,2530,2530,2530,2530,2530,2530,2530,2530,2530,2530,2530,\
                 2530,2530,2530,2530,2530,2530,2530,2530,2530,2530,2530,2530,2530,2530,2530])#Unit kW
            my_power=my_power*1000#Unit W
            my_wind_speed = (3,3.5,4.0,4.5,5.0,5.5,6.0,\
                             6.5,7.0,7.5,8.0,8.5,9.0,9.5,\
                             10.0,10.5,11.0,11.5,12.0,12.5,13.0,\
                             13.5,14.0,14.5,15.0,15.5,16.0,16.5,17.0,17.5,18.0,\
                             18.5,19.0,19.5,20.0,20.5,21.0,21.5,22.0,22.5,23.0,\
                             23.5,24.0,24.5,25.0)
            my_turbine2 = {
            "nominal_power": 2.53e6,  # in W
            "hub_height": 120,  # in m
            "power_curve": create_power_curve(wind_speed=my_wind_speed, power=my_power),}
            my_turbine2 = WindTurbine(**my_turbine2)       
            #initialize_wind_farms          
            # for each turbine type you can either specify the number of turbines of
            # that type in the wind farm (float values are possible as well) or the
            # total installed capacity of that turbine type in W
            #5.4MW/km2        
            wind_turbine_fleet = pd.DataFrame(
                {
                    "wind_turbine": [my_turbine2, my_turbine2],  # as windpowerlib.WindTurbine
                    "number_of_turbines": [None, None],
                    "total_capacity": [1500*1e6, 1500*1e6],
                }
            )
            # initialize WindFarm object
            example_farm = WindFarm(
                name="example_farm", wind_turbine_fleet=wind_turbine_fleet
            )
            example_farm.efficiency = 0.9
            # power output calculation for turbine_cluster
            # own specifications for TurbineClusterModelChain setup
            mc_example_farm = TurbineClusterModelChain(example_farm).run_model(weather)
            # write power output time series to WindFarm object
            example_farm.power_output = mc_example_farm.power_output
            
            cc=mc_example_farm.power_output/1000/1000/3000#MW
            evalRes[ii,:]=cc
        if ind[ii]==2:     
            my_power = pd.Series(
                [100,157.2438525,289.0957319,455.9707666,623.7876006,757.5819406,891.0819684,1027.054219,1183.746051,\
                 1353.38762,1543.748771,1762.952521,1988.748864,2256.985031,2532.761477,2835.073114,3131.19046,3427.458886,\
                 3737.022376,4050.262154,4301.815956,4595.158358,4902.417874,5193.058559,5514.877538,5806.390533,6101.644562,\
                 6391.07121,6693.663425,7021.370283,7300.319415,7509.222237,7668.680603,7788.995443,7882.52787,7940.625104,\
                 7973.176037,8000,8000,8000,8000,8000,8000,8000,8000,8000,8000,8000,8000,8000,8000,8000,8000,8000,8000,8000,\
                 8000,8000,8000,8000,8000,8000,8000,8000,8000,8000,8000,8000,8000,8000,8000,8000,8000,8000,8000,8000,8000,\
                 8000,8000,8000,8000,8000])#Unit kW
            my_power=my_power*1000#Unit W
            my_wind_speed = (4,4.080628619,4.357803143,4.634977667,4.912152192,5.189326716,5.466501241,5.743675765,6.020850289,\
                             6.298024814,6.575199338,6.852373863,7.129548387,7.406722911,7.671298594,7.935874276,8.187851117,\
                             8.427229115,8.666607113,8.89338627,9.094967742,9.296549214,9.510729529,9.712311001,9.926491315,\
                             10.12807279,10.30445658,10.48084036,10.68242184,10.93439868,11.2115732,11.48874773,11.76592225,\
                             12.04309677,12.3202713,12.59744582,12.87462035,13,13.15179487,13.4289694,13.70614392,13.98331844,\
                             14.26049297,14.53766749,14.81484202,15.09201654,15.36919107,15.64636559,15.92354012,16.20071464,\
                             16.47788916,16.75506369,17.03223821,17.30941274,17.58658726,17.86376179,18.14093631,18.41811084,\
                             18.69528536,18.97245988,19.24963441,19.52680893,19.80398346,20.08115798,20.35833251,20.63550703,\
                             20.91268156,21.18985608,21.4670306,21.74420513,22.02137965,22.29855418,22.5757287,22.85290323,\
                             23.13007775,23.40725227,23.6844268,23.96160132,24.23877585,24.51595037,24.7931249,24.99470637)
            my_turbine2 = {
            "nominal_power": 8e6,  # in W
            "hub_height": 120,  # in m
            "power_curve": create_power_curve(wind_speed=my_wind_speed, power=my_power),}
            my_turbine2 = WindTurbine(**my_turbine2)       
            #initialize_wind_farms          
            # for each turbine type you can either specify the number of turbines of
            # that type in the wind farm (float values are possible as well) or the
            # total installed capacity of that turbine type in W
            #5.4MW/km2        
            wind_turbine_fleet = pd.DataFrame(
                {
                    "wind_turbine": [my_turbine2, my_turbine2],  # as windpowerlib.WindTurbine
                    "number_of_turbines": [None, None],
                    "total_capacity": [1500*1e6, 1500*1e6],
                }
            )
            # initialize WindFarm object
            example_farm = WindFarm(
                name="example_farm", wind_turbine_fleet=wind_turbine_fleet
            )
            example_farm.efficiency = 0.9
            # power output calculation for turbine_cluster
            # own specifications for TurbineClusterModelChain setup
            mc_example_farm = TurbineClusterModelChain(example_farm).run_model(weather)
            # write power output time series to WindFarm object
            example_farm.power_output = mc_example_farm.power_output
            
            cc=mc_example_farm.power_output/1000/1000/3000#MW
            evalRes[ii,:]=cc        
#        mc_example_turbine = ModelChain(my_turbine2, wind_speed_model="hellman").run_model(weather)
#        aa = mc_example_turbine.power_output
#        mc_example_farm = TurbineClusterModelChain(example_farm).run_model(weather)
#        # write power output time series to WindFarm object
#        bb = mc_example_farm.power_output        
    del data       
    filename='F:\GlobalSolarNet\WindTurbinePotential\Wind_Farm_CF_'+str(year)+'.h5'
    f=h5py.File(filename,'w')
    f.create_dataset('data',data=evalRes)
    f.close()
#np.sum(cc)/1000/1000

