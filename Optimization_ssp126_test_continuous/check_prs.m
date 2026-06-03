prs = h5read('Optimization_SC_2050_Res.h5', '/prs');
res_scale = h5read('Optimization_SC_2050_Res.h5', '/res_scale');
fprintf('prs size: %d x %d\n', size(prs,1), size(prs,2));
fprintf('res_scale size: %d x %d\n', size(res_scale,1), size(res_scale,2));
fprintf('prs(1,:) = %.4f %.4f %.4f\n', prs(1,1), prs(1,2), prs(1,3));
fprintf('prs(end,:) = %.4f %.4f %.4f\n', prs(end,1), prs(end,2), prs(end,3));
