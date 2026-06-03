#!/usr/bin/env python3
"""
validate_continuous_results.py — Validate continuous capacity optimization results.

Checks performed:
  A. File completeness (required .h5 and .mat files exist)
  B. Fraction range (opt_solar / opt_wind values in [0, 1])
  C. Cross-year monotonicity (2030 <= 2040 <= 2050 element-wise)
  D. Capacity consistency (opt_solar_cap_twp ≈ opt_solar × max_capacity)
  E. H5-to-Sel.mat mapping (decision vector fractions match Sel.mat grids)
  F. Existing capacity constraint (actual capacity >= current installed)
  G. Markdown report generation

Usage:
    python validate_continuous_results.py \\
        --opt-dir Optimization_ssp126_test_continuous \\
        --binary-opt-dir Optimization_ssp126
"""

import argparse
import os
import sys
import numpy as np
import scipy.io as sio
import h5py
from datetime import datetime

# ── Constants ────────────────────────────────────────────────────────────
TOL = 1e-8
RTOL = 1e-4
EPS_ACTIVE = 1e-6

# Solar/wind installation densities
SOLAR_DENSITY_MW_KM2 = 74.0     # MW/km²
WIND_ONSHORE_DENSITY_MW_KM2 = 2.7
WIND_OFFSHORE_DENSITY_MW_KM2 = 4.6
LANDMASK_THRESHOLD = 100         # >100 = onshore

# Required result files per year
YEAR_FILES = {
    2050: {"h5": "Optimization_SC_2050_Res.h5", "sel": "Opt_SC_2050_Sel.mat"},
    2040: {"h5": "Optimization_SC_2040_Res.h5", "sel": "Opt_SC_2040_Sel.mat"},
    2030: {"h5": "Optimization_SA_2030_Res.h5", "sel": "Opt_SA_2030_Sel.mat"},
}

# 20 region names (6 continents subdivided)
REGION_NAMES = [
    "NA-East",        "NA-West",       "SA-North",      "SA-South",
    "EU-West",        "EU-East",       "Africa-North",  "Africa-South",
    "ME-Central",     "China-East",    "China-West",    "S-Asia",
    "SE-Asia",        "Japan-Korea",   "Russia-West",   "Russia-East",
    "Oceania",        "C-America",     "C-Asia",        "Others",
]


# ══════════════════════════════════════════════════════════════════════════
#  Validation report collector
# ══════════════════════════════════════════════════════════════════════════

class ValidationReport:
    """Collects check results and generates summary + markdown report."""

    def __init__(self):
        self.checks = []           # list of {name, passed, details}
        self.year_data = {}        # per-year statistics
        self.region_data = {}      # per-region capacity
        self.mono_data = {}        # monotonicity results
        self.mapping_data = {}     # H5-MAT mapping results
        self.existing_data = {}    # existing capacity check results

    def add_check(self, name, passed, details=""):
        status = "PASS" if passed else "FAIL"
        self.checks.append({"name": name, "passed": passed, "details": details})
        print(f"  [{status}] {name}" + (f" — {details}" if details else ""))

    @property
    def n_passed(self):
        return sum(1 for c in self.checks if c["passed"])

    @property
    def n_failed(self):
        return sum(1 for c in self.checks if not c["passed"])

    @property
    def all_passed(self):
        return all(c["passed"] for c in self.checks)

    def print_summary(self):
        print(f"\n{'═' * 70}")
        print(f"  Validation Summary")
        print(f"{'═' * 70}")
        for c in self.checks:
            icon = "✓" if c["passed"] else "✗"
            print(f"  {icon}  {c['name']}")
        print(f"\n  Total: {self.n_passed} passed, {self.n_failed} failed, "
              f"{len(self.checks)} total")
        if self.all_passed:
            print("  Result: ALL CHECKS PASSED")
        else:
            print("  Result: SOME CHECKS FAILED")
        print(f"{'═' * 70}")

    def write_markdown(self, path):
        """Generate the validation report markdown (Check G)."""
        lines = []
        lines.append("# Continuous Optimization Validation Report\n")
        lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")

        # ── Summary table ──
        lines.append("## Check Summary\n")
        lines.append("| Check | Result | Details |")
        lines.append("|-------|--------|---------|")
        for c in self.checks:
            icon = "PASS" if c["passed"] else "**FAIL**"
            lines.append(f"| {c['name']} | {icon} | {c['details']} |")
        lines.append("")

        # ── Per-year statistics ──
        lines.append("## Per-Year Statistics\n")
        lines.append("| Year | Solar (GW) | Wind (GW) | Total (GW) | "
                      "Active Solar | Active Wind | Partial Solar | Partial Wind | "
                      "Mean Solar Frac | Mean Wind Frac |")
        lines.append("|------|-----------|----------|-----------|"
                      "-------------|------------|--------------|-------------|"
                      "----------------|---------------|")
        for year in [2050, 2040, 2030]:
            d = self.year_data.get(year)
            if d is None:
                lines.append(f"| {year} | — | — | — | — | — | — | — | — | — |")
            else:
                lines.append(
                    f"| {year} "
                    f"| {d['solar_gw']:.1f} "
                    f"| {d['wind_gw']:.1f} "
                    f"| {d['total_gw']:.1f} "
                    f"| {d['n_solar_active']} "
                    f"| {d['n_wind_active']} "
                    f"| {d['n_solar_partial']} "
                    f"| {d['n_wind_partial']} "
                    f"| {d['mean_solar_frac']:.6f} "
                    f"| {d['mean_wind_frac']:.6f} |"
                )
        lines.append("")

        # ── Per-region capacity ──
        lines.append("## Per-Region Capacity\n")
        lines.append("| Region | 2050 Solar (GW) | 2050 Wind (GW) | "
                      "2040 Solar (GW) | 2040 Wind (GW) | "
                      "2030 Solar (GW) | 2030 Wind (GW) |")
        lines.append("|--------|----------------|---------------|"
                      "----------------|---------------|"
                      "----------------|---------------|")
        for r in range(20):
            parts = [f"| {r+1:2d} {REGION_NAMES[r]}"]
            for year in [2050, 2040, 2030]:
                rd = self.region_data.get(year)
                if rd is not None:
                    parts.append(f" {rd['solar'][r]:.1f} | {rd['wind'][r]:.1f}")
                else:
                    parts.append(" — | —")
            lines.append(" | ".join(p.strip() for p in parts) + " |")
        lines.append("")

        # ── Monotonicity ──
        lines.append("## Cross-Year Monotonicity\n")
        for pair, md in self.mono_data.items():
            lines.append(f"### {pair}\n")
            lines.append(f"- Solar violations: {md['solar_violations']}")
            if md['solar_max_diff'] is not None:
                lines.append(f"- Solar max negative diff: {md['solar_max_diff']:.2e}")
            lines.append(f"- Wind violations: {md['wind_violations']}")
            if md['wind_max_diff'] is not None:
                lines.append(f"- Wind max negative diff: {md['wind_max_diff']:.2e}")
            lines.append("")

        # ── H5-MAT Mapping ──
        lines.append("## H5-to-Sel.mat Mapping\n")
        for year, md in self.mapping_data.items():
            lines.append(f"### {year}\n")
            lines.append(f"- Solution index (MATLAB 1-based): {md.get('sol_idx', 'N/A')}")
            lines.append(f"- H5 solutions count: {md.get('n_solutions', 'N/A')}")
            lines.append(f"- Active grids (Sel.mat): solar={md.get('mat_solar_active', 'N/A')}, "
                          f"wind={md.get('mat_wind_active', 'N/A')}")
            lines.append(f"- Active fractions (H5 vector): {md.get('h5_frac_active', 'N/A')}")
            mat_frac_sum = md.get('mat_frac_sum')
            if isinstance(mat_frac_sum, (int, float)):
                lines.append(f"- Fraction sum (Sel.mat): {mat_frac_sum:.4f}")
            h5_frac_sum = md.get('h5_frac_sum')
            if isinstance(h5_frac_sum, (int, float)):
                lines.append(f"- Fraction sum (H5 vector): {h5_frac_sum:.4f}")
            if md.get('sorted_max_diff') is not None:
                lines.append(f"- Sorted fraction max abs diff: {md['sorted_max_diff']:.2e}")
            lines.append("")

        # ── Existing capacity constraint ──
        lines.append("## Existing Capacity Constraint\n")
        lines.append("| Year | Solar Actual (GW) | Solar Existing (GW) | Solar OK? | "
                      "Wind Actual (GW) | Wind Existing (GW) | Wind OK? |")
        lines.append("|------|-------------------|--------------------|-----------|"
                      "-----------------|--------------------|----------|")
        for year in [2050, 2040, 2030]:
            ed = self.existing_data.get(year)
            if ed is None:
                lines.append(f"| {year} | — | — | — | — | — | — |")
            else:
                s_ok = "Yes" if ed['solar_ok'] else "**No**"
                w_ok = "Yes" if ed['wind_ok'] else "**No**"
                lines.append(
                    f"| {year} | {ed['solar_actual']:.1f} | {ed['solar_existing']:.1f} | {s_ok} "
                    f"| {ed['wind_actual']:.1f} | {ed['wind_existing']:.1f} | {w_ok} |"
                )
        lines.append("")

        # ── Per-region existing capacity check ──
        lines.append("## Per-Region Existing Capacity Check\n")
        lines.append("| Region | Existing Solar (GW) | 2030 Solar (GW) | 2040 Solar (GW) | 2050 Solar (GW) | "
                      "Existing Wind (GW) | 2030 Wind (GW) | 2040 Wind (GW) | 2050 Wind (GW) |")
        lines.append("|--------|--------------------|----------------|----------------|----------------|"
                      "-------------------|---------------|---------------|---------------|")
        for r in range(20):
            parts = [f"| {r+1:2d} {REGION_NAMES[r]}"]
            # existing
            ex_s = self.existing_data.get(2050, {}).get('region_solar_existing', None)
            ex_w = self.existing_data.get(2050, {}).get('region_wind_existing', None)
            parts.append(f" {ex_s[r]:.1f}" if ex_s is not None else " —")
            for year in [2030, 2040, 2050]:
                rd = self.region_data.get(year)
                parts.append(f" {rd['solar'][r]:.1f}" if rd else " —")
            parts.append(f" {ex_w[r]:.1f}" if ex_w is not None else " —")
            for year in [2030, 2040, 2050]:
                rd = self.region_data.get(year)
                parts.append(f" {rd['wind'][r]:.1f}" if rd else " —")
            lines.append(" | ".join(p.strip() for p in parts) + " |")
        lines.append("")

        with open(path, "w") as f:
            f.write("\n".join(lines))
        print(f"\n  Report written to: {path}")


# ══════════════════════════════════════════════════════════════════════════
#  Helper functions
# ══════════════════════════════════════════════════════════════════════════

def build_capacity_grids(opt_dir):
    """Build 180x360 solar/wind max capacity grids (GW).

    Solar: 74 MW/km² × available_area_fraction × grid_area_km² / 1000 → GW
    Wind:  (2.7 onshore / 4.6 offshore) MW/km² × available_area_fraction × grid_area_km² / 1000 → GW
    """
    solar_luccs = sio.loadmat(
        os.path.join(opt_dir, "Global_Solar_Net_Area_Add_Egrid.mat")
    )["data"] / 100.0
    solar_area = sio.loadmat(
        os.path.join(opt_dir, "Global_Solar_Fishnet_Area.mat")
    )["data"].astype(float)
    solar_cap_gw = SOLAR_DENSITY_MW_KM2 * solar_luccs * solar_area / 1000.0

    wind_luccs = sio.loadmat(
        os.path.join(opt_dir, "Global_Wind_Net_Area_Add_Egrid.mat")
    )["data"] / 100.0
    wind_area = sio.loadmat(
        os.path.join(opt_dir, "Global_Wind_Fishnet_Area.mat")
    )["data"].astype(float)
    landmask = sio.loadmat(
        os.path.join(opt_dir, "Global_LandMask.mat")
    )["data"]
    density = np.where(landmask > LANDMASK_THRESHOLD,
                       WIND_OFFSHORE_DENSITY_MW_KM2,
                       WIND_ONSHORE_DENSITY_MW_KM2)
    wind_cap_gw = density * wind_luccs * wind_area / 1000.0

    return solar_cap_gw, wind_cap_gw


def load_sel(results_dir, year):
    """Load the Sel.mat file for a given year."""
    fname = YEAR_FILES[year]["sel"]
    path = os.path.join(results_dir, fname)
    return sio.loadmat(path)


def load_h5(results_dir, year):
    """Load the H5 result file for a given year."""
    fname = YEAR_FILES[year]["h5"]
    path = os.path.join(results_dir, fname)
    return h5py.File(path, "r")


def get_sol_idx(sel_mat):
    """Extract sol_idx from Sel.mat (1-based MATLAB index). Returns None if absent."""
    if "sol_idx" in sel_mat:
        val = sel_mat["sol_idx"]
        return int(np.asarray(val).flatten()[0])
    return None


def compute_region_capacity(opt_solar, opt_wind, solar_cap_gw, wind_cap_gw, grid_div):
    """Compute per-region solar/wind capacity (GW) for 20 regions."""
    region_solar = np.zeros(20)
    region_wind = np.zeros(20)
    for r in range(1, 21):
        mask = grid_div == r
        region_solar[r - 1] = float(np.sum(solar_cap_gw * opt_solar * mask))
        region_wind[r - 1] = float(np.sum(wind_cap_gw * opt_wind * mask))
    return region_solar, region_wind


def compute_grid_stats(opt_solar, opt_wind, eps=EPS_ACTIVE):
    """Compute grid statistics: active, partial, full counts and mean fraction."""
    s_active = opt_solar > eps
    w_active = opt_wind > eps
    s_full = opt_solar > (1.0 - eps)
    w_full = opt_wind > (1.0 - eps)
    s_partial = s_active & ~s_full
    w_partial = w_active & ~w_full

    # Mean fraction over active grids only
    s_active_vals = opt_solar[s_active]
    w_active_vals = opt_wind[w_active]
    mean_s = float(np.mean(s_active_vals)) if len(s_active_vals) > 0 else 0.0
    mean_w = float(np.mean(w_active_vals)) if len(w_active_vals) > 0 else 0.0

    return {
        "n_solar_active": int(np.count_nonzero(s_active)),
        "n_wind_active": int(np.count_nonzero(w_active)),
        "n_solar_full": int(np.count_nonzero(s_full)),
        "n_wind_full": int(np.count_nonzero(w_full)),
        "n_solar_partial": int(np.count_nonzero(s_partial)),
        "n_wind_partial": int(np.count_nonzero(w_partial)),
        "mean_solar_frac": mean_s,
        "mean_wind_frac": mean_w,
    }


# ══════════════════════════════════════════════════════════════════════════
#  Check A: File Completeness
# ══════════════════════════════════════════════════════════════════════════

def check_file_completeness(results_dir, report):
    """Verify all 6 required result files exist."""
    print("\n[A] File Completeness")
    all_ok = True
    missing = []
    for year in [2050, 2040, 2030]:
        for key in ["h5", "sel"]:
            fname = YEAR_FILES[year][key]
            fpath = os.path.join(results_dir, fname)
            if not os.path.exists(fpath):
                all_ok = False
                missing.append(fname)
                print(f"  Missing: {fname}")

    detail = f"{len(missing)} file(s) missing: {', '.join(missing)}" if missing else "All 6 files present"
    report.add_check("A. File Completeness", all_ok, detail)
    return all_ok


# ══════════════════════════════════════════════════════════════════════════
#  Check B: Fraction Range
# ══════════════════════════════════════════════════════════════════════════

def check_fraction_range(results_dir, report):
    """Verify opt_solar and opt_wind fractions are in [0, 1] with tolerance TOL."""
    print("\n[B] Fraction Range")
    all_ok = True
    for year in [2050, 2040, 2030]:
        sel = load_sel(results_dir, year)
        for var_name in ["opt_solar", "opt_wind"]:
            arr = sel[var_name].astype(float)
            lo = float(arr.min())
            hi = float(arr.max())
            ok = lo >= -TOL and hi <= 1.0 + TOL
            if not ok:
                all_ok = False
            detail = f"{year} {var_name}: min={lo:.2e}, max={hi:.6f}"
            report.add_check(f"B. Fraction Range ({year} {var_name})", ok, detail)
    return all_ok


# ══════════════════════════════════════════════════════════════════════════
#  Check C: Cross-year Monotonicity
# ══════════════════════════════════════════════════════════════════════════

def check_monotonicity(results_dir, report):
    """Check opt_solar_2030 <= opt_solar_2040 <= opt_solar_2050 (and wind)."""
    print("\n[C] Cross-year Monotonicity")
    all_ok = True
    pairs = [(2030, 2040), (2040, 2050)]
    for y_lo, y_hi in pairs:
        sel_lo = load_sel(results_dir, y_lo)
        sel_hi = load_sel(results_dir, y_hi)
        pair_label = f"{y_lo}→{y_hi}"
        if pair_label not in report.mono_data:
            report.mono_data[pair_label] = {
                "solar_violations": 0, "solar_max_diff": None,
                "wind_violations": 0, "wind_max_diff": None,
            }

        for var_name in ["opt_solar", "opt_wind"]:
            arr_lo = sel_lo[var_name].astype(float)
            arr_hi = sel_hi[var_name].astype(float)
            diff = arr_lo - arr_hi  # should be <= 0 everywhere
            violations = np.count_nonzero(diff > TOL)
            max_neg = float(diff.max()) if violations > 0 else 0.0
            ok = violations == 0
            if not ok:
                all_ok = False

            kind = "solar" if "solar" in var_name else "wind"
            report.mono_data[pair_label][f"{kind}_violations"] = violations
            report.mono_data[pair_label][f"{kind}_max_diff"] = max_neg if violations > 0 else None

            detail = f"violations={violations}"
            if violations > 0:
                detail += f", max excess={max_neg:.2e}"
            report.add_check(
                f"C. Monotonicity ({pair_label} {kind})", ok, detail
            )
    return all_ok


# ══════════════════════════════════════════════════════════════════════════
#  Check D: Capacity Consistency
# ══════════════════════════════════════════════════════════════════════════

def check_capacity_consistency(opt_dir, results_dir, report):
    """Verify opt_solar_cap_twp ≈ opt_solar × max_capacity_grid (RTOL)."""
    print("\n[D] Capacity Consistency")
    solar_cap_gw, wind_cap_gw = build_capacity_grids(opt_dir)
    all_ok = True

    for year in [2050, 2040, 2030]:
        sel = load_sel(results_dir, year)

        for kind, cap_grid, cap_key, frac_key in [
            ("solar", solar_cap_gw, "opt_solar_cap_twp", "opt_solar"),
            ("wind", wind_cap_gw, "opt_wind_cap_twp", "opt_wind"),
        ]:
            if cap_key not in sel:
                detail = f"{cap_key} not found in Sel.mat — skipped"
                report.add_check(
                    f"D. Capacity Consistency ({year} {kind})", True, detail
                )
                continue

            # cap_twp is in TW (from MATLAB), convert to GW
            cap_twp_gw = sel[cap_key].astype(float) * 1000.0
            frac = sel[frac_key].astype(float)
            expected_gw = frac * cap_grid

            # Only compare at active positions
            active = frac > EPS_ACTIVE
            if not np.any(active):
                detail = "no active grids — trivially consistent"
                report.add_check(
                    f"D. Capacity Consistency ({year} {kind})", True, detail
                )
                continue

            actual = cap_twp_gw[active]
            expect = expected_gw[active]

            # Relative error (avoid division by zero)
            denom = np.maximum(np.abs(expect), 1e-12)
            rel_err = np.abs(actual - expect) / denom
            max_rel_err = float(rel_err.max())
            mean_rel_err = float(rel_err.mean())
            ok = max_rel_err <= RTOL

            if not ok:
                all_ok = False

            detail = (f"max_rel_err={max_rel_err:.2e}, mean_rel_err={mean_rel_err:.2e}, "
                       f"active_grids={int(np.count_nonzero(active))}")
            report.add_check(
                f"D. Capacity Consistency ({year} {kind})", ok, detail
            )

    return all_ok


# ══════════════════════════════════════════════════════════════════════════
#  Check E: H5-to-Sel.mat Mapping
# ══════════════════════════════════════════════════════════════════════════

def check_h5_sel_mapping(results_dir, report):
    """For the selected Pareto solution, compare H5 decision vector with Sel.mat grids."""
    print("\n[E] H5-to-Sel.mat Mapping")
    all_ok = True

    for year in [2050, 2040, 2030]:
        sel = load_sel(results_dir, year)
        h5f = load_h5(results_dir, year)

        # Determine selected solution index
        sol_idx_matlab = get_sol_idx(sel)
        res_scale = h5f["res_scale"][:]  # shape (N_vars, N_solutions) in h5py
        n_solutions = res_scale.shape[1]

        if sol_idx_matlab is None:
            sol_idx_matlab = round(n_solutions / 2)
        sol_idx_python = sol_idx_matlab - 1  # convert 1-based → 0-based

        ok_idx = 0 <= sol_idx_python < n_solutions
        if not ok_idx:
            report.add_check(
                f"E. H5-MAT Mapping ({year})", False,
                f"sol_idx={sol_idx_matlab} out of range [1, {n_solutions}]"
            )
            all_ok = False
            h5f.close()
            continue

        # Get decision vector for the selected solution
        vec = res_scale[:, sol_idx_python]  # (N_vars,)

        # ── Grid fraction comparison ──
        # Sel.mat fractions
        opt_solar = sel["opt_solar"].astype(float)
        opt_wind = sel["opt_wind"].astype(float)
        mat_solar_active = opt_solar > EPS_ACTIVE
        mat_wind_active = opt_wind > EPS_ACTIVE
        n_mat_solar = int(np.count_nonzero(mat_solar_active))
        n_mat_wind = int(np.count_nonzero(mat_wind_active))
        mat_solar_vals = np.sort(opt_solar[mat_solar_active])
        mat_wind_vals = np.sort(opt_wind[mat_wind_active])
        mat_all_fracs = np.sort(np.concatenate([mat_solar_vals, mat_wind_vals]))
        mat_frac_sum = float(opt_solar[mat_solar_active].sum() +
                              opt_wind[mat_wind_active].sum())

        # H5 decision vector: values in (EPS_ACTIVE, 1+TOL] are grid fractions
        h5_frac_mask = (vec > EPS_ACTIVE) & (vec <= 1.0 + TOL)
        h5_frac_vals = np.sort(vec[h5_frac_mask])
        n_h5_frac = len(h5_frac_vals)
        h5_frac_sum = float(h5_frac_vals.sum())

        # Compare active grid counts
        n_mat_total = n_mat_solar + n_mat_wind
        count_ok = n_h5_frac == n_mat_total

        # Compare fraction sums
        sum_diff = abs(h5_frac_sum - mat_frac_sum)
        sum_ok = sum_diff < max(1.0, mat_frac_sum * RTOL)

        # Compare sorted fraction distributions
        sorted_max_diff = None
        sorted_ok = True
        if len(mat_all_fracs) == len(h5_frac_vals) and len(mat_all_fracs) > 0:
            sorted_max_diff = float(np.max(np.abs(mat_all_fracs - h5_frac_vals)))
            sorted_ok = sorted_max_diff < 0.01  # allow up to 1% abs diff per grid
        elif len(mat_all_fracs) != len(h5_frac_vals):
            sorted_ok = False
            sorted_max_diff = None

        ok = count_ok and sum_ok and sorted_ok
        if not ok:
            all_ok = False

        # Store mapping data for report
        report.mapping_data[year] = {
            "sol_idx": sol_idx_matlab,
            "n_solutions": n_solutions,
            "mat_solar_active": n_mat_solar,
            "mat_wind_active": n_mat_wind,
            "h5_frac_active": n_h5_frac,
            "mat_frac_sum": mat_frac_sum,
            "h5_frac_sum": h5_frac_sum,
            "sorted_max_diff": sorted_max_diff,
            "count_ok": count_ok,
            "sum_ok": sum_ok,
            "sorted_ok": sorted_ok,
        }

        detail_parts = []
        detail_parts.append(f"sol_idx={sol_idx_matlab}/{n_solutions}")
        detail_parts.append(f"grids: MAT={n_mat_total}, H5={n_h5_frac}")
        detail_parts.append(f"frac_sum: MAT={mat_frac_sum:.2f}, H5={h5_frac_sum:.2f}")
        if sorted_max_diff is not None:
            detail_parts.append(f"sorted_max_diff={sorted_max_diff:.2e}")
        detail = ", ".join(detail_parts)

        report.add_check(f"E. H5-MAT Mapping ({year})", ok, detail)
        h5f.close()

    return all_ok


# ══════════════════════════════════════════════════════════════════════════
#  Check F: Existing Capacity Constraint
# ══════════════════════════════════════════════════════════════════════════

def check_existing_capacity(opt_dir, results_dir, report):
    """Verify 20-region solar/wind actual capacity >= existing from Global_Init_State.mat."""
    print("\n[F] Existing Capacity Constraint")

    solar_cap_gw, wind_cap_gw = build_capacity_grids(opt_dir)
    grid_div = sio.loadmat(os.path.join(opt_dir, "Global_Grid_Division.mat"))["data"]

    # Load existing capacity (MW → GW)
    init = sio.loadmat(os.path.join(opt_dir, "Global_Init_State.mat"))
    cur_solar_mw = init["cur_solar"].flatten()  # (20,) in MW
    cur_wind_mw = init["cur_wind"].flatten()    # (20,) in MW
    cur_solar_gw = cur_solar_mw / 1000.0
    cur_wind_gw = cur_wind_mw / 1000.0

    all_ok = True
    for year in [2050, 2040, 2030]:
        sel = load_sel(results_dir, year)
        opt_solar = sel["opt_solar"].astype(float)
        opt_wind = sel["opt_wind"].astype(float)

        # Compute per-region actual capacity
        region_solar_gw, region_wind_gw = compute_region_capacity(
            opt_solar, opt_wind, solar_cap_gw, wind_cap_gw, grid_div
        )

        # Check >= existing
        solar_deficit = cur_solar_gw - region_solar_gw  # positive = violation
        wind_deficit = cur_wind_gw - region_wind_gw
        solar_violations = np.count_nonzero(solar_deficit > TOL)
        wind_violations = np.count_nonzero(wind_deficit > TOL)

        solar_ok = solar_violations == 0
        wind_ok = wind_violations == 0
        ok = solar_ok and wind_ok
        if not ok:
            all_ok = False

        total_solar_gw = float(region_solar_gw.sum())
        total_wind_gw = float(region_wind_gw.sum())

        # Store for report
        report.existing_data[year] = {
            "solar_actual": total_solar_gw,
            "wind_actual": total_wind_gw,
            "solar_existing": float(cur_solar_gw.sum()),
            "wind_existing": float(cur_wind_gw.sum()),
            "solar_ok": solar_ok,
            "wind_ok": wind_ok,
            "solar_violations": solar_violations,
            "wind_violations": wind_violations,
            "region_solar_actual": region_solar_gw,
            "region_wind_actual": region_wind_gw,
            "region_solar_existing": cur_solar_gw,
            "region_wind_existing": cur_wind_gw,
        }

        detail = (f"solar: {solar_violations} region violations, "
                   f"wind: {wind_violations} region violations")
        if solar_violations > 0:
            worst_s = int(np.argmax(solar_deficit))
            detail += (f" | worst solar region={worst_s+1} "
                        f"(actual={region_solar_gw[worst_s]:.1f} GW, "
                        f"existing={cur_solar_gw[worst_s]:.1f} GW)")
        if wind_violations > 0:
            worst_w = int(np.argmax(wind_deficit))
            detail += (f" | worst wind region={worst_w+1} "
                        f"(actual={region_wind_gw[worst_w]:.1f} GW, "
                        f"existing={cur_wind_gw[worst_w]:.1f} GW)")

        report.add_check(f"F. Existing Capacity ({year})", ok, detail)

    return all_ok


# ══════════════════════════════════════════════════════════════════════════
#  Collect per-year and per-region statistics for the report
# ══════════════════════════════════════════════════════════════════════════

def collect_statistics(opt_dir, results_dir, report):
    """Compute per-year grid statistics and per-region capacity for the report."""
    print("\n[*] Collecting statistics for report")
    solar_cap_gw, wind_cap_gw = build_capacity_grids(opt_dir)
    grid_div = sio.loadmat(os.path.join(opt_dir, "Global_Grid_Division.mat"))["data"]

    for year in [2050, 2040, 2030]:
        sel = load_sel(results_dir, year)
        opt_solar = sel["opt_solar"].astype(float)
        opt_wind = sel["opt_wind"].astype(float)

        # Capacity
        total_solar_gw = float(np.sum(solar_cap_gw * opt_solar))
        total_wind_gw = float(np.sum(wind_cap_gw * opt_wind))

        # Grid stats
        stats = compute_grid_stats(opt_solar, opt_wind)

        report.year_data[year] = {
            "solar_gw": total_solar_gw,
            "wind_gw": total_wind_gw,
            "total_gw": total_solar_gw + total_wind_gw,
            **stats,
        }

        # Per-region capacity
        region_solar, region_wind = compute_region_capacity(
            opt_solar, opt_wind, solar_cap_gw, wind_cap_gw, grid_div
        )
        report.region_data[year] = {
            "solar": region_solar,
            "wind": region_wind,
        }

        print(f"  {year}: solar={total_solar_gw:.1f} GW, wind={total_wind_gw:.1f} GW, "
              f"active_s={stats['n_solar_active']}, active_w={stats['n_wind_active']}")


# ══════════════════════════════════════════════════════════════════════════
#  Main
# ══════════════════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(
        description="Validate continuous capacity optimization results."
    )
    parser.add_argument(
        "--opt-dir",
        type=str,
        required=True,
        help="Path to the continuous optimization directory "
             "(e.g., Optimization_ssp126_test_continuous)",
    )
    parser.add_argument(
        "--binary-opt-dir",
        type=str,
        required=True,
        help="Path to the binary optimization directory for reference "
             "(e.g., Optimization_ssp126)",
    )
    parser.add_argument(
        "--results-subdir",
        type=str,
        default="results",
        help="Subdirectory name for results within opt-dir (default: 'results')",
    )
    args = parser.parse_args()

    opt_dir = os.path.abspath(args.opt_dir)
    binary_opt_dir = os.path.abspath(args.binary_opt_dir)
    results_dir = os.path.join(opt_dir, args.results_subdir)

    print(f"{'═' * 70}")
    print(f"  Continuous Optimization Validation")
    print(f"{'═' * 70}")
    print(f"  Optimization dir:   {opt_dir}")
    print(f"  Binary reference:    {binary_opt_dir}")
    print(f"  Results dir:         {results_dir}")
    print(f"  TOL = {TOL}, RTOL = {RTOL}, EPS_ACTIVE = {EPS_ACTIVE}")

    report = ValidationReport()

    # ── A. File Completeness ──
    files_ok = check_file_completeness(results_dir, report)
    if not files_ok:
        print("\n  ABORT: Required files missing. Cannot continue validation.")
        report.print_summary()
        sys.exit(1)

    # ── B. Fraction Range ──
    check_fraction_range(results_dir, report)

    # ── C. Cross-year Monotonicity ──
    check_monotonicity(results_dir, report)

    # ── D. Capacity Consistency ──
    check_capacity_consistency(opt_dir, results_dir, report)

    # ── E. H5-to-Sel.mat Mapping ──
    check_h5_sel_mapping(results_dir, report)

    # ── F. Existing Capacity Constraint ──
    check_existing_capacity(opt_dir, results_dir, report)

    # ── Collect statistics for report ──
    collect_statistics(opt_dir, results_dir, report)

    # ── G. Generate Report ──
    print("\n[G] Generating validation report")
    report_path = os.path.join(results_dir, "continuous_validation_report.md")
    report.write_markdown(report_path)

    # ── Summary ──
    report.print_summary()

    sys.exit(0 if report.all_passed else 1)


if __name__ == "__main__":
    main()
