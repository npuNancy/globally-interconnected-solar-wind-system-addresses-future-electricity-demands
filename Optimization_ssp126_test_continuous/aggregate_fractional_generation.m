function [grid_gens, effective_ins, site_frac] = ...
    aggregate_fractional_generation(ins_cap, gens, region_id, site_frac, n_regions)
% aggregate_fractional_generation
% 按照格网开发比例缩放装机容量和逐小时出力，并聚合到区域。
%
% 输入：
%   ins_cap    - 候选格网最大技术潜力容量向量（TWp），列向量或行向量
%   gens       - 候选格网逐小时发电时序矩阵（TWh, 8760h），行=格网，列=小时
%   region_id  - 候选格网所属区域编号向量（1~n_regions）
%   site_frac  - 候选格网开发比例向量（0~1）
%   n_regions  - 区域总数（通常为 20）
%
% 输出：
%   grid_gens     - n_regions × 8760 区域实际逐小时发电矩阵（TWh）
%   effective_ins - 候选格网实际装机容量向量（TWp）= ins_cap .* site_frac
%   site_frac     - 裁剪到 [0, 1] 后的开发比例向量

% 统一为列向量并裁剪到 [0, 1]
site_frac = site_frac(:);
site_frac = max(0, min(1, site_frac));

ins_cap = ins_cap(:);
region_id = region_id(:);

assert(length(site_frac) == length(ins_cap), ...
    'site_frac 与 ins_cap 长度不一致');
assert(size(gens, 1) == length(ins_cap), ...
    'gens 行数与候选格网数量不一致');

% 实际装机容量 = 最大技术潜力 × 开发比例
effective_ins = ins_cap .* site_frac;

% 按区域聚合逐小时出力
grid_gens = zeros(n_regions, size(gens, 2));

for region_idx = 1:n_regions
    index = (region_id == region_idx);
    grid_gens(region_idx, :) = ...
        sum(gens(index, :) .* site_frac(index), 1, 'omitnan');
end
end
