set -e
set -x

export PARPOOL_NUM_WORKERS=8
cd /data4/yanxiaokai/project_energy_climate/globally_interconnected_reRun/Optimization_ssp126
bash run_2050_pipeline.sh &> logs/run_2050.log

export PARPOOL_NUM_WORKERS=8
cd /data4/yanxiaokai/project_energy_climate/globally_interconnected_reRun/Optimization_ssp245
bash run_2050_pipeline.sh &> logs/run_2050.log

export PARPOOL_NUM_WORKERS=8
cd /data4/yanxiaokai/project_energy_climate/globally_interconnected_reRun/Optimization_ssp560
bash run_2050_pipeline.sh &> logs/run_2050.log