% RUN_LANDMASK_SEMANTICS_TEST_ALL — 统一入口：测试三个 SSP 目录的 landmask 语义
%
% 用法：matlab -batch "addpath('utils'); run_landmask_semantics_test_all"
%
% 测试内容：
%   1. 三个 SSP 目录的 Global_LandMask.tif 是否一致
%   2. 每个目录的原始值分布
%   3. 已知坐标点核验
%   4. 二值化全球地图可视化

clear, clc

script_dir = fileparts(mfilename('fullpath'));
addpath(script_dir);

project_root = fullfile(script_dir, '..');
output_base  = fullfile(project_root, 'results', 'tests');
if ~exist(output_base, 'dir'), mkdir(output_base); end

scenarios = { ...
    fullfile(project_root, 'Optimization_ssp126'), ...
    fullfile(project_root, 'Optimization_ssp245'), ...
    fullfile(project_root, 'Optimization_ssp560')  ...
};

%% 1. 检查三个目录的 landmask 是否一致
fprintf('========== 跨目录一致性检查 ==========\n');
masks = cell(1, 3);
orig_wd = pwd;
for i = 1:3
    cd(scenarios{i});
    masks{i} = double(readgeoraster('Global_LandMask.tif'));
    cd(orig_wd);
    fprintf('  已加载: %s  (%d x %d)\n', scenarios{i}, size(masks{i},1), size(masks{i},2));
end

eq_126_245 = isequal(masks{1}, masks{2});
eq_126_560 = isequal(masks{1}, masks{3});

fprintf('\nlandmask_equal_126_245: %s\n', mat2str(eq_126_245));
fprintf('landmask_equal_126_560: %s\n', mat2str(eq_126_560));

if eq_126_245 && eq_126_560
    fprintf('✓ 三个目录的 Global_LandMask.tif 完全一致。\n');
else
    fprintf('✗ 三个目录的 landmask 不一致，每个目录将分别测试。\n');
end

%% 2. 对每个目录分别运行测试
reports = cell(1, 3);
for i = 1:3
    reports{i} = test_landmask_semantics(scenarios{i}, output_base);
end

%% 3. 汇总表
fprintf('\n========== 汇总 ==========\n');
fprintf('%-25s %-20s %-8s %-10s\n', 'Scenario', 'Semantic', '100存在?', '全部通过?');
fprintf('%s\n', repmat('-', 1, 70));
for i = 1:3
    fprintf('%-25s %-20s %-8s %-10s\n', ...
        reports{i}.scenario_name, ...
        reports{i}.semantic, ...
        mat2str(reports{i}.has_value_100), ...
        mat2str(reports{i}.all_points_pass));
end

fprintf('\n输出目录: %s\n', output_base);
fprintf('测试完成。\n');
