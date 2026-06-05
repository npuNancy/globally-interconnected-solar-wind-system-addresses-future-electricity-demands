function cost_cfg = cost_model_config()
% COST_MODEL_CONFIG — 共享成本模型配置
%
% 集中存放所有成本相关参数：
%   - CAPEX（风光、储能、输电）
%   - WACC 与寿命
%   - O&M 比例
%   - 灵活电源成本开关
%   - 弃电约束与弃电成本开关
%   - 兼容旧成本口径的开关
%
% 用法：cost_cfg = cost_model_config();

%% 1. 成本模式
%   'legacy_capex'           — 旧版一次性建设成本（回归兼容）
%   'annualized_incremental' — 年度化增量系统成本（含运维）
cost_cfg.COST_MODE = 'annualized_incremental';

%% 2. 风光建设成本 CAPEX（USD/kW = billion USD/TW）
% 2.1 光伏：按洲差异化
cost_cfg.PV_CAPEX_USD_PER_KW = struct( ...
    'asia',         927.6,   ...  % 区域 9-13
    'north_america', 1012.6, ...  % 区域 1
    'europe',       1075.9,  ...  % 区域 5-8
    'latin_america', 861.4,  ...  % 区域 2-4
    'africa',       1256.6,  ...  % 区域 16-20
    'oceania',      922.5    ...  % 区域 14-15
);

% 2.2 陆上风电：按洲差异化
cost_cfg.ONWIND_CAPEX_USD_PER_KW = struct( ...
    'asia',         1313.0, ...
    'north_america', 1284.8, ...
    'europe',       1650.4, ...
    'latin_america', 1499.4, ...
    'africa',       1684.7, ...
    'oceania',      1360.7  ...
);

% 2.3 海上风电：全球统一
cost_cfg.OFFWIND_CAPEX_USD_PER_KW = 3461;

%% 3. 储能建设成本
cost_cfg.STORAGE_CAPEX_BILLION_PER_TWH = 350;  % billion USD / TWh

%% 4. 跨区域输电建设成本
cost_cfg.TX_CAPEX_BILLION_PER_TW = 98;  % billion USD / TW

%% 5. 加权平均资本成本（WACC）与技术寿命
cost_cfg.WACC = 0.074;
cost_cfg.LIFETIME_PV       = 25;   % 年
cost_cfg.LIFETIME_ONWIND   = 25;   % 年
cost_cfg.LIFETIME_OFFWIND  = 25;   % 年
cost_cfg.LIFETIME_STORAGE  = 15;   % 年
cost_cfg.LIFETIME_TX       = 40;   % 年

% 预计算资本回收系数 CRF = r*(1+r)^n / ((1+r)^n - 1)
r = cost_cfg.WACC;
cost_cfg.CRF_PV      = compute_crf(r, cost_cfg.LIFETIME_PV);
cost_cfg.CRF_ONWIND  = compute_crf(r, cost_cfg.LIFETIME_ONWIND);
cost_cfg.CRF_OFFWIND = compute_crf(r, cost_cfg.LIFETIME_OFFWIND);
cost_cfg.CRF_STORAGE = compute_crf(r, cost_cfg.LIFETIME_STORAGE);
cost_cfg.CRF_TX      = compute_crf(r, cost_cfg.LIFETIME_TX);

%% 6. 运维成本 O&M（年度，占 CAPEX 比例）
cost_cfg.PV_OM_RATIO      = 0.01;  % 光伏 1%/年
cost_cfg.ONWIND_OM_RATIO  = 0.03;  % 陆上风电 3%/年
cost_cfg.OFFWIND_OM_RATIO = 0.03;  % 海上风电 3%/年

% 储能和输电 O&M 可选开关
cost_cfg.ENABLE_STORAGE_OM = false;
cost_cfg.STORAGE_OM_RATIO  = 0.0;   % 占储能 CAPEX 比例

cost_cfg.ENABLE_TX_OM = false;
cost_cfg.TX_OM_RATIO  = 0.0;        % 占输电 CAPEX 比例

%% 7. 灵活电源运行成本（默认关闭）
cost_cfg.ENABLE_FLEXIBLE_OPEX = false;
cost_cfg.FLEXIBLE_MC_USD_PER_MWH = zeros(20, 1);  % 各区域边际成本 USD/MWh

%% 8. 弃电约束与弃电成本（默认关闭）
cost_cfg.ENABLE_CURTAILMENT_CONSTRAINT = false;
cost_cfg.MAX_CURTAILMENT = 0.15;

cost_cfg.ENABLE_CURTAILMENT_COST = false;
cost_cfg.CURTAILMENT_COST_USD_PER_MWH = 0;

end

%% ======== 辅助函数 ========
function crf = compute_crf(r, n)
% 资本回收系数 Capital Recovery Factor
%   r: 折现率（WACC）
%   n: 技术寿命（年）
%   crf = r * (1+r)^n / ((1+r)^n - 1)
    crf = r * (1 + r)^n / ((1 + r)^n - 1);
end
