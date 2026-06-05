function f = objective_total_cost(scale, ins_cap, gens, loads, CGrid_Index, ...
    base_load_ratio, interconnection_mode, cost_cfg, nonlsol)
% OBJECTIVE_TOTAL_COST — 单目标成本最小化目标函数
%
% 调用 evaluate_dispatch_and_cost 并返回标量：年度化系统总成本。
%
% 输入：
%   scale                - 决策向量
%   ins_cap, gens, loads, CGrid_Index - 模型数据
%   base_load_ratio      - 基荷比例
%   interconnection_mode - 'S-C' 或 'S-A'
%   cost_cfg             - 成本配置
%   nonlsol              - 光伏候选格网数
%
% 输出：
%   f - 标量，年度化系统总成本（billion USD/year 或 billion USD）

    metrics = evaluate_dispatch_and_cost_cached(scale, ins_cap, gens, loads, CGrid_Index, ...
        base_load_ratio, interconnection_mode, cost_cfg, nonlsol);
    f = metrics.total_annual_cost;
end
