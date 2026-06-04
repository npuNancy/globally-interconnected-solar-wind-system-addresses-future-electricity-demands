%% optimization_config.m — SSP2-4.5 优化配置参数
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
DEMAND_2050 = 51940;   % AR6 SSP2-4.5: 187.0 EJ/yr
DEMAND_2040 = 44521;   % AR6 SSP2-4.5: 160.3 EJ/yr
DEMAND_2030 = 37134;   % AR6 SSP2-4.5: 133.7 EJ/yr

%% 3. 基荷比例
BASE_LOAD_RATIO_2050 = 0.518;  % 51.8%
BASE_LOAD_RATIO_2040 = 0.639;  % 63.9%
BASE_LOAD_RATIO_2030 = 0.717;  % 71.7%
