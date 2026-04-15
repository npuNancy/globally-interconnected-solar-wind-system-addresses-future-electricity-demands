********************************************************************************
This collection contains analytical codes for the manuscript 
“Globally Interconnected Solar-wind System Addresses Future Electricity Demands”, 
including codes for global wind and solar potential assessment, 
spatial layout optimization under global interconnection scenarios, 
and energy access equity analysis.
********************************************************************************

Folder Structure：

********************************************************************************
# GlobalPotential.zip
  Codes for global wind and solar potential assessment

## LUCC_Suitability_Add_Egrid_solar.tif
	ArcGIS output of LUCC suitability results for solar deployment
## LUCC_Suitability_Add_Egrid_wind.tif
	ArcGIS output of LUCC suitability results for deploying wind turbines
## fishnet_area_global.tif
	ArcGIS output of the area of global 1° x 1° grids
## Global_fishnet.tif
	ArcGIS output of the area of continental 1° x 1° grids	
## 1.1_Simulate_Solar_CF_PVLIB.py
	Codes for simulating hourly capacity factor for solar power generation
## 1.2_Simulate_Wind_CF_windpowerlib.py
	Codes for simulating hourly capacity factor for wind power generation	
## Wind_Annual_CF.tif
	ArcGIS output of annual average of capacity factor for wind power generation	
## Global_land_CF.mat
	Annual average of capacity factor for solar power generation in continental 1° x 1° grids
## 1.3_Calculate_Wind_Solar_Annual_Potential.m	
    Code for calculating wind and solar generation in MATLAB
## Wind_Solar_AnnualPotential_025.tif	
	Results of global wind and solar generation (Unit TWh per year)
********************************************************************************	

********************************************************************************
# Optimization.zip
  Codes for spatial layout optimization under global interconnection scenarios

## Optimization_SG_2050.m
	Code for Obtaining Optimal Spatial Layout for the global interconnection scenario in 2050
## Global_Wind_Net_Area_Add_Egrid.tif	
	Net land area per grid for wind deployment	
## Global_Wind_Fishnet_Area.tif	
	ArcGIS output of the area of global 1° x 1° grids for wind potentials
## Global_LandMask.tif
	ArcGIS output of the area of continental 1° x 1° grids for wind potentials
## Global_Wind_CFs_Sel.h5
	Annual average of capacity factor for wind power generation in grids with wind turbines
## Global_fishnet.tif	
	ArcGIS output of the area of global 1° x 1° grids solar potentials	 
## Global_Solar_CFs.mat	
	Annual average of capacity factor for solar power generation in continental 1° x 1° grids
## Global_Solar_Net_Area_Add_Egrid.tif
	Net land area per grid for solar deployment	
## Global_Solar_Fishnet_Area.tif
	ArcGIS output of the area of continental 1° x 1° grids for solar potentials
## Global_Load_22region.mat
	Forecasted load profiles for different regions
## Global_Grid_Division.tif
	Indicates the regional grid to which each grid belongs
## Global_Init_State.mat
	Current capacities for solar, wind, storage, and transmission
## OptFun_SG_Dispatch_2050.m
	Code for electricity dispatch analysis under global interconnection scenario in the 2050s
## nonlcon2050.m
	Nonlinear constraint function under global interconnection scenario in the 2050s
## NonlConData.mat
	Nonlinear constraint matrix under global interconnection scenario in the 2050s
## Global_Trans.mat
	Possible trans-regional transmission routes and corresponding loss matrix
## Optimization_SC_2040.m
	Code for Obtaining Optimal Spatial Layout for the continental interconnection scenario in 2040
## Opt_SG_2050_Sel.mat
	Constraint matrix for layout optimization in 2040
## OptFun_SC_Dispatch_2040.m
	Code for electricity dispatch analysis under global interconnection scenario in the 2040s
## nonlcon2040.m
	Nonlinear constraint function under global interconnection scenario in the 2040s
## NonlConData2040.mat
	Nonlinear constraint matrix under global interconnection scenario in the 2040s
## Optimization_SA_2030.m
	Code for Obtaining Optimal Spatial Layout for the continental interconnection scenario in 2030
## Opt_SC_2040_Sel.mat
	Constraint matrix for layout optimization in 2030
## OptFun_SA_Dispatch_2030.m
	Code for electricity dispatch analysis under global interconnection scenario in the 2030s
## nonlcon2030.m
	Nonlinear constraint function under global interconnection scenario in the 2030s
## NonlConData2030.mat
	Nonlinear constraint matrix under global interconnection scenario in the 2030s
********************************************************************************

********************************************************************************
# Benefits.zip
  Codes for analysis of potential benefits
  
## Benefits_Data_Summary.xlsx	
	Statistical data to support analysis of potential benefits
## EnergyEquity.m	
	Code for plotting the Lorentz curve and calculating the Gini coefficient
## EnergyExchange.R	
	Codes for visualizing the transmission of power across regions
## Pressure.txt	
	Data to support analysis of economic pressure
## Pressure.R	
	Codes for visualizing the economic pressure (Fig. 3e)
## Smoothing_Effects.m	
	Codes for comparing the fuctuations in power generation curves between global interconnections and independent grids
********************************************************************************

********************************************************************************
# Resilience.zip
  Codes for resilience analysis of a globally interconnected system  
## Resilience_ClimateChange.m	
	Code for the scenario under climate changes
## Optimization_SA_2030_Res.h5	
	Optimization results for the 2030s
## Fun_SA_Dispatch_2030.m	
	Function for analyzing electricity dispatch in a given spatial layout for the 2030s
## Optimization_SC_2040_Res.h5	
	Optimization results for the 2040s
## Fun_SC_Dispatch_2040.m	
	Function for analyzing electricity dispatch in a given spatial layout for the 2040s
## Optimization_SG_2050_Res.h5	
	Optimization results for the 2050s
## Fun_SG_Dispatch_2050.m	
	Function for analyzing electricity dispatch in a given spatial layout for the 2050s
## Resilience_GenerationFailture.m
	Code for the scenario under extreme weather events
## Resilience_GreatPowerRivalry.m
	Code for the scenario under incompatible regional policies
## Resilience_GeopolticalTensions.m
	Code for the scenario under geopolitical tensions
## CompletingPrices.m
	Code for the scenario under market competition
********************************************************************************