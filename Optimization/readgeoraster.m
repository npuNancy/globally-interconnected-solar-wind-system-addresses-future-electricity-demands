function varargout = readgeoraster(filename)
% READGEORASTER  Drop-in replacement for Mapping Toolbox readgeoraster.
%   DATA = READGEORASTER(FILENAME)
%   [DATA, R] = READGEORASTER(FILENAME)
%
%   R is returned as an empty struct (the scripts in this project never
%   use the spatial-reference object, so this is safe).
%
%   Like geotiffread, this function first checks for a pre-converted
%   .mat file, then falls back to readtif_custom.
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
        R = struct();   % dummy spatial reference — not used by any script
        varargout = {data, R};
    else
        varargout = {data};
    end
end
