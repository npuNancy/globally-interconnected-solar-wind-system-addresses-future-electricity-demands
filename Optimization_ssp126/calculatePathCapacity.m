function minCapacity = calculatePathCapacity(path, capacityMatrix)
% calculatePathCapacity — 计算输电路径的最小可用容量
%
% 输电路径的瓶颈容量由路径上容量最小的单段决定（木桶效应）。
%
% 输入：
%   path           - 路径节点序列，如 [3, 5, 8] 表示 3→5→8
%   capacityMatrix - 区域间输电容量矩阵（20×20）
%
% 输出：
%   minCapacity - 路径最小容量（即瓶颈容量）

    minCapacity = Inf;  % 初始化为正无穷

    % 遍历路径上每一段连接
    for i = 1:(length(path) - 1)
        node1 = path(i);
        node2 = path(i + 1);
        edgeCapacity = capacityMatrix(node1, node2);
        minCapacity = min(minCapacity, edgeCapacity);
    end

    % 若路径长度不足2个节点（无连接），容量设为0
    if minCapacity == Inf
        minCapacity = 0;
    end
end
