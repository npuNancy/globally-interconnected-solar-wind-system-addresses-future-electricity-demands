function acceptance = check_final_solution_acceptance( ...
    c_strict, ceq, constraint_names, ...
    curtailment_rate, max_curtailment, ...
    curtailment_acceptance_margin, standard_tolerance)
% CHECK_FINAL_SOLUTION_ACCEPTANCE — 最终结果验收（弃电率允许余量）
%
% 逻辑：
%   - 除弃电率外，所有约束严格满足 c <= tolerance
%   - 弃电率允许 curtailment_rate <= max_curtailment + margin
%
% 输入：
%   c_strict                      — 严格不等式约束向量
%   ceq                           — 等式约束向量
%   constraint_names              — 约束名称 cell 数组
%   curtailment_rate              — 实际弃电率
%   max_curtailment               — 名义弃电率上限
%   curtailment_acceptance_margin — 验收余量
%   standard_tolerance            — 通用容差（默认 1e-6）
%
% 输出：acceptance 结构体

    if nargin < 7
        standard_tolerance = 1e-6;
    end

    c_accept = c_strict(:);

    idx = find(strcmp( ...
        constraint_names, ...
        'curtailment_upper_bound_strict'));

    if ~isempty(idx)
        c_accept(idx) = ...
            curtailment_rate ...
            - (max_curtailment ...
               + curtailment_acceptance_margin);
    end

    strict_feasibility = ...
        check_solution_feasibility( ...
            c_strict, ceq, standard_tolerance);

    acceptance_feasibility = ...
        check_solution_feasibility( ...
            c_accept, ceq, standard_tolerance);

    acceptance.strict_constraint_values = c_strict(:)';
    acceptance.acceptance_constraint_values = c_accept(:)';
    acceptance.strict_is_feasible = ...
        strict_feasibility.is_feasible;
    acceptance.is_accepted = ...
        acceptance_feasibility.is_feasible;
    acceptance.max_strict_violation = ...
        strict_feasibility.max_constraint_violation;
    acceptance.max_acceptance_violation = ...
        acceptance_feasibility.max_constraint_violation;
    acceptance.curtailment_rate = curtailment_rate;
    acceptance.max_curtailment = max_curtailment;
    acceptance.curtailment_acceptance_margin = ...
        curtailment_acceptance_margin;
    acceptance.final_acceptance_upper_bound = ...
        max_curtailment ...
        + curtailment_acceptance_margin;
end
