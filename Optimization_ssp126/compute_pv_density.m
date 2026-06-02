function pv_density = compute_pv_density(solar_index)
% compute_pv_density  计算每个光伏候选格网的纬度依赖装机密度
%
%   pv_density = compute_pv_density(solar_index)
%
%   输入：solar_index — 180×360 矩阵的线性索引向量
%   输出：pv_density  — 每个格网的 PV 装机密度（MW/km²），列向量
%
%   公式：pv_density = 161.9 × Ω(lat) × FR
%   其中：
%     161.9 W/m² = 光伏组件标准功率密度（STC）
%     Ω = cos(β) / (cos(β) + sin(β)/tan(α_min))  地面覆盖率比 GCR
%     β = |0.35396 × lat + sign(lat) × 16.84775|  面板倾角幅度
%       = 0.35396 × |lat| + 16.84775              对称化简
%     α_min = 90° − |lat| − 23.45°                 冬至正午太阳高度角
%     FR = 0.15                                     统一适宜性系数

    FR = 0.15;

    % 180×360 矩阵的行号（1=最北，180=最南）
    rows = mod(solar_index - 1, 180) + 1;
    lat  = 90.5 - rows;

    % 面板倾角幅度（南北半球对称）
    beta = 0.35396 * abs(lat) + 16.84775;

    % 冬至正午太阳高度角
    alpha_min = 90 - abs(lat) - 23.45;
    alpha_min = max(alpha_min, 0.1);  % 极夜保护，防止 tan(0) 除零

    beta_rad      = deg2rad(beta);
    alpha_min_rad = deg2rad(alpha_min);

    % 地面覆盖率比 GCR
    Omega = cos(beta_rad) ./ (cos(beta_rad) + sin(beta_rad) ./ tan(alpha_min_rad));

    % 装机密度（MW/km²）
    pv_density = 161.9 * Omega * FR;
    pv_density = pv_density(:);
end
