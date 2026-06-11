# Global_Solar_Fishnet_Area.tif 修复计划

## 1. 问题描述

`Global_Solar_Fishnet_Area.tif` 文件名暗示存储的是格网面积（km²），但实际内容是**格网编号**（uint32，1551~43191），与 `Global_fishnet.tif` 完全相同。这导致优化器中光伏可用面积被系统性高估约 **2.81 倍**。

## 2. 可用数据源分析

| 文件 | 路径 | dtype | 值域 (km²) | NoData | 状态 |
|---|---|---|---|---|---|
| `fishnet_area_global.tif` | `GlobalPotential/` | float32 | 108.84 ~ 12311.47 | -3.4e38 | 正确 |
| `Global_Wind_Fishnet_Area.tif` | 各 `Optimization*/` | float64 | 104.65 ~ 11837.95 | None | 正确 |
| `Global_Solar_Fishnet_Area.tif` | 各 `Optimization*/` | uint32 | 1551 ~ 43191 | 65536 | **错误（格网编号）** |

两个正确文件的相关系数为 1.0，但存在最大 473.5 km² 的数值差异（可能因面积计算方法/精度不同）。

**推荐数据源：`Global_Wind_Fishnet_Area.tif`**，理由：
1. 与目标文件位于同一目录，格式一致（同 CRS、同 Transform）
2. 已被优化器验证正确（风电结果可信）
3. 格网面积与能源类型无关，同一格网的风电面积 = 光伏面积
4. NoData 处理安全：优化器通过 `solar_index = find(grids < 65536)` 筛选格网，不依赖 Fishnet_Area 的 NoData 值

## 3. 修复方案

### 方案 A（推荐）：直接复制 Wind 版本

将每个 `Optimization*/` 目录下的 `Global_Wind_Fishnet_Area.tif` 复制为 `Global_Solar_Fishnet_Area.tif`。

**优点**：简单、零风险、保持与风电数据一致。
**缺点**：丢失了原 Solar 文件的 NoData=65536 标记（Wind 版本 NoData=None），但优化器不依赖此标记，无影响。

### 方案 B：从 fishnet_area_global.tif 重新生成

读取 `GlobalPotential/fishnet_area_global.tif`，处理 NoData（将 -3.4e38 替换为 0），写入为 `Global_Solar_Fishnet_Area.tif`。

**优点**：使用基础数据源，独立于风电数据。
**缺点**：需要额外处理 NoData 和格式差异；与 Wind 版本数值不一致（最大差异 ~473 km²）。

### 方案 C：修改代码而非数据

在所有 MATLAB 优化脚本中，将 `geotiffread('Global_Solar_Fishnet_Area.tif')` 改为 `geotiffread('Global_Wind_Fishnet_Area.tif')`。

**优点**：不修改数据文件。
**缺点**：需修改约 30 个源文件（含 Python 后处理、MATLAB 优化、MATLAB 韧性分析），维护成本高且易遗漏。

## 4. 推荐执行步骤（方案 A）

### 步骤 1：备份原始错误文件

```bash
for dir in Optimization Optimization_ssp126 Optimization_ssp245 Optimization_ssp560 Optimization_ssp126_test_continuous; do
    cp "${dir}/Global_Solar_Fishnet_Area.tif" "${dir}/Global_Solar_Fishnet_Area.tif.bak"
    cp "${dir}/Global_Solar_Fishnet_Area.mat" "${dir}/Global_Solar_Fishnet_Area.mat.bak"
done
```

### 步骤 2：用 Wind 版本替换 Solar 版本（.tif 和 .mat 均直接复制）

Wind 和 Solar 的 `.mat` 文件结构完全一致（key=`'data'`，shape=`(180, 360)`），可直接复制。

```bash
for dir in Optimization Optimization_ssp126 Optimization_ssp245 Optimization_ssp560 Optimization_ssp126_test_continuous; do
    cp "${dir}/Global_Wind_Fishnet_Area.tif" "${dir}/Global_Solar_Fishnet_Area.tif"
    cp "${dir}/Global_Wind_Fishnet_Area.mat" "${dir}/Global_Solar_Fishnet_Area.mat"
done
```

### 步骤 3：验证修复

对比替换后的 `Global_Solar_Fishnet_Area.tif` 与 `Global_Wind_Fishnet_Area.tif`：
- 确认值域为 104.65 ~ 11837.95 km²（而非 1551 ~ 43191）
- 确认 dtype 为 float64（而非 uint32）
- 确认光伏可用面积总和 ≈ 1,776,221 km²（而非错误的 4,995,196 km²）

### 步骤 4：评估是否需要重新运行优化

修复后所有已运行的优化结果（Pareto 前沿、装机方案）中光伏部分均受此 bug 影响。需根据研究进度判断是否需要重新运行优化。

## 5. 受影响的目录

| 目录 | .tif | .mat |
|---|---|---|
| `Optimization/` | 需替换 | 需替换 |
| `Optimization_ssp126/` | 需替换 | 需替换 |
| `Optimization_ssp245/` | 需替换 | 需替换 |
| `Optimization_ssp560/` | 需替换 | 需替换 |
| `Optimization_ssp126_test_continuous/` | 需替换 | 需替换 |

## 6. 受影响的下游代码

以下代码读取 `Global_Solar_Fishnet_Area.{tif,mat}`，修复数据后**无需修改代码**，重新运行即可得到正确结果：

- **MATLAB 优化脚本**：各 `Optimization*/Optimization_{SA,SC,SG}_*.m`
- **MATLAB 转换脚本**：各 `Optimization*/convert_h5_to_sel.m`
- **MATLAB 韧性分析**：`Resilience/Resilience_*.m`、`Benefits/Smoothing_Effects.m`
- **Python 后处理**：`plot_optimal_stations.py`、`calc_capacity_from_optimization.py`、`solar_wind_optimization_viz.ipynb`
