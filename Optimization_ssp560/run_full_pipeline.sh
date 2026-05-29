#!/bin/bash
# run_full_pipeline.sh — SSP5-6.0 三阶段优化自动化流水线
# 用法: bash run_full_pipeline.sh
#
# 执行顺序：
#   1. 2050年优化（大陆互联 S-C） → Opt_SC_2050_Sel.mat
#   2. 2040年优化（大陆互联 S-C） → Opt_SC_2040_Sel.mat
#   3. 2030年优化（邻近互联 S-A） → Opt_SA_2030_Sel.mat

set -e
MATLAB=/data6/yanxiaokai/MATLAB/R2024b/bin/matlab
LOGDIR=$(pwd)/logs
mkdir -p $LOGDIR

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

echo "=========================================="
echo "  SSP5-6.0 优化流水线"
echo "  开始时间：$(date)"
echo "=========================================="

# 阶段1：2050年优化（大陆互联）
echo ""
echo "--- 阶段1：Optimization_SC_2050（2050年，大陆互联） ---"
if ! run_matlab "Optimization_SC_2050" "$LOGDIR/sc2050.log"; then
    echo "流水线在第1阶段停止"
    exit 1
fi

# 后处理 2050 -> 生成 Opt_SC_2050_Sel.mat
echo ""
echo "--- 后处理：2050 -> Opt_SC_2050_Sel.mat ---"
if ! run_matlab "year=2050; sol_idx=0; convert_h5_to_sel" "$LOGDIR/convert2050.log"; then
    echo "流水线在2050后处理阶段停止"
    exit 1
fi

# 阶段2：2040年优化（大陆互联）
echo ""
echo "--- 阶段2：Optimization_SC_2040（2040年，大陆互联） ---"
if ! run_matlab "Optimization_SC_2040" "$LOGDIR/sc2040.log"; then
    echo "流水线在第2阶段停止"
    exit 1
fi

# 后处理 2040 -> 生成 Opt_SC_2040_Sel.mat
echo ""
echo "--- 后处理：2040 -> Opt_SC_2040_Sel.mat ---"
if ! run_matlab "year=2040; sol_idx=0; convert_h5_to_sel" "$LOGDIR/convert2040.log"; then
    echo "流水线在2040后处理阶段停止"
    exit 1
fi

# 阶段3：2030年优化（邻近互联）
echo ""
echo "--- 阶段3：Optimization_SA_2030（2030年，邻近互联） ---"
if ! run_matlab "Optimization_SA_2030" "$LOGDIR/sa2030.log"; then
    echo "流水线在第3阶段停止"
    exit 1
fi

# 后处理 2030 -> 生成 Opt_SA_2030_Sel.mat
echo ""
echo "--- 后处理：2030 -> Opt_SA_2030_Sel.mat ---"
if ! run_matlab "year=2030; sol_idx=0; convert_h5_to_sel" "$LOGDIR/convert2030.log"; then
    echo "流水线在2030后处理阶段停止"
    exit 1
fi

echo ""
echo "=========================================="
echo "  流水线完成：$(date)"
echo "=========================================="
echo ""
echo "输出文件："
ls -lh results/Optimization_*_Res.h5 results/Opt_*_Sel.mat 2>/dev/null
