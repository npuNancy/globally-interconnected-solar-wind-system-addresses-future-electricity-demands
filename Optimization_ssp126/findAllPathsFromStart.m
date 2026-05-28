function [paths, costs] = findAllPathsFromStart(adjMatrix, costMatrix, startNode, minNodes, maxNodes)
% findAllPathsFromStart — 从指定节点出发，DFS搜索所有可行输电路径
%
% 使用深度优先搜索（DFS）遍历邻接矩阵，找出从 startNode 出发、
% 节点数在 [minNodes, maxNodes] 范围内的所有简单路径，并计算各路径的累积损耗率。
%
% 输入：
%   adjMatrix  - 邻接矩阵（1=有连接，0=无连接）
%   costMatrix - 损耗率矩阵（0-1之间的输电损耗比例）
%   startNode  - 起始节点编号
%   minNodes   - 路径最少节点数
%   maxNodes   - 路径最多节点数（控制跳数：2=直连，3=1次中继）
%
% 输出：
%   paths - 所有路径的元胞数组，每条路径为节点编号序列
%   costs - 对应路径的累积损耗率数组

    visited = false(size(adjMatrix, 1), 1);
    currentPath = [];
    allPaths = {};

    % 深度优先搜索
    allPaths = dfsFromStart(adjMatrix, startNode, visited, currentPath, allPaths, minNodes, maxNodes);

    % 计算每条路径的累积损耗率
    costs = zeros(1, length(allPaths));
    for i = 1:length(allPaths)
        path = allPaths{i};
        costs(i) = calculatePathCost(path, costMatrix);
    end

    paths = allPaths;
end

%% --- 深度优先搜索子函数 ---
function allPaths = dfsFromStart(adjMatrix, currentNode, visited, currentPath, allPaths, minNodes, maxNodes)
    visited(currentNode) = true;
    currentPath = [currentPath, currentNode];

    % 超过最大节点数则回溯
    if length(currentPath) > maxNodes
        visited(currentNode) = false;
        return;
    end

    % 满足最小节点数要求的路径加入结果
    if length(currentPath) >= minNodes
        allPaths{end+1} = currentPath;
    end

    % 递归探索所有未访问的相邻节点
    for neighbor = 1:size(adjMatrix, 1)
        if adjMatrix(currentNode, neighbor) == 1 && ~visited(neighbor)
            allPaths = dfsFromStart(adjMatrix, neighbor, visited, currentPath, allPaths, minNodes, maxNodes);
        end
    end

    % 回溯：恢复访问状态
    visited(currentNode) = false;
end

%% --- 路径累积损耗率计算子函数 ---
function totalCost = calculatePathCost(path, costMatrix)
% 计算路径的累积损耗率（各段损耗按乘法叠加）
% 例如：路径 A→B→C，损耗率 = 1 - (1-loss_AB) * (1-loss_BC)

    totalCost = 0;
    for i = 1:(length(path) - 1)
        totalCost = 1-(1-totalCost) * (1-costMatrix(path(i), path(i+1)));
    end
end
