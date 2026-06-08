set -e
set -x

export PARPOOL_NUM_WORKERS=32
cd /data4/yanxiaokai/project_energy_climate/globally_interconnected_reRun/Optimization_ssp126
bash run_full_pipeline.sh &> logs/run_full.log

export PARPOOL_NUM_WORKERS=32
cd /data4/yanxiaokai/project_energy_climate/globally_interconnected_reRun/Optimization_ssp245
bash run_full_pipeline.sh &> logs/run_full.log

export PARPOOL_NUM_WORKERS=32
cd /data4/yanxiaokai/project_energy_climate/globally_interconnected_reRun/Optimization_ssp560
bash run_full_pipeline.sh &> logs/run_full.log