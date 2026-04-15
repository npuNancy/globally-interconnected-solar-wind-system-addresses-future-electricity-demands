#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Tue Jan 10 10:34:16 2023

@author: root
"""


import numpy as np
import pandas as pd
import xarray as xr
import h5py,time
import gsee.climatedata_interface.interface as interface
import multiprocessing as mp
import calendar,os,cv2
import matplotlib.pyplot as plt
import multiprocessing
from joblib import Parallel, delayed, wrap_non_picklable_objects
from joblib.parallel import get_active_backend
from gsee.climatedata_interface.pre_gsee_processing import resample_for_gsee
from calendar import monthrange
from itertools import product
import multiprocessing
from scipy import spatial


def run_interface(
        ghi_data: tuple,
        outfile: str,
        params: dict,
        frequency='detect',
        diffuse_data=('', ''),
        temp_data=('', ''),
        timeformat=None,
        pdfs_file='builtin',
        num_cores=multiprocessing.cpu_count()):
    """
    Input file must include 'time', 'lat' and 'lon' dimensions.

    Parameters
    ----------
    ghi_data: tuple
        Tuple with path to a NetCDF file with diffuse fraction data
        and variable name in that file.
    outfile: string
        Path to NetCDF file to store output in.
    params: dict
        Parameters for GSEE, i.e. 'tilt', 'azim',
        'tracking', 'capacity'. tilt can be a function depending on
        latitude -- see example input. Tracking can be 0, 1, 2 for no
        tracking, 1-axis tracking, 2-axis tracking.
    frequency: str, optional
        Frequency of the input data. One of ['A', 'S', 'M', 'D', 'H'],
        for annual, seasonal, monthly, daily, hourly. Defaults to 'detect',
        whith attempts to automatically detect the correct frequency.
    diffuse_data: tuple, optional
        Tuple with path to a NetCDF file with diffuse fraction data
        and variable name in that file. If not given, BRL model is
        used to estimate diffuse fraction.
    temp_data: tuple, optional
        Tuple with path to a NetCDF file with temperature data (°C or °K)
        and variable name in that file. If not given, constant
        temperatore of 20 degrees C is assumed.
    timeformat: string, optional
        If set to 'cmip5', then the date format common in the CMIP5
        dataset (e.g. '20070104.5') is correctly dealt with.
        Otherwise it is left to xarray to detect the time format.
    pdfs_file: str, optional
        Path to a NetCDF file with probability density functions to use
        for each month. Only for annual, seasonal and monthly data.
        Default is 'builtin', which automatically downloads and uses a
        built-in global PDF based on MERRA-2 data. Set to None to disable.
    num_cores: int, optional
        Number of cores that should be used for the computation.
        Default is all available cores.

    Returns
    -------
    None

    """

    # Read Files:
    ds_merged, ds_in = _open_files(ghi_data, diffuse_data, temp_data)

    # If 'cmip5' is given the string of the form %Y%m%d.%f will be transformed to datetime object
    if timeformat == 'cmip5':
        try:
            ds_merged['time'] = _parse_cmip_time_data(ds_merged)
        except Exception:
            raise ValueError(
                'Parsing of "cmip5" time dimension failed. Set timeformat to None, or check your data.'
            )

    # Check whether the time dimension was recognised correctly and interpreted as time by dataset
    if not type(ds_merged['time'].values[0]) is np.datetime64:
        raise ValueError(
            'Time format not recognised. Try setting timeformat="cmip5" or check your data.'
        )

    if os.path.isfile(outfile):
        print('{} already exists --> skipping'.format(outfile.split('/', -1)[-1]))
    else:
        print('{} does not yet exist --> Computing in '.format(outfile.split('/', -1)[-1]), end='')

        ds_pv = run_interface_from_dataset(
            data=ds_merged,
            params=params,
            frequency=frequency,
            pdfs_file=pdfs_file,
            num_cores=num_cores
        )

        for var in ds_in.data_vars:
            if var == 'time_bnds':
                ds_pv[var] = ds_in[var]

        # Save results with zlib compression
        encoding_params = {'zlib': True, 'complevel': 4}
        encoding = {k: encoding_params for k in list(ds_pv.data_vars)}
        ds_pv.to_netcdf(path=outfile, format='NETCDF4', encoding=encoding)


def _mod_time_dim(time_dim: pd.DatetimeIndex, freq: str):
    """
    Modify Time dimension so it fits the requirements of the "resample_for_gsee" function
    Parameters
    ----------
    time_dim: array
        with datetime entries
    freq: string
        representing data frequency of na_time

    Returns
    -------
    array
        modified time dimension
    """
    if freq == 'A':
        # Annual data is set to the beginning of the year
        return time_dim.map(lambda x: pd.Timestamp(year=x.year, month=1, day=1, hour=0, minute=0))
    elif freq in ['S', 'M']:
        # Seasonal data is set to middle of month, as it is often represented with the day in the middle of the season.
        # Monthly data is set to middle of month
        return time_dim.map(lambda x: pd.Timestamp(year=x.year, month=x.month,
                                                   day=int(monthrange(x.year, x.month)[1] / 2), hour=0,
                                                   minute=0))
    elif freq == 'D':
        # Daily data is set to 00:00 hours of the day
        return time_dim.map(lambda x: pd.Timestamp(year=x.year, month=x.month, day=x.day, hour=0, minute=0))
    else:
        return time_dim

# ----------------------------------------------------------------------------------------------------------------------
# Support functions for run_interface:
# ----------------------------------------------------------------------------------------------------------------------


def _detect_frequency(ds: xr.Dataset, frequency='detect'):
    """
    Tries to detect the frequency of the given dataset.

    Raises Warning if the detected freqency does not match that
    given in frequency, if frequency is not set to 'detect'.

    Parameters
    ----------
    ds : xarray Dataset
        Must contain a 'time' dimension.
    frequency : str, optional
        Optionalluy set this to frequencuy given by user: one of
        ['A', 'S', 'M', 'D', 'H'] for annual, seasonal, monthly, daily, hourly.

    Returns
    -------
    data_freq : str
        Detected or validated frequency.

    """
    # Tries to detect frequency, otherwise falls back to manual entry, also compares if the two match:
    nc_freq = None
    try:
        nc_freq = ds.attrs['frequency']
    except KeyError:
        try:
            nc_freq = pd.DatetimeIndex(data=ds['time'].values).inferred_freq[0]
        except:
            pass
    if not nc_freq:
        print('> No frequency detected --> checking manually given frequency', end='')
        if frequency in ['A', 'S', 'M', 'D', 'H']:
            print('...Manual entry is valid')
            data_freq = frequency
        else:
            raise ValueError('Detect failed or manual entry is invalid.')
    else:
        if nc_freq == 'year':
            data_freq = 'A'
        elif nc_freq == 'mon':
            data_freq = 'M'
        elif nc_freq == 'day':
            data_freq = 'D'
        else:
            data_freq = nc_freq
        print('> Detected frequency: {}'.format(data_freq))

    if frequency == 'S' and data_freq not in ['A', 'M', 'D', 'H']:
        print('> Frequency is detected, but is not "A", "M", "D", or "H" thus assumed some kind of seasonal')
        return frequency
    if data_freq in ['A', 'S', 'M', 'D', 'H'] and frequency != data_freq and frequency != 'detect':
        raise Warning(
            '\tManual given frequency is valid, however it does not match detected frequency. Check settings!')
    if data_freq not in ['A', 'S', 'M', 'D', 'H']:
        raise ValueError('> Time frequency invalid, use one from ["A", "S", "M", "D", "H"]')
    return data_freq


def _parse_cmip_time_data(ds: xr.Dataset):
    """
    Converts time data saved as number with format "day as %Y%m%d.%f" to datetime64 format
    Parameters
    ----------
    ds: xarray dataset
        with 'time' dimension in "day as %Y%m%d.%f" format

    Returns
    -------
    array
        with converted datetime64 entries

    """
    # Translates date-string used in CMIP5 data to datetime-objects
    timestr = [str(ti) for ti in ds['time'].values]
    vfunc = np.vectorize(lambda x: np.datetime64('{}-{}-{}T{:02d}:{}'.format(
        x[:4], x[4:6], x[6:8], int(24 * float('0.' + x[9:])), '00'))
    )
    return vfunc(timestr)


def _open_files(ghi_data: tuple, diffuse_data: tuple, temp_data: tuple):
    """
    Opens the given files for GHI, diffuse Fraction and temperature, extracts the corresponding variables
    and merges all three together to one dataset.

    Parameters
    ----------
    ghi_data: Tuple
        with Filepath for .nc file with diffuse fraction data and variable name in that file
    diffuse_data: Tuple
        Tuple with Filepath for .nc file with diffuse fraction data and variable name in that file
    temp_data: Tuple
        Tuple with Filepath for .nc file with temperature data (°C or °K) and variable name in that file

    Returns
    -------
    ds_tot: xarray dataset
        merged dataset with all available variables: global_horizontal, diffuse_fraction, temperature
    ds_th_in: xarray dataset
        dataset of input file without any being processed. Is used later to detect frequency
    """
    ghi_file, ghi_var = ghi_data
    diffuse_file, diffuse_var = diffuse_data
    temp_file, temp_var = temp_data

    try:
        ds_ghi_in = xr.open_dataset(ghi_file, autoclose=True)
    except Exception:
        raise FileNotFoundError('Radiation file not found')

    # makes sure only the specified variable gets used further:
    ds_ghi = ds_ghi_in[ghi_var].to_dataset()
    ds_merged = ds_ghi
    ds_merged.rename({ghi_var: 'global_horizontal'}, inplace=True)

    # Open diffuse_fraction file:
    try:
        ds_diffuse_in = xr.open_dataset(diffuse_file, autoclose=True)
        ds_diffuse = ds_diffuse_in[diffuse_var].to_dataset()
        if ds_ghi.dims != ds_diffuse.dims:
            raise ValueError('Dimension of diffuse fraciton file does not match radiation file')
        ds_merged = xr.merge([ds_merged, ds_diffuse])
        ds_merged.rename({diffuse_var: 'diffuse_fraction'}, inplace=True)

    except OSError:
        print('> No diffuse fraction file found -> will calculate with BRL-Model')
    # Open temperature file:
    try:
        ds_temp_in = xr.open_dataset(temp_file, autoclose=True)
        ds_temp = ds_temp_in[temp_var].to_dataset()
        if ds_temp[temp_var].mean().values > 200:
            print('> Average temperature above 200° detected --> will convert to °C')
            ds_temp = ds_temp - 273.15  # convert form kelvin to celsius
        if ds_ghi.dims != ds_temp.dims:
            raise ValueError('Dimension of temperature file does not match radiation file')
        ds_merged = xr.merge([ds_merged, ds_temp])
        ds_merged.rename({temp_var: 'temperature'}, inplace=True)

    except OSError:
        print('> No temperature file found -> will assume 20°C default value')

    assert ds_merged.dims == ds_ghi.dims

    return ds_merged, ds_ghi_in

def dotplus(a,b):
    res=np.zeros(a.shape)
    for i in range(0,a.shape[0]):
        for j in range(0,a.shape[1]):
            res[i,j]=a[i,j]/b[i,j]
    return res

ssrfilepath=r'/home/jianghou_PV/GSEE_CF/ERA5_MultiYear'
datanames = os.listdir(ssrfilepath)

import glob2,math,os
datanames = glob2.glob(ssrfilepath+'/'+'*.h5')
datanames=sorted(datanames)
#sorted(glob.glob('*.txt'), key=os.path.getmtime)
#sorted(glob.glob('*.txt'), key=os.path.getsize)
#datanames=datanames[0:20]
print(len(datanames))
batch=2000
loops=math.ceil(len(datanames)/batch)
for i in range(0,loops):
    gsrInput=[]
    difInput=[]
    tempInput=[]
    wsInput=[]
    times=[]
    for j in range(0,batch):
        num=batch*i+j
        if num>=len(datanames):
            break
        filename=datanames[batch*i+j]
        f = h5py.File(filename,'r')#W/m2
        gsr=f['/GSR'][:]
        gsr=gsr.astype(np.float)
        gsr=np.transpose(gsr,[1,0])
        dif=f['/DIR'][:]
        dif=dif.astype(np.float)
        dif=np.transpose(dif,[1,0])
        dif=gsr-dif
        diffrac=dotplus(dif,gsr)
        index=np.where(diffrac>1)
        diffrac[index]=1
        index=np.where(diffrac<0)
        diffrac[index]=0
        gsr=np.reshape(gsr,[1,gsr.shape[0],gsr.shape[1]])
        diffrac=np.reshape(diffrac,[1,diffrac.shape[0],diffrac.shape[1]])  
        gsrInput.append(gsr)
        difInput.append(diffrac)        
        temp=f['/Temp'][:]
        temp=temp.astype(np.float)
        temp=np.transpose(temp,[1,0])      
        temp=np.reshape(temp,[1,temp.shape[0],temp.shape[1]])
        tempInput.append(temp)
        ws=f['/Wind'][:]
        ws=ws.astype(np.float)
        ws=np.transpose(ws,[1,0])      
        ws=np.reshape(ws,[1,ws.shape[0],ws.shape[1]])
        wsInput.append(ws)        
        hour=int(filename[-5:-3])-1
        hstr=str(hour)
        if hour<10:
            hstr='0'+hstr        
        timestr='2020'+'-'+filename[-9:-7]+'-'+filename[-7:-5]+' '+hstr+':00:00' 
        times.append(timestr)
    gsrInput=np.concatenate(gsrInput,axis=0)
    difInput=np.concatenate(difInput,axis=0)   
    
    lat=np.arange(-90,90,1)
    lat=lat[::-1]      
    lon=np.arange(0,360,1)
    index=np.where(lon>180)
    lon[index]=lon[index]-360
    frequency='H'
    time11=pd.DatetimeIndex(times) 
    ds = xr.Dataset(
        data_vars={'global_horizontal': (('time', 'lat', 'lon'), gsrInput),
                   'diffuse_fraction': (('time', 'lat', 'lon'), difInput),
                   'temperature':(('time', 'lat', 'lon'), tempInput),
                   'windspeed':(('time', 'lat', 'lon'), wsInput)},
        coords={'time': time11,'lat': lat, 'lon':lon})       
    params = dict(tilt=lambda lat: 0.35396 * lat + np.sign(lat+0.0000001)*16.84775, azim=180, tracking=0, capacity=1000)
    #params = {'tilt': 35, 'azim': 180, 'tracking': 0, 'capacity': 1000}
    
        
    lonmat, latmat = np.meshgrid(lon, lat)
    period=np.size(gsrInput,0)
    data=ds
    frequency = _detect_frequency(data, frequency)
    num_cores=76

    # Produce list of coordinates of all grid points to iterate over
    coord_list = list(product(data['lat'].values, data['lon'].values))

    # Modify time dimension so it fits the requirements of
    # the "resample_for_gsee" function
    data['time'] = _mod_time_dim(pd.to_datetime(data['time'].values), frequency)

    # Shareable list with a place for every coordinate in the grid
    manager = multiprocessing.Manager()
    shr_mem = manager.list([None] * len(coord_list))
    # Store length of coordinate list in prog_mem to draw
    # the progress bar dynamically
    prog_mem = manager.list()
    prog_mem.append(len(coord_list))

    start = time.time()

    pdfs_file=None
    if num_cores > 1:
        print('Parallel mode: {} cores'.format(num_cores))
        from joblib import Parallel, delayed
        Parallel(n_jobs=num_cores)(delayed(resample_for_gsee)(
            data.sel(lat=coords[0], lon=coords[1]), frequency, params,
            i, coords, shr_mem, prog_mem,
            None if pdfs_file is None else pdfs.sel(lat=coord_list_nn[i][0], lon=coord_list_nn[i][1])
        ) for i, coords in enumerate(coord_list))
    else:
        print('Single core mode')
        for i, coords in enumerate(coord_list):
            resample_for_gsee(
                data.sel(lat=coords[0], lon=coords[1]),
                frequency, params, i, coords, shr_mem, prog_mem,
                None if pdfs_file is None else pdfs.sel(lat=coord_list_nn[i][0], lon=coord_list_nn[i][1])
            )

    end = time.time()
    print('\nComputation part took: {} seconds'.format(str(round(end - start, 2))))
   
    gseepv=np.zeros((len(lat),len(lon),period))
    print(len(shr_mem))
    start1 = time.time()   
    count=0
    for piece in shr_mem:
        count=count+1
        if count%100==0:
            print(count)
        siglat=piece.coords['lat'].values
        siglon=piece.coords['lon'].values
        pv_vec=piece['pv'].values
        sigind=np.where((latmat==siglat) & (lonmat==siglon))
        gseepv[sigind[0],sigind[1],:]=pv_vec
    end1 = time.time()
    print("\nComputation part took: {} seconds".format(str(round(end1 - start1, 2)))) 
    
    for ii in range(0,period):
        tmp=gseepv[:,:,ii]
        tmp=np.around(tmp,5)
        tmp=tmp*10
        tmp=tmp.astype(np.uint16)
        nstr=times[ii]
        filename=r'/home/jianghou_PV/GSEE_CF/ERA5_CF'
        filename=filename+'/PV_GSEE_Tilt_'+nstr[0:4]+nstr[5:7]+nstr[8:10]+nstr[11:13]+'.h5'
        f=h5py.File(filename, 'w')
        f.create_dataset('PV',data = tmp)
        f.close() 



