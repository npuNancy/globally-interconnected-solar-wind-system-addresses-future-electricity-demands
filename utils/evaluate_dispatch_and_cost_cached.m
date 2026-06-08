function [metrics, detail] = evaluate_dispatch_and_cost_cached(scale, ins_cap, gens, loads, ...
    CGrid_Index, base_load_ratio, interconnection_mode, cost_cfg, nonlsol)
% EVALUATE_DISPATCH_AND_COST_CACHED — 带 persistent 缓存的调度评估
%
% 缓存最近一次调用参数及其 metrics，避免同一候选解在目标函数和非线性约束中
% 重复调用 8760 小时调度模拟。
%
% 缓存键包含：scale、base_load_ratio、interconnection_mode、nonlsol，
% 避免同一 MATLAB 会话切换年份或情景时误用旧缓存。
%
% 用法与 evaluate_dispatch_and_cost 相同。
% 注意：缓存仅缓存 metrics，不缓存 detail（detail 按需计算）。

    persistent cached_scale cached_blr cached_mode cached_nonlsol cached_metrics has_cache
    if isempty(has_cache), has_cache = false; end

    want_detail = nargout >= 2;

    need_eval = true;
    if has_cache && ~isempty(cached_scale) && ...
       numel(scale) == numel(cached_scale) && ...
       isequal(round(scale(:) * 1e10), round(cached_scale(:) * 1e10)) && ...
       isequal(base_load_ratio, cached_blr) && ...
       strcmp(interconnection_mode, cached_mode) && ...
       isequal(nonlsol, cached_nonlsol)
        need_eval = false;
    end

    if need_eval
        cached_scale = scale(:);
        cached_blr   = base_load_ratio;
        cached_mode  = interconnection_mode;
        cached_nonlsol = nonlsol;
        if want_detail
            [cached_metrics, ~] = evaluate_dispatch_and_cost(ins_cap, gens, loads, ...
                CGrid_Index, scale, base_load_ratio, interconnection_mode, cost_cfg, nonlsol);
        else
            cached_metrics = evaluate_dispatch_and_cost(ins_cap, gens, loads, ...
                CGrid_Index, scale, base_load_ratio, interconnection_mode, cost_cfg, nonlsol);
        end
        has_cache = true;
    end

    metrics = cached_metrics;

    % detail 不缓存，需要时重新计算
    if want_detail
        [~, detail] = evaluate_dispatch_and_cost(ins_cap, gens, loads, ...
            CGrid_Index, scale, base_load_ratio, interconnection_mode, cost_cfg, nonlsol);
    end
end
