# Pandas 项目知识树与速查

Pandas 是 Python 的表格数据处理库。只有在项目需要复杂清洗、预测或绘图时使用，不要求先学完全部 API。

## 1. 导入和读取

```python
import pandas as pd

inventory = pd.read_csv(
    "data/resource_inventory.csv",
    dtype="string"
)
```

原始审计时按字符串读取，可以保留源格式。数据很大时优先使用 DuckDB，不要一次把所有 CSV 全部载入内存。

## 2. 快速认识 DataFrame

```python
inventory.head()
inventory.tail()
inventory.shape
inventory.columns
inventory.dtypes
inventory.info()
```

- DataFrame：一张表；
- Series：一列；
- index：行标签，不一定是业务主键。

## 3. 选择和筛选

```python
inventory[["resource_pool_id", "gpu_model"]]
```

```python
inventory.loc[
    inventory["region"].eq("ap-southeast-1"),
    ["resource_pool_id", "gpu_model", "gpu_count"]
]
```

## 4. 空值

```python
inventory.isna().sum()
```

```python
inventory["contract_id"].isna().mean()
```

不要直接执行全表 `fillna(0)`。先判断字段业务含义。

## 5. 重复

```python
inventory.duplicated().sum()
inventory.duplicated(subset=["resource_pool_id"], keep=False)
```

```python
duplicates = inventory.loc[
    inventory.duplicated(subset=["resource_pool_id"], keep=False)
].sort_values("resource_pool_id")
```

## 6. 分类值和分布

```python
inventory["procurement_model"].value_counts(dropna=False)
```

```python
inventory["gpu_count"].describe()
```

## 7. 文本标准化

```python
inventory["resource_pool_id_clean"] = (
    inventory["resource_pool_id"]
    .str.strip()
    .str.upper()
    .str.replace("_", "-", regex=False)
)
```

常用 `.str` 方法：`strip`、`upper`、`lower`、`replace`、`contains`。

## 8. 类型转换

```python
inventory["gpu_count_num"] = pd.to_numeric(
    inventory["gpu_count"],
    errors="coerce"
)
```

```python
usage["timestamp"] = pd.to_datetime(
    usage["timestamp_utc"],
    utc=True,
    errors="coerce"
)
```

`errors="coerce"` 会把转换失败值变成缺失值，之后必须统计失败数量。

## 9. 排序和去重

```python
usage = usage.sort_values(
    ["usage_record_id", "telemetry_status"]
)
```

```python
usage_clean = usage.drop_duplicates(
    subset=["usage_record_id"],
    keep="first"
)
```

只有先定义排序和保留规则，`drop_duplicates` 才有业务意义。

## 10. 新列

```python
inventory = inventory.assign(
    annual_run_rate=lambda df: (
        df["gpu_count_num"]
        * pd.to_numeric(df["effective_hourly_rate_usd"])
        * 24 * 365
    )
)
```

## 11. 分组汇总

```python
summary = (
    inventory
    .groupby(["team_id", "gpu_model"], dropna=False)
    .agg(
        pools=("resource_pool_id", "nunique"),
        gpus=("gpu_count_num", "sum")
    )
    .reset_index()
)
```

## 12. 合并表

```python
merged = usage.merge(
    inventory,
    on="resource_pool_id",
    how="left",
    validate="many_to_one",
    indicator=True
)
```

关键参数：

- `how="left"`：保留左表；
- `validate="many_to_one"`：要求右表键唯一；
- `indicator=True`：生成 `_merge`，用于检查关联率。

## 13. 透视表

```python
pivot = pd.pivot_table(
    monthly,
    index="month",
    columns="team_id",
    values="net_cost_usd",
    aggfunc="sum",
    fill_value=0
)
```

## 14. 时间序列

```python
monthly = monthly.sort_values("month")
monthly["previous_cost"] = monthly.groupby("team_id")["net_cost_usd"].shift(1)
monthly["growth"] = monthly["net_cost_usd"] / monthly["previous_cost"] - 1
```

## 15. 导出

```python
summary.to_csv("outputs/analysis/team_summary.csv", index=False)
summary.to_parquet("outputs/analysis/team_summary.parquet", index=False)
```

## 16. 常见错误

- 对大 CSV 直接 `read_csv` 导致内存不足；
- 把空值全填 0；
- `merge` 后不检查行数；
- 对百分比简单平均；
- 修改原始 DataFrame 后没有保留处理步骤；
- Notebook 单元格乱序运行；
- 导出时把 index 当成业务字段。

## 最小学习路径

```text
read_csv / head / info
→ isna / duplicated / value_counts
→ 文本和类型转换
→ groupby / agg
→ merge + validate
→ 时间序列
→ to_csv / to_parquet
```
