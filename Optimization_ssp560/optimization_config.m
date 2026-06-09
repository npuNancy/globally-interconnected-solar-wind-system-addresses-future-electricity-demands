%% optimization_config.m — SSP5-6.0 优化配置参数
%
% 基荷比例公式：(Nuclear + Geothermal + Oil + Coal_w/o_CCS + Gas_w/o_CCS) / Total
% 数据来源：AR6 5模型交集均值（详见 document/SSPs_Analysis_Report.md）

%% 1. NSGA-II 优化参数（可通过环境变量覆盖）
%   export POPULATION_SIZE=30    # 种群大小，默认 1000
%   export MAX_GENERATIONS=3     # 最大代数，默认 200
env_pop = getenv('POPULATION_SIZE');
env_gen = getenv('MAX_GENERATIONS');
if ~isempty(env_pop) && str2double(env_pop) > 0
    POPULATION_SIZE = str2double(env_pop);
else
    POPULATION_SIZE = 1000;
end
if ~isempty(env_gen) && str2double(env_gen) > 0
    MAX_GENERATIONS = str2double(env_gen);
else
    MAX_GENERATIONS = 200;
end

%% 2. 总电力需求（TWh）
DEMAND_2050 = 65277;   % AR6 SSP5-6.0: 235.0 EJ/yr
DEMAND_2040 = 53189;   % AR6 SSP5-6.0: 191.5 EJ/yr
DEMAND_2030 = 40483;   % AR6 SSP5-6.0: 145.7 EJ/yr

%% 3. 基荷比例
BASE_LOAD_RATIO_2050 = 0.642;  % 64.2%
BASE_LOAD_RATIO_2040 = 0.747;  % 74.7%
BASE_LOAD_RATIO_2030 = 0.788;  % 78.8%

%% 4. Pareto preferred solution 筛选配置

% SSP5-6.0：化石能源主导路径，不设置风光渗透率下界，使用五模型第二高值作为上界
SCENARIO_NAME = 'SSP5-6.0';
SELECTION_MODE = 'fossil_upper_bound';

MAX_CURTAILMENT = 0.30;

% 最终结果验收时，仅针对弃电率允许额外 1 个百分点余量。
% 注意：GA 搜索阶段仍然使用严格的 MAX_CURTAILMENT。
CURTAILMENT_ACCEPTANCE_MARGIN = 0.01;

% SSP5-6.0 不设置风光渗透率下界
MIN_VRE_SHARE_2030 = NaN;
MIN_VRE_SHARE_2040 = NaN;
MIN_VRE_SHARE_2050 = NaN;

% 五模型中的第二高值
MAX_VRE_SHARE_2030 = 0.0890;
MAX_VRE_SHARE_2040 = 0.1173;
MAX_VRE_SHARE_2050 = 0.1420;

%% 5. 既有装机约束的允许违反区域数量（成本最小化模式）
% 旧版 gamultiobj 通过 ConstraintTolerance 宽松容忍（2040=4, 2030=8），
% 但增加 VRE 渗透率上下界后不能用宽松容差，否则 VRE 约束也会被错误容忍。
% 改为 ConstraintTolerance=1e-6 + 显式写入约束：
%   c_existing_wind = unmet_wind_region_count - ALLOWED_UNMET_WIND_REGIONS
% 数据来源：与旧版 ConstraintTolerance 等价
ALLOWED_UNMET_WIND_REGIONS_2050 = 0;   % 2050 完全不允许违反
ALLOWED_UNMET_WIND_REGIONS_2040 = 4;   % 2040 允许 4 个风电区域不满足
ALLOWED_UNMET_WIND_REGIONS_2030 = 8;   % 2030 允许 8 个风电区域不满足

%% 6. GA 收敛参数
MAX_STALL_GENERATIONS = 25;  % 连续 N 代最优解无改善则提前终止

%% 7. GA 随机种子
% 默认固定为 42，便于复现实验。
% 如需调整，只修改本文件中的 GA_SEED。
GA_SEED = 42;

%% 8. 并行池 worker 数量
% GA 默认使用 64 个 worker，但高负载服务器可能无法启动。
% 可通过环境变量覆盖：export PARPOOL_NUM_WORKERS=32
env_parpool = getenv('PARPOOL_NUM_WORKERS');
if ~isempty(env_parpool) && str2double(env_parpool) > 0
    PARPOOL_NUM_WORKERS = str2double(env_parpool);
else
    PARPOOL_NUM_WORKERS = 64;
end

%% 9. 结果保存子目录
% 流水线脚本通过环境变量 RESULTS_SUBDIR 传入统一的时间戳子目录名。
% 若未设置（如单独运行优化脚本），则自动生成。
env_res = getenv('RESULTS_SUBDIR');
if ~isempty(env_res)
    RESULTS_SUBDIR = env_res;
else
    RESULTS_SUBDIR = ['results_' datestr(now, 'yyyymmdd_HHMM')];
end
