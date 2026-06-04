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
