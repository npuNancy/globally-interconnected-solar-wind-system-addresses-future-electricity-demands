function validate_curtailment_config(cost_cfg, acceptance_margin)
% VALIDATE_CURTAILMENT_CONFIG — 校验弃电率配置完整性
%
% 输入：
%   cost_cfg           — 成本模型配置结构体
%   acceptance_margin  — 弃电率验收余量（标量）

    if cost_cfg.ENABLE_CURTAILMENT_CONSTRAINT
        if ~isfield(cost_cfg, 'MAX_CURTAILMENT') ...
                || isempty(cost_cfg.MAX_CURTAILMENT) ...
                || ~isscalar(cost_cfg.MAX_CURTAILMENT) ...
                || ~isfinite(cost_cfg.MAX_CURTAILMENT)
            error('Config:MissingMaxCurtailment', ...
                ['cost_cfg.MAX_CURTAILMENT 未设置。' ...
                 '请从 Optimization_ssp*/optimization_config.m 注入。']);
        end
    end

    if nargin >= 2
        if ~isscalar(acceptance_margin) ...
                || ~isfinite(acceptance_margin) ...
                || acceptance_margin < 0
            error('Config:InvalidCurtailmentAcceptanceMargin', ...
                'CURTAILMENT_ACCEPTANCE_MARGIN 必须为非负标量。');
        end
    end
end
