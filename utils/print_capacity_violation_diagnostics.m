function print_capacity_violation_diagnostics( ...
    best_scale, persistent_data, allowed_unmet_solar, allowed_unmet_wind)
% PRINT_CAPACITY_VIOLATION_DIAGNOSTICS — 打印逐区域的既有装机容量违反详情
%
% 输入：
%   best_scale          — 最优解向量
%   persistent_data     — 包含 nonlcon_sel, nonlcon_ins, nonlsol, nonlwin, cur_solar, cur_wind
%   allowed_unmet_solar — 允许的光伏区域不满足数量
%   allowed_unmet_wind  — 允许的风电区域不满足数量

    nonlcon_sel = persistent_data.nonlcon_sel;
    nonlcon_ins = persistent_data.nonlcon_ins;
    nonlsol_n   = persistent_data.nonlsol;
    nonlwin_n   = persistent_data.nonlwin;
    cur_solar   = persistent_data.cur_solar;
    cur_wind    = persistent_data.cur_wind;

    region_names = get_region_names();

    %% ======== 光伏装机逐区域诊断 ========
    tmp_a = best_scale(1:nonlsol_n);
    tmp_b = nonlcon_ins(1:nonlsol_n);
    tmp_c = tmp_a(:) .* tmp_b(:);
    tmp_d = nonlcon_sel(1:nonlsol_n);
    opt_solar = zeros(20, 1);
    for i = 1:20
        idx = find(tmp_d == i);
        opt_solar(i) = sum(tmp_c(idx));
    end
    solar_unmet = opt_solar < cur_solar;
    solar_unmet_count = sum(solar_unmet);

    fprintf('\n=== 光伏装机容量逐区域诊断 ===\n');
    fprintf('违反区域数: %d / 20,  允许违反数: %d\n', ...
        solar_unmet_count, allowed_unmet_solar);
    if solar_unmet_count > 0
        unmet_idx = find(solar_unmet);
        for k = 1:length(unmet_idx)
            r = unmet_idx(k);
            fprintf('  区域 %2d (%s): 优化容量 = %.4f TWp,  要求容量 = %.4f TWp,  缺口 = %.4f TWp\n', ...
                r, region_names{r}, opt_solar(r), cur_solar(r), cur_solar(r) - opt_solar(r));
        end
    else
        fprintf('  所有区域均满足既有光伏装机要求。\n');
    end

    %% ======== 风电装机逐区域诊断 ========
    tmp_a2 = best_scale(nonlsol_n+1 : nonlsol_n+nonlwin_n);
    tmp_b2 = nonlcon_ins(nonlsol_n+1 : nonlsol_n+nonlwin_n);
    tmp_c2 = tmp_a2(:) .* tmp_b2(:);
    tmp_d2 = nonlcon_sel(nonlsol_n+1 : nonlsol_n+nonlwin_n);
    opt_wind = zeros(20, 1);
    for i = 1:20
        idx = find(tmp_d2 == i);
        opt_wind(i) = sum(tmp_c2(idx));
    end
    wind_unmet = opt_wind < cur_wind;
    wind_unmet_count = sum(wind_unmet);

    fprintf('\n=== 风电装机容量逐区域诊断 ===\n');
    fprintf('违反区域数: %d / 20,  允许违反数: %d\n', ...
        wind_unmet_count, allowed_unmet_wind);
    if wind_unmet_count > 0
        unmet_idx = find(wind_unmet);
        for k = 1:length(unmet_idx)
            r = unmet_idx(k);
            fprintf('  区域 %2d (%s): 优化容量 = %.4f TWp,  要求容量 = %.4f TWp,  缺口 = %.4f TWp\n', ...
                r, region_names{r}, opt_wind(r), cur_wind(r), cur_wind(r) - opt_wind(r));
        end
    else
        fprintf('  所有区域均满足既有风电装机要求。\n');
    end

    fprintf('\n');
end


function names = get_region_names()
    names = {
        'North America',      % 1
        'Central America',    % 2
        'South America',      % 3
        'Europe',             % 4
        'North Africa',       % 5
        'West Africa',        % 6
        'East Africa',        % 7
        'Southern Africa',    % 8
        'Middle East',        % 9
        'Central Asia',       % 10
        'South Asia',         % 11
        'East Asia',          % 12
        'Southeast Asia',     % 13
        'Oceania-Australia',  % 14
        'Japan-Korea',        % 15
        'Russia',             % 16
        'Caribbean',          % 17
        'Pacific Islands',    % 18
        'Greenland',          % 19
        'Antarctica'          % 20
    };
end
