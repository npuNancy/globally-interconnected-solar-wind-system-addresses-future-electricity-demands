# Continuous Optimization Validation Report

Generated: 2026-06-03 21:22:45

## Check Summary

| Check | Result | Details |
|-------|--------|---------|
| A. File Completeness | PASS | All 6 files present |
| B. Fraction Range (2050 opt_solar) | PASS | 2050 opt_solar: min=0.00e+00, max=0.997296 |
| B. Fraction Range (2050 opt_wind) | PASS | 2050 opt_wind: min=0.00e+00, max=0.994582 |
| B. Fraction Range (2040 opt_solar) | PASS | 2040 opt_solar: min=0.00e+00, max=0.995160 |
| B. Fraction Range (2040 opt_wind) | PASS | 2040 opt_wind: min=0.00e+00, max=0.983261 |
| B. Fraction Range (2030 opt_solar) | PASS | 2030 opt_solar: min=0.00e+00, max=0.980909 |
| B. Fraction Range (2030 opt_wind) | PASS | 2030 opt_wind: min=0.00e+00, max=0.982939 |
| C. Monotonicity (2030→2040 solar) | **FAIL** | violations=18, max excess=1.11e-01 |
| C. Monotonicity (2030→2040 wind) | **FAIL** | violations=254, max excess=1.94e-01 |
| C. Monotonicity (2040→2050 solar) | PASS | violations=0 |
| C. Monotonicity (2040→2050 wind) | PASS | violations=0 |
| D. Capacity Consistency (2050 solar) | PASS | max_rel_err=5.91e-16, mean_rel_err=1.00e-16, active_grids=5716 |
| D. Capacity Consistency (2050 wind) | PASS | max_rel_err=5.08e-16, mean_rel_err=9.71e-17, active_grids=6880 |
| D. Capacity Consistency (2040 solar) | PASS | max_rel_err=5.87e-16, mean_rel_err=9.96e-17, active_grids=5716 |
| D. Capacity Consistency (2040 wind) | PASS | max_rel_err=5.41e-16, mean_rel_err=9.63e-17, active_grids=6879 |
| D. Capacity Consistency (2030 solar) | PASS | max_rel_err=5.46e-16, mean_rel_err=1.01e-16, active_grids=5708 |
| D. Capacity Consistency (2030 wind) | PASS | max_rel_err=5.99e-16, mean_rel_err=9.86e-17, active_grids=6872 |
| E. H5-MAT Mapping (2050) | PASS | sol_idx=6/11, grids: MAT=12596, H5=12596, frac_sum: MAT=6297.90, H5=6297.90, sorted_max_diff=0.00e+00 |
| E. H5-MAT Mapping (2040) | **FAIL** | sol_idx=1/1, grids: MAT=12595, H5=12596, frac_sum: MAT=3657.20, H5=3658.20 |
| E. H5-MAT Mapping (2030) | **FAIL** | sol_idx=1/1, grids: MAT=12580, H5=12582, frac_sum: MAT=2630.32, H5=2632.32 |
| F. Existing Capacity (2050) | PASS | solar: 0 region violations, wind: 0 region violations |
| F. Existing Capacity (2040) | **FAIL** | solar: 2 region violations, wind: 3 region violations | worst solar region=7 (actual=47.0 GW, existing=71.9 GW) | worst wind region=10 (actual=238.9 GW, existing=288.8 GW) |
| F. Existing Capacity (2030) | **FAIL** | solar: 3 region violations, wind: 5 region violations | worst solar region=6 (actual=114.7 GW, existing=147.5 GW) | worst wind region=10 (actual=196.7 GW, existing=288.8 GW) |

## Per-Year Statistics

| Year | Solar (GW) | Wind (GW) | Total (GW) | Active Solar | Active Wind | Partial Solar | Partial Wind | Mean Solar Frac | Mean Wind Frac |
|------|-----------|----------|-----------|-------------|------------|--------------|-------------|----------------|---------------|
| 2050 | 29225.9 | 4188.1 | 33414.0 | 5716 | 6880 | 5716 | 6880 | 0.499506 | 0.500396 |
| 2040 | 16977.1 | 2425.7 | 19402.8 | 5716 | 6879 | 5716 | 6879 | 0.290413 | 0.290333 |
| 2030 | 12099.8 | 1757.0 | 13856.8 | 5708 | 6872 | 5708 | 6872 | 0.208260 | 0.209775 |

## Per-Region Capacity

| Region | 2050 Solar (GW) | 2050 Wind (GW) | 2040 Solar (GW) | 2040 Wind (GW) | 2030 Solar (GW) | 2030 Wind (GW) |
|--------|----------------|---------------|----------------|---------------|----------------|---------------|
|  1 NA-East | 5637.1 | 576.8 | 3234.1 | 321.8 | 2251.0 | 224.4 |
|  2 NA-West | 1034.2 | 73.3 | 618.2 | 43.7 | 453.7 | 31.2 |
|  3 SA-North | 42.4 | 18.5 | 28.3 | 11.4 | 21.1 | 8.4 |
|  4 SA-South | 3136.4 | 455.1 | 1783.7 | 272.4 | 1265.9 | 198.5 |
|  5 EU-West | 149.0 | 139.9 | 96.4 | 78.0 | 71.9 | 54.1 |
|  6 EU-East | 283.9 | 116.8 | 164.2 | 64.4 | 114.7 | 53.6 |
|  7 Africa-North | 82.6 | 71.3 | 47.0 | 40.2 | 43.7 | 32.6 |
|  8 Africa-South | 915.2 | 591.2 | 571.4 | 333.5 | 425.4 | 235.4 |
|  9 ME-Central | 2443.9 | 239.5 | 1391.8 | 138.6 | 975.4 | 98.2 |
| 10 China-East | 2827.8 | 416.3 | 1649.5 | 238.9 | 1178.2 | 196.7 |
| 11 China-West | 2532.3 | 245.9 | 1367.2 | 144.0 | 950.4 | 102.1 |
| 12 S-Asia | 2733.1 | 314.5 | 1667.0 | 190.3 | 1204.6 | 138.3 |
| 13 SE-Asia | 95.6 | 54.7 | 55.0 | 31.2 | 38.4 | 21.3 |
| 14 Japan-Korea | 0.9 | 1.7 | 0.3 | 1.0 | 0.1 | 0.5 |
| 15 Russia-West | 544.2 | 176.1 | 279.7 | 106.6 | 187.2 | 66.5 |
| 16 Russia-East | 3152.7 | 244.3 | 1852.0 | 139.5 | 1325.1 | 99.8 |
| 17 Oceania | 1015.3 | 152.9 | 572.2 | 91.8 | 411.7 | 65.4 |
| 18 C-America | 462.4 | 18.8 | 291.9 | 10.4 | 216.2 | 7.4 |
| 19 C-Asia | 1076.3 | 108.3 | 647.0 | 59.7 | 475.4 | 41.8 |
| 20 Others | 1060.6 | 172.0 | 660.3 | 108.2 | 489.9 | 80.6 |

## Cross-Year Monotonicity

### 2030→2040

- Solar violations: 18
- Solar max negative diff: 1.11e-01
- Wind violations: 254
- Wind max negative diff: 1.94e-01

### 2040→2050

- Solar violations: 0
- Wind violations: 0

## H5-to-Sel.mat Mapping

### 2050

- Solution index (MATLAB 1-based): 6
- H5 solutions count: 11
- Active grids (Sel.mat): solar=5716, wind=6880
- Active fractions (H5 vector): 12596
- Fraction sum (Sel.mat): 6297.8980
- Fraction sum (H5 vector): 6297.8980
- Sorted fraction max abs diff: 0.00e+00

### 2040

- Solution index (MATLAB 1-based): 1
- H5 solutions count: 1
- Active grids (Sel.mat): solar=5716, wind=6879
- Active fractions (H5 vector): 12596
- Fraction sum (Sel.mat): 3657.1999
- Fraction sum (H5 vector): 3658.1999

### 2030

- Solution index (MATLAB 1-based): 1
- H5 solutions count: 1
- Active grids (Sel.mat): solar=5708, wind=6872
- Active fractions (H5 vector): 12582
- Fraction sum (Sel.mat): 2630.3198
- Fraction sum (H5 vector): 2632.3198

## Existing Capacity Constraint

| Year | Solar Actual (GW) | Solar Existing (GW) | Solar OK? | Wind Actual (GW) | Wind Existing (GW) | Wind OK? |
|------|-------------------|--------------------|-----------|-----------------|--------------------|----------|
| 2050 | 29225.9 | 1415.5 | Yes | 4188.1 | 799.5 | Yes |
| 2040 | 16977.1 | 1415.5 | **No** | 2425.7 | 799.5 | **No** |
| 2030 | 12099.8 | 1415.5 | **No** | 1757.0 | 799.5 | **No** |

## Per-Region Existing Capacity Check

| Region | Existing Solar (GW) | 2030 Solar (GW) | 2040 Solar (GW) | 2050 Solar (GW) | Existing Wind (GW) | 2030 Wind (GW) | 2040 Wind (GW) | 2050 Wind (GW) |
|--------|--------------------|----------------|----------------|----------------|-------------------|---------------|---------------|---------------|
|  1 NA-East | 143.6 | 2251.0 | 3234.1 | 5637.1 | 165.0 | 224.4 | 321.8 | 576.8 |
|  2 NA-West | 12.8 | 453.7 | 618.2 | 1034.2 | 8.6 | 31.2 | 43.7 | 73.3 |
|  3 SA-North | 13.4 | 21.1 | 28.3 | 42.4 | 10.9 | 8.4 | 11.4 | 18.5 |
|  4 SA-South | 49.1 | 1265.9 | 1783.7 | 3136.4 | 39.8 | 198.5 | 272.4 | 455.1 |
|  5 EU-West | 27.2 | 71.9 | 96.4 | 149.0 | 54.8 | 54.1 | 78.0 | 139.9 |
|  6 EU-East | 147.5 | 114.7 | 164.2 | 283.9 | 76.5 | 53.6 | 64.4 | 116.8 |
|  7 Africa-North | 71.9 | 43.7 | 47.0 | 82.6 | 44.9 | 32.6 | 40.2 | 71.3 |
|  8 Africa-South | 40.2 | 425.4 | 571.4 | 915.2 | 18.4 | 235.4 | 333.5 | 591.2 |
|  9 ME-Central | 1.6 | 975.4 | 1391.8 | 2443.9 | 1.4 | 98.2 | 138.6 | 239.5 |
| 10 China-East | 734.2 | 1178.2 | 1649.5 | 2827.8 | 288.8 | 196.7 | 238.9 | 416.3 |
| 11 China-West | 29.6 | 950.4 | 1367.2 | 2532.3 | 13.4 | 102.1 | 144.0 | 245.9 |
| 12 S-Asia | 74.0 | 1204.6 | 1667.0 | 2733.1 | 47.2 | 138.3 | 190.3 | 314.5 |
| 13 SE-Asia | 25.7 | 38.4 | 55.0 | 95.6 | 6.9 | 21.3 | 31.2 | 54.7 |
| 14 Japan-Korea | 0.3 | 0.1 | 0.3 | 0.9 | 0.1 | 0.5 | 1.0 | 1.7 |
| 15 Russia-West | 33.0 | 187.2 | 279.7 | 544.2 | 14.0 | 66.5 | 106.6 | 176.1 |
| 16 Russia-East | 3.1 | 1325.1 | 1852.0 | 3152.7 | 4.0 | 99.8 | 139.5 | 244.3 |
| 17 Oceania | 0.9 | 411.7 | 572.2 | 1015.3 | 0.3 | 65.4 | 91.8 | 152.9 |
| 18 C-America | 0.4 | 216.2 | 291.9 | 462.4 | 0.0 | 7.4 | 10.4 | 18.8 |
| 19 C-Asia | 1.2 | 475.4 | 647.0 | 1076.3 | 0.9 | 41.8 | 59.7 | 108.3 |
| 20 Others | 5.8 | 489.9 | 660.3 | 1060.6 | 3.4 | 80.6 | 108.2 | 172.0 |
