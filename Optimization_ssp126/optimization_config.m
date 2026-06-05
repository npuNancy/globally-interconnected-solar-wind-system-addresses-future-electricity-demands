%% optimization_config.m — SSP1-2.6 优化配置参数
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
DEMAND_2050 = 54767;   % AR6 SSP1-2.6: 197.2 EJ/yr
DEMAND_2040 = 44860;   % AR6 SSP1-2.6: 161.5 EJ/yr
DEMAND_2030 = 34633;   % AR6 SSP1-2.6: 124.7 EJ/yr

%% 3. 基荷比例
BASE_LOAD_RATIO_2050 = 0.239;  % 23.9%
BASE_LOAD_RATIO_2040 = 0.375;  % 37.5%
BASE_LOAD_RATIO_2030 = 0.558;  % 55.8%

%% 4. Pareto preferred solution 筛选配置
% 弃电率上限统一为 15%
% SSP1-2.6：积极转型路径，使用 AR6 五模型均值作为风光渗透率下界、最大值作为上界
SCENARIO_NAME = 'SSP1-2.6';
SELECTION_MODE = 'bounded_transition';

MAX_CURTAILMENT = 0.15;

MIN_VRE_SHARE_2030 = 0.2635;
MIN_VRE_SHARE_2040 = 0.4308;
MIN_VRE_SHARE_2050 = 0.5544;

MAX_VRE_SHARE_2030 = 0.5789;
MAX_VRE_SHARE_2040 = 0.6823;
MAX_VRE_SHARE_2050 = 0.7111;

%% 5. 既有装机约束的允许违反区域数量（成本最小化模式）
% 旧版 gamultiobj 通过 ConstraintTolerance 宽松容忍（2040=4, 2030=8），
% 但增加 VRE 渗透率上下界后不能用宽松容差，否则 VRE 约束也会被错误容忍。
% 改为 ConstraintTolerance=1e-6 + 显式写入约束：
%   c_existing_wind = unmet_wind_region_count - ALLOWED_UNMET_WIND_REGIONS
% 数据来源：与旧版 ConstraintTolerance 等价
ALLOWED_UNMET_WIND_REGIONS_2050 = 0;   % 2050 完全不允许违反
ALLOWED_UNMET_WIND_REGIONS_2040 = 4;   % 2040 允许 4 个风电区域不满足
ALLOWED_UNMET_WIND_REGIONS_2030 = 8;   % 2030 允许 8 个风电区域不满足
