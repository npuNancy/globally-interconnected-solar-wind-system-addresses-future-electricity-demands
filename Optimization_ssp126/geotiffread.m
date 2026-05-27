function data = geotiffread(filename)
% GEOTIFFREAD  Drop-in replacement for Mapping Toolbox geotiffread.
%   DATA = GEOTIFFREAD(FILENAME) reads a single-band TIFF file using
%   readtif_custom (pure MATLAB, no toolbox needed) and returns the data
%   matrix.  Spatial-reference output (second return value) is not
%   supported — use readgeoraster wrapper if you need it.
%
%   The function first looks for a pre-converted .mat file (created by
%   convert_tif_to_mat.py) which is faster.  If the .mat file is absent,
%   it falls back to reading the .tif directly.
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
end
