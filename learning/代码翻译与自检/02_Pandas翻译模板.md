# Pandas 翻译模板

Pandas 和 SQL 解决的是同一类业务动作。先说清“筛什么、按什么分、算什么”，再换成代码。以下假设已经执行 `import pandas as pd`。

## 一、业务动作对照

| 业务动作 | Pandas 写法 |
|---|---|
| 读取表 | `pd.read_csv()` |
| 看字段、类型、样例 | `columns`、`dtypes`、`head()` |
| 筛选 | `df.loc[条件]` |
| 求和 | `sum()` |
| 计数/对象去重计数 | `len()`、`nunique()` |
| 分组汇总 | `groupby().agg()` |
| 排序 | `sort_values()` |
| 关联 | `merge()` |
| 检查空值/重复 | `isna()`、`duplicated()` |
| 上一期 | `shift()` |

## 二、读取与认识数据

```python
import pandas as pd

df = pd.read_csv(
    "【文件路径】",          # 替换为输入文件；例：outputs/cleaned/cloud_billing.csv
    low_memory=False,
)

print(df.columns.tolist())  # 字段名
print(df.dtypes)            # 数据类型
print(df.head(【样例行数】)) # 替换为少量行数；例：10
print(df.shape)             # (行数, 列数)
```

读取后先看结构，不要立即修改原表。

## 三、选择字段与筛选

```python
selected = df.loc[
    【行筛选条件】,          # 例：df["charge_type"].isin(included_types)
    [【字段列表】],          # 例："invoice_month", "net_cost_usd"
].copy()
```

常用条件：

```python
df["【字段】"] == 【单个值】
df["【字段】"].isin([【值1】, 【值2】])
df["【字段】"].isna()
df["【字段】"].notna()
(df["【数值字段】"] >= 【下界】) & (df["【数值字段】"] <= 【上界】)
```

多个条件必须分别加括号，使用 `&` 或 `|`，不要用 Python 的 `and` 或 `or`。

## 四、求总额与计数

```python
total = filtered["【数值字段】"].sum()  # 例：net_cost_usd
row_count = len(filtered)
object_count = filtered["【对象ID】"].nunique() # 例：billing_line_id
```

默认 `sum()` 会跳过空值。因此还要单独检查数值字段空值，不能把“得到数字”当成“没有漏算”。

## 五、分组汇总与排序

```python
summary = (
    filtered
    .groupby(["【分组字段】"], dropna=False, as_index=False) # 例：invoice_month
    .agg(
        metric_value=("【数值字段】", "sum"),                # 例：net_cost_usd
        row_count=("【候选主键】", "size"),                  # 例：billing_line_id
        object_count=("【候选主键】", "nunique"),
    )
    .sort_values("【排序字段】", ascending=【True或False】)    # 时间True，排名False
)
```

`dropna=False` 会保留分组字段为空的记录，便于发现未归属成本；是否最终展示由业务口径决定。

## 六、比例与安全除法

```python
summary["【比例字段】"] = (
    summary["【分子字段】"]
    .div(summary["【分母字段】"].replace(0, pd.NA))
    .mul(100)
)
```

先确认分子和分母处于同一粒度、同一时间范围、同一单位，再计算比例。

## 七、分类

简单两类：

```python
df["【分类字段】"] = "【默认标签】"
df.loc[【条件】, "【分类字段】"] = "【命中标签】"
```

多档区间：

```python
df["【分类字段】"] = pd.cut(
    df["【数值字段】"],
    bins=[【边界列表】],       # 例：float('-inf'), 20, 60, float('inf')
    labels=[【标签列表】],     # 标签数量必须比边界数量少1
)
```

## 八、空值与重复

```python
missing = (
    df.isna()
    .sum()
    .rename("missing_rows")
    .to_frame()
)
missing["missing_pct"] = missing["missing_rows"] / len(df) * 100
```

```python
key_cols = [【候选主键字段列表】] # 单字段例：["billing_line_id"]；组合主键可放多个字段
duplicate_mask = df.duplicated(subset=key_cols, keep=False)
duplicate_rows = df.loc[duplicate_mask].sort_values(key_cols)
```

不要看到重复就直接删除。先分清完全重复、修订记录、正常的一对多和真正的脏数据。

## 九、表关联

```python
joined = left.merge(
    right[["【右关联键】", "【补充字段】"]],
    how="left",                  # 成本事实表通常先全部保留
    left_on="【左关联键】",
    right_on="【右关联键】",
    validate="many_to_one",     # 左表多行可对应右表唯一一行
    indicator=True,              # 生成 _merge，检查未匹配
)
```

`validate` 是重要保护：

- `one_to_one`：两边键都唯一；
- `many_to_one`：左边可重复，右边必须唯一；
- `one_to_many`：左边唯一，右边可重复；
- `many_to_many`：不会阻止放大，除非业务明确允许，否则不建议使用。

关联后至少检查：

```python
print(joined["_merge"].value_counts(dropna=False))
print(left["【金额字段】"].sum(), joined["【金额字段】"].sum()) # 例：net_cost_usd
```

## 十、日期与环比

```python
df["【日期字段】"] = pd.to_datetime(
    df["【日期字段】"],
    errors="coerce",           # 无法解析的值变为空，随后必须统计
)

monthly = (
    df.groupby("【月份字段】", dropna=False, as_index=False)
      .agg(metric_value=("【数值字段】", "sum"))
      .sort_values("【月份字段】")
)
monthly["previous_value"] = monthly["metric_value"].shift(1)
monthly["change_pct"] = (
    monthly["metric_value"].sub(monthly["previous_value"])
    .div(monthly["previous_value"].replace(0, pd.NA))
    .mul(100)
)
```

转换日期后立即检查 `isna().sum()`，因为 `errors='coerce'` 可能暴露原始坏值。

## 十一、类型转换

```python
df["【数值字段】"] = pd.to_numeric(df["【数值字段】"], errors="coerce")
df["【文本字段】"] = df["【文本字段】"].astype("string").str.strip()
```

类型转换不是填值。转换产生的空值必须记录，原始缺失值不要随意填 0。

## 十二、Pandas 报错或结果异常时

按顺序检查：

1. 字段名是否存在、大小写和下划线是否一致；
2. 条件是否逐个加括号；
3. 数字和日期是否已转换类型；
4. 筛选前后行数是否符合预期；
5. `groupby` 是否遗漏 `dropna=False`；
6. `merge` 的左右键是否选对、类型是否一致；
7. `validate` 是否符合真实关系；
8. 聚合结果是否仍处于预期粒度。

下一步：[固定自检程序](03_固定自检程序.md) · [GPU 成本完整范例](04_GPU成本完整范例.md)
