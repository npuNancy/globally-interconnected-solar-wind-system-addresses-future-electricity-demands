# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the codebase for the paper **"Globally Interconnected Solar-wind System Addresses Future Electricity Demands"**. It analyzes global wind/solar energy potential, performs multi-objective spatial layout optimization across three interconnection scenarios, and evaluates benefits and system resilience.

## Pipeline Architecture

The analysis follows a strict four-stage pipeline, where each stage depends on the previous:

```
Stage 1: GlobalPotential/    Resource assessment → annual generation potential maps
Stage 2: Optimization/       NSGA-II optimization → Pareto-optimal layouts (2050→2040→2030)
Stage 3: Benefits/           Energy equity, smoothing effects, exchange visualization
Stage 4: Resilience/         Stress testing under climate, geopolitical, market scenarios
```

The optimization is top-down nested: 2050 global (S-G) results constrain 2040 continental (S-C), which constrains 2030 adjacent (S-A).

## Languages and Tools

- **Python** (in `.venv/`): Solar CF simulation (`gsee`), wind CF simulation (`windpowerlib`), data processing
- **MATLAB** (R2024b, no Mapping Toolbox): Annual potential calculation, spatial optimization (`gamultiobj`/NSGA-II), resilience analysis. 
  - Matlab 在这不可用，需要重写 MATLAB 代码为 Python 代码。
    - 例如 读取 .tif 文件可以使用 `rasterio`
- **R**: Chord diagrams (`circlize`), polar charts (`ggplot2`) in Benefits/. 
  - R 语言在这不可用，需要重写 R 代码为 Python 代码（如使用 `matplotlib`、`seaborn`、`plotly` 等库）。


## Running the Code


## Key Technical Parameters

- **Grid resolution**: 1°×1° for optimization, 0.25°×0.25° for potential maps (720×1440 global grid)
- **20 global regions** subdivided from 6 continents (see Code_Documentation.md §4 for full mapping)
- **Optimization objectives**: (1) minimize curtailment rate, (2) maximize renewable penetration, (3) minimize total cost
- **Decision variables per stage**: grid selection (0/1) + storage power (20 regions) + storage duration (20 regions) + transmission power (route count)
- **Dispatch model**: 8760 hourly time steps, storage efficiency 95% charge/discharge, base-load fractions vary by year (2030: 36%, 2040: 11%, 2050: 9%)
- **Installation densities**: solar 74 MW/km², onshore wind 2.7 MW/km², offshore wind 4.6 MW/km²

## Key Data Files

GeoTIFFs (`.tif`), HDF5 (`.h5`), and MATLAB (`.mat`) files serve as inter-stage data exchange formats. Most are ArcGIS outputs. The Optimization stage produces `.h5` result files consumed by Benefits/ and Resilience/. See `Readme.txt` for the complete file inventory.

## Documentation

- `Readme.txt` — Full file inventory and descriptions (English)
- `Code_Documentation.md` — Detailed technical documentation (Chinese), includes all parameters, algorithms, and data flow
- `论文.md` — Paper manuscript (Chinese)
