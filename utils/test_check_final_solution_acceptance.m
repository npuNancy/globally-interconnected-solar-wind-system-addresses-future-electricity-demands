% test_check_final_solution_acceptance — 单元测试
%
% 测试 check_final_solution_acceptance 的弃电率验收余量逻辑
%
% 用法：cd Optimization_ssp126 && matlab -batch "run('../utils/test_check_final_solution_acceptance.m')"

MAX_CURTAILMENT = 0.15;
CURTAILMENT_ACCEPTANCE_MARGIN = 0.01;

passed = 0;
failed = 0;

%% Test 1: 弃电率 0.1499, 其他约束满足 → 接受，严格可行
c = [-0.1; 0; -0.12; -0.03; 0.1499 - MAX_CURTAILMENT];
ceq = [];
constraint_names = {'existing_solar_unmet_region_count', ...
    'existing_wind_unmet_region_count_minus_allowance', ...
    'vre_lower_bound', 'vre_upper_bound', 'curtailment_upper_bound_strict'};
acc = check_final_solution_acceptance(c, ceq, constraint_names, ...
    0.1499, MAX_CURTAILMENT, CURTAILMENT_ACCEPTANCE_MARGIN, 1e-6);
if acc.is_accepted && acc.strict_is_feasible
    fprintf('PASS Test 1: curt=0.1499 → accepted, strictly feasible\n');
    passed = passed + 1;
else
    fprintf('FAIL Test 1: curt=0.1499 → accepted=%s, strict=%s\n', ...
        mat2str(acc.is_accepted), mat2str(acc.strict_is_feasible));
    failed = failed + 1;
end

%% Test 2: 弃电率 0.1503, 其他约束满足 → 接受，使用余量
c = [-0.1; 0; -0.12; -0.03; 0.1503 - MAX_CURTAILMENT];
acc = check_final_solution_acceptance(c, ceq, constraint_names, ...
    0.1503, MAX_CURTAILMENT, CURTAILMENT_ACCEPTANCE_MARGIN, 1e-6);
if acc.is_accepted && ~acc.strict_is_feasible
    fprintf('PASS Test 2: curt=0.1503 → accepted, uses margin\n');
    passed = passed + 1;
else
    fprintf('FAIL Test 2: curt=0.1503 → accepted=%s, strict=%s\n', ...
        mat2str(acc.is_accepted), mat2str(acc.strict_is_feasible));
    failed = failed + 1;
end

%% Test 3: 弃电率 0.1599, 其他约束满足 → 接受，使用余量
c = [-0.1; 0; -0.12; -0.03; 0.1599 - MAX_CURTAILMENT];
acc = check_final_solution_acceptance(c, ceq, constraint_names, ...
    0.1599, MAX_CURTAILMENT, CURTAILMENT_ACCEPTANCE_MARGIN, 1e-6);
if acc.is_accepted && ~acc.strict_is_feasible
    fprintf('PASS Test 3: curt=0.1599 → accepted, uses margin\n');
    passed = passed + 1;
else
    fprintf('FAIL Test 3: curt=0.1599 → accepted=%s, strict=%s\n', ...
        mat2str(acc.is_accepted), mat2str(acc.strict_is_feasible));
    failed = failed + 1;
end

%% Test 4: 弃电率 0.1600, 其他约束满足 → 接受（边界）
c = [-0.1; 0; -0.12; -0.03; 0.16 - MAX_CURTAILMENT];
acc = check_final_solution_acceptance(c, ceq, constraint_names, ...
    0.16, MAX_CURTAILMENT, CURTAILMENT_ACCEPTANCE_MARGIN, 1e-6);
if acc.is_accepted
    fprintf('PASS Test 4: curt=0.1600 → accepted (boundary)\n');
    passed = passed + 1;
else
    fprintf('FAIL Test 4: curt=0.1600 → accepted=%s\n', mat2str(acc.is_accepted));
    failed = failed + 1;
end

%% Test 5: 弃电率 0.1601, 其他约束满足 → 拒绝
c = [-0.1; 0; -0.12; -0.03; 0.1601 - MAX_CURTAILMENT];
acc = check_final_solution_acceptance(c, ceq, constraint_names, ...
    0.1601, MAX_CURTAILMENT, CURTAILMENT_ACCEPTANCE_MARGIN, 1e-6);
if ~acc.is_accepted
    fprintf('PASS Test 5: curt=0.1601 → rejected\n');
    passed = passed + 1;
else
    fprintf('FAIL Test 5: curt=0.1601 → accepted=%s (should be rejected)\n', ...
        mat2str(acc.is_accepted));
    failed = failed + 1;
end

%% Test 6: 弃电率 0.1503, VRE 上界越界 → 拒绝
c = [-0.1; 0; -0.12; 0.01; 0.1503 - MAX_CURTAILMENT];  % vre_upper_bound > 0
acc = check_final_solution_acceptance(c, ceq, constraint_names, ...
    0.1503, MAX_CURTAILMENT, CURTAILMENT_ACCEPTANCE_MARGIN, 1e-6);
if ~acc.is_accepted
    fprintf('PASS Test 6: curt=0.1503, VRE violated → rejected\n');
    passed = passed + 1;
else
    fprintf('FAIL Test 6: curt=0.1503, VRE violated → accepted=%s (should be rejected)\n', ...
        mat2str(acc.is_accepted));
    failed = failed + 1;
end

%% Test 7: 弃电率 0.1503, 既有装机约束越界 → 拒绝
c = [0.5; 0; -0.12; -0.03; 0.1503 - MAX_CURTAILMENT];  % solar unmet > 0
acc = check_final_solution_acceptance(c, ceq, constraint_names, ...
    0.1503, MAX_CURTAILMENT, CURTAILMENT_ACCEPTANCE_MARGIN, 1e-6);
if ~acc.is_accepted
    fprintf('PASS Test 7: curt=0.1503, solar violated → rejected\n');
    passed = passed + 1;
else
    fprintf('FAIL Test 7: curt=0.1503, solar violated → accepted=%s (should be rejected)\n', ...
        mat2str(acc.is_accepted));
    failed = failed + 1;
end

%% Summary
fprintf('\n=== Test Summary ===\n');
fprintf('Passed: %d\n', passed);
fprintf('Failed: %d\n', failed);
if failed > 0
    error('test_check_final_solution_acceptance: %d tests FAILED', failed);
else
    fprintf('All %d tests passed.\n', passed);
end
