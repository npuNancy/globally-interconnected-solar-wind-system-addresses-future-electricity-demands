"""
run_optimization_2050.py — 2050年全球互联情景（S-G）空间布局优化主程序

对应 MATLAB Optimization_SG_2050.m。
使用 NSGA-II 多目标优化算法求解帕累托最优解集。

用法:
    cd /data6/yanxiaokai/project_energy_climate/globally_interconnected_reRun
    source .venv/bin/activate
    python -m Optimization_py.run_optimization_2050
"""

import sys
import os
import time
import numpy as np
import h5py
from datetime import datetime

# 将项目根目录加入路径
project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if project_root not in sys.path:
    sys.path.insert(0, project_root)

from Optimization_py.config import SCENARIO_SG_2050
from Optimization_py.data_loader import (
    load_wind_data,
    load_solar_data,
    load_load_profiles,
    load_transmission_data,
    build_combined_data,
    build_variable_bounds,
)
from Optimization_py.problem import EnergyOptimizationProblem


def main():
    """主优化流程"""
    scenario = SCENARIO_SG_2050
    pop_size = 200  # 种群大小
    n_gen = 100  # 最大代数

    print(f"========== 2050 全球互联 (S-G) 空间布局优化 ==========")
    print(f"开始时间: {datetime.now()}")

    # 数据目录（从 Optimization/ 读取输入数据）
    opt_dir = os.path.join(project_root, "Optimization")

    # ==================================================================
    # 阶段一：数据加载
    # ==================================================================
    print("\n--- 阶段一：数据加载 ---")

    # 加载风电数据
    wind = load_wind_data(opt_dir)

    # 加载光伏数据
    solar = load_solar_data(opt_dir)

    # 加载负荷曲线
    all_loads = load_load_profiles(opt_dir, scenario)

    # 合并风光数据
    combined = build_combined_data(solar, wind, all_loads, opt_dir, scenario)

    # 构建变量边界
    bounds = build_variable_bounds(combined, opt_dir, scenario)

    # 将所有数据合并为一个字典传递给 Problem
    data = {
        **combined,
        **bounds,
    }

    # 加载输电数据（已在 bounds 中但需要单独字段）
    trans_data = load_transmission_data(opt_dir, scenario)
    data["trans_connections"] = trans_data["trans_connections"]
    data["trans_loss"] = trans_data["trans_loss"]

    print(f"\n数据汇总:")
    print(f"  候选格网: {data['n_grid']} ({data['nonlsol']} 光伏 + {data['nonlwin']} 风电)")
    print(f"  输电链路: {data['n_trans']}")
    print(f"  总变量数: {len(data['lb'])}")

    # ==================================================================
    # 阶段二：优化求解
    # ==================================================================
    print(f"\n--- 阶段二：NSGA-II 优化求解 ---")

    # 导入 pymoo（延迟导入以避免在数据加载阶段出错）
    from pymoo.algorithms.moo.nsga2 import NSGA2
    from pymoo.operators.sampling.rnd import IntegerRandomSampling
    from pymoo.operators.crossover.sbx import SBX
    from pymoo.operators.mutation.pm import PM
    from pymoo.optimize import minimize
    from pymoo.termination import get_termination

    # 创建优化问题
    problem = EnergyOptimizationProblem(data, scenario)

    # 配置 NSGA-II 算法
    algorithm = NSGA2(
        pop_size=pop_size,
        sampling=IntegerRandomSampling(),
        crossover=SBX(prob=1.0, eta=20),
        mutation=PM(eta=20),
        eliminate_duplicates=True,
    )

    # 终止条件
    termination = get_termination("n_gen", n_gen)

    # 运行优化
    print(f"种群大小: {pop_size}, 最大代数: {n_gen}")
    print(f"优化开始时间: {datetime.now()}")

    start_time = time.time()
    result = minimize(
        problem,
        algorithm,
        termination,
        seed=42,  # 对应 MATLAB 的 "rng default"
        verbose=True,  # 显示每代的优化进度
    )
    elapsed = time.time() - start_time

    print(f"\n优化完成！耗时: {elapsed/3600:.1f} 小时")

    # ==================================================================
    # 阶段三：结果保存
    # ==================================================================
    print(f"\n--- 阶段三：结果保存 ---")

    output_dir = os.path.join(project_root, "Optimization_py")
    os.makedirs(output_dir, exist_ok=True)

    # 保存帕累托解集
    if result.X is not None and len(result.X) > 0:
        output_file = os.path.join(output_dir, "Optimization_SG_2050_Res_reRun.h5")
        with h5py.File(output_file, "w") as f:
            f.create_dataset("res_scale", data=result.X)
            f.create_dataset("prs", data=result.F)
        print(f"结果已保存至: {output_file}")
        print(f"  帕累托解数: {len(result.X)}")
        print(f"  目标函数范围:")
        print(f"    f1 (弃电率):      [{result.F[:, 0].min():.4f}, {result.F[:, 0].max():.4f}]")
        print(f"    f2 (1-渗透率):    [{result.F[:, 1].min():.4f}, {result.F[:, 1].max():.4f}]")
        print(f"    f3 (成本/十亿$):  [{result.F[:, 2].min():.2f}, {result.F[:, 2].max():.2f}]")
    else:
        print("警告: 优化未找到可行解！")

    print(f"\n结束时间: {datetime.now()}")


if __name__ == "__main__":
    main()
