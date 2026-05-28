function y = nansum(x, dim)
% nansum — NaN 安全求和（Statistics Toolbox 替代实现）
%
% 功能等同于 sum(x, dim, 'omitnan')，但不依赖 Statistics Toolbox。
% 当 dim 未指定时，自动对第一个非单例维度求和。

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
