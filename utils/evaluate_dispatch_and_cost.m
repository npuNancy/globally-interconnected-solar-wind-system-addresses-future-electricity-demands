function [metrics, detail] = evaluate_dispatch_and_cost(ins_cap, gens, loads, CGrid_Index, scale, ...
    base_load_ratio, interconnection_mode, cost_cfg, nonlsol)
% EVALUATE_DISPATCH_AND_COST — 8760小时逐时调度模拟与成本核算
%
% 将逐小时调度与成本核算封装成一个共享函数。
% 调度逻辑从现有 OptFun_*_Dispatch_*.m 平移，不调整基荷、0/1 选址和充放电顺序。
%
% 输入：
%   ins_cap              - 候选格网装机容量向量（TWp）
%   gens                 - 候选格网发电时序矩阵（TWh, 8760h）
%   loads                - 20区域负荷时序矩阵（TW, 8760h）
%   CGrid_Index          - 候选格网区域索引矩阵 [区域编号, 选中状态, 陆海标记]
%                        CGrid_Index(:,3): 0 = 陆上（onshore），1 = 海上（offshore）
%   scale                - 决策向量
%   base_load_ratio      - 基荷比例
%   interconnection_mode - 'S-C'（大陆互联, maxNodes=3）或 'S-A'（邻近互联, maxNodes=2）
%   cost_cfg             - 成本模型配置（来自 cost_model_config()）
%   nonlsol              - 光伏候选格网数量（用于区分光伏/风电）
%
% 输出：
%   metrics - 结构体（同前）
%   detail  - 可选第二输出，包含逐小时能源流数据（仅当 nargout >= 2 时计算）
%       .raw_vre_generation_twh_hourly  - 原始风光发电量 (1×8760)
%       .load_twh_hourly                - 原始总负荷 (1×8760)
%       .actual_vre_generation_twh_hourly - 负荷侧实际风光供电量 (1×8760)
%       .storage_discharge_twh_hourly   - 储能放电 (1×8760)
%       .storage_charge_twh_hourly      - 储能充电 (1×8760)
%       .base_generation_twh_hourly     - 基荷 (1×8760)
%       .flexible_generation_twh_hourly - 灵活电源 (1×8760)
%       .curtailment_twh_hourly         - 弃电 (1×8760)
%       .stored_energy_twh_hourly       - 储能电量 (1×8761)

    want_detail = nargout >= 2;

%% ======================== 1. 计算各区域发电曲线 ========================
CGrid_Index(:,2) = round(scale(1:length(CGrid_Index)));
grid_gens = zeros(20, 8760);
for gg_ind = 1:20
    index = find((CGrid_Index(:,1) == gg_ind) & (CGrid_Index(:,2) == 1));
    selgens = gens(index, :);
    grid_gens(gg_ind, :) = sum(selgens, 1, 'omitnan');
end

%% ======================== 2. 保存原始负荷并扣除基荷发电（非可再生调度电源） ========================
loads_original = loads;
grid_load = loads;
for gg_ind = 1:20
    tmp = grid_load(gg_ind, :);
    tmp = tmp - sum(tmp) * base_load_ratio / 8760;
    grid_load(gg_ind, :) = tmp;
end

%% ======================== 3. 储能与输电参数 ========================
toStorageLoss = 0.95;     % 储能充电效率
fromStorageLoss = 0.95;   % 储能放电效率
load Global_Trans trans_connections trans_loss

% 大陆互联和邻近互联均移除跨洲连接
trans_connections(trans_connections == 2) = 0;

% 从决策向量提取储能参数
storagePow = scale(length(CGrid_Index)+1 : length(CGrid_Index)+20) / 1000;  % TW
storageCap = storagePow .* scale(length(CGrid_Index)+21 : length(CGrid_Index)+40);  % TWh

%% ======================== 4. 调度变量初始化 ========================
stored_ele = zeros(8761, 20);
stored_ele(1, :) = storageCap * 0.5;
curtailed_ele = zeros(8760, 20);
flexible_ele = zeros(8760, 20);
shifted_ele = zeros(8760, 20, 20);
consumed_ele = zeros(8760, 20);

% 储能充放电追踪（用于 detail 输出）
storage_discharge_ele = zeros(8760, 20);
storage_charge_ele = zeros(8760, 20);

% 原始风光发电量（用于 detail 输出）
if want_detail
    raw_vre_by_region = sum(grid_gens, 2);  % 用于验证
end

%% ======================== 5. 构建输电拓扑与路径 ========================
trans_power = zeros(20, 20);
trans_power(trans_connections == 1) = scale(length(CGrid_Index)+41 : end) / 1000;

% 根据互联模式确定最大路径跳数
if strcmp(interconnection_mode, 'S-A')
    maxNodes = 2;   % 邻近互联：仅允许1跳（直接相连区域）
else
    maxNodes = 3;   % 大陆互联：最多2跳（含中继）
end

all_paths = {};
all_costs = {};
for gg_ind = 1:20
    startNode = gg_ind;
    minNodes = 2;
    trans_conn = int16(trans_power > 0);
    [tmp_paths, tmp_costs] = findAllPathsFromStart(trans_conn, trans_loss, startNode, minNodes, maxNodes);
    [tmp_costs, sortOrder] = sort(tmp_costs);
    tmp_paths = tmp_paths(sortOrder);
    tmp_costs = tmp_costs(tmp_costs < 1);
    tmp_paths = tmp_paths(tmp_costs < 1);
    all_paths{gg_ind} = tmp_paths;
    all_costs{gg_ind} = tmp_costs;
end
clear tmp_paths tmp_costs

%% ======================== 6. 8760小时调度循环 ========================
for time_ind = 1:8760
    % 恢复输电容量（每小时重置）
    trans_power = zeros(20, 20);
    trans_power(trans_connections == 1) = scale(length(CGrid_Index)+41 : end) / 1000;

    % 计算各区域供需差
    d_g_s = zeros(20, 3);
    d_g_s(:,1) = grid_load(:, time_ind);   % 需求
    d_g_s(:,2) = grid_gens(:, time_ind);   % 发电
    d_g_s(:,3) = d_g_s(:,2) - d_g_s(:,1); % 差值：<0 缺电；>0 富余

    % 计算直接消纳量
    index = d_g_s(:,3) < 0;
    consumed_ele(time_ind, index) = d_g_s(index, 2);
    consumed_ele(time_ind, ~index) = d_g_s(~index, 1);

    % --- 跨区输电调度 ---
    for gg_ind = 1:20
        if d_g_s(gg_ind, 3) <= 0
            continue;
        end
        g_costs = all_costs{gg_ind};
        g_paths = all_paths{gg_ind};
        for ad_grid_ind = 1:length(g_paths)
            g_route = g_paths{ad_grid_ind};
            if d_g_s(g_route(end), 3) >= 0
                continue;
            end
            g_capacities = calculatePathCapacity(g_route, trans_power);
            if g_capacities <= 0
                continue;
            end
            t_amount = min(min(abs(d_g_s(g_route(end),3)) / (1 - g_costs(ad_grid_ind)), ...
                g_capacities), d_g_s(gg_ind, 3));
            shifted_ele(time_ind, gg_ind, g_route(end)) = ...
                shifted_ele(time_ind, gg_ind, g_route(end)) + t_amount;
            d_g_s(gg_ind, 3) = d_g_s(gg_ind, 3) - t_amount;
            d_g_s(g_route(end), 3) = d_g_s(g_route(end), 3) + t_amount * (1 - g_costs(ad_grid_ind));
            for j = 1:(length(g_route) - 1)
                trans_power(g_route(j), g_route(j+1)) = ...
                    trans_power(g_route(j), g_route(j+1)) - t_amount;
            end
        end
    end

    % --- 储能充放电调度 ---
    for gg_ind = 1:20
        if d_g_s(gg_ind, 3) >= 0  % 富余 → 充电
            t_amount = min(min(d_g_s(gg_ind,3), storagePow(gg_ind)), ...
                (storageCap(gg_ind) - stored_ele(time_ind, gg_ind)) / toStorageLoss);
            stored_ele(time_ind+1, gg_ind) = stored_ele(time_ind, gg_ind) + t_amount * toStorageLoss;
            curtailed_ele(time_ind, gg_ind) = d_g_s(gg_ind, 3) - t_amount;
            storage_charge_ele(time_ind, gg_ind) = t_amount;
            d_g_s(gg_ind, 3) = 0;
        else  % 缺电 → 放电
            t_amount = min(min(storagePow(gg_ind) / fromStorageLoss, abs(d_g_s(gg_ind,3))), ...
                stored_ele(time_ind, gg_ind));
            stored_ele(time_ind+1, gg_ind) = max(stored_ele(time_ind, gg_ind) - t_amount, 0);
            storage_discharge_ele(time_ind, gg_ind) = t_amount;
            flexible_ele(time_ind, gg_ind) = abs(d_g_s(gg_ind, 3) + t_amount);
            d_g_s(gg_ind, 3) = 0;
        end
    end
end

%% ======================== 7. 计算诊断指标 ========================

% ---- 基础统计 ----
total_load_twh = sum(loads(:));

% 计算选中 VRE 总容量（TWp）
total_vre_cap = sum(ins_cap(CGrid_Index(:,2) == 1));

% ---- 容量诊断指标（GW） ----
sel_mask = CGrid_Index(:,2) == 1;
grid_idx = (1:length(CGrid_Index))';
pv_sel   = sel_mask & (grid_idx <= nonlsol);
wind_sel = sel_mask & (grid_idx > nonlsol);

pv_capacity_gw   = sum(ins_cap(pv_sel)) * 1000;    % TWp → GWp
wind_capacity_gw = sum(ins_cap(wind_sel)) * 1000;
total_vre_capacity_gw = pv_capacity_gw + wind_capacity_gw;
selected_pv_grid_count   = sum(pv_sel);
selected_wind_grid_count = sum(wind_sel);

% 陆上/海上风电拆分（CGrid_Index(:,3): 0=onshore, 1=offshore）
onshore_wind_sel  = wind_sel & (CGrid_Index(:,3) == 0);
offshore_wind_sel = wind_sel & (CGrid_Index(:,3) == 1);
onshore_wind_capacity_gw  = sum(ins_cap(onshore_wind_sel)) * 1000;
offshore_wind_capacity_gw = sum(ins_cap(offshore_wind_sel)) * 1000;

% ---- 调度前原始风光发电量 ----
gross_pv_generation_twh   = sum(gens(pv_sel, :), 'all');
gross_wind_generation_twh = sum(gens(wind_sel, :), 'all');
gross_vre_generation_twh  = gross_pv_generation_twh + gross_wind_generation_twh;

% 原始风光发电量 / 总负荷，仅用于诊断超配程度
gross_vre_to_load_ratio = gross_vre_generation_twh / total_load_twh;

% ---- 弃电量与弃电率 ----
curtailed_vre_twh = sum(curtailed_ele(:));

if gross_vre_generation_twh <= 0
    curtailment_rate = 0;
else
    curtailment_rate = curtailed_vre_twh / gross_vre_generation_twh;
end

% ---- 实际风光发电量 ----
actual_vre_generation_twh = max(gross_vre_generation_twh - curtailed_vre_twh, 0);

% ---- 其他电源 ----
base_generation_twh = base_load_ratio * total_load_twh;
flexible_generation_twh = sum(flexible_ele(:));
flexible_ratio = flexible_generation_twh / total_load_twh;

% ---- 总发电量（储能放电不计入，避免重复计算） ----
total_generation_twh = actual_vre_generation_twh ...
    + base_generation_twh ...
    + flexible_generation_twh;

if total_generation_twh <= 0
    error('Dispatch:InvalidTotalGeneration', ...
        '总发电量必须大于 0，当前值为 %.6f TWh', total_generation_twh);
end

% ---- 严格定义的 VRE 渗透率 ----
vre_share = actual_vre_generation_twh / total_generation_twh;

% 输电容量（TW）
trans_power = zeros(20, 20);
trans_power(trans_connections == 1) = scale(length(CGrid_Index)+41 : end) / 1000;
transmission_capacity_TW = sum(trans_power(:));

%% ======================== 8. 成本计算 ========================
if strcmp(cost_cfg.COST_MODE, 'legacy_capex')
    % =============== 旧版一次性建设成本（回归兼容） ===============
    obj_cost = compute_legacy_capex(ins_cap, CGrid_Index, nonlsol, ...
        transmission_capacity_TW, storageCap, cost_cfg);

    metrics.total_annual_cost = obj_cost;
    metrics.cost_breakdown = struct( ...
        'vre_capex_billion',    obj_cost - cost_cfg.STORAGE_CAPEX_BILLION_PER_TWH * sum(storageCap(:)) ...
                                  - cost_cfg.TX_CAPEX_BILLION_PER_TW * transmission_capacity_TW, ...
        'storage_capex_billion', cost_cfg.STORAGE_CAPEX_BILLION_PER_TWH * sum(storageCap(:)), ...
        'tx_capex_billion',     cost_cfg.TX_CAPEX_BILLION_PER_TW * transmission_capacity_TW, ...
        'vre_om_billion',       0, ...
        'storage_om_billion',   0, ...
        'tx_om_billion',        0, ...
        'flexible_opex_billion', 0 ...
    );

else
    % =============== 年度化增量系统成本 ===============
    % 加载当前装机容量
    load Global_Init_State cur_solar cur_wind cur_storage cur_trans
    cur_solar = cur_solar / 1e6;   % MWp → TWp
    cur_wind  = cur_wind  / 1e6;   % MWp → TWp
    cur_storage_twh = cur_storage / 1e6;  % MWh → TWh

    % 清理跨洲链路后获取当前输电容量
    cur_trans(6,1)=0; cur_trans(7,1)=0; cur_trans(1,6)=0; cur_trans(1,7)=0;
    cur_trans(17,4)=0; cur_trans(18,4)=0; cur_trans(4,17)=0; cur_trans(4,18)=0;
    cur_trans(cur_trans < 2) = 0;
    current_trans_TW = sum(cur_trans(:)) / 1000;  % GW → TW

    % ---- 8a. 增量 VRE CAPEX（分区域） ----
    vre_capex = 0;

    % 亚洲（区域 9-13）
    idx = find((CGrid_Index(:,1)>8) & (CGrid_Index(:,1)<14) & (CGrid_Index(:,2)==1) & (CGrid_Index(:,3)==0));
    vre_capex = vre_capex + cost_cfg.PV_CAPEX_USD_PER_KW.asia * sum(ins_cap(idx(idx<=nonlsol)));
    vre_capex = vre_capex + cost_cfg.ONWIND_CAPEX_USD_PER_KW.asia * sum(ins_cap(idx(idx>nonlsol)));

    % 北美（区域 1）
    idx = find((CGrid_Index(:,1)==1) & (CGrid_Index(:,2)==1) & (CGrid_Index(:,3)==0));
    vre_capex = vre_capex + cost_cfg.PV_CAPEX_USD_PER_KW.north_america * sum(ins_cap(idx(idx<=nonlsol)));
    vre_capex = vre_capex + cost_cfg.ONWIND_CAPEX_USD_PER_KW.north_america * sum(ins_cap(idx(idx>nonlsol)));

    % 欧洲（区域 5-8）
    idx = find((CGrid_Index(:,1)>4) & (CGrid_Index(:,1)<9) & (CGrid_Index(:,2)==1) & (CGrid_Index(:,3)==0));
    vre_capex = vre_capex + cost_cfg.PV_CAPEX_USD_PER_KW.europe * sum(ins_cap(idx(idx<=nonlsol)));
    vre_capex = vre_capex + cost_cfg.ONWIND_CAPEX_USD_PER_KW.europe * sum(ins_cap(idx(idx>nonlsol)));

    % 拉丁美洲（区域 2-4）
    idx = find((CGrid_Index(:,1)>1) & (CGrid_Index(:,1)<5) & (CGrid_Index(:,2)==1) & (CGrid_Index(:,3)==0));
    vre_capex = vre_capex + cost_cfg.PV_CAPEX_USD_PER_KW.latin_america * sum(ins_cap(idx(idx<=nonlsol)));
    vre_capex = vre_capex + cost_cfg.ONWIND_CAPEX_USD_PER_KW.latin_america * sum(ins_cap(idx(idx>nonlsol)));

    % 非洲（区域 16-20）
    idx = find((CGrid_Index(:,1)>15) & (CGrid_Index(:,1)<21) & (CGrid_Index(:,2)==1) & (CGrid_Index(:,3)==0));
    vre_capex = vre_capex + cost_cfg.PV_CAPEX_USD_PER_KW.africa * sum(ins_cap(idx(idx<=nonlsol)));
    vre_capex = vre_capex + cost_cfg.ONWIND_CAPEX_USD_PER_KW.africa * sum(ins_cap(idx(idx>nonlsol)));

    % 大洋洲（区域 14-15）
    idx = find((CGrid_Index(:,1)>13) & (CGrid_Index(:,1)<16) & (CGrid_Index(:,2)==1) & (CGrid_Index(:,3)==0));
    vre_capex = vre_capex + cost_cfg.PV_CAPEX_USD_PER_KW.oceania * sum(ins_cap(idx(idx<=nonlsol)));
    vre_capex = vre_capex + cost_cfg.ONWIND_CAPEX_USD_PER_KW.oceania * sum(ins_cap(idx(idx>nonlsol)));

    % 海上风电（全球统一成本）
    idx = find((CGrid_Index(:,3)==1) & (CGrid_Index(:,2)==1));
    offwind_capex = cost_cfg.OFFWIND_CAPEX_USD_PER_KW * sum(ins_cap(idx(idx>nonlsol)));
    vre_capex = vre_capex + offwind_capex;

    % 按区域分解光伏和陆上风电 CAPEX（用于计算各自 O&M）
    pv_capex = 0; onwind_capex = 0;
    regions_pv = [1012.6, 861.4, 861.4, 861.4, 1075.9, 1075.9, 1075.9, 1075.9, ...
                  927.6, 927.6, 927.6, 927.6, 927.6, 922.5, 922.5, 1256.6, 1256.6, 1256.6, 1256.6, 1256.6];
    regions_ow = [1284.8, 1499.4, 1499.4, 1499.4, 1650.4, 1650.4, 1650.4, 1650.4, ...
                  1313.0, 1313.0, 1313.0, 1313.0, 1313.0, 1360.7, 1360.7, 1684.7, 1684.7, 1684.7, 1684.7, 1684.7];
    for r = 1:20
        idx = find((CGrid_Index(:,1)==r) & (CGrid_Index(:,2)==1) & (CGrid_Index(:,3)==0));
        pv_capex = pv_capex + regions_pv(r) * sum(ins_cap(idx(idx<=nonlsol)));
        onwind_capex = onwind_capex + regions_ow(r) * sum(ins_cap(idx(idx>nonlsol)));
    end

    % 增量 VRE CAPEX = 总 VRE CAPEX - 当前装机成本（常数，不影响最优解）
    current_vre_cap = sum(cur_solar) + sum(cur_wind);
    % 使用加权平均成本估算当前装机 CAPEX（用于增量计算）
    avg_vre_cost = vre_capex / max(total_vre_cap, 1e-10);
    incremental_vre_capex = vre_capex - avg_vre_cost * current_vre_cap;
    incremental_vre_capex = max(incremental_vre_capex, 0);

    % VRE 年度化 CAPEX（使用加权 CRF）
    if vre_capex > 0
        % 按各技术 CAPEX 比例加权 CRF
        vre_capex_no_offwind = vre_capex - offwind_capex;
        if vre_capex_no_offwind > 0
            crf_vre_land = (pv_capex * cost_cfg.CRF_PV + onwind_capex * cost_cfg.CRF_ONWIND) / vre_capex_no_offwind;
        else
            crf_vre_land = cost_cfg.CRF_PV;
        end
        annualized_vre_capex = incremental_vre_capex * ...
            ((vre_capex_no_offwind * crf_vre_land + offwind_capex * cost_cfg.CRF_OFFWIND) / vre_capex);
    else
        annualized_vre_capex = 0;
    end

    % ---- 8b. 增量储能 CAPEX ----
    storage_capex_total = cost_cfg.STORAGE_CAPEX_BILLION_PER_TWH * sum(storageCap(:));
    current_storage_capex = cost_cfg.STORAGE_CAPEX_BILLION_PER_TWH * sum(cur_storage_twh(:));
    incremental_storage_capex = max(storage_capex_total - current_storage_capex, 0);
    annualized_storage_capex = incremental_storage_capex * cost_cfg.CRF_STORAGE;

    % ---- 8c. 增量输电 CAPEX（保持原逻辑：98 × Σ 线路容量） ----
    tx_capex_billion = cost_cfg.TX_CAPEX_BILLION_PER_TW * transmission_capacity_TW;
    current_tx_capex = cost_cfg.TX_CAPEX_BILLION_PER_TW * current_trans_TW;
    incremental_tx_capex = max(tx_capex_billion - current_tx_capex, 0);
    annualized_tx_capex = incremental_tx_capex * cost_cfg.CRF_TX;

    % ---- 8d. 运维成本（年度） ----
    annual_pv_om      = pv_capex      * cost_cfg.PV_OM_RATIO;
    annual_onwind_om  = onwind_capex  * cost_cfg.ONWIND_OM_RATIO;
    annual_offwind_om = offwind_capex * cost_cfg.OFFWIND_OM_RATIO;
    vre_om = annual_pv_om + annual_onwind_om + annual_offwind_om;

    storage_om = 0;
    if cost_cfg.ENABLE_STORAGE_OM
        storage_om = storage_capex_total * cost_cfg.STORAGE_OM_RATIO;
    end

    tx_om = 0;
    if cost_cfg.ENABLE_TX_OM
        tx_om = tx_capex_billion * cost_cfg.TX_OM_RATIO;
    end

    % ---- 8e. 灵活电源运行成本（可选） ----
    flexible_opex = 0;
    if cost_cfg.ENABLE_FLEXIBLE_OPEX
        % flexible_ele: TWh; MC: USD/MWh
        % TWh × USD/MWh / 1000 = billion USD
        for r = 1:20
            flexible_opex = flexible_opex + ...
                sum(flexible_ele(:, r)) * cost_cfg.FLEXIBLE_MC_USD_PER_MWH(r) / 1000;
        end
    end

    % ---- 8f. 弃电成本（可选） ----
    curtailment_cost = 0;
    if cost_cfg.ENABLE_CURTAILMENT_COST
        curtailment_cost = sum(curtailed_ele(:)) * cost_cfg.CURTAILMENT_COST_USD_PER_MWH / 1000;
    end

    % ---- 汇总 ----
    metrics.total_annual_cost = annualized_vre_capex + annualized_storage_capex + ...
        annualized_tx_capex + vre_om + storage_om + tx_om + flexible_opex + curtailment_cost;

    metrics.cost_breakdown = struct( ...
        'vre_capex_billion',              vre_capex, ...
        'incremental_vre_capex_billion',  incremental_vre_capex, ...
        'annualized_vre_capex_billion',   annualized_vre_capex, ...
        'storage_capex_billion',          storage_capex_total, ...
        'incremental_storage_capex_billion', incremental_storage_capex, ...
        'annualized_storage_capex_billion',  annualized_storage_capex, ...
        'tx_capex_billion',               tx_capex_billion, ...
        'incremental_tx_capex_billion',   incremental_tx_capex, ...
        'annualized_tx_capex_billion',    annualized_tx_capex, ...
        'vre_om_billion',                 vre_om, ...
        'storage_om_billion',             storage_om, ...
        'tx_om_billion',                  tx_om, ...
        'flexible_opex_billion',          flexible_opex, ...
        'curtailment_cost_billion',       curtailment_cost ...
    );
end

%% ======================== 9. 组装输出 ========================
metrics.curtailment_rate  = curtailment_rate;
metrics.flexible_ratio    = flexible_ratio;
metrics.vre_share         = vre_share;
metrics.total_load_twh    = total_load_twh;
metrics.total_vre_cap_twp = total_vre_cap;
metrics.transmission_capacity_TW = transmission_capacity_TW;
metrics.grid_gens         = grid_gens;
metrics.flexible_ele      = flexible_ele;
metrics.curtailed_ele     = curtailed_ele;

% 容量诊断
metrics.pv_capacity_gw             = pv_capacity_gw;
metrics.wind_capacity_gw           = wind_capacity_gw;
metrics.onshore_wind_capacity_gw   = onshore_wind_capacity_gw;
metrics.offshore_wind_capacity_gw  = offshore_wind_capacity_gw;
metrics.total_vre_capacity_gw      = total_vre_capacity_gw;
metrics.selected_pv_grid_count     = selected_pv_grid_count;
metrics.selected_wind_grid_count   = selected_wind_grid_count;

% 原始发电量诊断
metrics.gross_pv_generation_twh    = gross_pv_generation_twh;
metrics.gross_wind_generation_twh  = gross_wind_generation_twh;
metrics.gross_vre_generation_twh   = gross_vre_generation_twh;
metrics.gross_vre_to_load_ratio    = gross_vre_to_load_ratio;

% 调度后发电量诊断
metrics.actual_vre_generation_twh  = actual_vre_generation_twh;
metrics.base_generation_twh        = base_generation_twh;
metrics.flexible_generation_twh    = flexible_generation_twh;
metrics.total_generation_twh       = total_generation_twh;
metrics.curtailed_vre_twh          = curtailed_vre_twh;

%% ======================== 10. 可选逐小时 detail 输出 ========================
if want_detail
    detail = struct();

    % 时间字段
    detail.hour_index = (1:8760);

    % 图 A：发电侧原始出力
    detail.raw_vre_generation_twh_hourly = sum(grid_gens, 1);
    detail.load_twh_hourly = sum(loads_original, 1);

    % 图 B：负荷侧供电结构 — 按区域构建
    % 基荷：每区域每小时的恒定基荷
    base_by_region_twh = zeros(20, 8760);
    for gg_ind = 1:20
        base_by_region_twh(gg_ind, :) = sum(loads_original(gg_ind, :)) * base_load_ratio / 8760;
    end

    % 灵活电源（已追踪）
    flexible_by_region_twh = flexible_ele';  % 8760×20 → 20×8760

    % 储能放电（已追踪）
    storage_discharge_by_region_twh = storage_discharge_ele';  % 8760×20 → 20×8760

    % 负荷侧实际风光供电量 = 负荷 - 储能放电 - 基荷 - 灵活电源
    load_by_region_twh = loads_original;  % 20×8760
    actual_vre_by_region_twh = load_by_region_twh ...
        - storage_discharge_by_region_twh ...
        - base_by_region_twh ...
        - flexible_by_region_twh;
    actual_vre_by_region_twh = max(actual_vre_by_region_twh, 0);

    % 全球逐小时汇总
    detail.actual_vre_generation_twh_hourly = sum(actual_vre_by_region_twh, 1);
    detail.storage_discharge_twh_hourly = sum(storage_discharge_by_region_twh, 1);
    detail.storage_charge_twh_hourly = sum(storage_charge_ele, 2)';
    detail.base_generation_twh_hourly = sum(base_by_region_twh, 1);
    detail.flexible_generation_twh_hourly = sum(flexible_by_region_twh, 1);
    detail.curtailment_twh_hourly = sum(curtailed_ele, 2)';
    detail.stored_energy_twh_hourly = sum(stored_ele, 2)';  % 1×8761
end

end

%% ======================== 辅助函数 ========================
function obj_cost = compute_legacy_capex(ins_cap, CGrid_Index, nonlsol, ...
    transmission_capacity_TW, storageCap, cost_cfg)
% 旧版一次性建设成本计算（与 OptFun_SC_Dispatch_2050.m 完全一致）
% 所有成本系数引用 cost_cfg，确保修改配置后全局生效
    obj_cost = 0;
    pv = cost_cfg.PV_CAPEX_USD_PER_KW;
    ow = cost_cfg.ONWIND_CAPEX_USD_PER_KW;

    % 海上风电
    idx = find((CGrid_Index(:,3)==1) & (CGrid_Index(:,2)==1));
    obj_cost = obj_cost + cost_cfg.OFFWIND_CAPEX_USD_PER_KW * sum(ins_cap(idx(idx>nonlsol)));

    % 亚洲（区域 9-13）
    idx = find((CGrid_Index(:,1)>8) & (CGrid_Index(:,1)<14) & (CGrid_Index(:,2)==1) & (CGrid_Index(:,3)==0));
    obj_cost = obj_cost + pv.asia * sum(ins_cap(idx(idx<=nonlsol)));
    obj_cost = obj_cost + ow.asia * sum(ins_cap(idx(idx>nonlsol)));

    % 北美（区域 1）
    idx = find((CGrid_Index(:,1)==1) & (CGrid_Index(:,2)==1) & (CGrid_Index(:,3)==0));
    obj_cost = obj_cost + pv.north_america * sum(ins_cap(idx(idx<=nonlsol)));
    obj_cost = obj_cost + ow.north_america * sum(ins_cap(idx(idx>nonlsol)));

    % 欧洲（区域 5-8）
    idx = find((CGrid_Index(:,1)>4) & (CGrid_Index(:,1)<9) & (CGrid_Index(:,2)==1) & (CGrid_Index(:,3)==0));
    obj_cost = obj_cost + pv.europe * sum(ins_cap(idx(idx<=nonlsol)));
    obj_cost = obj_cost + ow.europe * sum(ins_cap(idx(idx>nonlsol)));

    % 拉丁美洲（区域 2-4）
    idx = find((CGrid_Index(:,1)>1) & (CGrid_Index(:,1)<5) & (CGrid_Index(:,2)==1) & (CGrid_Index(:,3)==0));
    obj_cost = obj_cost + pv.latin_america * sum(ins_cap(idx(idx<=nonlsol)));
    obj_cost = obj_cost + ow.latin_america * sum(ins_cap(idx(idx>nonlsol)));

    % 非洲（区域 16-20）
    idx = find((CGrid_Index(:,1)>15) & (CGrid_Index(:,1)<21) & (CGrid_Index(:,2)==1) & (CGrid_Index(:,3)==0));
    obj_cost = obj_cost + pv.africa * sum(ins_cap(idx(idx<=nonlsol)));
    obj_cost = obj_cost + ow.africa * sum(ins_cap(idx(idx>nonlsol)));

    % 大洋洲（区域 14-15）
    idx = find((CGrid_Index(:,1)>13) & (CGrid_Index(:,1)<16) & (CGrid_Index(:,2)==1) & (CGrid_Index(:,3)==0));
    obj_cost = obj_cost + pv.oceania * sum(ins_cap(idx(idx<=nonlsol)));
    obj_cost = obj_cost + ow.oceania * sum(ins_cap(idx(idx>nonlsol)));

    % 输电
    obj_cost = obj_cost + cost_cfg.TX_CAPEX_BILLION_PER_TW * transmission_capacity_TW;
    % 储能
    obj_cost = obj_cost + cost_cfg.STORAGE_CAPEX_BILLION_PER_TWH * sum(storageCap(:));
end
