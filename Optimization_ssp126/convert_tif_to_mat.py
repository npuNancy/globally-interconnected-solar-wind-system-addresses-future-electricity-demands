"""
convert_tif_to_mat.py
=====================
Convert every .tif in the current directory (or a given directory) into a
matching .mat file that the wrapper geotiffread / readgeoraster functions
can load instantly.

Each output .mat contains a single variable called 'data' (the raster
matrix) and is saved with zlib compression.

Usage:
    /usr/local/anaconda3/bin/python3 convert_tif_to_mat.py            # current dir
    /usr/local/anaconda3/bin/python3 convert_tif_to_mat.py /path/to   # specific dir
"""
import sys
import os
import glob

try:
    import rasterio
except ImportError:
    sys.exit("ERROR: rasterio is required.  Install with:\n"
             "  pip install rasterio   (or conda install rasterio)")

from scipy.io import savemat
import numpy as np


def convert_tif(tif_path):
    """Read a single TIF and write <basename>.mat with variable 'data'."""
    base, _ = os.path.splitext(tif_path)
    mat_path = base + ".mat"

    with rasterio.open(tif_path) as src:
        arr = src.read(1)

    savemat(mat_path, {"data": arr}, do_compression=True)
    return mat_path, arr.shape, arr.dtype


def main():
    target_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    tifs = sorted(glob.glob(os.path.join(target_dir, "*.tif")))

    if not tifs:
        print(f"No .tif files found in: {os.path.abspath(target_dir)}")
        return

    print(f"Converting {len(tifs)} TIF file(s) in: {os.path.abspath(target_dir)}\n")
    for tif in tifs:
        mat_path, shape, dtype = convert_tif(tif)
        name = os.path.basename(tif)
        mat_size_kb = os.path.getsize(mat_path) / 1024
        print(f"  {name:<50s}  shape={shape!s:<16s}  dtype={dtype!s:<10s}  "
              f"→ {os.path.basename(mat_path)}  ({mat_size_kb:.0f} KB)")

    print("\nDone.  Wrapper geotiffread/readgeoraster will now use .mat files.")


if __name__ == "__main__":
    main()
