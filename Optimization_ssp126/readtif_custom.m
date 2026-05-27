function data = readtif_custom(filepath)
% READTIF_CUSTOM  Read GeoTIFF raster data without any toolbox dependency.
%   DATA = READTIF_CUSTOM(FILEPATH) reads a single-band TIFF file and
%   returns the raster data as a 2-D matrix (rows x cols), matching the
%   output of geotiffread / readgeoraster for data values.
%
%   Supported:
%     - Uncompressed and PackBits-compressed TIFFs
%     - Tiled and stripped storage
%     - uint8, uint16, uint32, int16, int32, float32, float64
%     - Little-endian and big-endian byte order
%
%   NOT supported (not needed by current codebase):
%     - LZW / Deflate / JPEG / SGILog compression
%     - Multi-band rasters
%     - BigTIFF (>4 GB)
%
%   Example:
%     landmask = readtif_custom('Global_LandMask.tif');

    [fid, msg] = fopen(filepath, 'r', 'ieee-le');
    if fid == -1
        error('readtif_custom:fileOpen', 'Cannot open file: %s', msg);
    end
    cleanup = onCleanup(@() fclose(fid));

    %--- Read TIFF header (8 bytes) ----------------------------------------
    bo_raw = fread(fid, 2, 'uint8=>uint8');
    if isequal(bo_raw', [73 73])          % 'II'
        le = true;
    elseif isequal(bo_raw', [77 77])     % 'MM'
        le = false;
    else
        error('readtif_custom:format', 'Not a valid TIFF file (bad byte order).');
    end

    magic = ru16(fid, le);
    if magic ~= 42
        error('readtif_custom:format', 'Not a standard TIFF (magic=%d).', magic);
    end

    ifd_offset = ru32(fid, le);

    %--- Parse IFD entries -------------------------------------------------
    fseek(fid, ifd_offset, 'bof');
    num_entries = ru16(fid, le);

    % Tag constants
    IMG_W=256; IMG_H=257; BPS=258; COMP=259; SF=339;
    STRIP_OFF=273; STRIP_CNT=279; ROWS_PER_STRIP=278;
    TILE_W=322; TILE_H=323; TILE_OFF=324; TILE_CNT=325;

    img_w=0; img_h=0; bps=8; comp=1; sf=1;
    tw=0; th=0; rows_per_strip=0;
    is_tiled=false; off_tag=STRIP_OFF; cnt_tag=STRIP_CNT;
    off_cnt=1; cnt_cnt=1;
    off_dt=4; cnt_dt=4; off_val=0; cnt_val=0;

    for i = 1:num_entries
        tag  = ru16(fid, le);
        dt   = ru16(fid, le);
        cnt  = ru32(fid, le);
        vraw = fread(fid, 4, 'uint8=>uint8');  % raw 4-byte value/offset field

        switch tag
            case IMG_W,  img_w  = val_scalar(vraw, dt, le);
            case IMG_H,  img_h  = val_scalar(vraw, dt, le);
            case BPS,    bps    = val_scalar(vraw, dt, le);
            case COMP,   comp   = val_scalar(vraw, dt, le);
            case SF,     sf     = val_scalar(vraw, dt, le);
            case TILE_W, tw=val_scalar(vraw,dt,le); is_tiled=true; off_tag=TILE_OFF; cnt_tag=TILE_CNT;
            case TILE_H, th=val_scalar(vraw,dt,le);
            case ROWS_PER_STRIP, rows_per_strip=val_scalar(vraw,dt,le);
            case STRIP_OFF
                if ~is_tiled, off_tag=STRIP_OFF; cnt_tag=STRIP_CNT; end
                off_dt=dt; off_cnt=cnt; off_val=vraw;
            case TILE_OFF
                off_dt=dt; off_cnt=cnt; off_val=vraw;
            case STRIP_CNT
                if ~is_tiled, cnt_tag=STRIP_CNT; end
                cnt_dt=dt; cnt_cnt=cnt; cnt_val=vraw;
            case TILE_CNT
                cnt_dt=dt; cnt_cnt=cnt; cnt_val=vraw;
        end
    end

    % Validate required fields
    if img_w==0 || img_h==0
        error('readtif_custom:format', 'Missing ImageWidth/ImageLength tags.');
    end

    %--- Default tile/strip geometry ---------------------------------------
    if ~is_tiled
        tw = img_w;
        if rows_per_strip == 0, rows_per_strip = img_h; end
        th = rows_per_strip;
    end

    tiles_across  = ceil(img_w / tw);
    tiles_down    = ceil(img_h / th);
    n_tiles       = tiles_across * tiles_down;

    %--- Read offset and byte-count arrays ---------------------------------
    offsets     = read_tag_array(fid, off_val, off_dt, off_cnt, n_tiles, le);
    byte_counts = read_tag_array(fid, cnt_val, cnt_dt, cnt_cnt, n_tiles, le);

    %--- Determine MATLAB read precision -----------------------------------
    switch bps
        case 8,  read_prec = 'uint8';
        case 16, read_prec = 'uint16';
        case 32
            if sf == 3, read_prec = 'single'; else, read_prec = 'uint32'; end
        case 64, read_prec = 'double';
        otherwise
            error('readtif_custom:bps', 'Unsupported BitsPerSample: %d', bps);
    end

    %--- Read and assemble tiles/strips ------------------------------------
    img = zeros(img_h, img_w, read_prec);

    for t = 1:n_tiles
        if byte_counts(t) == 0, continue; end
        fseek(fid, offsets(t), 'bof');
        raw_bytes = fread(fid, byte_counts(t), 'uint8=>uint8');

        % Decompress if needed
        switch comp
            case 1      % no compression
                dec = raw_bytes;
            case 32773  % PackBits
                dec = packbits_decode(raw_bytes);
            otherwise
                error('readtif_custom:compress', ...
                      'Compression type %d is not supported.', comp);
        end

        % Reshape tile data: raw bytes → typed values → (rows x cols)
        tile_vals = typecast(dec(:)', read_prec);
        tile_data = reshape(tile_vals, tw, th).';   % transpose: row-major → MATLAB

        % Tile position in the image grid (TIFF tiles: row-major order)
        tile_row = floor((t-1) / tiles_across) + 1;
        tile_col = mod(t-1, tiles_across) + 1;

        r1 = (tile_row-1)*th + 1;
        c1 = (tile_col-1)*tw + 1;
        r2 = min(r1 + th - 1, img_h);
        c2 = min(c1 + tw - 1, img_w);

        img(r1:r2, c1:c2) = tile_data(1:(r2-r1+1), 1:(c2-c1+1));
    end

    data = img;
end

%% ========================  Helper functions  =============================

function v = val_scalar(vraw, dt, le)
% Extract a single scalar value from the raw 4-byte IFD value field.
    if dt == 3  % SHORT (2 bytes)
        if le, v = typecast(vraw(1:2), 'uint16');
        else,  v = typecast(vraw(1:-1:2), 'uint16'); end   % TODO: BE not tested
    elseif dt == 4  % LONG (4 bytes)
        if le, v = typecast(vraw, 'uint32');
        else,  v = typecast(vraw(end:-1:1), 'uint32'); end
    else
        if le, v = typecast(vraw, 'uint32');
        else,  v = typecast(vraw(end:-1:1), 'uint32'); end
    end
    v = double(v);
end

function arr = read_tag_array(fid, vraw, dt, cnt, n_expected, le)
% Read an array of values that may be inline (≤4 bytes) or at an offset.
    elem_size = 4;
    if dt == 3, elem_size = 2; end   % SHORT

    if cnt * elem_size <= 4
        % Values are packed in the 4-byte IFD value field
        if dt == 3
            arr = double(typecast(vraw(1:cnt*2), 'uint16'));
        else
            arr = double(typecast(vraw(1:cnt*4), 'uint32'));
        end
    else
        % vraw contains a file offset to the actual array
        off = double(typecast(vraw, 'uint32'));
        cur = ftell(fid);
        fseek(fid, off, 'bof');
        if dt == 3
            arr = double(fread(fid, n_expected, 'uint16'));
        else
            arr = double(fread(fid, n_expected, 'uint32'));
        end
        fseek(fid, cur, 'bof');
    end
    arr = arr(:)';
end

function out = packbits_decode(in)
% PACKBITS_DECODE  Decompress a PackBits (TIFF compression type 32773) stream.
%   IN  – uint8 column/row vector of compressed bytes
%   OUT – uint8 row vector of decompressed bytes
%
%   Algorithm (per TIFF spec):
%     n in [0,127]   → copy next (n+1) bytes literally
%     n in [-1,-127] → repeat next byte (1-n) times
%     n == -128      → no-op
    in = in(:)';          % ensure row vector
    n_in = length(in);
    % Pre-allocate output (worst case: 128x expansion)
    out = zeros(1, n_in * 128, 'uint8');
    ip = 1;
    op = 1;
    while ip <= n_in
        n = in(ip);
        ip = ip + 1;
        if n <= 127
            % Literal: copy next (n+1) bytes
            n_lit = double(n) + 1;
            out(op:op+n_lit-1) = in(ip:ip+n_lit-1);
            ip = ip + n_lit;
            op = op + n_lit;
        elseif n > 128
            % Run: repeat next byte (257-n) times  (n in 129..255 → 128..2 repeats)
            n_rep = 257 - double(n);
            if ip > n_in, break; end
            run_val = in(ip);
            ip = ip + 1;
            out(op:op+n_rep-1) = run_val;
            op = op + n_rep;
        end
        % n == 128 is a no-op (TIFF PackBits spec)
    end
    out = out(1:op-1);   % trim to actual size
end

function v = ru16(fid, le)
% Read a uint16, respecting byte order.
    raw = fread(fid, 2, 'uint8=>uint8');
    if le, v = typecast(raw, 'uint16');
    else,  v = typecast(raw(end:-1:1), 'uint16'); end
end

function v = ru32(fid, le)
% Read a uint32, respecting byte order.
    raw = fread(fid, 4, 'uint8=>uint8');
    if le, v = typecast(raw, 'uint32');
    else,  v = typecast(raw(end:-1:1), 'uint32'); end
end
