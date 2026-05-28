function data = geotiffread(filename)
% GEOTIFFREAD — GeoTIFF 读取（Mapping Toolbox 替代实现）
%
% 无需 Mapping Toolbox 即可读取单波段 TIFF 文件。
% 优先加载预转换的 .mat 文件（由 convert_tif_to_mat.py 生成），
% 若 .mat 不存在则回退至 readtif_custom 直接读取 .tif。
%
% 输入：filename - TIFF 文件路径
% 输出：data - 二维栅格数据矩阵

    [p, f, ext] = fileparts(filename);
    if isempty(ext), ext = '.tif'; end
    if isempty(p)
        mat_file = [f '.mat'];
    else
        mat_file = fullfile(p, [f '.mat']);
    end
    % 优先从预转换的 .mat 文件加载（速度更快）
    if exist(mat_file, 'file')
        s = load(mat_file, 'data');
        data = s.data;
    else
        tif_file = [p filesep f ext];
        data = readtif_custom(tif_file);
    end
end
