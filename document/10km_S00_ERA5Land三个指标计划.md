# 计划：计算 ERA5-Land 气候多年平均值

## 目标

写一个 Python 脚本，计算 ERA5-Land 数据集的三个气候指标，输出为全球网格 [lat, lon] 的多年平均值（无时间维度）。

## 三个指标

| # | 指标 | 输出文件名 | 输出变量名 | 单位 |
|---|------|-----------|-----------|------|
| 1 | 100 m 平均风速 | `wind_speed_100m.nc` | `wind_speed_100m` | m s⁻¹ |
| 2 | 日均太阳辐照时数 | `solar_radiation_hours.nc` | `sunshine_hours` | h day⁻¹ |
| 3 | 平均地表空气温度 | `surface_air_temperature.nc` | `t2m_mean` | °C |

## 数据源

### 文件组织

```
data/ERA5_land/global/{var}/{var}_{YYYY}_{MM}.nc
```

变量目录：`u10`、`v10`、`ssrd`、`t2m`

### 文件结构（实际探测结果）

- 坐标名：`valid_time`（非 `time`）、`latitude`（非 `lat`）、`longitude`（非 `lon`）
- 空间网格：latitude 1801 点（90.0 → -90.0，步长 0.1°），longitude 3600 点（0.0 → 359.9，步长 0.1°）
- 额外坐标：`number`（单值 0）、`expver`（单值 `'0001'`）
- 单个文件约 3 GB

### 各变量属性

| 变量 | ERA5-Land 变量名 | stepType | 单位 | 时间分辨率 |
|------|-----------------|----------|------|-----------|
| 10m U风速 | `u10` | instant | m s⁻¹ | 逐小时 |
| 10m V风速 | `v10` | instant | m s⁻¹ | 逐小时 |
| 短波辐射 | `ssrd` | **accum** | **J m⁻²** | 逐小时 |
| 2m温度 | `t2m` | instant | K | 逐小时 |

关键区别：`ssrd` 是**小时累积量**（J m⁻²），不是瞬时通量；每个时间步的值代表此前 1 小时内的辐射能累积。其他三个是瞬时值。

## 计算方法

### 1. 100 m 平均风速

```
ws10 = sqrt(u10² + v10²)              # 合成 10m 风速
ws100 = ws10 * (100/10)^(1/7)          # 幂律外推到 100m，alpha=1/7
result = mean(ws100, axis=time)         # 所有时刻取均值
```

参考：`S01E02_Simulate_Wind_CF_BCSD.py`（L226-230 幂律外推）和 `S02E02_Simulate_Wind_CF_ERA5Land.py`。

### 2. 日均太阳辐照时数

```
# ssrd 是小时累积量 (J m⁻²)，转为平均辐照度 (W m⁻²)
GHI = ssrd / 3600.0                     # W m⁻²

# 每小时判定是否为日照：GHI > 0 即视为有太阳辐照
# （夜间 GHI ≈ 0，自然过滤）
is_sunshine = (GHI > 0).astype(int)     # 1 = 有日照，0 = 无日照

# 按日聚合：每天的总日照时数
daily_sunshine = sum(is_sunshine, axis=hours_per_day)   # shape: [day, lat, lon]

# 多年所有天的平均
result = mean(daily_sunshine, axis=day)  # shape: [lat, lon]
```

说明：
- 使用 GHI > 0 作为日照判定阈值。这是最直接的方式，等价于统计每个网格的"日光时数"（有短波辐射到达地表的小时数）。
- 不需要计算太阳天顶角或大气层外辐射即可完成此指标。
- ERA5-Land 的小时累积 ssrd 在夜间几乎为 0，因此 GHI > 0 的阈值自然排除了夜间。

### 3. 平均地表空气温度

```
t2m_C = t2m - 273.15                    # K → °C
result = mean(t2m_C, axis=time)          # 所有时刻取均值
```

## 命令行接口

```
python compute_era5land_climatology.py \
  --data_dir data/ERA5_land/global \
  --start_year 2015 --end_year 2025 \
  --output_dir output/era5land_climatology
```

参数：
- `--data_dir`：ERA5-Land 数据根目录，默认 `data/ERA5_land/global`。该目录下应有 `u10/`、`v10/`、`ssrd/`、`t2m/` 子目录。
- `--start_year` / `--end_year`：起止年份（含），默认 2015-2025。
- `--output_dir`：输出目录，默认 `output`。脚本在其中新建子目录 `era5land_climatology_{start_year}_{end_year}/`。
- `--overwrite`：覆盖已有输出文件。
- `--chunk_lat`：分块处理的纬度带大小，默认 100（每次处理 100 条纬线）。

## 内存与性能策略

### 问题

单个变量一个月的文件 ≈ 3 GB（744 h × 1801 × 3600 × float32）。2015-2025 共 132 个月。全量加载不可行。

### 解决方案：逐月逐纬度块增量统计

按月份循环，每个月按纬度分块读取，累加 sum 和 count，最后求 mean：

```
sum_arr = zeros([n_lat, n_lon], float64)
count_arr = zeros([n_lat, n_lon], int32)

for (year, month) in all_year_months:
    u10_file, v10_file = open corresponding files
    for lat_start in range(0, 1801, chunk_lat):
        lat_end = min(lat_start + chunk_lat, 1801)
        # 只读取当前纬度带的所有时间步
        u10_chunk = u10.isel(latitude=slice(lat_start, lat_end)).values  # [time, chunk_lat, lon]
        v10_chunk = v10.isel(latitude=slice(lat_start, lat_end)).values
        ws100 = compute(u10_chunk, v10_chunk)
        valid = isfinite(ws100)
        sum_arr[lat_start:lat_end][valid] += ws100[valid]
        count_arr[lat_start:lat_end][valid] += 1

result = sum_arr / count_arr
```

- 每次只加载一个纬度带（约 100 × 3600 × 744 × 4 bytes ≈ 1 GB），可控。
- 风速和温度可以共享同一次文件遍历（同时读取 u10+v10 和 t2m）。
- 日照时数需要按日聚合，略复杂但同样可以逐块处理。

### 数据读取优化

- 使用 `xarray.open_dataset` 打开每月文件，配合 `isel` 按纬度切片读取。
- 每个月处理完后立即关闭文件，释放资源。
- 用 `prepare_dataarray` 函数压缩 `number`、`expver` 等单值维度（复用 `S02E02` 的模式）。

## 输出格式

每个输出 nc 文件：
- 维度：`lat(1801)` × `lon(3600)`
- 坐标变量：`lat`（float32，90.0 → -90.0）、`lon`（float32，0.0 → 359.9）
- 数据变量：单个 float32 变量（见上方表格）
- 全局属性：source、start_year、end_year、description 等

输出目录结构：
```
output/era5land_climatology_2015_2025/
├── wind_speed_100m.nc
├── solar_radiation_hours.nc
└── surface_air_temperature.nc
```

## 处理细节

### 坐标名兼容

ERA5-Land 使用 `valid_time`、`latitude`、`longitude`，脚本内部统一重命名为 `time`、`lat`、`lon`，输出使用 `lat`/`lon`。

### 单值维度压缩

ERA5-Land 数据包含 `number`（=0）和 `expver`（='0001'）等单值坐标。读取后用 `isel(dim=0, drop=True)` 压缩。

### ssrd 累积量处理

ERA5-Land ssrd 的 `GRIB_stepType=accum`，每个时间步是此前 1 小时的累积量（J m⁻²）。
- 转换为平均辐照度：GHI (W m⁻²) = ssrd (J m⁻²) / 3600 (s)
- 日照判定：GHI > 0 → 1 小时日照
- 注意：月首日 00:00 时刻的累积值可能为 0 或代表前一日最后 1 小时，但夜间 GHI 自然为 0，不影响统计。

### 按日聚合日照时数

需要将逐小时数据按日分组求和。方法：
1. 从 `valid_time` 提取日期
2. 对同一日期的所有小时，累加 `is_sunshine` 标志
3. 得到每日日照时数 → 再对所有日求均值

实现上：在每个纬度块内，按天索引分组求和，然后累加到全局 sum/count。

### NaN 处理

- ERA5-Land 使用缺失值（`GRIB_missingValue = 3.4e38`），xarray 会自动识别为 NaN。
- 使用 `np.isfinite()` 过滤，只对有效值累加统计。
- 输出中无有效数据的格点保留 NaN。

### 断点续算

- 输出文件已存在时默认跳过（除非 `--overwrite`）。
- 使用临时文件 + `os.replace` 保证写入原子性。

## 代码组织

```
compute_era5land_climatology.py
├── parse_years / parse_months
├── iter_year_months
├── era5land_file
├── find_coord_name / rename_coords
├── prepare_dataarray        # 压缩单值维度
├── compute_wind_speed_100m  # 指标1：逐月逐块累加
├── compute_sunshine_hours   # 指标2：逐月逐块按日聚合
├── compute_mean_temperature # 指标3：逐月逐块累加
├── save_result              # 写出单个 nc 文件
└── main                     # CLI 入口
```

## 验证方式

1. 检查输出 shape 是否为 [1801, 3600]
2. 风速：全球平均应在 3-8 m/s 范围内，赤道低、中高纬度偏高
3. 日照时数：全球日均应在 0-16 h 范围内，赤道和副热带高值，极地低值
4. 温度：全球平均应在 -50°C ~ +40°C 范围内
5. 可用 `plot_cf.py` 或手动绘制全球分布图做目视检查
