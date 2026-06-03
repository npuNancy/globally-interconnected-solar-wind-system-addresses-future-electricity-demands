function data = readtif_custom(filepath)
% READTIF_CUSTOM — 纯 MATLAB GeoTIFF 读取器（无工具箱依赖）
%
% 用法：DATA = READTIF_CUSTOM(FILEPATH)
%   读取单波段 TIFF 文件，返回二维栅格数据矩阵（行×列）。
%
% 支持：
%   - 无压缩和 PackBits 压缩的 TIFF
%   - 分块（tiled）和条带（stripped）存储方式
%   - 数据类型：uint8, uint16, uint32, int16, int32, float32, float64
%   - 小端和大端字节序
%
% 不支持（本项目不需要）：
%   - LZW / Deflate / JPEG / SGILog 压缩
%   - 多波段栅格
%   - BigTIFF（>4 GB）
%
% 示例：
%   landmask = readtif_custom('Global_LandMask.tif');

    [fid, msg] = fopen(filepath, 'r', 'ieee-le');
    if fid == -1
        error('readtif_custom:fileOpen', '无法打开文件：%s', msg);
    end
    cleanup = onCleanup(@() fclose(fid));

    %--- 读取 TIFF 文件头（8字节） ---
    bo_raw = fread(fid, 2, 'uint8=>uint8');
    if isequal(bo_raw', [73 73])          % 'II' = 小端
        le = true;
    elseif isequal(bo_raw', [77 77])     % 'MM' = 大端
        le = false;
    else
        error('readtif_custom:format', '不是有效的 TIFF 文件（字节序错误）');
    end

    magic = ru16(fid, le);
    if magic ~= 42
        error('readtif_custom:format', '非标准 TIFF（magic=%d）', magic);
    end

    ifd_offset = ru32(fid, le);

    %--- 解析 IFD 目录条目 ---
    fseek(fid, ifd_offset, 'bof');
    num_entries = ru16(fid, le);

    % TIFF 标签常量
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
        vraw = fread(fid, 4, 'uint8=>uint8');  % 4字节值/偏移字段

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

    % 校验必要字段
    if img_w==0 || img_h==0
        error('readtif_custom:format', '缺少 ImageWidth/ImageLength 标签');
    end

    %--- 计算分块/条带几何 ---
    if ~is_tiled
        tw = img_w;
        if rows_per_strip == 0, rows_per_strip = img_h; end
        th = rows_per_strip;
    end

    tiles_across  = ceil(img_w / tw);  % 水平方向块数
    tiles_down    = ceil(img_h / th);  % 垂直方向块数
    n_tiles       = tiles_across * tiles_down;

    %--- 读取偏移和字节数数组 ---
    offsets     = read_tag_array(fid, off_val, off_dt, off_cnt, n_tiles, le);
    byte_counts = read_tag_array(fid, cnt_val, cnt_dt, cnt_cnt, n_tiles, le);

    %--- 确定 MATLAB 读取精度 ---
    switch bps
        case 8,  read_prec = 'uint8';
        case 16, read_prec = 'uint16';
        case 32
            if sf == 3, read_prec = 'single'; else, read_prec = 'uint32'; end
        case 64, read_prec = 'double';
        otherwise
            error('readtif_custom:bps', '不支持的位深度：%d', bps);
    end

    %--- 逐块读取并拼装图像 ---
    img = zeros(img_h, img_w, read_prec);

    for t = 1:n_tiles
        if byte_counts(t) == 0, continue; end
        fseek(fid, offsets(t), 'bof');
        raw_bytes = fread(fid, byte_counts(t), 'uint8=>uint8');

        % 解压
        switch comp
            case 1      % 无压缩
                dec = raw_bytes;
            case 32773  % PackBits 压缩
                dec = packbits_decode(raw_bytes);
            otherwise
                error('readtif_custom:compress', ...
                      '不支持的压缩类型：%d', comp);
        end

        % 将原始字节转为类型化数值并重塑为 (行×列)
        tile_vals = typecast(dec(:)', read_prec);
        tile_data = reshape(tile_vals, tw, th).';   % 转置：行主序→MATLAB列主序

        % 计算当前块在图像中的位置
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

%% ======================== 辅助函数 =============================

function v = val_scalar(vraw, dt, le)
% 从4字节 IFD 值字段中提取标量
    if dt == 3  % SHORT（2字节）
        if le, v = typecast(vraw(1:2), 'uint16');
        else,  v = typecast(vraw(1:-1:2), 'uint16'); end
    elseif dt == 4  % LONG（4字节）
        if le, v = typecast(vraw, 'uint32');
        else,  v = typecast(vraw(end:-1:1), 'uint32'); end
    else
        if le, v = typecast(vraw, 'uint32');
        else,  v = typecast(vraw(end:-1:1), 'uint32'); end
    end
    v = double(v);
end

function arr = read_tag_array(fid, vraw, dt, cnt, n_expected, le)
% 读取可能内联（≤4字节）或偏移存储的值数组
    elem_size = 4;
    if dt == 3, elem_size = 2; end

    if cnt * elem_size <= 4
        % 值直接内嵌在4字节 IFD 字段中
        if dt == 3
            arr = double(typecast(vraw(1:cnt*2), 'uint16'));
        else
            arr = double(typecast(vraw(1:cnt*4), 'uint32'));
        end
    else
        % vraw 包含指向实际数组的文件偏移
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
% PACKBITS_DECODE — 解压 PackBits（TIFF 压缩类型 32773）
%
%   IN  — uint8 压缩字节流
%   OUT — uint8 解压后的字节流
%
%   TIFF PackBits 算法：
%     n ∈ [0, 127]    → 原样复制后续 (n+1) 字节
%     n ∈ [-127, -1]  → 将后续1字节重复 (1-n) 次
%     n == -128       → 无操作

    in = in(:)';
    n_in = length(in);
    out = zeros(1, n_in * 128, 'uint8');  % 预分配（最坏情况128倍膨胀）
    ip = 1;
    op = 1;
    while ip <= n_in
        n = in(ip);
        ip = ip + 1;
        if n <= 127
            % 原样复制 (n+1) 字节
            n_lit = double(n) + 1;
            out(op:op+n_lit-1) = in(ip:ip+n_lit-1);
            ip = ip + n_lit;
            op = op + n_lit;
        elseif n > 128
            % 重复后续字节 (257-n) 次
            n_rep = 257 - double(n);
            if ip > n_in, break; end
            run_val = in(ip);
            ip = ip + 1;
            out(op:op+n_rep-1) = run_val;
            op = op + n_rep;
        end
        % n == 128 为无操作
    end
    out = out(1:op-1);
end

function v = ru16(fid, le)
% 按字节序读取 uint16
    raw = fread(fid, 2, 'uint8=>uint8');
    if le, v = typecast(raw, 'uint16');
    else,  v = typecast(raw(end:-1:1), 'uint16'); end
end

function v = ru32(fid, le)
% 按字节序读取 uint32
    raw = fread(fid, 4, 'uint8=>uint8');
    if le, v = typecast(raw, 'uint32');
    else,  v = typecast(raw(end:-1:1), 'uint32'); end
end
