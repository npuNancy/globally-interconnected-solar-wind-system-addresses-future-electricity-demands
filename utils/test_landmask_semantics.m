function report = test_landmask_semantics(scenario_dir, output_base)
% TEST_LANDMASK_SEMANTICS — 确认 landmask == 1 表示陆地还是海洋
%
% 输入：
%   scenario_dir  — SSP 目录（包含 Global_LandMask.tif / .mat）
%   output_base   — 测试结果输出根目录（如 'results/tests'）
%
% 输出：report struct，包含以下字段：
%   scenario_name
%   n_rows, n_cols
%   raw_unique, raw_counts
%   has_value_100
%   binary_unique, binary_counts
%   known_points (table)
%   semantic  — 'land=0,ocean=1' / 'land=1,ocean=0' / 'UNKNOWN'
%   all_points_pass

    if nargin < 2, output_base = 'results/tests'; end
    if ~exist(output_base, 'dir'), mkdir(output_base); end

    [~, scenario_name] = fileparts(scenario_dir);
    fprintf('\n============================================================\n');
    fprintf('  landmask 语义测试: %s\n', scenario_name);
    fprintf('============================================================\n');

    report.scenario_name = scenario_name;

    %% 1. 读取原始 landmask
    orig_dir = pwd;
    cd(scenario_dir);
    mask_raw = readgeoraster('Global_LandMask.tif');
    cd(orig_dir);
    mask_raw = double(mask_raw);
    [n_rows, n_cols] = size(mask_raw);
    report.n_rows = n_rows;
    report.n_cols = n_cols;
    fprintf('栅格尺寸: %d x %d\n', n_rows, n_cols);

    %% 2. 原始值分布
    raw_unique = unique(mask_raw(:));
    report.raw_unique = raw_unique;
    fprintf('原始 unique 值 (%d 个): ', length(raw_unique));
    fprintf('%d ', raw_unique);
    fprintf('\n');

    raw_counts = zeros(size(raw_unique));
    for i = 1:length(raw_unique)
        raw_counts(i) = sum(mask_raw(:) == raw_unique(i));
    end
    report.raw_counts = raw_counts;

    fprintf('原始值分布:\n');
    for i = 1:length(raw_unique)
        fprintf('  %4d : %8d 个像素\n', raw_unique(i), raw_counts(i));
    end

    %% 3. 检查是否存在 mask == 100
    count_lt_100 = sum(mask_raw(:) < 100);
    count_eq_100 = sum(mask_raw(:) == 100);
    count_gt_100 = sum(mask_raw(:) > 100);
    report.has_value_100 = (count_eq_100 > 0);

    fprintf('\ncount(mask < 100)  = %d\n', count_lt_100);
    fprintf('count(mask == 100) = %d\n', count_eq_100);
    fprintf('count(mask > 100)  = %d\n', count_gt_100);

    if report.has_value_100
        fprintf('*** 警告：存在 mask == 100 的像素，需要显式处理！ ***\n');
    else
        fprintf('✓ 不存在 mask == 100 的像素，当前 <100/>100 二分法安全。\n');
    end

    %% 4. 二值化（与现有代码一致）
    mask_bin = zeros(size(mask_raw));
    mask_bin(mask_raw > 100) = 1;
    % mask_raw < 100 → 0 (默认)
    % mask_raw == 100 → 保持 0 (但上面已确认不存在)

    bin_unique = unique(mask_bin(:));
    report.binary_unique = bin_unique;
    bin_counts = zeros(size(bin_unique));
    for i = 1:length(bin_unique)
        bin_counts(i) = sum(mask_bin(:) == bin_unique(i));
    end
    report.binary_counts = bin_counts;

    fprintf('\n二值化后 unique 值: ');
    fprintf('%d ', bin_unique);
    fprintf('\n');
    for i = 1:length(bin_unique)
        fprintf('  %d : %8d 个像素\n', bin_unique(i), bin_counts(i));
    end

    %% 5. 坐标核验
    % 约定：row 0 = 90°N（从上到下递减），col 0 = 180°W（从左到右递增）
    % 1°x1° 栅格，每个像素中心在整数坐标
    % row = 90 - lat, col = lon + 180
    known_points = {
        'China_inland',      35,  105, 'land';
        'USA_central',       40, -100, 'land';
        'Sahara',            23,   10, 'land';
        'Australia_inland', -25,  135, 'land';
        'North_Atlantic',    30,  -40, 'ocean';
        'South_Pacific',    -20, -150, 'ocean';
        'Indian_Ocean',     -20,   80, 'ocean';
        'North_Pacific',     30, -170, 'ocean';
    };

    fprintf('\n=== 坐标点核验 ===\n');
    fprintf('%-20s %6s %7s %8s %6s %6s %6s\n', ...
        'Location', 'Lat', 'Lon', 'Expected', 'Raw', 'Bin', 'Pass');
    fprintf('%s\n', repmat('-', 1, 72));

    n_points = size(known_points, 1);
    loc_names  = cell(n_points, 1);
    lats       = zeros(n_points, 1);
    lons       = zeros(n_points, 1);
    expected_s = cell(n_points, 1);
    raw_vals   = zeros(n_points, 1);
    bin_vals   = zeros(n_points, 1);
    pass_flags = false(n_points, 1);

    for i = 1:n_points
        loc = known_points{i, 1};
        lat = known_points{i, 2};
        lon = known_points{i, 3};
        expected = known_points{i, 4};

        row = round(90 - lat) + 1;   % MATLAB 1-indexed
        col = round(lon + 180) + 1;

        rv = mask_raw(row, col);
        bv = mask_bin(row, col);

        if strcmp(expected, 'land')
            pass = (bv == 0);
        else
            pass = (bv == 1);
        end

        fprintf('%-20s %6.0f %7.0f %8s %6.0f %6.0f %6s\n', ...
            loc, lat, lon, expected, rv, bv, mat2str(pass));

        loc_names{i}  = loc;
        lats(i)       = lat;
        lons(i)       = lon;
        expected_s{i} = expected;
        raw_vals(i)   = rv;
        bin_vals(i)   = bv;
        pass_flags(i) = pass;
    end

    report.known_points = table(loc_names, lats, lons, expected_s, ...
        raw_vals, bin_vals, pass_flags, ...
        'VariableNames', {'location_name', 'lat', 'lon', 'expected_surface', ...
                         'raw_mask_value', 'binary_mask_value', 'pass'});

    all_pass = all(pass_flags);
    report.all_points_pass = all_pass;
    if all_pass
        fprintf('✓ 所有坐标点核验通过。\n');
    else
        fprintf('✗ 存在核验失败的点！\n');
    end

    %% 6. 语义判定
    if all_pass
        % land points → binary 0, ocean points → binary 1
        report.semantic = 'land=0,ocean=1';
        fprintf('\n结论：landmask == 1 表示海洋（offshore），landmask == 0 表示陆地（onshore）。\n');
    else
        report.semantic = 'UNKNOWN';
        fprintf('\n结论：无法确定语义，请人工检查。\n');
    end

    %% 7. 写 CSV
    csv_file = fullfile(output_base, 'landmask_known_points.csv');
    writetable(report.known_points, csv_file);
    fprintf('\nCSV 已保存：%s\n', csv_file);

    %% 8. 生成二值化全球地图
    fig = figure('Visible', 'off', 'Position', [100, 100, 1440, 720]);
    imagesc(mask_bin);
    colormap(gray);
    title(sprintf('Landmask Binary — %s (black=0/land, white=1/ocean)', scenario_name));
    axis image off;
    png_file = fullfile(output_base, 'landmask_binary_map.png');
    print(fig, png_file, '-dpng', '-r150');
    close(fig);
    fprintf('PNG 已保存：%s\n', png_file);
end
