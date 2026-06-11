# 代码撰写 Plan：生成 `Global_fishnet.tif` 与 `Global_LandMask.tif`

## 0. 目标

新增两个 Python 文件：

```text
S02E01_Global_fishnet.py
S02E02_Global_LandMask.py
```

两者都使用 Python package：

```text
global-land-mask
```

安装方式：

```bash
pip install global-land-mask rasterio numpy
```

统一使用 `global_land_mask.globe.is_land()` 获取海陆掩码。

本计划生成的是一套**可复现的简化替代版本**，用于兼容原仓库的 MATLAB 读取逻辑。它不要求和原始 ArcGIS 产物逐像元完全一致。

---

## 0.1 本版修改：新输出改为全球 0.1° × 0.1° 网格

上传的两个原始 GeoTIFF 仍然是论文仓库中的全球 `1° × 1°` 参考文件。
本版脚本不再生成 `180 × 360` 网格，而是生成：

```text
全球 0.1° × 0.1° 网格
height = 1800
width  = 3600
```

经纬度边界保持不变：

```text
经度：[-180, 180]
纬度：[-90, 90]
```

像元中心改为：

```text
经度中心：-179.95, -179.85, ..., 179.85, 179.95
纬度中心：  89.95,   89.85, ..., -89.85, -89.95
```

`0.1°` 在赤道附近约为 `11 km`。由于经线间距随纬度升高而缩短，
它不是严格等距的 `10 km × 10 km` 投影网格。

---

# 1. 已上传原始 TIF 的参考信息

对原仓库中的两个 `1° × 1°` GeoTIFF 进行检查后，可将其作为空间范围、编码约定和下游兼容性的参考。新脚本的目标分辨率为 `0.1° × 0.1°`，因此不会与原始文件具有相同栅格大小。

## 1.1 原始 `Global_fishnet.tif`

| 属性 | 值 |
|---|---|
| 栅格大小 | `180 × 360` |
| 空间范围 | `[-180, 180] × [-90, 90]` |
| 分辨率 | `1° × 1°` |
| 数据类型 | `uint32` |
| NoData | `65536` |
| 有效格网判断 | `< 65536` |
| 原始有效格网数 | `13296` |
| 原始无效格网数 | `51504` |

原文件中的有效格网具有不同编号，但下游 MATLAB 代码只使用：

```matlab
solar_index = find(grids < 65536);
```

因此，新文件不需要复刻原始编号。统一令：

```text
有效陆地格网 = 0
无效格网     = 65536
```

即可满足下游筛选逻辑。

## 1.2 原始 `Global_LandMask.tif`

| 属性 | 值 |
|---|---|
| 栅格大小 | `180 × 360` |
| 空间范围 | `[-180, 180] × [-90, 90]` |
| 分辨率 | `1° × 1°` |
| 数据类型 | `uint8` |
| NoData | `255` |
| 原始陆地判断 | `< 100` |
| 原始海洋判断 | `> 100` |
| 原始陆地格网数 | `15390` |
| 原始海洋 / NoData 格网数 | `49410` |

原仓库 MATLAB 代码使用：

```matlab
landmask(landmask < 100) = 0;
landmask(landmask > 100) = 1;
```

因此，新文件建议统一令：

```text
陆地 = 0
海洋 = 255
```

不要使用：

```text
陆地 = 1
海洋 = 0
```

也不要使用：

```text
陆地 = 0
海洋 = 1
```

否则会破坏原仓库中基于 `<100` 与 `>100` 的判断逻辑。


## 1.3 原始 TIF 的经度范围核验

已使用 `rasterio` 读取上传的两个原始 GeoTIFF 元数据。

### `Global_fishnet.tif`

```text
width  = 360
height = 180
transform =
| 1.00,  0.00, -180.00 |
| 0.00, -1.00,   90.00 |
| 0.00,  0.00,    1.00 |

bounds =
left   = -180.0
right  =  180.0
bottom =  -90.0
top    =   90.0
```

### `Global_LandMask.tif`

```text
width  = 360
height = 180
transform =
| 1.00,  0.00, -180.00 |
| 0.00, -1.00,   90.00 |
| 0.00,  0.00,    1.00 |

bounds =
left   = -180.0
right  =  180.0
bottom =  -90.0
top    =   90.0
```

结论：

```text
两个原始文件的经度范围都是 [-180, 180]
不是 [0, 360]
```

对应的 1° 像元中心为：

```text
经度中心：-179.5, -178.5, ..., 178.5, 179.5
纬度中心：  89.5,   88.5, ..., -88.5, -89.5
```

注意：

- 原始 `Global_LandMask.tif` 带有 `EPSG:4326`；
- 原始 `Global_fishnet.tif` 的 CRS 元数据为空，但其仿射变换和边界仍明确对应 `[-180, 180] × [-90, 90]`；
- 新生成的两个文件建议都显式写入：

```python
crs = "EPSG:4326"
```

这样可以避免后续 GIS 软件对 `Global_fishnet.tif` 的空间参考产生歧义。


---

# 2. 统一空间网格

两个脚本必须使用完全相同的全球 0.0.1° 网格。

## 2.1 网格定义

栅格大小：

```python
height = 1800
width = 3600
```

像元边界：

```text
经度：[-180, 180]
纬度：[-90, 90]
```

该范围已经通过上传的两个原始 TIF 元数据核验。不要改成：

```text
[0, 360]
```

像元中心：

```python
lons = -180.0 + (np.arange(3600, dtype=np.float64) + 0.5) * 0.1
lats =   90.0 - (np.arange(1800, dtype=np.float64) + 0.5) * 0.1
```

注意纬度必须从北向南排列，以匹配 GeoTIFF 的行顺序。

构造二维中心点：

```python
lon_grid, lat_grid = np.meshgrid(lons, lats)
```

调用：

```python
from global_land_mask import globe

is_land = globe.is_land(lat_grid, lon_grid)
```

`is_land` 的形状必须是：

```python
(1800, 3600)
```

数据类型通常为：

```python
bool
```

## 2.2 GeoTIFF 地理参考

输出数组规模：

| 文件 | 数据类型 | 数组形状 | 未压缩数组约占内存 |
|---|---|---:|---:|
| `Global_fishnet.tif` | `uint32` | `1800 × 3600` | `24.7 MiB` |
| `Global_LandMask.tif` | `uint8` | `1800 × 3600` | `6.2 MiB` |

构造 `lat_grid` 和 `lon_grid` 时会额外占用内存。应避免创建不必要的重复数组。

使用：

```python
from rasterio.transform import from_origin

transform = from_origin(
    west=-180.0,
    north=90.0,
    xsize=0.1,
    ysize=0.1,
)
```

CRS：

```python
crs = "EPSG:4326"
```

两个脚本必须写出一致的：

```text
width
height
transform
crs
```

---

# 3. 文件一：`S02E01_Global_fishnet.py`

## 3.1 功能

生成：

```text
Global_fishnet.tif
```

用途：

```matlab
solar_index = find(grids < 65536);
```

本脚本输出的是**光伏候选陆地格网掩膜**，不是原 ArcGIS fishnet 编号。

## 3.2 输出编码

| 区域 | 输出值 |
|---|---:|
| 普通陆地 | `0` |
| 海洋 | `65536` |
| 格陵兰 | `65536` |
| 南极洲 | `65536` |

数据类型：

```python
np.uint32
```

NoData：

```python
65536
```

## 3.3 基本算法

```python
is_land = globe.is_land(lat_grid, lon_grid)

fishnet = np.full(is_land.shape, 65536, dtype=np.uint32)
fishnet[is_land] = 0
```

然后额外排除：

```text
Antarctica
Greenland
```

最终：

```python
fishnet[antarctica_mask] = 65536
fishnet[greenland_mask] = 65536
```

## 3.4 南极洲排除规则

只使用经纬度即可稳定处理：

```python
antarctica_mask = lat_grid <= -60.0
```

然后：

```python
fishnet[antarctica_mask] = 65536
```

说明：

- 该规则会把南纬 60° 以南全部设为无效；
- 对海洋像元没有副作用，因为海洋本来就是 `65536`；
- 对陆地像元可以完整排除南极洲；
- 该规则清晰、可复现，不依赖额外矢量文件。

## 3.5 格陵兰排除规则

仅使用 `global-land-mask` 时，不能直接获得国家边界。因此，不建议用一个宽泛矩形直接排除，否则可能误伤加拿大北极群岛或冰岛。

推荐使用：

```text
限定范围 + 连通域洪泛
```

### 3.5.1 限定范围

```python
greenland_bbox = (
    (lat_grid >= 59.0)
    & (lat_grid <= 84.0)
    & (lon_grid >= -74.0)
    & (lon_grid <= -10.0)
)
```

### 3.5.2 候选格网

```python
greenland_candidates = is_land & greenland_bbox
```

### 3.5.3 从格陵兰内部种子点做四邻域洪泛

选择远离海岸的种子点：

```python
seed_lat = 72.5
seed_lon = -40.5
```

在 0.1° 网格中找到最近格点，从该格点开始，仅在：

```python
greenland_candidates
```

中进行四邻域 BFS 或 DFS。

四邻域：

```text
上、下、左、右
```

不要使用八邻域，避免跨越狭窄海峡误连到其他岛屿。

返回：

```python
greenland_mask
```

然后：

```python
fishnet[greenland_mask] = 65536
```

### 3.5.4 防御性检查

必须检查：

```python
assert greenland_candidates[seed_row, seed_col]
```

否则抛出清晰错误：

```text
Greenland seed point is not classified as land by global-land-mask.
```

同时打印：

```text
Greenland excluded cells: N
```

便于审查。

## 3.6 建议函数拆分

```python
def build_global_0p1deg_centers() -> tuple[np.ndarray, np.ndarray]:
    ...

def flood_fill_4_connected(mask: np.ndarray, seed_row: int, seed_col: int) -> np.ndarray:
    ...

def build_greenland_mask(
    is_land: np.ndarray,
    lat_grid: np.ndarray,
    lon_grid: np.ndarray,
) -> np.ndarray:
    ...

def build_antarctica_mask(lat_grid: np.ndarray) -> np.ndarray:
    ...

def build_global_fishnet(
    is_land: np.ndarray,
    lat_grid: np.ndarray,
    lon_grid: np.ndarray,
) -> np.ndarray:
    ...

def write_geotiff(
    output_path: Path,
    data: np.ndarray,
    *,
    nodata: int,
    dtype: str,
) -> None:
    ...
```

## 3.7 CLI

```bash
python S02E01_Global_fishnet.py \
  --output Global_fishnet.tif
```

建议参数：

| 参数 | 默认值 | 含义 |
|---|---|---|
| `--output` | `Global_fishnet.tif` | 输出路径 |
| `--overwrite` | `False` | 是否覆盖已有文件 |
| `--print_stats` | `False` | 打印统计信息 |

## 3.8 统计输出

当启用：

```bash
--print_stats
```

打印：

```text
total cells
land cells before exclusion
ocean cells
Greenland excluded cells
Antarctica excluded cells
valid fishnet cells after exclusion
invalid fishnet cells after exclusion
```

---

# 4. 文件二：`S02E02_Global_LandMask.py`

## 4.1 功能

生成：

```text
Global_LandMask.tif
```

用途：

```matlab
landmask(landmask < 100) = 0;
landmask(landmask > 100) = 1;
```

下游借此区分：

```text
陆上风电
海上风电
```

## 4.2 输出编码

| 区域 | 输出值 |
|---|---:|
| 陆地 | `0` |
| 海洋 | `255` |

数据类型：

```python
np.uint8
```

NoData：

```python
255
```

说明：

- 这里沿用原文件“海洋值大于 100”的约定；
- 对格陵兰和南极洲不做额外排除；
- 它是正常海陆掩膜，而不是光伏候选掩膜。

## 4.3 算法

```python
is_land = globe.is_land(lat_grid, lon_grid)

landmask = np.full(is_land.shape, 255, dtype=np.uint8)
landmask[is_land] = 0
```

写出：

```text
Global_LandMask.tif
```

## 4.4 建议函数拆分

优先复用公共函数，避免两个脚本重复维护。

推荐新增：

```text
mask_utils.py
```

结构：

```text
mask_utils.py
S02E01_Global_fishnet.py
S02E02_Global_LandMask.py
```

`mask_utils.py` 中放：

```python
build_global_0p1deg_centers()
get_global_land_mask()
write_geotiff()
print_mask_stats()
```

`S02E01_Global_fishnet.py` 中放：

```python
build_greenland_mask()
build_antarctica_mask()
build_global_fishnet()
```

`S02E02_Global_LandMask.py` 中放：

```python
build_global_landmask()
```

如果项目明确只允许新增两个文件，也可以将少量公共函数分别复制到两个脚本中，但要保持完全一致。

## 4.5 CLI

```bash
python S02E02_Global_LandMask.py \
  --output Global_LandMask.tif
```

建议参数：

| 参数 | 默认值 | 含义 |
|---|---|---|
| `--output` | `Global_LandMask.tif` | 输出路径 |
| `--overwrite` | `False` | 是否覆盖已有文件 |
| `--print_stats` | `False` | 打印统计信息 |

---

# 5. 和原仓库 MATLAB 代码的兼容性

## 5.1 `Global_fishnet.tif`

原代码：

```matlab
grids = geotiffread('Global_fishnet.tif');
solar_index = find(grids < 65536);
```

新文件：

```text
陆地有效格网 = 0
其余格网     = 65536
```

因此：

```matlab
find(grids < 65536)
```

仍然可以正确取得有效陆地候选格网。

## 5.2 `Global_LandMask.tif`

原代码：

```matlab
landmask = readgeoraster('Global_LandMask.tif');
landmask(landmask < 100) = 0;
landmask(landmask > 100) = 1;
```

新文件：

```text
陆地 = 0
海洋 = 255
```

因此：

```text
陆地 → 0
海洋 → 1
```

仍然和原代码兼容。

---

# 6. 和原始 ArcGIS 产物的差异

## 6.1 不要求逐像元完全一致

新脚本基于：

```text
global-land-mask
```

而原始论文文件来自：

```text
ArcGIS 上游预处理
```

因此，不应要求：

```text
新文件 == 原始文件
```

逐像元完全相同。

## 6.2 需要明确的差异来源

可能包括：

1. `global-land-mask` 使用 GLOBE 数据构建海陆掩膜；
2. 原始 ArcGIS 流程可能使用 Natural Earth 海岸线、行政边界或 EEZ；
3. 两者对湖泊、沿海像元、小岛的处理可能不同；
4. 新 `Global_fishnet.tif` 显式排除了格陵兰和南极洲；
5. 原始 `Global_fishnet.tif` 还可能隐含其他筛选条件。

## 6.3 输出文件命名建议

为了避免覆盖原始文件，第一次运行建议输出：

```text
Global_fishnet_global_land_mask.tif
Global_LandMask_global_land_mask.tif
```

确认结果后，再决定是否使用正式文件名：

```text
Global_fishnet.tif
Global_LandMask.tif
```

---

# 7. 验收标准

## 7.1 两个文件的共同检查

```python
assert arr.shape == (1800, 3600)
assert transform == from_origin(-180.0, 90.0, 0.1, 0.1)
assert bounds.left == -180.0
assert bounds.right == 180.0
assert bounds.bottom == -90.0
assert bounds.top == 90.0
assert crs.to_string() == "EPSG:4326"
```

## 7.2 `S02E01_Global_fishnet.py`

```python
assert fishnet.dtype == np.uint32
assert set(np.unique(fishnet)) <= {0, 65536}
assert np.all(fishnet[lat_grid <= -60.0] == 65536)
assert np.all(fishnet[greenland_mask] == 65536)
```

GeoTIFF：

```python
with rasterio.open(output_path) as ds:
    assert ds.width == 3600
    assert ds.height == 1800
    assert ds.dtypes[0] == "uint32"
    assert ds.nodata == 65536
```

## 7.3 `S02E02_Global_LandMask.py`

```python
assert landmask.dtype == np.uint8
assert set(np.unique(landmask)) <= {0, 255}
assert np.all(landmask[is_land] == 0)
assert np.all(landmask[~is_land] == 255)
```

GeoTIFF：

```python
with rasterio.open(output_path) as ds:
    assert ds.width == 3600
    assert ds.height == 1800
    assert ds.dtypes[0] == "uint8"
    assert ds.nodata == 255
```

## 7.4 和上传原始文件对比

上传的原始参考文件为 `1° × 1°`，而新脚本输出为 `0.1° × 0.1°`。
因此不能直接逐像元比较。脚本应先将新生成的布尔分类按 `10 × 10`
窗口聚合回 `1° × 1°`，再进行诊断性比较。

推荐聚合规则：

```text
majority：一个 1° 参考格网内，至少 50% 的 0.1° 子格网有效，则聚合后判定为有效
```

该比较仅用于发现明显异常，不代表新文件必须复刻原始 ArcGIS 结果。

建议脚本可选增加：

```text
--reference
```

例如：

```bash
python S02E01_Global_fishnet.py \
  --output Global_fishnet_global_land_mask.tif \
  --reference Global_fishnet.tif \
  --print_stats

python S02E02_Global_LandMask.py \
  --output Global_LandMask_global_land_mask.tif \
  --reference Global_LandMask.tif \
  --print_stats
```

对比输出：

```text
generated valid cells
reference valid cells
same cells
different cells
generated-only valid cells
reference-only valid cells
agreement ratio
```

对于 `Global_LandMask.tif`：

```text
generated land cells
reference land-like cells (<100)
same cells
different cells
agreement ratio
```

不要把“不完全一致”直接视为报错，但必须打印统计信息。

---

# 8. 单元测试

建议新增：

```text
tests/
├── test_S02E01_Global_fishnet.py
└── test_S02E02_Global_LandMask.py
```

## 8.1 `test_S02E01_Global_fishnet.py`

覆盖：

1. 网格中心是 `89.95 → -89.95` 和 `-179.95 → 179.95`；
2. 输出形状为 `(1800, 3600)`；
3. 仅存在 `0` 和 `65536`；
4. 海洋全部为 `65536`；
5. 南纬 `60°` 以南全部为 `65536`；
6. 格陵兰洪泛区全部为 `65536`；
7. 普通大陆内部种子点为 `0`，例如：
   - 中国内陆；
   - 美国中部；
   - 欧洲大陆；
   - 非洲大陆；
   - 澳大利亚内陆；
8. 输出 GeoTIFF 元数据正确；
9. 默认不覆盖已有文件；
10. `--overwrite` 可覆盖已有文件。

## 8.2 `test_S02E02_Global_LandMask.py`

覆盖：

1. 输出形状为 `(1800, 3600)`；
2. 仅存在 `0` 和 `255`；
3. 陆地全部为 `0`；
4. 海洋全部为 `255`；
5. 格陵兰和南极仍按照正常海陆掩膜保留为陆地；
6. 输出 GeoTIFF 元数据正确；
7. 默认不覆盖已有文件；
8. `--overwrite` 可覆盖已有文件。

---

# 9. 推荐实现顺序

## 第一步：完成共用网格定义

实现：

```python
build_global_0p1deg_centers()
```

检查：

```text
shape = (1800, 3600)
```

## 第二步：完成 `S02E02_Global_LandMask.py`

该脚本最简单，只需要：

```text
global-land-mask → 0 / 255 → GeoTIFF
```

先用它验证：

```text
网格方向
GeoTIFF transform
CRS
global-land-mask 调用
```

## 第三步：完成 `S02E01_Global_fishnet.py`

在正常海陆掩膜基础上增加：

```text
南极洲排除
格陵兰洪泛排除
```

输出：

```text
0 / 65536
```

## 第四步：运行原文件对比

打印：

```text
有效格网数
差异格网数
一致率
```

## 第五步：验证 MATLAB 兼容性

最小验证：

```matlab
grids = geotiffread('Global_fishnet_global_land_mask.tif');
solar_index = find(grids < 65536);

landmask = readgeoraster('Global_LandMask_global_land_mask.tif');
landmask(landmask < 100) = 0;
landmask(landmask > 100) = 1;
```

检查：

```text
solar_index 非空
landmask 仅包含 0 和 1
```

---

# 10. Codex 交付物

Codex 最终提交：

```text
S02E01_Global_fishnet.py
S02E02_Global_LandMask.py
tests/test_S02E01_Global_fishnet.py
tests/test_S02E02_Global_LandMask.py
README.md
```

README 中写明：

1. 使用 `global-land-mask`；
2. 网格为全球 `0.1° × 0.1°`；
3. `Global_fishnet.tif` 使用 `0 / 65536`；
4. `Global_fishnet.tif` 排除格陵兰和南极洲；
5. `Global_LandMask.tif` 使用 `0 / 255`；
6. 两个文件是基于 `global-land-mask` 的可复现替代版本；
7. 不保证和原 ArcGIS 文件逐像元一致；
8. 下游 MATLAB 兼容方式；
9. 两个输出文件统一使用 `[-180, 180]` 经度范围，而不是 `[0, 360]`。


---

# 11. 本版相对上一版的修改摘要

1. 目标网格由 `1° × 1°` 改为 `0.1° × 0.1°`；
2. 输出数组由 `180 × 360` 改为 `1800 × 3600`；
3. 像元中心改为 `-179.95 ... 179.95` 和 `89.95 ... -89.95`；
4. GeoTIFF transform 改为 `from_origin(-180.0, 90.0, 0.1, 0.1)`；
5. 函数名改为 `build_global_0p1deg_centers()`；
6. 上传的原始 `1° × 1°` TIF 仅作为参考文件；
7. 与原始参考文件比较时，先按 `10 × 10` majority 规则聚合回 `1° × 1°`；
8. 代码文件名采用当前项目中的命名：
   - `S02E01_Global_fishnet.py`
   - `S02E02_Global_LandMask.py`
