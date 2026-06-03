function [c, ceq] = continuous_capacity_constraints(x, data_file)
% continuous_capacity_constraints
% 保证各区域未来光伏和风电实际装机不低于已有装机。
%
% MATLAB 非线性约束要求 c <= 0。
%
% 输入：
%   x         - 决策向量（前 nonlsol+nonlwin 个为格网开发比例）
%   data_file - NonlConData*.mat 文件名
%
% 输出：
%   c   - 40×1 不等式约束向量 [光伏20区域缺口; 风电20区域缺口]
%          c(i) <= 0 表示区域 i 满足约束
%   ceq - 等式约束（空）

load(data_file, ...
    'nonlcon_sel', ...
    'nonlcon_ins', ...
    'nonlcon_ub', ...
    'nonlsol', ...
    'nonlwin');

load Global_Init_State cur_solar cur_wind

cur_solar = cur_solar / 1e6;  % MW -> TW
cur_wind  = cur_wind  / 1e6;

% 提取格网开发比例
site_frac = x(1:(nonlsol + nonlwin));
site_frac = site_frac(:);

solar_frac = site_frac(1:nonlsol);
wind_frac = site_frac(nonlsol+1:nonlsol+nonlwin);

solar_ins = nonlcon_ins(1:nonlsol);
wind_ins = nonlcon_ins(nonlsol+1:nonlsol+nonlwin);

solar_region_id = nonlcon_sel(1:nonlsol, 1);
wind_region_id = nonlcon_sel(nonlsol+1:nonlsol+nonlwin, 1);

% 按区域聚合实际装机容量
solar_region = accumarray( ...
    solar_region_id, ...
    solar_frac .* solar_ins, ...
    [20, 1], ...
    @sum, ...
    0 ...
);

wind_region = accumarray( ...
    wind_region_id, ...
    wind_frac .* wind_ins, ...
    [20, 1], ...
    @sum, ...
    0 ...
);

% 约束：已有装机 - 实际装机 <= 0（即实际装机 >= 已有装机）
c = [
    cur_solar(:) - solar_region(:);
    cur_wind(:)  - wind_region(:)
];

ceq = [];
end
