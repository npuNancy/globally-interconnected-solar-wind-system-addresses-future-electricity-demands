function cfg = continuous_config()
% continuous_config — 连续容量实验的统一参数
%
% 三个年份（2050/2040/2030）共享同一组阈值和优化参数。
% 可通过环境变量覆盖，便于 smoke test。

cfg.EPS_ACTIVE = 1e-6;
cfg.CONSTRAINT_TOL = 1e-8;

% 正式运行参数
cfg.POPULATION_SIZE = 1000;
cfg.MAX_GENERATIONS = 200;

% 支持环境变量覆盖，便于 smoke test
tmp = str2double(getenv('CONTINUOUS_POPULATION_SIZE'));
if ~isnan(tmp) && tmp > 0
    cfg.POPULATION_SIZE = tmp;
end

tmp = str2double(getenv('CONTINUOUS_MAX_GENERATIONS'));
if ~isnan(tmp) && tmp > 0
    cfg.MAX_GENERATIONS = tmp;
end
end
