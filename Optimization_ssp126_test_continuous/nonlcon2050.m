function [c, ceq] = nonlcon2050(x)
% nonlcon2050 — 2050年非线性约束函数（连续容量版本）
%
% 薄封装：委托给 continuous_capacity_constraints。
% 约束：各区域实际装机 >= 已有装机，c <= 0 表示满足。

[c, ceq] = continuous_capacity_constraints(x, 'NonlConData.mat');
end
