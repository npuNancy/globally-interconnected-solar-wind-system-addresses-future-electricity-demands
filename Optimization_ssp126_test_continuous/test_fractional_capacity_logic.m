% test_fractional_capacity_logic.m — 连续容量逻辑单元测试
%
% 使用合成数据验证：
%   1. 出力缩放正确性
%   2. 边界值（0/1）行为
%   3. 浮点裁剪
%   4. 跨年份单调性
%   5. 二值兼容回归
%
% 用法：cd Optimization_ssp126_test_continuous && matlab -batch test_fractional_capacity_logic

n_pass = 0;
n_fail = 0;

%% 测试 1：出力缩放测试
fprintf('测试 1：出力缩放... ');
ins_cap = [1; 2];
gens = [
    10, 10, 10;
    20, 20, 20
];
region_id = [1; 1];
site_frac = [0.30; 0.50];

[grid_gens, effective_ins, site_frac_out] = ...
    aggregate_fractional_generation(ins_cap, gens, region_id, site_frac, 2);

% effective_ins = [0.30; 1.00]
assert(abs(effective_ins(1) - 0.30) < 1e-12, 'effective_ins(1) 应为 0.30');
assert(abs(effective_ins(2) - 1.00) < 1e-12, 'effective_ins(2) 应为 1.00');

% grid_gens(1,:) = [0.30*10 + 0.50*20, ...] = [13.0, 13.0, 13.0]
assert(abs(grid_gens(1,1) - 13.0) < 1e-12, 'grid_gens(1,1) 应为 13.0');
assert(abs(grid_gens(1,2) - 13.0) < 1e-12, 'grid_gens(1,2) 应为 13.0');
assert(abs(grid_gens(1,3) - 13.0) < 1e-12, 'grid_gens(1,3) 应为 13.0');

% 区域 2 无格网，出力应为 0
assert(all(grid_gens(2,:) == 0), '区域 2 出力应为 0');

fprintf('通过\n');
n_pass = n_pass + 1;

%% 测试 2：边界测试（0/1 与二值模型一致）
fprintf('测试 2：边界值... ');
ins_cap = [5; 3; 8];
gens = [
    1, 2, 3;
    4, 5, 6;
    7, 8, 9
];
region_id = [1; 1; 2];
site_frac = [0; 1; 1];

[grid_gens, effective_ins, ~] = ...
    aggregate_fractional_generation(ins_cap, gens, region_id, site_frac, 2);

% site_frac=0 的格网不贡献出力
assert(effective_ins(1) == 0, 'site_frac=0 时 effective_ins 应为 0');

% site_frac=1 的格网贡献完整出力
assert(abs(effective_ins(2) - 3) < 1e-12, 'site_frac=1 时 effective_ins 应等于 ins_cap');
assert(abs(effective_ins(3) - 8) < 1e-12, 'site_frac=1 时 effective_ins 应等于 ins_cap');

% 区域 1：格网 1（frac=0）不贡献 + 格网 2（frac=1）完整贡献
assert(abs(grid_gens(1,1) - 4) < 1e-12, '区域 1 出力应仅来自格网 2（格网 1 的 frac=0）');
% 区域 2：格网 3 完整贡献
assert(abs(grid_gens(2,1) - 7) < 1e-12, '区域 2 出力应来自格网 3');

fprintf('通过\n');
n_pass = n_pass + 1;

%% 测试 3：浮点裁剪测试
fprintf('测试 3：浮点裁剪... ');
ins_cap = [1; 1];
gens = [
    10, 20, 30;
    40, 50, 60
];
region_id = [1; 1];
site_frac = [-1e-12; 1 + 1e-12];

[grid_gens, effective_ins, site_frac_out] = ...
    aggregate_fractional_generation(ins_cap, gens, region_id, site_frac, 1);

% 应被裁剪到 [0, 1]
assert(site_frac_out(1) == 0, '负值应被裁剪为 0');
assert(site_frac_out(2) == 1, '大于 1 的值应被裁剪为 1');

% effective_ins 应正确
assert(effective_ins(1) == 0, '裁剪后 effective_ins(1) 应为 0');
assert(abs(effective_ins(2) - 1) < 1e-12, '裁剪后 effective_ins(2) 应为 1');

% grid_gens 应只包含格网 2 的完整出力
assert(abs(grid_gens(1,1) - 40) < 1e-12, '裁剪后 grid_gens 应仅含格网 2');

fprintf('通过\n');
n_pass = n_pass + 1;

%% 测试 4：跨年份单调性测试
fprintf('测试 4：跨年份单调性... ');
ins_cap = [10; 20];
gens = [
    1, 1, 1;
    2, 2, 2
];
region_id = [1; 1];

frac_2050 = [0.8; 1.0];
frac_2040 = [0.5; 0.7];
frac_2030 = [0.2; 0.6];

[grid_gens_2050, eff_2050, ~] = ...
    aggregate_fractional_generation(ins_cap, gens, region_id, frac_2050, 1);
[grid_gens_2040, eff_2040, ~] = ...
    aggregate_fractional_generation(ins_cap, gens, region_id, frac_2040, 1);
[grid_gens_2030, eff_2030, ~] = ...
    aggregate_fractional_generation(ins_cap, gens, region_id, frac_2030, 1);

% 单调性：2030 <= 2040 <= 2050
assert(all(frac_2030 <= frac_2040), 'frac_2030 <= frac_2040');
assert(all(frac_2040 <= frac_2050), 'frac_2040 <= frac_2050');

% 实际装机也应满足单调性
assert(all(eff_2030 <= eff_2040), 'eff_2030 <= eff_2040');
assert(all(eff_2040 <= eff_2050), 'eff_2040 <= eff_2050');

% 区域出力也应满足单调性
assert(all(grid_gens_2030(1,:) <= grid_gens_2040(1,:)), 'grid_gens_2030 <= grid_gens_2040');
assert(all(grid_gens_2040(1,:) <= grid_gens_2050(1,:)), 'grid_gens_2040 <= grid_gens_2050');

fprintf('通过\n');
n_pass = n_pass + 1;

%% 测试 5：二值兼容回归测试
fprintf('测试 5：二值兼容回归... ');
% 构造较大的随机测试集
rng(42);
N = 100;
ins_cap = rand(N, 1) * 10;
gens = rand(N, 8760) * 5;
region_id = randi(20, N, 1);

% 二值比例：随机 0/1
binary_frac = randi([0, 1], N, 1);

% 方法 A：原始二值聚合逻辑（模拟旧代码）
grid_gens_old = zeros(20, 8760);
for gg_ind = 1:20
    index = find((region_id == gg_ind) & (binary_frac == 1));
    selgens = gens(index, :);
    grid_gens_old(gg_ind, :) = nansum(selgens, 1);
end

% 方法 B：新的连续容量聚合函数
[grid_gens_new, ~, ~] = ...
    aggregate_fractional_generation(ins_cap, gens, region_id, binary_frac, 20);

% 两者应完全一致
max_diff = max(abs(grid_gens_old(:) - grid_gens_new(:)));
assert(max_diff < 1e-12, sprintf('二值兼容：最大差异 = %e，应 < 1e-12', max_diff));

fprintf('通过（最大差异 = %e）\n', max_diff);
n_pass = n_pass + 1;

%% 测试 6：多区域聚合正确性
fprintf('测试 6：多区域聚合... ');
ins_cap = [1; 2; 3; 4];
gens = [
    10, 10;
    20, 20;
    30, 30;
    40, 40
];
region_id = [1; 2; 1; 3];
site_frac = [0.5; 0.8; 1.0; 0.0];

[grid_gens, effective_ins, ~] = ...
    aggregate_fractional_generation(ins_cap, gens, region_id, site_frac, 3);

% 区域 1：格网 1（0.5*10）+ 格网 3（1.0*30）= 35
assert(abs(grid_gens(1,1) - 35) < 1e-12, '区域 1 聚合应为 35');
% 区域 2：格网 2（0.8*20）= 16
assert(abs(grid_gens(2,1) - 16) < 1e-12, '区域 2 聚合应为 16');
% 区域 3：格网 4（0.0*40）= 0
assert(abs(grid_gens(3,1) - 0) < 1e-12, '区域 3 聚合应为 0');

% effective_ins
assert(abs(effective_ins(1) - 0.5) < 1e-12, 'effective_ins(1) 应为 0.5');
assert(abs(effective_ins(2) - 1.6) < 1e-12, 'effective_ins(2) 应为 1.6');
assert(abs(effective_ins(3) - 3.0) < 1e-12, 'effective_ins(3) 应为 3.0');
assert(abs(effective_ins(4) - 0.0) < 1e-12, 'effective_ins(4) 应为 0.0');

fprintf('通过\n');
n_pass = n_pass + 1;

%% 汇总
fprintf('\n========================================\n');
fprintf('测试完成：%d 通过，%d 失败\n', n_pass, n_fail);
fprintf('========================================\n');

if n_fail > 0
    error('存在失败的测试');
end
