"""
path_finding.py — 图路径搜索工具

实现 MATLAB 中缺失的两个辅助函数：
- findAllPathsFromStart: 从起始节点搜索所有指定长度范围内的路径
- calculatePathCapacity: 计算路径上的瓶颈输电容量
"""

import numpy as np
from typing import List, Tuple


def find_all_paths_from_start(
    adjacency: np.ndarray,
    edge_costs: np.ndarray,
    start_node: int,
    min_nodes: int,
    max_nodes: int,
) -> Tuple[List[np.ndarray], np.ndarray]:
    """
    从起始节点搜索所有指定长度范围内的路径（DFS）。

    对应 MATLAB 的 findAllPathsFromStart(trans_conn, trans_loss, startNode, minNodes, maxNodes)。

    参数：
        adjacency: (N, N) 二值邻接矩阵，1 表示有连接
        edge_costs: (N, N) 浮点矩阵，每条边的传输损耗（分数形式）
        start_node: 起始节点（0-based 索引）
        min_nodes: 路径最小节点数（2 = 直接相连）
        max_nodes: 路径最大节点数

    返回：
        paths: 路径列表，每个路径为 1D int 数组（0-based 节点索引）
        costs: 1D float 数组，每条路径的端到端损耗（乘积累积：`1 - Π(1 - cᵢ)`）

    路径损耗计算方式：cost = 1 - Π(1 - edge_costs[path[j], path[j+1]])
    """
    n = adjacency.shape[0]
    paths = []
    costs = []

    # 使用栈实现迭代 DFS，避免递归深度限制
    # 栈元素: (当前节点, 路径列表, 累积损耗)
    stack = [(start_node, [start_node], 0.0)]

    while stack:
        current, path, cost = stack.pop()

        # 路径长度达到上限则不再扩展
        if len(path) >= max_nodes:
            continue

        # 遍历所有邻居
        for neighbor in range(n):
            if adjacency[current, neighbor] == 0:
                continue
            # 不重复访问已路径中的节点（避免环路）
            if neighbor in path:
                continue

            new_cost = 1 - (1 - cost) * (1 - edge_costs[current, neighbor])
            new_path = path + [neighbor]

            # 路径长度 >= min_nodes 时记录
            if len(new_path) >= min_nodes:
                paths.append(np.array(new_path, dtype=np.int32))
                costs.append(new_cost)

            # 继续扩展
            stack.append((neighbor, new_path, new_cost))

    if len(costs) == 0:
        return [], np.array([])

    costs = np.array(costs)
    return paths, costs


def calculate_path_capacity(
    route: np.ndarray,
    trans_power: np.ndarray,
) -> float:
    """
    计算路径上的瓶颈输电容量。

    对应 MATLAB 的 calculatePathCapacity(g_route, trans_power)。
    返回路径上所有边的最小剩余容量。

    参数：
        route: 1D int 数组，路径经过的节点序列（0-based）
        trans_power: (N, N) 浮点矩阵，各链路的剩余输电容量 (TW)

    返回：
        float: 路径瓶颈容量 (TW)
    """
    if len(route) < 2:
        return 0.0
    # 利用 numpy 花式索引高效提取路径上所有边的容量
    edge_caps = trans_power[route[:-1], route[1:]]
    return float(edge_caps.min())


def find_and_sort_paths(
    trans_power: np.ndarray,
    trans_loss: np.ndarray,
    start_node: int,
    min_nodes: int = 2,
    max_nodes: int = 6,
) -> Tuple[List[np.ndarray], np.ndarray]:
    """
    搜索路径并按损耗升序排序，过滤损耗 >= 1.0 的路径。

    对应 MATLAB dispatch 函数中的路径预处理逻辑（lines 38-55），
    修正了 MATLAB 代码中 tmp_costs/tmp_paths 过滤的潜在 bug。

    参数：
        trans_power: (20, 20) 当前解的输电容量矩阵 (TW)
        trans_loss: (20, 20) 各链路损耗矩阵
        start_node: 起始区域（0-based）
        min_nodes: 最小路径节点数
        max_nodes: 最大路径节点数

    返回：
        sorted_paths: 按损耗升序排列的路径列表
        sorted_costs: 对应的升序损耗数组（均 < 1.0）
    """
    # 用当前解的输电容量确定连通性
    adjacency = (trans_power > 0).astype(np.int32)

    # 搜索所有路径
    paths, costs = find_all_paths_from_start(
        adjacency, trans_loss, start_node, min_nodes, max_nodes
    )

    if len(costs) == 0:
        return [], np.array([])

    # 按损耗升序排序
    sort_idx = np.argsort(costs)
    costs = costs[sort_idx]
    paths = [paths[i] for i in sort_idx]

    # 过滤损耗 >= 1.0 的路径（传输效率为负，无意义）
    # 修正 MATLAB bug: 先计算掩码，再同时应用到 costs 和 paths
    mask = costs < 1.0
    costs = costs[mask]
    paths = [paths[i] for i in range(len(mask)) if mask[i]]

    return paths, costs
