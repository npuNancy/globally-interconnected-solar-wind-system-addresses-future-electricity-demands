#!/bin/bash
# run_full_pipeline.sh — SSP1-2.6 三阶段优化自动化流水线
# 用法: bash run_full_pipeline.sh
#
# 环境变量配置（可选）：
#   export POPULATION_SIZE=30    # NSGA-II 种群大小，默认 1000
#   export MAX_GENERATIONS=3     # NSGA-II 最大代数，默认 200
#
# 执行顺序：
#   1. 2050年优化（大陆互联 S-C） → Opt_SC_2050_Sel.mat
#   2. 2040年优化（大陆互联 S-C） → Opt_SC_2040_Sel.mat
#   3. 2030年优化（邻近互联 S-A） → Opt_SA_2030_Sel.mat

set -e
MATLAB=/data6/yanxiaokai/MATLAB/R2024b/bin/matlab
PYTHON=${PYTHON:-python}
TIMESTAMP=$(date +%Y%m%d_%H%M)
RESULTS_SUBDIR=results_${TIMESTAMP}
export RESULTS_SUBDIR
LOGDIR=$(pwd)/logs/logs_${TIMESTAMP}
IMGDIR=$(pwd)/results/img
mkdir -p "$LOGDIR"
mkdir -p "$IMGDIR"

run_matlab() {
    local script=$1
    local logfile=$2
    echo "[$(date)] 正在运行：$script -> $logfile"
    $MATLAB -batch "try, $script; disp('=== ${script} 完成 ==='); catch ME, fprintf('错误：%s\n%s\n', ME.identifier, ME.message); for i=1:length(ME.stack), fprintf('  位于 %s（第 %d 行）\n', ME.stack(i).name, ME.stack(i).line); end; exit(1); end; exit;" > "$logfile" 2>&1
    if [ $? -ne 0 ]; then
        echo "[$(date)] 失败：$script（详见 $logfile）"
        return 1
    fi
    echo "[$(date)] 完成：$script"
    return 0
}

plot_pareto() {
    local scenario=$1
    local year=$2
    local h5file=$3
    local selfile=$4
    local outfile=$5

    echo "[$(date)] 正在绘制 Pareto 前沿：$scenario $year"

    if [ -n "$selfile" ] && [ -f "$selfile" ]; then
        $PYTHON ../plot_pareto_front.py \
          --scenario "$scenario" \
          --year "$year" \
          --h5 "$h5file" \
          --sel-mat "$selfile" \
          --output "$outfile"
    else
        $PYTHON ../plot_pareto_front.py \
          --scenario "$scenario" \
          --year "$year" \
          --h5 "$h5file" \
          --output "$outfile"
    fi

    if [ $? -ne 0 ]; then
        echo "[$(date)] Pareto 前沿绘图失败：$scenario $year"
        return 1
    fi

    echo "[$(date)] Pareto 前沿已保存：$outfile"
}

echo "=========================================="
echo "  SSP1-2.6 优化流水线"
echo "  开始时间：$(date)"
echo "=========================================="

# 阶段1：2050年优化（大陆互联）
echo ""
echo "--- 阶段1：Optimization_SC_2050（2050年，大陆互联） ---"
# 清理可能存在的旧结果，避免误用
rm -f results/${RESULTS_SUBDIR}/Optimization_SC_2050_Res.h5
rm -f results/${RESULTS_SUBDIR}/Optimization_SC_2050_metrics.mat
rm -f results/${RESULTS_SUBDIR}/Opt_SC_2050_Sel.mat
if ! run_matlab "Optimization_SC_2050" "$LOGDIR/sc2050.log"; then
    echo "流水线在第1阶段停止"
    exit 1
fi

# 后处理 2050 -> 生成 Opt_SC_2050_Sel.mat
echo ""
echo "--- 后处理：2050 -> Opt_SC_2050_Sel.mat ---"
convert_2050_ok=true
if ! run_matlab "year=2050; sol_idx=0; convert_h5_to_sel" "$LOGDIR/convert2050.log"; then
    convert_2050_ok=false
fi

# Pareto 前沿绘图：2050（即使 convert 失败也尝试可视化）
# plot_pareto "SSP1-2.6" 2050 "results/Optimization_SC_2050_Res.h5" "results/Opt_SC_2050_Sel.mat" "results/img/pareto_front_2050.png" || true

if [ "$convert_2050_ok" = false ]; then
    echo "流水线在2050后处理阶段停止"
    exit 1
fi

# 阶段2：2040年优化（大陆互联）
echo ""
echo "--- 阶段2：Optimization_SC_2040（2040年，大陆互联） ---"
# 清理可能存在的旧结果，避免误用
rm -f results/${RESULTS_SUBDIR}/Optimization_SC_2040_Res.h5
rm -f results/${RESULTS_SUBDIR}/Optimization_SC_2040_metrics.mat
rm -f results/${RESULTS_SUBDIR}/Opt_SC_2040_Sel.mat
if ! run_matlab "Optimization_SC_2040" "$LOGDIR/sc2040.log"; then
    echo "流水线在第2阶段停止"
    exit 1
fi

# 后处理 2040 -> 生成 Opt_SC_2040_Sel.mat
echo ""
echo "--- 后处理：2040 -> Opt_SC_2040_Sel.mat ---"
convert_2040_ok=true
if ! run_matlab "year=2040; sol_idx=0; convert_h5_to_sel" "$LOGDIR/convert2040.log"; then
    convert_2040_ok=false
fi

# Pareto 前沿绘图：2040（即使 convert 失败也尝试可视化）
# plot_pareto "SSP1-2.6" 2040 "results/Optimization_SC_2040_Res.h5" "results/Opt_SC_2040_Sel.mat" "results/img/pareto_front_2040.png" || true

if [ "$convert_2040_ok" = false ]; then
    echo "流水线在2040后处理阶段停止"
    exit 1
fi

# 阶段3：2030年优化（邻近互联）
echo ""
echo "--- 阶段3：Optimization_SA_2030（2030年，邻近互联） ---"
# 清理可能存在的旧结果，避免误用
rm -f results/${RESULTS_SUBDIR}/Optimization_SA_2030_Res.h5
rm -f results/${RESULTS_SUBDIR}/Optimization_SA_2030_metrics.mat
rm -f results/${RESULTS_SUBDIR}/Opt_SA_2030_Sel.mat
if ! run_matlab "Optimization_SA_2030" "$LOGDIR/sa2030.log"; then
    echo "流水线在第3阶段停止"
    exit 1
fi

# 后处理 2030 -> 生成 Opt_SA_2030_Sel.mat
echo ""
echo "--- 后处理：2030 -> Opt_SA_2030_Sel.mat ---"
convert_2030_ok=true
if ! run_matlab "year=2030; sol_idx=0; convert_h5_to_sel" "$LOGDIR/convert2030.log"; then
    convert_2030_ok=false
fi

# Pareto 前沿绘图：2030（即使 convert 失败也尝试可视化）
# plot_pareto "SSP1-2.6" 2030 "results/Optimization_SA_2030_Res.h5" "results/Opt_SA_2030_Sel.mat" "results/img/pareto_front_2030.png" || true

if [ "$convert_2030_ok" = false ]; then
    echo "流水线在2030后处理阶段停止"
    exit 1
fi

echo ""
echo "=========================================="
echo "  流水线完成：$(date)"
echo "=========================================="
echo ""
echo "输出文件："
ls -lh results/${RESULTS_SUBDIR}/Optimization_*_Res.h5 results/${RESULTS_SUBDIR}/Opt_*_Sel.mat 2>/dev/null
