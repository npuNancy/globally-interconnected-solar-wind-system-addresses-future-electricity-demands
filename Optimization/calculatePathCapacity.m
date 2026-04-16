function minCapacity = calculatePathCapacity(path, capacityMatrix)
    % Calculate the connectivity capacity for a given path
    % path: Sequence of nodes in the path
    % capacityMatrix: Connection capacity matrix

    minCapacity = Inf;  % Initialize minimum capacity to positive infinity

    % Iterate through each pair of consecutive nodes in the path
    for i = 1:(length(path) - 1)
        node1 = path(i);
        node2 = path(i + 1);

        % Get the capacity for the edge between node1 and node2
        edgeCapacity = capacityMatrix(node1, node2);

        % Update the minimum capacity if the current edge capacity is lower
        minCapacity = min(minCapacity, edgeCapacity);
    end

    % If no edges are found (path length is less than 2), set capacity to 0
    if minCapacity == Inf
        minCapacity = 0;
    end
end
