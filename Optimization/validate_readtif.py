#!/usr/bin/env python3
"""
validate_readtif.py
===================
Validate that readtif_custom.m produces identical results to rasterio.

Generates:
  - ref_tif_data.mat  : ground-truth arrays from rasterio
  - Prints per-file validation info and PackBits sanity check
"""
import os, struct, numpy as np
from scipy.io import savemat
import rasterio

DIR = os.path.dirname(os.path.abspath(__file__))

tifs = [
    'Global_Wind_Net_Area_Add_Egrid.tif',
    'Global_Wind_Fishnet_Area.tif',
    'Global_LandMask.tif',
    'Global_fishnet.tif',
    'Global_Solar_Net_Area_Add_Egrid.tif',
    'Global_Solar_Fishnet_Area.tif',
    'Global_Grid_Division.tif',
]

ref = {}
all_ok = True

for name in tifs:
    path = os.path.join(DIR, name)
    with rasterio.open(path) as src:
        arr = src.read(1)
    key = name.replace('.tif', '').replace('.', '_')
    ref[key] = arr

    # Also read raw bytes for PackBits validation
    with open(path, 'rb') as f:
        bo = f.read(2)
        _magic = struct.unpack('<H', f.read(2))[0]
        ifd_off = struct.unpack('<I', f.read(4))[0]
        f.seek(ifd_off)
        n_tags = struct.unpack('<H', f.read(2))[0]
        comp = None
        for _ in range(n_tags):
            tag = struct.unpack('<H', f.read(2))[0]
            dt  = struct.unpack('<H', f.read(2))[0]
            cnt = struct.unpack('<I', f.read(4))[0]
            raw = f.read(4)
            if tag == 259:
                comp = struct.unpack('<H', raw[:2])[0]

    comp_name = {1: 'None', 32773: 'PackBits'}.get(comp, f'Other({comp})')
    print(f'  {name:<50s}  shape={str(arr.shape):<12s}  dtype={str(arr.dtype):<10s}  '
          f'comp={comp_name:<10s}  min={arr.min():.4f}  max={arr.max():.4f}')

# Validate PackBits decompression in Python against rasterio output
print('\n--- PackBits decompression sanity check ---')

def packbits_decode_py(data):
    """Python equivalent of the MATLAB packbits_decode function."""
    out = bytearray()
    i = 0
    n = len(data)
    while i < n:
        hdr = data[i]; i += 1
        if hdr <= 127:
            cnt = hdr + 1
            out.extend(data[i:i+cnt])
            i += cnt
        elif hdr > 128:
            cnt = 257 - hdr
            out.extend([data[i]] * cnt)
            i += 1
        # hdr == 128 is no-op
    return bytes(out)

for name in tifs:
    path = os.path.join(DIR, name)
    with open(path, 'rb') as f:
        # Parse header: byte-order(2) + magic(2) + IFD-offset(4) = 8 bytes
        _bo = f.read(2)
        _magic = struct.unpack('<H', f.read(2))[0]
        ifd_off = struct.unpack('<I', f.read(4))[0]
        f.seek(ifd_off)
        n_tags = struct.unpack('<H', f.read(2))[0]

        tags = {}
        for _ in range(n_tags):
            tag, dt, cnt = struct.unpack('<HHI', f.read(8))
            vraw = f.read(4)
            if dt == 3 and cnt == 1:
                val = struct.unpack('<H', vraw[:2])[0]
            elif dt == 4 and cnt == 1:
                val = struct.unpack('<I', vraw)[0]
            else:
                val = struct.unpack('<I', vraw)[0]
            tags[tag] = (dt, cnt, val, vraw)

        w = tags[256][2]; h = tags[257][2]; bps = tags[258][2]
        comp = tags.get(259, (0,0,1,(0,0,0,0)))[2]
        sf = tags.get(339, (0,0,1,(1,0,0,0)))[2]
        tw = tags.get(322, (0,0,0,(0,0,0,0)))[2]
        th = tags.get(323, (0,0,0,(0,0,0,0)))[2]

        if tw == 0:
            print(f'  SKIP {name} (not tiled or strip-based)')
            continue

        ta = (w + tw - 1) // tw
        td = (h + th - 1) // th
        nt = ta * td

        # Read tile offsets and byte counts
        def read_arr(tag_id, n_exp):
            dt_t, cnt_t, val_t, vraw_t = tags[tag_id]
            if cnt_t <= 2 and dt_t == 3:
                arr = list(struct.unpack(f'<{cnt_t}H', vraw_t[:cnt_t*2]))
            elif cnt_t == 1 and dt_t == 4:
                arr = [val_t]
            else:
                f.seek(val_t)
                if dt_t == 3:
                    arr = list(struct.unpack(f'<{n_exp}H', f.read(n_exp*2)))
                else:
                    arr = list(struct.unpack(f'<{n_exp}I', f.read(n_exp*4)))
            return arr

        offsets = read_arr(324, nt)
        byte_counts = read_arr(325, nt)

        # Read all tiles, decompress, assemble
        bps_bytes = bps // 8
        dt_map = {1: 'u1', 2: 'i1', 3: 'f4', 4: 'f8',
                  8: 'u1', 9: 'i1', 11: 'f4', 12: 'f8'}
        np_dt = f'<f8' if bps == 64 else (f'<u4' if bps == 32 and sf != 3 else f'<u1')

        img = np.zeros((h, w))
        for ti in range(nt):
            f.seek(offsets[ti])
            raw = f.read(byte_counts[ti])
            if comp == 32773:
                dec = packbits_decode_py(raw)
            else:
                dec = raw

            tile_row = ti // ta
            tile_col = ti % ta

            if bps == 64:
                vals = np.frombuffer(dec, dtype='<f8')
            elif bps == 32:
                vals = np.frombuffer(dec, dtype='<u4')
            else:
                vals = np.frombuffer(dec, dtype='<u1')

            tile_data = vals.reshape(th, tw)
            r1 = tile_row * th
            c1 = tile_col * tw
            r2 = min(r1 + th, h)
            c2 = min(c1 + tw, w)
            img[r1:r2, c1:c2] = tile_data[:r2-r1, :c2-c1]

        # Compare against rasterio
        with rasterio.open(path) as src:
            ref_arr = src.read(1)

        if bps in (8, 32) and sf != 3:
            match = np.array_equal(img.astype(ref_arr.dtype), ref_arr)
        else:
            match = np.allclose(img, ref_arr, rtol=1e-12, atol=0)

        status = 'OK' if match else 'MISMATCH!'
        if not match:
            all_ok = False
        print(f'  {name:<50s}  PackBits decode: {status}')

# Save reference data for MATLAB validation
ref_path = os.path.join(DIR, 'ref_tif_data.mat')
savemat(ref_path, ref, do_compression=True)
print(f'\nReference data saved to: {ref_path}')
print('Run test_readtif.m in MATLAB to validate readtif_custom.m')
print(f'\nOverall: {"ALL PASSED" if all_ok else "SOME FAILED"}')
