function results_dir = setup_results_dir(subdir)
% SETUP_RESULTS_DIR — 创建并返回带时间戳的结果目录
%
% 输入：
%   subdir — 子目录名（如 'results_20260608_1024'），来自 optimization_config.m
%
% 输出：
%   results_dir — 完整相对路径，如 'results/results_20260608_1024'

    results_dir = fullfile('results', subdir);

    if ~exist(results_dir, 'dir')
        mkdir(results_dir);
    end

    % 确保 results/failed 也存在
    failed_dir = fullfile('results', 'failed');
    if ~exist(failed_dir, 'dir')
        mkdir(failed_dir);
    end

    fprintf('结果保存目录: %s\n', results_dir);
end
