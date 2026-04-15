"""
problem.py — pymoo 优化问题定义

将调度函数和约束封装为 pymoo Problem 子类，
使用 NSGA-II 算法求解三目标优化问题。
"""

import numpy as np
from pymoo.core.problem import Problem

from .config import N_REGIONS
from .dispatch import dispatch
from .constraints import nonlcon


class EnergyOptimizationProblem(Problem):
    """
    全球风光空间布局三目标优化问题。

    目标:
        f1: 弃电率（最小化）
        f2: 1 - 可再生渗透率（最小化）
        f3: 总投资成本（最小化，USD billion）

    约束:
        g1: 光伏装机不达标区域数 <= 0
        g2: 风电装机不达标区域数 <= 0

    决策变量:
        [0, n_grid):             格网选择 (0/1 整数)
        [n_grid, n_grid+20):     储能功率 (GW, 整数)
        [n_grid+20, n_grid+40):  储能时长 (h, 整数)
        [n_grid+40, ...):        输电功率 (GW, 整数)
    """

    def __init__(self, data: dict, scenario: dict):
        """
        参数:
            data: 包含所有预加载数据的字典
            scenario: 情景参数字典 (来自 config.py)
        """
        self._data = data
        self._scenario = scenario

        lb = data['lb']
        ub = data['ub']
        n_vars = len(lb)

        # 使用 xl/xu 数组接口（兼容 pymoo 0.6.x）
        # 所有变量均为整数，匹配 MATLAB intcon=1:nvars
        super().__init__(
            n_var=n_vars,
            n_obj=3,
            n_ieq_constr=2,
            xl=np.floor(lb).astype(np.float64),
            xu=np.ceil(ub).astype(np.float64),
            vtype=int,
        )

    def _evaluate(self, X, out, *args, **kwargs):
        """
        评估一组候选解的目标函数值和约束值。

        参数:
            X: (pop_size, n_vars) 种群矩阵
            out: 输出字典
        """
        n_pop = X.shape[0]
        F = np.zeros((n_pop, 3))
        G = np.zeros((n_pop, 2))

        data = self._data

        for i in range(n_pop):
            scale = X[i].astype(np.float64)
            n_grid = data['n_grid']

            # 解析决策变量
            grid_sel = np.round(scale[:n_grid]).astype(int)
            storage_pow_gw = scale[n_grid:n_grid + N_REGIONS]
            storage_dur_h = scale[n_grid + N_REGIONS:n_grid + 2 * N_REGIONS]
            trans_pow_gw = scale[n_grid + 2 * N_REGIONS:]

            # 计算约束
            G[i] = nonlcon(
                grid_sel, data['all_ins'],
                data['CGrid_Index'][:, 0],
                data['nonlsol'],
                data['cur_solar_tw'],
                data['cur_wind_tw'],
            )

            # 计算目标函数
            f1, f2, f3 = dispatch(
                grid_sel, storage_pow_gw, storage_dur_h, trans_pow_gw,
                data['all_gens'], data['all_ins'], data['all_loads'],
                data['CGrid_Index'],
                data['trans_connections'], data['trans_loss'],
                data['trans_mask'], data['nonlsol'],
                self._scenario,
            )
            F[i] = [f1, f2, f3]

        out['F'] = F
        out['G'] = G
