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
