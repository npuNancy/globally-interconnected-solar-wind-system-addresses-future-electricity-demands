#!/usr/bin/env python3
"""
汇总三个 SSP 成本最小化优化的诊断输出。

读取：
  Optimization_ssp126/results/Optimization_SC_2050_metrics.mat
  Optimization_ssp126/results/Optimization_SC_2040_metrics.mat
  Optimization_ssp126/results/Optimization_SA_2030_metrics.mat
  （以及 ssp245、ssp560 对应文件）

输出：
  results/SSPs_2050_diagnostics.csv
  results/SSPs_all_years_diagnostics.csv
  results/SSPs_优化结果汇总_诊断增强版.md
"""

import os
import numpy as np
import scipy.io as sio
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent

SSP_DIRS = {
    'SSP1-2.6': PROJECT_ROOT / 'Optimization_ssp126',
    'SSP2-4.5': PROJECT_ROOT / 'Optimization_ssp245',
    'SSP5-6.0': PROJECT_ROOT / 'Optimization_ssp560',
}

YEARS = {
    2050: {'prefix': 'SC', 'suffix': '2050'},
    2040: {'prefix': 'SC', 'suffix': '2040'},
    2030: {'prefix': 'SA', 'suffix': '2030'},
}

DIAG_LABELS = {
    'pv_capacity_gw': '光伏装机容量 (GW)',
    'wind_capacity_gw': '风电装机容量 (GW)',
    'onshore_wind_capacity_gw': '陆上风电装机容量 (GW)',
    'offshore_wind_capacity_gw': '海上风电装机容量 (GW)',
    'total_vre_capacity_gw': 'VRE 总装机容量 (GW)',
    'selected_pv_grid_count': '选中光伏格网数',
    'selected_wind_grid_count': '选中风电格网数',
    'gross_pv_generation_twh': '光伏原始发电量 (TWh)',
    'gross_wind_generation_twh': '风电原始发电量 (TWh)',
    'gross_vre_generation_twh': '原始风光发电量 (TWh)',
    'gross_vre_share': '原始风光发电占比',
    'base_load_twh': '基荷发电量 (TWh)',
    'flexible_generation_twh': '灵活电源发电量 (TWh)',
    'residual_vre_service_twh': 'VRE 剩余负荷服务等价值 (TWh)',
    'curtailed_vre_twh': '弃电量 (TWh)',
    'curtailment_rate': '弃电率',
    'total_load_twh': '总负荷 (TWh)',
    'transmission_capacity_tw': '输电容量 (TW)',
    'vre_share': 'VRE 渗透率 (残差定义)',
    'flexible_ratio': '灵活电源比例',
    'total_annual_cost': '年度总成本 (billion USD/year)',
}


def load_mat(ssp_dir, year):
    """加载 sidecar MAT 文件并提取诊断数据。"""
    info = YEARS[year]
    mat_file = ssp_dir / 'results' / f'Optimization_{info["prefix"]}_{info["suffix"]}_metrics.mat'
    if not mat_file.exists():
        return None

    m = sio.loadmat(str(mat_file), squeeze_me=True)

    result = {
        'ssp': ssp_dir.name.replace('Optimization_', ''),
        'year': year,
        'mode': f'{info["prefix"]}-{info["suffix"]}',
    }

    # 从 diag_names / diag_values 提取
    if 'diag_names' in m and 'diag_values' in m:
        names = m['diag_names']
        values = m['diag_values']
        if hasattr(names, '__iter__'):
            for i, n in enumerate(names):
                name = n.strip() if isinstance(n, str) else str(n).strip()
                result[name] = float(values[i]) if i < len(values) else np.nan

    # exitflag
    if 'exitflag' in m:
        result['exitflag'] = int(np.squeeze(m['exitflag']))
    else:
        result['exitflag'] = np.nan

    # scenario_cfg
    if 'scenario_cfg' in m:
        sc = m['scenario_cfg']
        if isinstance(sc, np.ndarray) and sc.dtype.names:
            sc = sc.item()
        if hasattr(sc, 'dtype') and sc.dtype.names:
            for field in sc.dtype.names:
                val = sc[field]
                if isinstance(val, np.ndarray):
                    val = val.item() if val.size == 1 else val
                result[f'scenario_{field}'] = val

    # best_cost
    if 'best_cost' in m:
        result['best_cost'] = float(np.squeeze(m['best_cost']))

    return result


def results_to_csv(rows):
    """将结果列表转为 CSV 字符串。"""
    if not rows:
        return ''
    # 收集所有键
    keys = []
    for r in rows:
        for k in r:
            if k not in keys:
                keys.append(k)

    lines = [','.join(keys)]
    for r in rows:
        vals = []
        for k in keys:
            v = r.get(k, '')
            if isinstance(v, float):
                vals.append(f'{v:.6f}')
            elif isinstance(v, (np.floating, np.integer)):
                vals.append(f'{float(v):.6f}')
            else:
                vals.append(str(v))
        lines.append(','.join(vals))
    return '\n'.join(lines)


def write_markdown(rows_2050, rows_all, output_path):
    """生成增强版 Markdown 汇总。"""
    lines = ['# SSPs 成本最小化优化结果汇总（诊断增强版）\n']

    # ---- 2050 年对比 ----
    lines.append('## 2050 年三情景对比\n')
    if rows_2050:
        lines.append('| 指标 | ' + ' | '.join(r['ssp'] for r in rows_2050) + ' |')
        lines.append('|---|' + '|'.join(['---:'] * len(rows_2050)) + '|')

        for key, label in DIAG_LABELS.items():
            vals = []
            for r in rows_2050:
                v = r.get(key, np.nan)
                if isinstance(v, (int, np.integer)):
                    vals.append(f'{int(v)}')
                elif isinstance(v, float) or isinstance(v, (np.floating,)):
                    if abs(v) >= 100:
                        vals.append(f'{v:,.2f}')
                    else:
                        vals.append(f'{v:.4f}')
                else:
                    vals.append(str(v))
            lines.append(f'| {label} | ' + ' | '.join(vals) + ' |')

        # exitflag
        vals = [str(r.get('exitflag', 'N/A')) for r in rows_2050]
        lines.append(f'| GA exitflag | ' + ' | '.join(vals) + ' |')
    else:
        lines.append('（无可用数据）\n')

    lines.append('')

    # ---- 全年度汇总 ----
    lines.append('## 全年度汇总\n')
    if rows_all:
        lines.append('| SSP | 年份 | 光伏装机 (GW) | 风电装机 (GW) | 原始风光发电占比 | 弃电率 | VRE 渗透率 | 年度成本 (B$/yr) | exitflag |')
        lines.append('|---|---:|---:|---:|---:|---:|---:|---:|---:|')
        for r in rows_all:
            lines.append(
                f'| {r["ssp"]} | {r["year"]} '
                f'| {r.get("pv_capacity_gw", np.nan):,.2f} '
                f'| {r.get("wind_capacity_gw", np.nan):,.2f} '
                f'| {r.get("gross_vre_share", np.nan):.4f} '
                f'| {r.get("curtailment_rate", np.nan):.4f} '
                f'| {r.get("vre_share", np.nan):.4f} '
                f'| {r.get("total_annual_cost", np.nan):,.2f} '
                f'| {r.get("exitflag", "N/A")} |'
            )
    else:
        lines.append('（无可用数据）\n')

    lines.append('')
    lines.append('---')
    lines.append('*由 summarize_costmin_results.py 自动生成*\n')

    with open(output_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))


def main():
    results_dir = PROJECT_ROOT / 'results'
    results_dir.mkdir(exist_ok=True)

    all_rows = []
    rows_2050 = []

    for ssp_name, ssp_dir in SSP_DIRS.items():
        for year in [2050, 2040, 2030]:
            row = load_mat(ssp_dir, year)
            if row is not None:
                row['ssp'] = ssp_name
                all_rows.append(row)
                if year == 2050:
                    rows_2050.append(row)
            else:
                print(f'  跳过：{ssp_name} {year} 年结果不存在')

    # CSV 输出
    csv_2050 = results_dir / 'SSPs_2050_diagnostics.csv'
    with open(csv_2050, 'w') as f:
        f.write(results_to_csv(rows_2050))
    print(f'已保存: {csv_2050}')

    csv_all = results_dir / 'SSPs_all_years_diagnostics.csv'
    with open(csv_all, 'w') as f:
        f.write(results_to_csv(all_rows))
    print(f'已保存: {csv_all}')

    # Markdown 输出
    md_path = results_dir / 'SSPs_优化结果汇总_诊断增强版.md'
    write_markdown(rows_2050, all_rows, md_path)
    print(f'已保存: {md_path}')


if __name__ == '__main__':
    main()
