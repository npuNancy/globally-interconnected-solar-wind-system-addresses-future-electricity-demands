function result = select_preferred_solution( ...
    prs, ...
    base_load_ratio, ...
    min_vre_share, ...
    max_vre_share, ...
    max_curtailment, ...
    selection_mode)
% select_preferred_solution
%
% 从 NSGA-II Pareto 解中筛选 preferred solution。
%
% 输入：
%   prs(:,1)            弃电率
%   prs(:,2)            灵活电源比例
%   prs(:,3)            成本
%   base_load_ratio     基荷比例
%   min_vre_share       风光渗透率下界；SSP5-6.0 使用 NaN
%   max_vre_share       风光渗透率上界
%   max_curtailment     弃电率上限，本项目固定为 0.15
%   selection_mode      bounded_transition / fossil_upper_bound
%
% 输出：
%   result.sol_idx
%   result.status
%   result.curtailment
%   result.flexible_ratio
%   result.vre_share
%   result.cost
%   result.n_total
%   result.n_curtailment_ok
%   result.n_vre_ok
%   result.n_qualified

curtailment = prs(:, 1);
flexible_ratio = prs(:, 2);
cost = prs(:, 3);

vre_share = 1 - base_load_ratio - flexible_ratio;

curtailment_ok = curtailment <= max_curtailment;

switch selection_mode
    case 'bounded_transition'
        if isnan(min_vre_share)
            error('bounded_transition 模式必须提供 min_vre_share');
        end

        vre_ok = ...
            vre_share >= min_vre_share & ...
            vre_share <= max_vre_share;

    case 'fossil_upper_bound'
        vre_ok = vre_share <= max_vre_share;

    otherwise
        error('未知 selection_mode: %s', selection_mode);
end

qualified = find(curtailment_ok & vre_ok);

result = struct();
result.status = 'qualified';
result.n_total = length(curtailment);
result.n_curtailment_ok = nnz(curtailment_ok);
result.n_vre_ok = nnz(vre_ok);
result.n_qualified = length(qualified);
result.min_vre_share = min_vre_share;
result.max_vre_share = max_vre_share;
result.max_curtailment = max_curtailment;
result.selection_mode = selection_mode;

if isempty(qualified)
    result.status = 'no_qualified_solution';

    fprintf('\n=== Pareto 筛选失败：没有合格解 ===\n');
    fprintf('模式：%s\n', selection_mode);
    fprintf('Pareto 解总数：%d\n', result.n_total);
    fprintf('满足弃电率上限的解数量：%d\n', result.n_curtailment_ok);
    fprintf('满足风光约束的解数量：%d\n', result.n_vre_ok);
    fprintf('同时满足全部约束的解数量：%d\n', result.n_qualified);
    fprintf('最低弃电率：%.4f\n', min(curtailment));
    fprintf('风光渗透率范围：[%.4f, %.4f]\n', min(vre_share), max(vre_share));

    error('当前 Pareto 前沿不存在合格 preferred solution');
end

% 在合格解中选择成本最低方案
[~, local_idx] = min(cost(qualified));
sol_idx = qualified(local_idx);

result.sol_idx = sol_idx;
result.curtailment = curtailment(sol_idx);
result.flexible_ratio = flexible_ratio(sol_idx);
result.vre_share = vre_share(sol_idx);
result.cost = cost(sol_idx);

fprintf('\n=== Preferred solution ===\n');
fprintf('模式：%s\n', selection_mode);
fprintf('Pareto 解总数：%d\n', result.n_total);
fprintf('满足弃电率上限的解数量：%d\n', result.n_curtailment_ok);
fprintf('满足风光约束的解数量：%d\n', result.n_vre_ok);
fprintf('同时满足全部约束的解数量：%d\n', result.n_qualified);
fprintf('选中解编号：%d\n', result.sol_idx);
fprintf('弃电率：%.4f\n', result.curtailment);
fprintf('风光渗透率：%.4f\n', result.vre_share);
fprintf('灵活电源比例：%.4f\n', result.flexible_ratio);
fprintf('成本：%.1f 十亿美元\n', result.cost);
end
