function test_curtailment_constraint()
% TEST_CURTAILMENT_CONSTRAINT — 验证弃电率约束逻辑
%
% 检查：
%   curtailment_rate <= MAX_CURTAILMENT 约束生效
%   check_solution_feasibility 正确判定可行/不可行

    fprintf('=== test_curtailment_constraint ===\n');

    cost_cfg = cost_model_config();

    % 检查 1: 弃电率约束已启用
    assert(cost_cfg.ENABLE_CURTAILMENT_CONSTRAINT == true, ...
        'ENABLE_CURTAILMENT_CONSTRAINT 应为 true');

    % 检查 2: MAX_CURTAILMENT = 0.15
    assert(abs(cost_cfg.MAX_CURTAILMENT - 0.15) < 1e-10, ...
        'MAX_CURTAILMENT 应为 0.15');

    % 检查 3: 弃电率 0.10 满足约束
    c = [];
    curtailment_rate = 0.10;
    if cost_cfg.ENABLE_CURTAILMENT_CONSTRAINT
        c(end+1) = curtailment_rate - cost_cfg.MAX_CURTAILMENT;
    end
    assert(c(end) <= 0, '弃电率 0.10 应满足约束');
    fprintf('  弃电率 0.10: 约束值 = %.4f <= 0  ✓\n', c(end));

    % 检查 4: 弃电率 0.20 违反约束
    c = [];
    curtailment_rate = 0.20;
    if cost_cfg.ENABLE_CURTAILMENT_CONSTRAINT
        c(end+1) = curtailment_rate - cost_cfg.MAX_CURTAILMENT;
    end
    assert(c(end) > 0, '弃电率 0.20 应违反约束');
    fprintf('  弃电率 0.20: 约束值 = %.4f > 0  ✓\n', c(end));

    % 检查 5: 使用 check_solution_feasibility 判定
    c_full = [0; -0.01; 0.05];  % 最后一个违反弃电率
    ceq = [];
    feasibility = check_solution_feasibility(c_full, ceq, 1e-6);
    assert(~feasibility.is_feasible, '含弃电率违反的解应为不可行');
    fprintf('  弃电率违反 → 不可行  ✓\n');

    % 检查 6: 全部约束满足
    c_ok = [-0.01; -0.1; -0.001];  % 全部 <= 0
    feasibility_ok = check_solution_feasibility(c_ok, ceq, 1e-6);
    assert(feasibility_ok.is_feasible, '全部约束满足应为可行');
    fprintf('  全部约束满足 → 可行  ✓\n');

    fprintf('  全部断言通过。\n');
end
