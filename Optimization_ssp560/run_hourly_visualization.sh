#!/usr/bin/env bash
# run_hourly_visualization.sh — 逐小时能源出力可视化（SSP5-6.0）

set -euo pipefail

YEAR="${1:-2050}"
SSP="ssp560"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 查找最新的 results_<timestamp> 子目录
RESULTS_DIR="${SCRIPT_DIR}/results"
LATEST_SUBDIR=$(ls -d "${RESULTS_DIR}"/results_* 2>/dev/null | sort | tail -1)
if [ -n "${LATEST_SUBDIR}" ]; then
    RESULTS_DIR="${LATEST_SUBDIR}"
fi

echo "=== 逐小时可视化: ${SSP} ${YEAR} ==="
echo "结果目录: ${RESULTS_DIR}"

cd "${SCRIPT_DIR}"
MATLAB="/data6/yanxiaokai/MATLAB/R2024b/bin/matlab"
"${MATLAB}" -batch "year=${YEAR}; addpath(fullfile('${PROJ_ROOT}','utils')); export_hourly_dispatch_detail(${YEAR}, '${SCRIPT_DIR}')"

cd "${PROJ_ROOT}"
source .venv/bin/activate

python plot_hourly_energy_output.py \
    --ssp "${SSP}" \
    --year "${YEAR}" \
    --input "${RESULTS_DIR}/hourly/hourly_dispatch_${YEAR}.csv" \
    --output-dir "${RESULTS_DIR}/img/hourly"

echo "=== 完成 ==="
