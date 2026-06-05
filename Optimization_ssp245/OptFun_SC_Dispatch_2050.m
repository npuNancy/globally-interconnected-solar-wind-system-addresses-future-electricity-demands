function f = OptFun_SC_Dispatch_2050(ins_cap, gens, loads, CGrid_Index, scale, base_load_ratio)
% OptFun_SC_Dispatch_2050 — 2050年成本最小化目标函数（大陆互联 S-C）
%
% 阶段封装：加载成本配置，调用共享 objective_total_cost。
%
% 输入：
%   ins_cap           - 候选格网装机容量向量（TWp）
%   gens              - 候选格网发电时序矩阵（TWh, 8760h）
%   loads             - 20区域负荷时序矩阵（TW, 8760h）
%   CGrid_Index       - 候选格网区域索引矩阵 [区域编号, 选中状态, 陆海标记]
%   scale             - 决策向量
%   base_load_ratio   - 基荷比例
%
% 输出：
%   f - 标量，年度化系统总成本

    persistent cost_cfg nonlsol
    if isempty(cost_cfg)
        cost_cfg = cost_model_config();
        load NonlConData.mat nonlsol
    end

    f = objective_total_cost(scale, ins_cap, gens, loads, CGrid_Index, ...
        base_load_ratio, 'S-C', cost_cfg, nonlsol);
end
