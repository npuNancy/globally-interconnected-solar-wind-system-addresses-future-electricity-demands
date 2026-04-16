function [paths, costs] = findAllPathsFromStart(adjMatrix, costMatrix,startNode, minNodes, maxNodes)
    % Find all possible paths starting from the given node and calculate the total cost and capacity for each path
    % adjMatrix: Adjacency matrix
    % costMatrix: Connection cost matrix
    % capacityMatrix: Connection capacity matrix
    % startNode: Starting node
    % minNodes: Minimum number of nodes in the path
    % maxNodes: Maximum number of nodes in the path

    visited = false(size(adjMatrix, 1), 1);  % Mark nodes as visited
    currentPath = [];  % Current path
    allPaths = {};  % Store all paths

    % Start depth-first search
    allPaths = dfsFromStart(adjMatrix, startNode, visited, currentPath, allPaths, minNodes, maxNodes);
    
    % Calculate the cost and capacity for each path
    costs = zeros(1, length(allPaths));       % Initialize array to store path costs    
    for i = 1:length(allPaths)
        path = allPaths{i};
        costs(i) = calculatePathCost(path, costMatrix);          % Calculate the total cost of each path
    end
    
    % Return paths, corresponding costs, and capacities
    paths = allPaths;
end

function allPaths = dfsFromStart(adjMatrix, currentNode, visited, currentPath, allPaths, minNodes, maxNodes)
    visited(currentNode) = true;  % Mark the current node as visited
    currentPath = [currentPath, currentNode];  % Add the current node to the path

    % If the path length exceeds the maximum node count, backtrack
    if length(currentPath) > maxNodes
        visited(currentNode) = false;
        return;
    end
    
    % Save the current path only if its length is greater than or equal to the minimum node count
    if length(currentPath) >= minNodes
        allPaths{end+1} = currentPath;  % Store the current path in the collection
    end

    % Explore all neighbor nodes
    for neighbor = 1:size(adjMatrix, 1)
        if adjMatrix(currentNode, neighbor) == 1 && ~visited(neighbor)
            % If there is a connection and the neighbor has not been visited, continue recursion
            allPaths = dfsFromStart(adjMatrix, neighbor, visited, currentPath, allPaths, minNodes, maxNodes);
        end
    end

    % Backtrack and restore state
    visited(currentNode) = false;
end

function totalCost = calculatePathCost(path, costMatrix)
    % Calculate the total cost for a given path
    % path: Sequence of nodes in the path
    % costMatrix: Connection cost matrix
    
    totalCost = 0;  % Initialize total cost
    for i = 1:(length(path) - 1)
        totalCost = 1-(1-totalCost) * (1-costMatrix(path(i), path(i+1)));  % Accumulate the connection costs between adjacent nodes
    end
end
