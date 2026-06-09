function print_constraint_diagnostics( ...
    constraint_names, c_strict, ceq, strict_tolerance, ...
    curtailment_rate, max_curtailment, curtailment_acceptance_margin)
% PRINT_CONSTRAINT_DIAGNOSTICS — 逐项打印约束值与弃电率验收信息
%
% 输入：
%   constraint_names              — 约束名称 cell 数组
%   c_strict                      — 严格不等式约束向量
%   ceq                           — 等式约束向量
%   strict_tolerance              — 严格容差
%   curtailment_rate              — 实际弃电率
%   max_curtailment               — 名义弃电率上限
%   curtailment_acceptance_margin — 验收余量

    fprintf('\n=== 最终约束逐项诊断 ===\n\n');

    for i = 1:length(c_strict)
        fprintf('[%d] %s\n', i, constraint_names{i});
        fprintf('    中文名称     = %s\n', ...
            get_constraint_name_zh(constraint_names{i}));
        fprintf('    strict_value = %.8e\n', c_strict(i));
        fprintf('    strict_pass  = %s\n', ...
            mat2str(c_strict(i) <= strict_tolerance));
    end

    if ~isempty(ceq)
        for i = 1:length(ceq)
            fprintf('[eq-%d] equality_constraint_%d\n', i, i);
            fprintf('    中文名称       = 等式约束 %d\n', i);
            fprintf('    equality_value = %.8e\n', ceq(i));
            fprintf('    equality_pass  = %s\n', ...
                mat2str(abs(ceq(i)) <= strict_tolerance));
        end
    end

    fprintf('\n=== 弃电率最终验收 ===\n\n');

    fprintf('actual_curtailment_rate\n');
    fprintf('  中文名称                      = 实际弃电率\n');
    fprintf('  value                         = %.6f\n', ...
        curtailment_rate);

    fprintf('\nconfigured_max_curtailment\n');
    fprintf('  中文名称                      = 配置中的名义弃电率上限\n');
    fprintf('  value                         = %.6f\n', ...
        max_curtailment);

    fprintf('\ncurtailment_acceptance_margin\n');
    fprintf('  中文名称                      = 最终验收允许的弃电率余量\n');
    fprintf('  value                         = %.6f\n', ...
        curtailment_acceptance_margin);

    fprintf('\nfinal_acceptance_upper_bound\n');
    fprintf('  中文名称                      = 最终验收弃电率上限\n');
    fprintf('  value                         = %.6f\n', ...
        max_curtailment + curtailment_acceptance_margin);

    fprintf('\nfinal_acceptance_pass\n');
    fprintf('  中文名称                      = 是否通过最终弃电率验收\n');
    fprintf('  value                         = %s\n', ...
        mat2str(curtailment_rate <= ...
            max_curtailment + curtailment_acceptance_margin + 1e-10));

end


function zh_name = get_constraint_name_zh(en_name)

    switch en_name
        case 'existing_solar_unmet_region_count'
            zh_name = '既有光伏装机未满足区域数量';

        case 'existing_wind_unmet_region_count_minus_allowance'
            zh_name = '既有风电装机未满足区域数量减允许违反区域数';

        case 'vre_lower_bound'
            zh_name = 'VRE 渗透率下界约束';

        case 'vre_upper_bound'
            zh_name = 'VRE 渗透率上界约束';

        case 'curtailment_upper_bound_strict'
            zh_name = '弃电率名义上限约束';

        otherwise
            zh_name = '未定义中文名称';
    end
end
