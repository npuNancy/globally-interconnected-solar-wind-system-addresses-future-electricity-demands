function metrics = evaluate_dispatch_and_cost_cached(scale, ins_cap, gens, loads, ...
    CGrid_Index, base_load_ratio, interconnection_mode, cost_cfg, nonlsol)
% EVALUATE_DISPATCH_AND_COST_CACHED — 带 persistent 缓存的调度评估
%
% 缓存最近一次 scale 及其 metrics，避免同一候选解在目标函数和非线性约束中
% 重复调用 8760 小时调度模拟。
%
% 用法与 evaluate_dispatch_and_cost 相同。

    persistent cached_scale cached_metrics has_cache
    if isempty(has_cache), has_cache = false; end

    need_eval = true;
    if has_cache && ~isempty(cached_scale) && ...
       numel(scale) == numel(cached_scale) && ...
       isequal(round(scale(:) * 1e10), round(cached_scale(:) * 1e10))
        need_eval = false;
    end

    if need_eval
        cached_scale = scale(:);
        cached_metrics = evaluate_dispatch_and_cost(ins_cap, gens, loads, ...
            CGrid_Index, scale, base_load_ratio, interconnection_mode, cost_cfg, nonlsol);
        has_cache = true;
    end

    metrics = cached_metrics;
end
