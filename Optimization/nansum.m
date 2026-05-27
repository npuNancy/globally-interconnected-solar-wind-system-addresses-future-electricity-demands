function y = nansum(x, dim)
if nargin < 2
    if isvector(x)
        dim = find(size(x) ~= 1, 1);
        if isempty(dim), dim = 1; end
    else
        dim = 1;
    end
end
y = sum(x, dim, 'omitnan');
end
