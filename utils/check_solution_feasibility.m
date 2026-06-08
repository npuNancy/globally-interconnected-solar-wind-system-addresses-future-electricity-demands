function feasibility = check_solution_feasibility(c, ceq, tolerance)
% CHECK_SOLUTION_FEASIBILITY — 检查最终解是否满足所有约束
%
% 输入：
%   c         — 不等式约束向量 (c <= 0 为可行)
%   ceq       — 等式约束向量 (ceq == 0 为可行)
%   tolerance — 容差（默认 1e-6）
%
% 输出：feasibility 结构体
%   .constraint_values       — 不等式约束原始值
%   .equality_values         — 等式约束原始值
%   .max_constraint_violation— 最大约束违反量
%   .is_feasible             — 是否可行

    if nargin < 3, tolerance = 1e-6; end

    feasibility.constraint_values = c(:)';
    if isempty(ceq)
        feasibility.equality_values = [];
    else
        feasibility.equality_values = ceq(:)';
    end

    % 不等式违反：c > 0 的部分
    if isempty(c)
        ineq_violation = 0;
    else
        ineq_violation = max([0; c(:)]);
    end

    % 等式违反：|ceq| 的最大值
    if isempty(ceq)
        eq_violation = 0;
    else
        eq_violation = max([0; abs(ceq(:))]);
    end

    feasibility.max_constraint_violation = max(ineq_violation, eq_violation);
    feasibility.is_feasible = feasibility.max_constraint_violation <= tolerance;
end
