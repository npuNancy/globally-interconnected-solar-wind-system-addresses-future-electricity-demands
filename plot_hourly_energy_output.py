#!/usr/bin/env python3
"""plot_hourly_energy_output.py -- Hourly energy dispatch visualization

Two modes:
  1) Plot-only:   --input <csv> reads an existing CSV and plots.
  2) Full pipeline: --results-dir reads HDF5/MAT, replays dispatch, exports CSV, then plots.

Usage examples:
  # Plot-only
  python plot_hourly_energy_output.py \\
    --ssp ssp245 --year 2050 \\
    --input Optimization_ssp245/results/hourly/hourly_dispatch_2050.csv \\
    --img-dir Optimization_ssp245/results/img/hourly

  # Full pipeline (results + Global_Trans in same dir)
  python plot_hourly_energy_output.py \\
    --ssp ssp126 --year 2050 \\
    --results-dir Optimization_ssp126/results/results_20260609_1138 \\
    --img-dir output/img

  # Full pipeline (results and Global_Trans in separate dirs)
  python plot_hourly_energy_output.py \\
    --ssp ssp126 --year 2050 \\
    --results-dir Optimization_ssp126/results/results_20260609_1138 \\
    --ssp-dir Optimization_ssp126 \\
    --csv-dir output/csv \\
    --img-dir output/img
"""

import argparse
import os
import sys

import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import numpy as np
import pandas as pd

# ---------------------------------------------------------------------------
# Helpers: file name templates by year
# ---------------------------------------------------------------------------

_H5_NAMES = {2050: "Optimization_SC_2050_Res.h5",
             2040: "Optimization_SC_2040_Res.h5",
             2030: "Optimization_SA_2030_Res.h5"}

_MD_NAMES = {2050: "model_data_2050.mat",
             2040: "model_data_2040.mat",
             2030: "model_data_2030.mat"}

_METRICS_NAMES = {2050: "Optimization_SC_2050_metrics.mat",
                  2040: "Optimization_SC_2040_metrics.mat",
                  2030: "Optimization_SA_2030_metrics.mat"}

_BASE_LOAD_RATIO = {2050: 0.09, 2040: 0.11, 2030: 0.36}
_INTERCON_MODE = {2050: "S-C", 2040: "S-C", 2030: "S-A"}


# ---------------------------------------------------------------------------
# Data loading helpers
# ---------------------------------------------------------------------------

def load_data_files(results_dir: str, ssp_dir: str, year: int) -> dict:
    """Read HDF5 + MAT files from the given directories."""
    import h5py
    from scipy.io import loadmat

    h5_path = os.path.join(results_dir, _H5_NAMES[year])
    md_path = os.path.join(results_dir, _MD_NAMES[year])
    gt_path = os.path.join(ssp_dir, "Global_Trans.mat")

    for p, label in [(h5_path, "HDF5"), (md_path, "model_data"),
                     (gt_path, "Global_Trans")]:
        if not os.path.isfile(p):
            sys.exit(f"找不到 {label} 文件: {p}")

    # --- HDF5: best_scale ---
    with h5py.File(h5_path, "r") as f:
        best_scale = f["/res_scale"][:].flatten()

    # --- model_data ---
    md = loadmat(md_path, squeeze_me=True)
    model_data = md["model_data"]
    ins_cap = np.asarray(model_data["ins_cap"].item()).flatten().astype(float)
    gens = np.asarray(model_data["gens"].item()).astype(float)
    loads = np.asarray(model_data["loads"].item()).astype(float)
    CGrid_Index = np.asarray(model_data["CGrid_Index"].item()).astype(float)
    nonlsol = int(np.asarray(model_data["nonlsol"].item()).flatten()[0])

    # --- Global_Trans ---
    gt = loadmat(gt_path, squeeze_me=True)
    trans_connections = np.array(gt["trans_connections"])
    trans_loss = np.array(gt["trans_loss"])

    return dict(
        best_scale=best_scale,
        ins_cap=ins_cap, gens=gens, loads=loads,
        CGrid_Index=CGrid_Index, nonlsol=nonlsol,
        trans_connections=trans_connections, trans_loss=trans_loss,
    )


def load_scenario_cfg(results_dir: str, year: int):
    """Return (base_load_ratio, interconnection_mode)."""
    from scipy.io import loadmat

    metrics_path = os.path.join(results_dir, _METRICS_NAMES[year])
    if os.path.isfile(metrics_path):
        m = loadmat(metrics_path, squeeze_me=True)
        cfg = m.get("scenario_cfg", None)
        if cfg is not None:
            blr = float(cfg["base_load_ratio"].item())
            im = str(cfg["interconnection_mode"].item())
            return blr, im

    return _BASE_LOAD_RATIO[year], _INTERCON_MODE[year]


# ---------------------------------------------------------------------------
# Dispatch replay helpers (translated from MATLAB)
# ---------------------------------------------------------------------------

def _dfs_from_start(adj, node, visited, path, results, min_nodes, max_nodes):
    """DFS path enumeration (mirrors findAllPathsFromStart.m)."""
    visited[node] = True
    path.append(node)

    if len(path) > max_nodes:
        visited[node] = False
        path.pop()
        return

    if len(path) >= min_nodes:
        results.append(list(path))

    for neighbor in range(adj.shape[0]):
        if adj[node, neighbor] == 1 and not visited[neighbor]:
            _dfs_from_start(adj, neighbor, visited, path, results,
                            min_nodes, max_nodes)

    visited[node] = False
    path.pop()


def _path_cost(path, cost_matrix):
    """Cumulative transmission loss along a path."""
    total = 0.0
    for i in range(len(path) - 1):
        total = 1 - (1 - total) * (1 - cost_matrix[path[i], path[i + 1]])
    return total


def _path_capacity(path, cap_matrix):
    """Bottleneck capacity (min edge) along a path."""
    cap = np.inf
    for i in range(len(path) - 1):
        cap = min(cap, cap_matrix[path[i], path[i + 1]])
    return 0.0 if cap == np.inf else cap


def _build_all_paths(trans_power, trans_loss, interconnection_mode):
    """Build sorted path lists for all 20 source regions."""
    max_nodes = 2 if interconnection_mode == "S-A" else 3
    n = trans_power.shape[0]
    adj = (trans_power > 0).astype(np.int16)

    all_paths = []
    all_costs = []
    for src in range(n):
        visited = np.zeros(n, dtype=bool)
        raw = []
        _dfs_from_start(adj, src, visited, [], raw, 2, max_nodes)
        costs = np.array([_path_cost(p, trans_loss) for p in raw])
        # sort by cost ascending
        order = np.argsort(costs)
        sorted_paths = [raw[i] for i in order]
        sorted_costs = costs[order]
        # filter out loss >= 1
        mask = sorted_costs < 1
        all_paths.append([sorted_paths[i] for i in range(len(mask)) if mask[i]])
        all_costs.append(sorted_costs[mask])
    return all_paths, all_costs


def replay_dispatch(data: dict, base_load_ratio: float,
                    interconnection_mode: str) -> pd.DataFrame:
    """Replay 8760-h dispatch and return hourly detail as DataFrame."""
    best_scale = data["best_scale"]
    ins_cap = data["ins_cap"]
    gens = data["gens"]
    loads = data["loads"]
    CGrid_Index = data["CGrid_Index"]
    nonlsol = data["nonlsol"]
    trans_connections = data["trans_connections"].copy()
    trans_loss = data["trans_loss"]

    N = len(CGrid_Index)
    n_regions = 20
    n_hours = 8760

    # --- Section 1: regional generation curves ---
    CGrid_Index[:, 1] = np.round(best_scale[:N])
    grid_gens = np.zeros((n_regions, n_hours))
    for r in range(n_regions):
        mask = (CGrid_Index[:, 0] == r + 1) & (CGrid_Index[:, 1] == 1)
        grid_gens[r] = np.nansum(gens[mask], axis=0)

    # --- Section 2: subtract baseload ---
    loads_original = loads.copy()
    grid_load = loads.copy()
    for r in range(n_regions):
        annual = np.sum(grid_load[r])
        grid_load[r] = grid_load[r] - annual * base_load_ratio / n_hours

    # --- Section 3: storage & transmission params ---
    to_storage_loss = 0.95
    from_storage_loss = 0.95

    trans_connections[trans_connections == 2] = 0

    storage_pow = best_scale[N:N + n_regions] / 1000.0  # TW
    storage_cap = storage_pow * best_scale[N + n_regions:N + 2 * n_regions]  # TWh

    # --- Section 4: init dispatch variables ---
    stored = np.zeros((n_hours + 1, n_regions))
    stored[0] = storage_cap * 0.5
    curtailed = np.zeros((n_hours, n_regions))
    flexible = np.zeros((n_hours, n_regions))
    storage_discharge = np.zeros((n_hours, n_regions))
    storage_charge = np.zeros((n_hours, n_regions))

    # --- Section 5: build transmission topology ---
    trans_power_base = np.zeros((n_regions, n_regions))
    conn_mask = trans_connections == 1
    trans_power_base[conn_mask] = best_scale[N + 2 * n_regions:] / 1000.0

    all_paths, all_costs = _build_all_paths(
        trans_power_base, trans_loss, interconnection_mode)

    # --- Section 6: 8760-hour dispatch loop ---
    for t in range(n_hours):
        tp = trans_power_base.copy()

        supply_gen = grid_gens[:, t]
        demand = grid_load[:, t]
        surplus = supply_gen - demand  # >0 surplus, <0 deficit

        # -- cross-region transmission --
        for src in range(n_regions):
            if surplus[src] <= 0:
                continue
            for pi in range(len(all_paths[src])):
                route = all_paths[src][pi]
                dst = route[-1]
                if surplus[dst] >= 0:
                    continue
                cap = _path_capacity(route, tp)
                if cap <= 0:
                    continue
                amount = min(
                    abs(surplus[dst]) / (1 - all_costs[src][pi]),
                    cap,
                    surplus[src],
                )
                surplus[src] -= amount
                surplus[dst] += amount * (1 - all_costs[src][pi])
                for j in range(len(route) - 1):
                    tp[route[j], route[j + 1]] -= amount

        # -- storage charge/discharge --
        for r in range(n_regions):
            if surplus[r] >= 0:  # surplus -> charge
                amount = min(
                    surplus[r],
                    storage_pow[r],
                    (storage_cap[r] - stored[t, r]) / to_storage_loss,
                )
                stored[t + 1, r] = stored[t, r] + amount * to_storage_loss
                curtailed[t, r] = surplus[r] - amount
                storage_charge[t, r] = amount
                surplus[r] = 0
            else:  # deficit -> discharge
                amount = min(
                    storage_pow[r] / from_storage_loss,
                    abs(surplus[r]),
                    stored[t, r],
                )
                stored[t + 1, r] = max(stored[t, r] - amount, 0)
                storage_discharge[t, r] = amount
                flexible[t, r] = abs(surplus[r] + amount)
                surplus[r] = 0

    # --- Section 10: build detail ---
    hour_index = np.arange(1, n_hours + 1)

    # time fields
    day_of_year = (hour_index - 1) // 24 + 1
    hour_of_day = (hour_index - 1) % 24
    days_in_month = np.array([31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31])
    cum_days = np.cumsum(np.concatenate([[0], days_in_month]))
    month = np.zeros(n_hours, dtype=int)
    for h in range(n_hours):
        d = day_of_year[h]
        for m in range(11, -1, -1):
            if d > cum_days[m]:
                month[h] = m + 1
                break

    # generation-side
    raw_vre = np.sum(grid_gens, axis=0)
    load_total = np.sum(loads_original, axis=0)

    # load-side supply stack (back-calculated per region)
    base_by_region = np.zeros((n_regions, n_hours))
    for r in range(n_regions):
        base_by_region[r] = np.sum(loads_original[r]) * base_load_ratio / n_hours

    actual_vre_by_region = (loads_original
                            - storage_discharge.T
                            - base_by_region
                            - flexible.T)
    actual_vre_by_region = np.maximum(actual_vre_by_region, 0)

    df = pd.DataFrame({
        "hour": hour_index,
        "month": month,
        "day_of_year": day_of_year,
        "hour_of_day": hour_of_day,
        "load_twh": load_total,
        "raw_vre_twh": raw_vre,
        "actual_vre_twh": np.sum(actual_vre_by_region, axis=0),
        "storage_discharge_twh": np.sum(storage_discharge, axis=1),
        "base_twh": np.sum(base_by_region, axis=0),
        "flexible_twh": np.sum(flexible, axis=1),
        "curtailment_twh": np.sum(curtailed, axis=1),
        "storage_charge_twh": np.sum(storage_charge, axis=1),
    })
    return df


# ---------------------------------------------------------------------------
# CSV export
# ---------------------------------------------------------------------------

def save_hourly_csv(df: pd.DataFrame, csv_dir: str, year: int) -> str:
    os.makedirs(csv_dir, exist_ok=True)
    path = os.path.join(csv_dir, f"hourly_dispatch_{year}.csv")
    df.to_csv(path, index=False)
    print(f"CSV 已保存: {path}")
    return path


# ---------------------------------------------------------------------------
# Plotting (unchanged from original)
# ---------------------------------------------------------------------------

def load_data(csv_path: str) -> pd.DataFrame:
    df = pd.read_csv(csv_path)
    required = [
        "hour", "load_twh", "raw_vre_twh", "actual_vre_twh",
        "storage_discharge_twh", "base_twh", "flexible_twh",
        "curtailment_twh", "storage_charge_twh",
    ]
    for col in required:
        if col not in df.columns:
            sys.exit(f"CSV 缺少必要列: {col}")
    return df


def check_energy_balance(df: pd.DataFrame) -> None:
    supply = (
        df["actual_vre_twh"]
        + df["storage_discharge_twh"]
        + df["base_twh"]
        + df["flexible_twh"]
    )
    error = supply - df["load_twh"]
    max_err = error.abs().max()
    mean_err = error.abs().mean()
    print(f"能量平衡校验: max_abs_error={max_err:.2e}, mean_abs_error={mean_err:.2e}")
    if max_err > 1e-6:
        print(f"  ⚠ 警告: 能量平衡最大偏差 {max_err:.2e} 超过 1e-6 TWh")


def check_annual_totals(df: pd.DataFrame) -> None:
    print("\n年度总量:")
    print(f"  sum(load_twh)        = {df['load_twh'].sum():.6f}")
    print(f"  sum(raw_vre_twh)     = {df['raw_vre_twh'].sum():.6f}")
    print(f"  sum(actual_vre_twh)  = {df['actual_vre_twh'].sum():.6f}")
    print(f"  sum(base_twh)        = {df['base_twh'].sum():.6f}")
    print(f"  sum(flexible_twh)    = {df['flexible_twh'].sum():.6f}")
    print(f"  sum(curtailment_twh) = {df['curtailment_twh'].sum():.6f}")
    print(f"  sum(storage_discharge)= {df['storage_discharge_twh'].sum():.6f}")
    print(f"  sum(storage_charge)  = {df['storage_charge_twh'].sum():.6f}")
    net_storage = df["storage_discharge_twh"].sum() - df["storage_charge_twh"].sum()
    print(f"  净储能放电           = {net_storage:.6f}")


def plot_figure_a(
    df: pd.DataFrame, x: np.ndarray, title_suffix: str
) -> plt.Figure:
    fig, ax = plt.subplots(figsize=(14, 4.5))

    ax.fill_between(
        x, 0, df["raw_vre_twh"].values, alpha=0.75, label="Raw VRE generation", color="#2ca02c"
    )
    ax.plot(x, df["load_twh"].values, label="Load", linewidth=1.0, color="#d62728")

    ax.set_xlabel("Hour of year")
    ax.set_ylabel("Electricity (TWh/h)")
    ax.set_title(f"Figure A. Generation-side raw hourly VRE output  ({title_suffix})")
    ax.legend(loc="upper right")
    ax.set_xlim(x[0], x[-1])
    ax.yaxis.set_major_formatter(ticker.FormatStrFormatter("%.2f"))
    fig.tight_layout()
    return fig


def plot_figure_b(
    df: pd.DataFrame, x: np.ndarray, title_suffix: str
) -> plt.Figure:
    fig, ax = plt.subplots(figsize=(14, 4.5))

    stack = [
        df["actual_vre_twh"].values,
        df["storage_discharge_twh"].values,
        df["base_twh"].values,
        df["flexible_twh"].values,
    ]
    labels = [
        "Actual VRE generation",
        "Storage discharge",
        "Baseload",
        "Flexible generation",
    ]
    colors = ["#2ca02c", "#1f77b4", "#ff7f0e", "#9467bd"]

    ax.stackplot(x, stack, labels=labels, colors=colors, alpha=0.85)
    ax.plot(
        x, df["load_twh"].values, label="Load", linewidth=1.0, color="#d62728"
    )

    ax.set_xlabel("Hour of year")
    ax.set_ylabel("Electricity (TWh/h)")
    ax.set_title(f"Figure B. Load-side actual hourly supply structure  ({title_suffix})")
    ax.legend(loc="upper right")
    ax.set_xlim(x[0], x[-1])
    ax.yaxis.set_major_formatter(ticker.FormatStrFormatter("%.2f"))
    fig.tight_layout()
    return fig


def plot_all(df: pd.DataFrame, ssp: str, year: int, img_dir: str) -> None:
    os.makedirs(img_dir, exist_ok=True)
    ssp_year = f"{ssp.upper()} {year}"

    # --- full year ---
    x_full = df["hour"].values

    fig_a = plot_figure_a(df, x_full, f"{ssp_year} — full year")
    pa = os.path.join(img_dir, f"hourly_energy_A_generation_side_{year}_full_year.png")
    fig_a.savefig(pa, dpi=200)
    print(f"已保存: {pa}")
    plt.close(fig_a)

    fig_b = plot_figure_b(df, x_full, f"{ssp_year} — full year")
    pb = os.path.join(img_dir, f"hourly_energy_B_load_side_{year}_full_year.png")
    fig_b.savefig(pb, dpi=200)
    print(f"已保存: {pb}")
    plt.close(fig_b)

    # --- first month ---
    df_jan = df[df["month"] == 1].copy()
    if len(df_jan) > 0:
        x_jan = df_jan["hour"].values

        fig_a_jan = plot_figure_a(df_jan, x_jan, f"{ssp_year} — January")
        pa_jan = os.path.join(img_dir, f"hourly_energy_A_generation_side_{year}_first_month.png")
        fig_a_jan.savefig(pa_jan, dpi=200)
        print(f"已保存: {pa_jan}")
        plt.close(fig_a_jan)

        fig_b_jan = plot_figure_b(df_jan, x_jan, f"{ssp_year} — January")
        pb_jan = os.path.join(img_dir, f"hourly_energy_B_load_side_{year}_first_month.png")
        fig_b_jan.savefig(pb_jan, dpi=200)
        print(f"已保存: {pb_jan}")
        plt.close(fig_b_jan)

    # --- sample week (days 183-189, early July) ---
    week_days = range(183, 190)
    df_week = df[df["day_of_year"].isin(week_days)].copy()
    if len(df_week) > 0:
        x_week = df_week["hour"].values

        fig_a_w = plot_figure_a(df_week, x_week, f"{ssp_year} — sample week (Jul)")
        pa_w = os.path.join(img_dir, f"hourly_energy_A_generation_side_{year}_sample_week.png")
        fig_a_w.savefig(pa_w, dpi=200)
        print(f"已保存: {pa_w}")
        plt.close(fig_a_w)

        fig_b_w = plot_figure_b(df_week, x_week, f"{ssp_year} — sample week (Jul)")
        pb_w = os.path.join(img_dir, f"hourly_energy_B_load_side_{year}_sample_week.png")
        fig_b_w.savefig(pb_w, dpi=200)
        print(f"已保存: {pb_w}")
        plt.close(fig_b_w)

    print("\n全部图形输出完成。")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def parse_args():
    p = argparse.ArgumentParser(description="逐小时能源出力可视化")
    p.add_argument("--ssp", required=True, help="SSP scenario, e.g. ssp245")
    p.add_argument("--year", required=True, type=int, help="Year: 2030/2040/2050")

    g = p.add_mutually_exclusive_group(required=True)
    g.add_argument("--input", help="Path to existing hourly_dispatch CSV (plot-only mode)")
    g.add_argument("--results-dir", help="Directory with HDF5 + model_data MAT (full pipeline mode)")

    p.add_argument("--ssp-dir", help="Directory with Global_Trans.mat (default: same as --results-dir)")
    p.add_argument("--csv-dir", help="CSV output directory (default: <results-dir>/hourly)")
    p.add_argument("--img-dir", required=True, help="Image output directory")
    return p.parse_args()


def main():
    args = parse_args()

    if args.input:
        # --- plot-only mode ---
        print(f"=== 纯绘图模式: {args.ssp} {args.year} ===")
        df = load_data(args.input)
        print(f"已加载 {len(df)} 行数据")
    else:
        # --- full pipeline mode ---
        results_dir = args.results_dir
        ssp_dir = args.ssp_dir or results_dir
        csv_dir = args.csv_dir or os.path.join(results_dir, "hourly")

        print(f"=== 完整流水线: {args.ssp} {args.year} ===")
        print(f"结果目录: {results_dir}")
        print(f"SSP 目录: {ssp_dir}")

        data = load_data_files(results_dir, ssp_dir, args.year)
        base_load_ratio, interconnection_mode = load_scenario_cfg(results_dir, args.year)
        print(f"base_load_ratio: {base_load_ratio:.4f}")
        print(f"interconnection_mode: {interconnection_mode}")

        print("\n正在 replay dispatch...")
        df = replay_dispatch(data, base_load_ratio, interconnection_mode)
        print(f"调度完成, {len(df)} 行")

        csv_path = save_hourly_csv(df, csv_dir, args.year)

    # --- shared: check & plot ---
    check_energy_balance(df)
    check_annual_totals(df)
    plot_all(df, args.ssp, args.year, args.img_dir)


if __name__ == "__main__":
    main()
