# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the codebase for the paper **"Globally Interconnected Solar-wind System Addresses Future Electricity Demands"**. It analyzes global wind/solar energy potential, performs multi-objective spatial layout optimization across three interconnection scenarios (2030/2040/2050), and evaluates benefits and system resilience under multiple SSP scenarios.

## Pipeline Architecture

The analysis follows a strict four-stage pipeline where each stage depends on the previous:

```
Stage 1: GlobalPotential/    Resource assessment → annual generation potential maps
Stage 2: Optimization*/      NSGA-II optimization → Pareto-optimal layouts (2050→2040→2030)
Stage 3: Benefits/           Energy equity, smoothing effects, exchange visualization
Stage 4: Resilience/         Stress testing under climate, geopolitical, market scenarios
```

The optimization is top-down nested: 2050 global results constrain 2040 continental, which constrains 2030 adjacent. This runs across four scenario variants:
- `Optimization/` — Baseline
- `Optimization_ssp126/` — SSP1-2.6
- `Optimization_ssp245/` — SSP2-4.5
- `Optimization_ssp560/` — SSP5-6.0

Each SSP variant has identical file structure (optimizers, dispatch functions, constraints, config, shell scripts).

## Languages and Tools

- **Python** (`.venv/`): Solar CF simulation (`pvlib`), wind CF simulation (`windpowerlib`), data processing, visualization.
  - 激活虚拟环境: `source .venv/bin/activate`
  - 安装包: `uv pip install <package-name>`，并写入 `requirements.txt`
- **MATLAB** (R2024b, no Mapping Toolbox): Annual potential calculation, spatial optimization (`gamultiobj`/NSGA-II), resilience analysis.
  - 命令行执行: `/data6/yanxiaokai/MATLAB/R2024b/bin/matlab -batch "script_name"` (需先进入 .m 文件所在目录)
- **R**: 不可用。Benefits/ 中的 R 代码需重写为 Python（`matplotlib`、`seaborn`、`plotly`）。

## Running the Code

### Full pipeline (all SSP scenarios)
```bash
bash run_all.sh
```

### Single SSP scenario pipeline
```bash
cd Optimization_ssp126  # or ssp245, ssp560
bash run_full_pipeline.sh
```
This runs the three-stage sequential pipeline: 2050 optimization → convert_h5_to_sel → 2040 optimization → convert_h5_to_sel → 2030 optimization → convert_h5_to_sel.

### Individual optimization stage
```bash
cd Optimization_ssp126
bash run_2050_pipeline.sh  # only the 2050 stage
```

### Hourly dispatch visualization
```bash
cd Optimization_ssp126
bash run_hourly_visualization.sh  # MATLAB export + Python plotting
```

### Python visualization scripts (run from project root with venv activated)
```bash
python plot_optimal_stations.py     # Solar/wind station siting maps
python plot_pareto_front.py         # Pareto front and cost breakdown
python plot_hourly_energy_output.py # Hourly dispatch curves
python plot_transmission_network.py # Global transmission network map
python calc_capacity_from_optimization.py  # Installed capacity comparison
python summarize_costmin_results.py # Aggregate SSP diagnostics
```

### Stage 1: GlobalPotential (Python + MATLAB)
```bash
source .venv/bin/activate
python GlobalPotential/1.1_Simulate_Solar_CF_PVLIB.py
python GlobalPotential/1.2_Simulate_Wind_CF_windpowerlib.py
# Then MATLAB for annual potential:
cd GlobalPotential && /data6/yanxiaokai/MATLAB/R2024b/bin/matlab -batch "1.3_Calculate_Wind_Solar_Annual_Potential"
```

## Key Architecture Details

### Optimization entry points (MATLAB)
Each Optimization*/ directory has three optimizer entry points that call `ga()` with nonlinear constraints:
- `Optimization_SC_2050.m` → calls `nonlcon2050.m` + `OptFun_SC_Dispatch_2050.m`
- `Optimization_SC_2040.m` → calls `nonlcon2040.m` + `OptFun_SC_Dispatch_2040.m`
- `Optimization_SA_2030.m` → calls `nonlcon2030.m` + `OptFun_SA_Dispatch_2030.m`

### Shared utilities (`utils/`)
- `evaluate_dispatch_and_cost.m` — Core dispatch + cost evaluation (largest file, ~25KB)
- `cost_model_config.m` — Central cost parameters: CAPEX by continent, WACC (7.4%), technology lifetimes, O&M ratios, storage/transmission costs, curtailment constraints
- `build_greedy_initial_solution.m` / `build_initial_population.m` — GA initial population construction
- `select_preferred_solution.m` — Picks preferred Pareto solution
- `export_hourly_dispatch_detail.m` — Exports hourly dispatch to CSV for Python plotting

### Configuration
No YAML/JSON/TOML config files. All configuration is in MATLAB:
- `optimization_config.m` (in each Optimization_ssp*/ dir) — NSGA-II population size (1000), max generations (200), demand by year, base-load ratios, VRE share bounds, GA seed, parallel workers. Overridable via environment variables.
- `cost_model_config.m` (in `utils/`) — Cost model parameters. Note: `optimization_config.m`'s `MAX_CURTAILMENT` overrides the default from `cost_model_config.m`.

### Data flow between stages
- `.tif` (GeoTIFF) → `convert_tif_to_mat.py` → `.mat` (MATLAB) → optimizers → `.h5` (HDF5 results) → `convert_h5_to_sel.m` → `.mat` (spatial layout) → Benefits/ and Resilience/ consumers

## Key Technical Parameters

- **Grid resolution**: 1°×1° for optimization, 0.25°×0.25° for potential maps (720×1440 global grid)
- **20 global regions** subdivided from 6 continents (see Code_Documentation.md §4 for full mapping)
- **Optimization objectives**: (1) minimize curtailment rate, (2) maximize renewable penetration, (3) minimize total cost
- **Decision variables per stage**: grid selection (0/1) + storage power (20 regions) + storage duration (20 regions) + transmission power (route count)
- **Dispatch model**: 8760 hourly time steps, storage efficiency 95% charge/discharge, base-load fractions vary by year (2030: 36%, 2040: 11%, 2050: 9%)
- **Installation densities**: solar 74 MW/km², onshore wind 2.7 MW/km², offshore wind 4.6 MW/km²

## Documentation

- `Readme.txt` — Full file inventory and descriptions (English)
- `Code_Documentation.md` — Detailed technical documentation (Chinese), includes all parameters, algorithms, and data flow
- `论文.md` — Paper manuscript (Chinese)

## 要求
- plan mode 时，plan 使用中文撰写
