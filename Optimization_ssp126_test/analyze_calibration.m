%% analyze_calibration.m — 分析校准结果并与 AR6 SSP1-2.6 对比
%
% 功能：读取优化结果 .h5 文件，计算装机容量统计、目标函数分布，
%       并与 AR6 SSP1-2.6 参考值对比，判断验收是否通过。
%
% 用法：
%   analyze_calibration                                  % 分析默认文件
%   analyze_calibration('Optimization_SC_2050_Res_sm2.50_cp12.5.h5')
%
% 输出：命令行打印汇总报告

%% ======================== 配置 ========================
AR6_SOLAR_GW   = 5799;
AR6_WIND_GW    = 6418;
AR6_TOTAL_GW   = 12217;
AR6_SOLAR_PCT  = 47.5;
AR6_WIND_PCT   = 52.5;

SOLAR_SHARE_LO = 42.5;  SOLAR_SHARE_HI = 52.5;
TOTAL_CAP_LO   = 10384; TOTAL_CAP_HI   = 14050;

% 指定结果文件（留空则自动查找最新）
result_file = '';

%% ======================== 确定结果文件 ========================
if isempty(result_file)
    % 自动查找最新的 _sm*_cp*.h5 文件，否则用默认
    files = dir('Optimization_SC_2050_Res_sm*.h5');
    if ~isempty(files)
        [~, idx] = max([files.datenum]);
        result_file = files(idx).name;
    else
        result_file = 'Optimization_SC_2050_Res.h5';
    end
end

if ~exist(result_file, 'file')
    error('结果文件不存在: %s', result_file);
end

fprintf('分析文件: %s\n', result_file);

%% ======================== 加载数据 ========================
% h5 文件存储格式：res_scale = (n_pareto, nvars)，prs = (n_pareto, 3)
res_scale = h5read(result_file, '/res_scale');
prs       = h5read(result_file, '/prs');
n_pareto  = size(res_scale, 1);  % Pareto 解数（行）

load NonlConData nonlcon_sel nonlcon_ins nonlsol nonlwin
N = nonlsol + nonlwin;  % 总候选格网数（= res_scale 的列数中前 N 列为选址变量）

%% ======================== 从文件名解析参数 ========================
tokens = regexp(result_file, '_sm([\d.]+)_cp([\d.]+)', 'tokens');
if ~isempty(tokens)
    solar_mult  = str2double(tokens{1}{1});
    cap_penalty = str2double(tokens{1}{2});
    fprintf('校准参数: solar_mult=%.4f, cap_penalty=%.2f\n', solar_mult, cap_penalty);
else
    fprintf('校准参数: 未在文件名中识别（使用默认 sm=1.00, cp=0.00）\n');
    solar_mult  = 1.0;
    cap_penalty = 0;
end

%% ======================== 计算装机容量统计 ========================
solar_caps = zeros(n_pareto, 1);
wind_caps  = zeros(n_pareto, 1);
region_solar = zeros(20, n_pareto);
region_wind  = zeros(20, n_pareto);

for i = 1:n_pareto
    site_sel = round(res_scale(i, 1:N));  % 第 i 个 Pareto 解的选址变量（行向量）
    % nonlcon_ins 是列向量 (N,1)，site_sel 是行向量 (1,N)，.* 会广播为 (N,N)
    % 需要确保 site_sel 为列向量
    site_sel = site_sel(:);
    solar_caps(i) = sum(nonlcon_ins(1:nonlsol) .* site_sel(1:nonlsol)) * 1000;  % GW
    wind_caps(i)  = sum(nonlcon_ins(nonlsol+1:N) .* site_sel(nonlsol+1:N)) * 1000;

    % 各区域装机
    for r = 1:20
        idx_sol = (nonlcon_sel(1:nonlsol)==r) & (site_sel(1:nonlsol)==1);
        idx_win = (nonlcon_sel(nonlsol+1:N)==r) & (site_sel(nonlsol+1:N)==1);
        region_solar(r,i) = sum(nonlcon_ins(1:nonlsol) .* idx_sol) * 1000;
        region_wind(r,i)  = sum(nonlcon_ins(nonlsol+1:N) .* idx_win) * 1000;
    end
end

total_caps = solar_caps + wind_caps;
solar_pcts = solar_caps ./ total_caps * 100;
wind_pcts  = wind_caps  ./ total_caps * 100;

%% ======================== 目标函数统计 ========================
curtail_rates = prs(:,1);  % 弃电率（列向量）
penetration   = prs(:,2);  % 1-渗透率
costs         = prs(:,3);  % 系统总成本（$B）

%% ======================== 找到中位成本解 ========================
[sorted_costs, sort_idx] = sort(costs);
med_idx = sort_idx(round(n_pareto/2));  % 中位成本对应的索引
med_solar_gw  = solar_caps(med_idx);
med_wind_gw   = wind_caps(med_idx);
med_total_gw  = total_caps(med_idx);
med_solar_pct = solar_pcts(med_idx);
med_wind_pct  = wind_pcts(med_idx);

%% ======================== 打印报告 ========================
fprintf('\n========================================\n');
fprintf('  校准分析报告\n');
fprintf('========================================\n\n');

fprintf('Pareto 解数量: %d\n\n', n_pareto);

% --- 装机统计 ---
fprintf('--- 装机容量统计（全部 Pareto 解，GW） ---\n');
fprintf('%-15s %-12s %-12s %-12s %-12s %-12s\n', ...
    '指标', '最小值', '25%%分位', '中位数', '75%%分位', '最大值');
fprintf('%-15s %-12.0f %-12.0f %-12.0f %-12.0f %-12.0f\n', ...
    '光伏 (GW)', prctile(solar_caps,[0 25 50 75 100]));
fprintf('%-15s %-12.0f %-12.0f %-12.0f %-12.0f %-12.0f\n', ...
    '风电 (GW)', prctile(wind_caps,[0 25 50 75 100]));
fprintf('%-15s %-12.0f %-12.0f %-12.0f %-12.0f %-12.0f\n', ...
    '合计 (GW)', prctile(total_caps,[0 25 50 75 100]));
fprintf('%-15s %-12.1f %-12.1f %-12.1f %-12.1f %-12.1f\n', ...
    '光伏占比 %%', prctile(solar_pcts,[0 25 50 75 100]));
fprintf('%-15s %-12.1f %-12.1f %-12.1f %-12.1f %-12.1f\n\n', ...
    '风电占比 %%', prctile(wind_pcts,[0 25 50 75 100]));

% --- 目标函数 ---
fprintf('--- 目标函数统计 ---\n');
fprintf('%-15s %-12s %-12s %-12s %-12s %-12s\n', ...
    '目标', '最小值', '25%%分位', '中位数', '75%%分位', '最大值');
fprintf('%-15s %-12.4f %-12.4f %-12.4f %-12.4f %-12.4f\n', ...
    '弃电率', prctile(curtail_rates,[0 25 50 75 100]));
fprintf('%-15s %-12.4f %-12.4f %-12.4f %-12.4f %-12.4f\n', ...
    '1-渗透率', prctile(penetration,[0 25 50 75 100]));
fprintf('%-15s %-12.0f %-12.0f %-12.0f %-12.0f %-12.0f\n\n', ...
    '成本 $B', prctile(costs,[0 25 50 75 100]));

% --- 中位成本解 ---
fprintf('--- 中位成本 Pareto 解 ---\n');
fprintf('  光伏: %.0f GW (%.1f%%)\n', med_solar_gw, med_solar_pct);
fprintf('  风电: %.0f GW (%.1f%%)\n', med_wind_gw, med_wind_pct);
fprintf('  合计: %.0f GW\n', med_total_gw);
fprintf('  弃电率:    %.4f\n', curtail_rates(med_idx));
fprintf('  1-渗透率:  %.4f\n', penetration(med_idx));
fprintf('  成本:      %.0f $B\n\n', costs(med_idx));

% --- 与 AR6 对比 ---
fprintf('--- 与 AR6 SSP1-2.6 对比（中位数） ---\n');
med_solar = median(solar_caps);
med_wind  = median(wind_caps);
med_total = median(total_caps);
med_spct  = median(solar_pcts);
med_wpct  = median(wind_pcts);

fprintf('%-12s %-12s %-12s %-12s %-10s\n', '', '优化中位', 'AR6', '倍率', '状态');
fprintf('%-12s %-12.0f %-12d %-12.2f %-10s\n', '光伏 GW', ...
    med_solar, AR6_SOLAR_GW, med_solar/AR6_SOLAR_GW, ...
    ternary(med_spct>=SOLAR_SHARE_LO && med_spct<=SOLAR_SHARE_HI, 'PASS(占比)', 'FAIL(占比)'));
fprintf('%-12s %-12.0f %-12d %-12.2f %-10s\n', '风电 GW', ...
    med_wind, AR6_WIND_GW, med_wind/AR6_WIND_GW, ...
    ternary(med_wpct>=100-SOLAR_SHARE_HI && med_wpct<=100-SOLAR_SHARE_LO, 'PASS(占比)', 'FAIL(占比)'));
fprintf('%-12s %-12.0f %-12d %-12.2f %-10s\n\n', '合计 GW', ...
    med_total, AR6_TOTAL_GW, med_total/AR6_TOTAL_GW, ...
    ternary(med_total>=TOTAL_CAP_LO && med_total<=TOTAL_CAP_HI, 'PASS', 'FAIL'));

% --- 验收结果 ---
pass_solar = med_spct >= SOLAR_SHARE_LO && med_spct <= SOLAR_SHARE_HI;
pass_total = med_total >= TOTAL_CAP_LO && med_total <= TOTAL_CAP_HI;

fprintf('========================================\n');
fprintf('  验收结果\n');
fprintf('========================================\n');
fprintf('  光伏占比: %s (%.1f%% in [%.1f%%, %.1f%%])\n', ...
    ternary(pass_solar, 'PASS', 'FAIL'), med_spct, SOLAR_SHARE_LO, SOLAR_SHARE_HI);
fprintf('  总装机:   %s (%.0f GW in [%d, %d])\n', ...
    ternary(pass_total, 'PASS', 'FAIL'), med_total, TOTAL_CAP_LO, TOTAL_CAP_HI);
if pass_solar && pass_total
    fprintf('\n  *** 全部验收通过 ***\n');
else
    fprintf('\n  验收未完全通过，需继续调整参数。\n');
end

%% ======================== 辅助函数 ========================
function s = ternary(cond, t, f)
    if cond, s = t; else, s = f; end
end
