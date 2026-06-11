# `S04_Global_Wind_Solar_Fishnet_Area.py` 代码实现计划

## 1. 任务目标

在仓库分支 `dev-SSPs-cost-only-10km` 中新增脚本：

```text
GlobalPotential_10km/S04_Global_Wind_Solar_Fishnet_Area.py
```

脚本用于生成全球 `0.1° × 0.1°` 格网的面积数据。全球栅格尺寸固定为：

```text
纬度方向：1800 行
经度方向：3600 列
总格网数：6,480,000
```


经纬度边界保持不变：

```text
经度：[-180, 180]
纬度：[-90, 90]
```


每个像元存储对应格网的面积，单位为 `km²`。

风电格网面积和光伏格网面积在物理意义上完全相同，因此脚本只计算一次面积矩阵，然后分别保存为风电和光伏版本。不要分别执行两套面积计算逻辑。

---

## 2. 与现有目录结构的衔接

当前 `GlobalPotential_10km/` 中已有：

```text
S01E01_Simulate_Solar_CF_ERA5Land.py
S01E02_Simulate_Wind_CF_ERA5Land.py
S01E03_Compute_Mean_Hourly_CF.py
S02E01_Global_fishnet.py
S02E02_Global_LandMask.py
S03_Global_Grid_Division.py
```

新增脚本继续沿用现有编号顺序：

```text
S04_Global_Wind_Solar_Fishnet_Area.py
```

默认输出目录与现有脚本一致：

```text
GlobalPotential_10km/outputs/
```

脚本运行后应新增四个文件：

```text
GlobalPotential_10km/outputs/Global_Wind_Fishnet_Area.tif
GlobalPotential_10km/outputs/Global_Wind_Fishnet_Area.mat
GlobalPotential_10km/outputs/Global_Solar_Fishnet_Area.tif
GlobalPotential_10km/outputs/Global_Solar_Fishnet_Area.mat
```

---

## 3. 参考文件格式

上传的 `1° × 1°` 原始文件已经确认具有以下特征：

### 3.1 GeoTIFF

```text
shape      = (180, 360)
dtype      = float64
CRS        = EPSG:4326
orientation:
  行方向：北 → 南
  列方向：西 → 东
AREA_OR_POINT = Area
nodata     = None
```

风电和光伏两个 TIF 中的数据完全一致。

### 3.2 MAT

```text
变量名     = data
shape      = (180, 360)
dtype      = float64
orientation:
  行方向：北 → 南
  列方向：西 → 东
```

风电和光伏两个 MAT 中的数据完全一致；同名 TIF 与 MAT 中的矩阵也完全一致。

### 3.3 新脚本应保持的兼容格式

新的 `0.1° × 0.1°` 结果必须保持相同的数据语义与矩阵方向，只将 shape 改为：

```text
shape = (1800, 3600)
dtype = float64
```

MAT 文件继续使用变量名：

```python
{"data": area_grid}
```

---

## 4. 面积计算方法

## 4.1 不要使用简单上采样

不要将 `1° × 1°` 原始面积简单地重复为 100 个子格网，也不要直接将父格网面积除以 100。

原因是：即使位于同一个 `1° × 1°` 父格网内部，不同纬度的 `0.1° × 0.1°` 子格网面积仍然略有差异。直接除以 100 会丢失这种纬度差异。

## 4.2 推荐方法：基于 WGS84 椭球直接计算

使用：

```python
from pyproj import Geod
geod = Geod(ellps="WGS84")
```

对每一个纬度行计算一个 `0.1° × 0.1°` 格网多边形的面积，然后沿经度方向广播到 3600 列。

由于 WGS84 椭球具有经向对称性，同一纬度带内所有经度格网的面积相同。因此只需执行 1800 次多边形面积计算，而不是执行 6,480,000 次计算。

建议逻辑：

```python
RESOLUTION = 0.1
HEIGHT = 1800
WIDTH = 3600
WEST = -180.0
NORTH = 90.0

row_areas = np.empty(HEIGHT, dtype=np.float64)

for row in range(HEIGHT):
    north = NORTH - row * RESOLUTION
    south = north - RESOLUTION

    lons = [WEST, WEST + RESOLUTION, WEST + RESOLUTION, WEST]
    lats = [south, south, north, north]

    area_m2, _ = geod.polygon_area_perimeter(lons, lats)
    row_areas[row] = abs(area_m2) / 1e6

area_grid = np.repeat(row_areas[:, None], WIDTH, axis=1)
```

面积单位必须转换为：

```text
km²
```

## 4.3 原始 1° 文件仅用于格式参考与可选对比

上传的旧版 `1° × 1°` 数据可以用于：

- 检查矩阵方向；
- 检查 MAT 变量名；
- 检查 GeoTIFF 的 CRS；
- 检查面积随纬度变化的趋势；
- 执行可选的聚合差异报告。

不要将旧版面积矩阵作为新脚本的必需输入。新脚本应能够独立生成 `0.1° × 0.1°` 面积数据。

---

## 5. 脚本结构

建议实现以下常量：

```python
BASE_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = BASE_DIR / "outputs"

WIDTH = 3600
HEIGHT = 1800
WEST = -180.0
NORTH = 90.0
RESOLUTION = 0.1
CRS = "EPSG:4326"
```

建议拆分为以下函数：

```python
def _import_rasterio():
    ...

def _import_pyproj():
    ...

def build_global_01deg_cell_area() -> np.ndarray:
    ...

def write_geotiff(output_path: Path, data: np.ndarray, *, overwrite: bool) -> None:
    ...

def write_mat(output_path: Path, data: np.ndarray, *, overwrite: bool) -> None:
    ...

def write_all_outputs(output_dir: Path, data: np.ndarray, *, overwrite: bool) -> None:
    ...

def validate_area_grid(data: np.ndarray) -> None:
    ...

def print_stats(data: np.ndarray) -> None:
    ...

def compare_with_1deg_reference(data: np.ndarray, reference_tif: Path) -> None:
    ...

def parse_args(argv=None) -> argparse.Namespace:
    ...

def main(argv=None) -> int:
    ...
```

---

## 6. GeoTIFF 保存格式

使用 `rasterio` 写出 GeoTIFF：

```python
from rasterio.transform import from_origin

transform = from_origin(
    WEST,
    NORTH,
    RESOLUTION,
    RESOLUTION,
)
```

建议写入参数：

```python
with rasterio.open(
    output_path,
    "w",
    driver="GTiff",
    width=WIDTH,
    height=HEIGHT,
    count=1,
    dtype="float64",
    crs=CRS,
    transform=transform,
    nodata=None,
    compress="deflate",
) as dst:
    dst.write(data, 1)
    dst.update_tags(
        AREA_OR_POINT="Area",
        generated_by="S04_Global_Wind_Solar_Fishnet_Area.py",
        description="Global 0.1-degree grid-cell area in km^2.",
        units="km^2",
        longitude_bounds="[-180, 180]",
        latitude_bounds="[-90, 90]",
    )
```

输出像元中心应为：

```text
lon = -179.95, -179.85, ..., 179.95
lat =   89.95,   89.85, ..., -89.95
```

不要复刻旧文件左边界中的极小浮点漂移，应使用精确的：

```text
WEST = -180.0
```

---

## 7. MAT 保存格式

使用：

```python
import scipy.io as sio

sio.savemat(
    output_path,
    {"data": data},
    do_compression=True,
)
```

注意：

- MAT 文件中的变量名必须为 `data`；
- 数据类型必须保留为 `float64`；
- 不要将数据转为 `float32`；
- 不要转置矩阵；
- 当前矩阵约为 `51.84 MB`，未超过 MATLAB v5 MAT 文件的限制，不需要使用 HDF5 或 MATLAB v7.3 格式。

---

## 8. 输出复用逻辑

只计算一次：

```python
area_grid = build_global_01deg_cell_area()
```

随后将同一个数组分别写出：

```python
Global_Wind_Fishnet_Area.tif
Global_Wind_Fishnet_Area.mat
Global_Solar_Fishnet_Area.tif
Global_Solar_Fishnet_Area.mat
```

写出后必须检查：

```python
wind_tif == solar_tif
wind_mat == solar_mat
wind_tif == wind_mat
solar_tif == solar_mat
```

数值应逐像元完全一致。

---

## 9. 命令行接口

建议支持：

```bash
python GlobalPotential_10km/S04_Global_Wind_Solar_Fishnet_Area.py
```

默认写入：

```text
GlobalPotential_10km/outputs/
```

建议增加以下参数：

```text
--output-dir PATH
    自定义输出目录。

--overwrite
    覆盖已存在的输出文件。

--print-stats
    输出 shape、dtype、最小值、最大值、总面积等统计量。

--reference-1deg-tif PATH
    可选。将生成的 0.1° 面积聚合回 1°，并与旧版 1° TIF 进行差异统计。
    仅用于报告，不作为生成逻辑的一部分。
```

运行示例：

```bash
python GlobalPotential_10km/S04_Global_Wind_Solar_Fishnet_Area.py \
    --overwrite \
    --print-stats
```

带旧版参考文件的对比示例：

```bash
python GlobalPotential_10km/S04_Global_Wind_Solar_Fishnet_Area.py \
    --overwrite \
    --print-stats \
    --reference-1deg-tif /path/to/Global_Wind_Fishnet_Area.tif
```

---

## 10. 校验要求

## 10.1 基础校验

脚本内部必须检查：

```text
shape == (1800, 3600)
dtype == float64
所有数值均为有限值
所有面积均 > 0
```

## 10.2 地理参考校验

新 TIF 必须满足：

```text
CRS       = EPSG:4326
bounds    = (-180, -90, 180, 90)
resolution= (0.1, 0.1)
transform = from_origin(-180, 90, 0.1, 0.1)
```

## 10.3 数值趋势校验

应满足：

```text
赤道附近格网面积最大
两极附近格网面积最小
同一纬度带的 3600 个格网面积完全一致
南北半球对应纬度的面积基本对称
```

使用 WGS84 椭球直接计算时，预期：

```text
最小面积约为 0.10887 km²
最大面积约为 123.09069 km²
全球面积总和约为 510,065,622 km²
```

允许因底层库版本造成极小的浮点差异。

## 10.4 四个输出文件的一致性校验

建议在脚本执行完毕后重新读取结果，并断言：

```text
Global_Wind_Fishnet_Area.tif
Global_Wind_Fishnet_Area.mat
Global_Solar_Fishnet_Area.tif
Global_Solar_Fishnet_Area.mat
```

四者的矩阵完全一致。

## 10.5 可选的旧版 1° 对比报告

将生成的 `0.1° × 0.1°` 数据按 `10 × 10` 聚合回 `1° × 1°`：

```python
aggregated = (
    area_grid
    .reshape(180, 10, 360, 10)
    .sum(axis=(1, 3))
)
```

然后与旧版 `Global_Wind_Fishnet_Area.tif` 对比，输出：

```text
旧版 shape
聚合后 shape
最大绝对差
平均绝对差
平均相对差
总面积差
```

注意：该对比只用于诊断。不要强制要求与旧版逐像元完全相等，因为新脚本采用 WGS84 椭球直接计算真实格网面积，而旧版文件可能来自不同的 ArcGIS 面积计算流程。

---

## 11. 依赖更新

脚本需要：

```text
numpy
scipy
rasterio
pyproj
```

当前仓库已经使用 `numpy`、`scipy` 和 `rasterio` 相关功能。为了避免依赖由其他包间接安装，建议在根目录 `requirements.txt` 中显式补充：

```text
rasterio
pyproj
```

---

## 12. 错误处理

脚本应采用与现有 `S02E01_Global_fishnet.py` 和 `S02E02_Global_LandMask.py` 相同的稳健风格：

- 延迟导入第三方依赖，缺包时给出清晰安装命令；
- 默认不覆盖已有文件；
- 使用 `--overwrite` 显式允许覆盖；
- 输出目录不存在时自动创建；
- 可先写入临时文件，再原子替换正式输出；
- 任意一个输出失败时清理对应临时文件；
- 在错误信息中明确显示失败文件路径。

---

## 13. 验收标准

完成实现后，执行：

```bash
python GlobalPotential_10km/S04_Global_Wind_Solar_Fishnet_Area.py \
    --overwrite \
    --print-stats
```

必须满足：

1. 在 `GlobalPotential_10km/outputs/` 中生成四个文件；
2. 两个 TIF 均为 `1800 × 3600`、`float64`、`EPSG:4326`；
3. 两个 MAT 均包含变量 `data`，shape 为 `1800 × 3600`，dtype 为 `float64`；
4. 四个文件中的面积矩阵逐像元一致；
5. 格网面积单位为 `km²`；
6. 面积随纬度变化合理，赤道最大、两极最小；
7. 脚本不依赖 ArcGIS；
8. 脚本不依赖旧版 `1° × 1°` 输入文件；
9. 脚本支持重复运行，并通过 `--overwrite` 控制覆盖行为；
10. 代码中只保留一套面积计算逻辑，风电与光伏复用同一矩阵。

---

## 14. 本次任务边界

本次只新增：

```text
GlobalPotential_10km/S04_Global_Wind_Solar_Fishnet_Area.py
```

并按需更新：

```text
requirements.txt
```

本次不要修改：

```text
Optimization*/
S01*
S02*
S03_Global_Grid_Division.py
```

本次也不要生成或修改：

```text
Global_Wind_Net_Area_Add_Egrid.*
Global_Solar_Net_Area_Add_Egrid.*
```

这些是另一项土地适宜性处理任务，不属于本脚本职责范围。
