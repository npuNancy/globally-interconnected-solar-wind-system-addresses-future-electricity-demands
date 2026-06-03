#!/usr/bin/env python3
"""compare_binary_vs_continuous.py

Compare the original binary SSP1-2.6 optimization results with the new
continuous-capacity optimization results.

Usage:
    python compare_binary_vs_continuous.py

Outputs:
    Optimization_ssp126_test_continuous/results/binary_vs_continuous_comparison.csv
    Optimization_ssp126_test_continuous/results/binary_vs_continuous_comparison.md
"""

import csv
import warnings
from pathlib import Path

import numpy as np
import scipy.io as sio

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
PROJECT_ROOT = Path(__file__).resolve().parent

BINARY_DIR = PROJECT_ROOT / "Optimization_ssp126"
CONTINUOUS_DIR = PROJECT_ROOT / "Optimization_ssp126_test_continuous"

# Installation densities (MW/km^2)
SOLAR_DENSITY = 74.0          # solar PV
WIND_ONSHORE_DENSITY = 2.7    # onshore wind
WIND_OFFSHORE_DENSITY = 4.6   # offshore wind

EPS_ACTIVE = 1e-6             # threshold for "active" grid cell

# File-name patterns per year: (sel_mat_prefix, year)
YEAR_CONFIG = {
    2050: "Opt_SC_2050",
    2040: "Opt_SC_2040",
    2030: "Opt_SA_2030",
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _find_sel_mat(base_dir: Path, prefix: str) -> Path | None:
    """Locate a Sel.mat file under *base_dir*/results (search subdirs too)."""
    results_dir = base_dir / "results"
    if not results_dir.is_dir():
        return None

    target_name = f"{prefix}_Sel.mat"

    # Check results/ itself first
    candidate = results_dir / target_name
    if candidate.is_file():
        return candidate

    # Check immediate subdirectories (e.g. results_1000_200)
    for sub in sorted(results_dir.iterdir()):
        if sub.is_dir():
            candidate = sub / target_name
            if candidate.is_file():
                return candidate

    return None


def _load_grid_data():
    """Load static grid data used to build capacity grids.

    Returns
    -------
    solar_area_km2 : ndarray (180, 360)  – grid-cell area for solar (km^2)
    solar_avail_frac : ndarray (180, 360) – available-area fraction for solar
    wind_area_km2 : ndarray (180, 360)   – available wind area (km^2)
    wind_avail_frac : ndarray (180, 360) – available-area fraction for wind
    ocean_mask : ndarray (180, 360) bool – True = ocean / offshore
    """
    data_dir = BINARY_DIR  # same grid structure for both

    # Grid-cell areas (km^2)
    solar_area_km2 = sio.loadmat(data_dir / "Global_Solar_Fishnet_Area.mat")["data"].astype(np.float64)
    wind_area_km2 = sio.loadmat(data_dir / "Global_Wind_Fishnet_Area.mat")["data"].astype(np.float64)

    # Available-area fractions (stored as percentages in .mat → divide by 100)
    solar_avail_frac = sio.loadmat(data_dir / "Global_Solar_Net_Area_Add_Egrid.mat")["data"].astype(np.float64) / 100.0
    wind_avail_frac = sio.loadmat(data_dir / "Global_Wind_Net_Area_Add_Egrid.mat")["data"].astype(np.float64) / 100.0

    # Land/ocean mask: values > 100 in the .mat → ocean
    landmask_raw = sio.loadmat(data_dir / "Global_LandMask.mat")["data"]
    ocean_mask = landmask_raw > 100  # True = offshore

    return solar_area_km2, solar_avail_frac, wind_area_km2, wind_avail_frac, ocean_mask


def _build_capacity_grids():
    """Build per-cell maximum installable capacity grids (GW).

    Returns
    -------
    solar_cap_grid : ndarray (180, 360) – solar capacity in GW
    wind_cap_grid  : ndarray (180, 360) – wind  capacity in GW
    """
    solar_area_km2, solar_avail_frac, wind_area_km2, wind_avail_frac, ocean_mask = _load_grid_data()

    # Solar: density * available_fraction * grid_area / 1000 → GW
    solar_cap_grid = SOLAR_DENSITY * solar_avail_frac * solar_area_km2 / 1000.0

    # Wind: onshore vs offshore density
    wind_density = np.where(ocean_mask, WIND_OFFSHORE_DENSITY, WIND_ONSHORE_DENSITY)
    wind_cap_grid = wind_density * wind_avail_frac * wind_area_km2 / 1000.0

    return solar_cap_grid, wind_cap_grid


def _extract_fraction(sel_data: dict, key_frac: str, key_fallback: str) -> np.ndarray:
    """Return the development-fraction grid from a Sel.mat dict.

    Prefer *key_frac* (e.g. ``opt_solar_frac``) if present, otherwise fall
    back to *key_fallback* (e.g. ``opt_solar``).
    """
    if key_frac in sel_data:
        return np.asarray(sel_data[key_frac], dtype=np.float64)
    return np.asarray(sel_data[key_fallback], dtype=np.float64)


def _compute_metrics(frac: np.ndarray, cap_grid: np.ndarray):
    """Compute capacity and grid-count metrics.

    Parameters
    ----------
    frac : ndarray (180, 360) – development fraction (binary 0/1 or continuous)
    cap_grid : ndarray (180, 360) – max capacity per cell (GW)

    Returns
    -------
    dict with keys: actual_gw, n_active, n_partial, mean_frac
    """
    actual_cap = cap_grid * frac          # GW per cell
    total_gw = float(np.sum(actual_cap))

    active_mask = frac > EPS_ACTIVE
    n_active = int(np.sum(active_mask))

    partial_mask = (frac > EPS_ACTIVE) & (frac < 1.0 - EPS_ACTIVE)
    n_partial = int(np.sum(partial_mask))

    if n_active > 0:
        mean_frac = float(np.mean(frac[active_mask]))
    else:
        mean_frac = 0.0

    return {
        "actual_gw": total_gw,
        "n_active": n_active,
        "n_partial": n_partial,
        "mean_frac": mean_frac,
    }


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    solar_cap_grid, wind_cap_grid = _build_capacity_grids()

    # Collect rows for CSV / Markdown
    rows = []  # list of dicts

    for year in [2030, 2040, 2050]:
        prefix = YEAR_CONFIG[year]

        # --- binary ---
        bin_path = _find_sel_mat(BINARY_DIR, prefix)
        if bin_path is None:
            warnings.warn(f"[binary {year}] {prefix}_Sel.mat not found — skipping")
        else:
            sel = sio.loadmat(bin_path)
            solar_frac = _extract_fraction(sel, "opt_solar_frac", "opt_solar")
            wind_frac = _extract_fraction(sel, "opt_wind_frac", "opt_wind")

            sm = _compute_metrics(solar_frac, solar_cap_grid)
            wm = _compute_metrics(wind_frac, wind_cap_grid)

            rows.append({
                "year": year,
                "mode": "binary",
                "solar_gw": sm["actual_gw"],
                "wind_gw": wm["actual_gw"],
                "total_gw": sm["actual_gw"] + wm["actual_gw"],
                "n_solar_active": sm["n_active"],
                "n_wind_active": wm["n_active"],
                "n_solar_partial": sm["n_partial"],
                "n_wind_partial": wm["n_partial"],
                "solar_mean_frac": sm["mean_frac"],
                "wind_mean_frac": wm["mean_frac"],
            })
            print(f"[binary  {year}] solar={sm['actual_gw']:.1f} GW  wind={wm['actual_gw']:.1f} GW  "
                  f"total={sm['actual_gw'] + wm['actual_gw']:.1f} GW")

        # --- continuous ---
        cont_path = _find_sel_mat(CONTINUOUS_DIR, prefix)
        if cont_path is None:
            warnings.warn(f"[continuous {year}] {prefix}_Sel.mat not found — skipping")
        else:
            sel = sio.loadmat(cont_path)
            solar_frac = _extract_fraction(sel, "opt_solar_frac", "opt_solar")
            wind_frac = _extract_fraction(sel, "opt_wind_frac", "opt_wind")

            sm = _compute_metrics(solar_frac, solar_cap_grid)
            wm = _compute_metrics(wind_frac, wind_cap_grid)

            rows.append({
                "year": year,
                "mode": "continuous",
                "solar_gw": sm["actual_gw"],
                "wind_gw": wm["actual_gw"],
                "total_gw": sm["actual_gw"] + wm["actual_gw"],
                "n_solar_active": sm["n_active"],
                "n_wind_active": wm["n_active"],
                "n_solar_partial": sm["n_partial"],
                "n_wind_partial": wm["n_partial"],
                "solar_mean_frac": sm["mean_frac"],
                "wind_mean_frac": wm["mean_frac"],
            })
            print(f"[cont    {year}] solar={sm['actual_gw']:.1f} GW  wind={wm['actual_gw']:.1f} GW  "
                  f"total={sm['actual_gw'] + wm['actual_gw']:.1f} GW")

    if not rows:
        print("\nNo Sel.mat files found for any year. Nothing to compare.")
        return

    # ------------------------------------------------------------------
    # Write CSV
    # ------------------------------------------------------------------
    out_dir = CONTINUOUS_DIR / "results"
    out_dir.mkdir(parents=True, exist_ok=True)

    csv_path = out_dir / "binary_vs_continuous_comparison.csv"
    csv_fields = [
        "year", "mode",
        "solar_gw", "wind_gw", "total_gw",
        "n_solar_active", "n_wind_active",
        "n_solar_partial", "n_wind_partial",
        "solar_mean_frac", "wind_mean_frac",
    ]
    with open(csv_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=csv_fields)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)
    print(f"\nCSV written: {csv_path}")

    # ------------------------------------------------------------------
    # Build lookup for Markdown table
    # ------------------------------------------------------------------
    lookup: dict[tuple[int, str], dict] = {}
    for row in rows:
        lookup[(row["year"], row["mode"])] = row

    def _get(year: int, mode: str, key: str, fmt: str = ".1f") -> str:
        r = lookup.get((year, mode))
        if r is None:
            return "N/A"
        val = r[key]
        if isinstance(val, float):
            return f"{val:{fmt}}"
        return str(val)

    # ------------------------------------------------------------------
    # Write Markdown
    # ------------------------------------------------------------------
    md_path = out_dir / "binary_vs_continuous_comparison.md"

    metrics = [
        ("光伏实际装机容量 (GW)", "solar_gw", ".1f"),
        ("风电实际装机容量 (GW)", "wind_gw", ".1f"),
        ("总装机容量 (GW)", "total_gw", ".1f"),
        ("光伏有效开发格网数", "n_solar_active", "d"),
        ("风电有效开发格网数", "n_wind_active", "d"),
        ("光伏部分开发格网数", "n_solar_partial", "d"),
        ("风电部分开发格网数", "n_wind_partial", "d"),
        ("光伏平均开发比例", "solar_mean_frac", ".4f"),
        ("风电平均开发比例", "wind_mean_frac", ".4f"),
    ]

    header = "| 指标 | 2030 二值 | 2030 连续 | 2040 二值 | 2040 连续 | 2050 二值 | 2050 连续 |"
    sep    = "|---|---:|---:|---:|---:|---:|---:|"

    lines = [
        "# SSP1-2.6 二值 vs 连续容量优化结果对比",
        "",
        header,
        sep,
    ]
    for label, key, fmt in metrics:
        cols = []
        for year in [2030, 2040, 2050]:
            cols.append(_get(year, "binary", key, fmt))
            cols.append(_get(year, "continuous", key, fmt))
        lines.append(f"| {label} | {' | '.join(cols)} |")

    lines.append("")
    lines.append("> 注：\"有效开发\" = 开发比例 > 1e-6；\"部分开发\" = 1e-6 < 开发比例 < 1-1e-6")
    lines.append(">")
    lines.append("> 容量计算参数：光伏 74 MW/km²，陆上风电 2.7 MW/km²，海上风电 4.6 MW/km²")
    lines.append("")

    md_text = "\n".join(lines)
    md_path.write_text(md_text, encoding="utf-8")
    print(f"Markdown written: {md_path}")

    # Print the table to stdout as well
    print("\n" + md_text)


if __name__ == "__main__":
    main()
