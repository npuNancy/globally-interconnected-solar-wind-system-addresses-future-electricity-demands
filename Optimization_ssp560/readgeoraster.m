function varargout = readgeoraster(filename)
% READGEORASTER — 地理栅格读取（Mapping Toolbox 替代实现）
%
% 用法：
%   DATA = READGEORASTER(FILENAME)
%   [DATA, R] = READGEORASTER(FILENAME)
%
% R 返回为空结构体（本项目的脚本不使用空间参考对象）。
% 内部逻辑与 geotiffread 相同：优先加载 .mat，回退至 readtif_custom。

    [p, f, ext] = fileparts(filename);
    if isempty(ext), ext = '.tif'; end
    if isempty(p)
        mat_file = [f '.mat'];
    else
        mat_file = fullfile(p, [f '.mat']);
    end
    if exist(mat_file, 'file')
        s = load(mat_file, 'data');
        data = s.data;
    else
        tif_file = [p filesep f ext];
        data = readtif_custom(tif_file);
    end
    if nargout >= 2
        R = struct();   % 空空间参考——本项目不使用
        varargout = {data, R};
    else
        varargout = {data};
    end
end
