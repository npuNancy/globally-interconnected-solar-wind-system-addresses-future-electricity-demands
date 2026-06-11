# Net_Area 与 Fishnet_Area 文件说明

优化器中有四组"净可用面积占比 + 格网面积"文件，风电和光伏各一对，逻辑完全对称。


| 文件 | 标称含义 | 实际内容 | 数据类型 | 值域 | 是否正确 |
|---|---|---|---|---|---|
| `Global_Wind_Net_Area_Add_Egrid.tif` | 风电适宜性 | 风电适宜性百分比 | float64 | 0~100 | ✅ |
| `Global_Wind_Fishnet_Area.tif` | 风电格网面积 | 格网面积 (km²) | float64 | 104.7~11838 | ✅ |
| `Global_Solar_Net_Area_Add_Egrid.tif` | 光伏适宜性 | 光伏适宜性百分比 | float64 | 0~100 | ✅ |
| `Global_Solar_Fishnet_Area.tif` | 光伏格网面积 | **格网编号（非面积）** | uint32 | 1551~43191 | **❌ 错误** (已修复) |
## 1. 风电

### Global_Wind_Net_Area_Add_Egrid.tif

- **含义**：每个 1°×1° 格网中可用于风电部署的**净陆地面积占比**（百分比）
- **值域**：0~100
- **来源**：ArcGIS 将 LUCC（土地利用/覆盖）与电网覆盖叠加分析得到
- **用途**：在优化器中除以 100 后，大于 0 的格网被选为风电候选场站

### Global_Wind_Fishnet_Area.tif

- **含义**：每个 1°×1° 格网的总面积（km²）
- **数据类型**：float64
- **值域**：104.7 ~ 11838 km²
- **来源**：ArcGIS fishnet 生成
- **验证**：与 `fishnet_area_global.tif` 的相关系数为 1.0，数据正确

### 在 Optimization\* 中的使用方式

```matlab
luccs = geotiffread('Global_Wind_Net_Area_Add_Egrid.tif');
luccs = luccs / 100;
win_index = find(luccs > 0);          % 风电候选格网

fish_area = geotiffread('Global_Wind_Fishnet_Area.tif');
fish_area = double(fish_area);
areas = luccs(win_index) .* fish_area(win_index);   % 实际可装机面积 (km²)
```

## 2. 光伏

### Global_Solar_Net_Area_Add_Egrid.tif

- **含义**：每个 1°×1° 格网中可用于光伏部署的**净陆地面积占比**（百分比）
- **值域**：0~100
- **来源**：ArcGIS 将 LUCC 与电网覆盖叠加分析得到
- **用途**：与 `Global_fishnet.tif` 配合确定光伏候选格网，再乘以格网面积得到可装机面积

### Global_Solar_Fishnet_Area.tif

> **<span style="color:red">⚠️ 严重错误：此文件名暗示存储的是面积（Area），但经逐像素比对，其实际内容与 Global_fishnet.tif 完全相同（max diff = 0），存储的是格网编号（uint32，1551~43191 + NoData 65536），并非面积（km²）。</span>**
>
> **<span style="color:red">正确的面积文件应类似 Global_Wind_Fishnet_Area.tif（float64，值域 104.7~11838 km²）或 fishnet_area_global.tif（float32，值域 108.8~12311.5 km²）。</span>**

### 在 Optimization\* 中的使用方式

```matlab
grids = geotiffread('Global_fishnet.tif');
solar_index = find(grids < 65536);     % 光伏候选格网（排除海洋、格陵兰、南极洲）

luccs = geotiffread('Global_Solar_Net_Area_Add_Egrid.tif');
luccs = luccs / 100;

fish_area = geotiffread('Global_Solar_Fishnet_Area.tif');  % ← 读到的是格网编号，不是面积！
fish_area(fish_area < 0) = 0;
fish_area = double(fish_area);
areas = luccs(solar_index) .* fish_area(solar_index);       % ← 适宜性 × 格网编号 = 错误的面积
```

### 对优化结果的影响

**光伏可用面积被系统性高估：**

| 指标 | 错误值（使用格网编号） | 正确值（使用实际面积） | 偏差 |
|---|---|---|---|
| 全球光伏可用面积总计 | 4,995,196 km² | 1,776,221 km² | **2.81 倍** |
| 格网编号 / 实际面积 比值 | — | — | 0.31× ~ 6.83×（中位数 2.89×） |

由于光伏装机量 = 装机密度 × 可用面积，面积被高估约 2.81 倍会直接导致：
- 光伏装机量（GW）被高估
- 光伏发电量（TWh）被高估
- 优化结果中光伏选址对应的实际发电能力低于计算值

### 修复方案

将 `Global_Solar_Fishnet_Area.tif` 替换为正确的面积数据（即 `fishnet_area_global.tif` 或与 `Global_Wind_Fishnet_Area.tif` 同源的面积文件），或修改代码直接使用 `Global_Wind_Fishnet_Area.tif`（两者覆盖的格网一致）。

## 3. 核心公式

```
实际可装机面积 (km²) = Net_Area占比 × Fishnet_Area (km²)
                     = (luccs / 100) × fish_area
```


