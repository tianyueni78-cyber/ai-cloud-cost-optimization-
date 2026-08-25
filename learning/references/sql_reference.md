# SQL 项目知识树与速查

这不是完整 SQL 教程，只包含本作品集需要的语法。示例使用 DuckDB。

## 1. 直接读取 CSV

```sql
SELECT *
FROM read_csv_auto('data/resource_inventory.csv')
LIMIT 10;
```

```sql
DESCRIBE SELECT *
FROM read_csv_auto('data/resource_inventory.csv');
```

## 2. SELECT：选择列

```sql
SELECT resource_pool_id, gpu_model, gpu_count
FROM read_csv_auto('data/resource_inventory.csv');
```

避免长期使用 `SELECT *`，正式分析应明确需要的列。

## 3. WHERE：筛选行

```sql
SELECT *
FROM clean_inventory
WHERE region = 'ap-southeast-1'
  AND procurement_model IN ('Reserved', 'SavingsPlan');
```

空值使用：

```sql
WHERE contract_id IS NULL
```

不能写 `contract_id = NULL`。

## 4. CASE：分类

```sql
SELECT
  resource_pool_id,
  CASE
    WHEN gpu_count >= 24 THEN 'large'
    WHEN gpu_count >= 8 THEN 'medium'
    ELSE 'small'
  END AS pool_size
FROM clean_inventory;
```

## 5. 聚合与 GROUP BY

```sql
SELECT
  team_id,
  COUNT(*) AS pools,
  SUM(gpu_count) AS total_gpus,
  AVG(effective_hourly_rate_usd) AS avg_rate
FROM clean_inventory
GROUP BY team_id
ORDER BY total_gpus DESC;
```

常用聚合：`COUNT`、`COUNT(DISTINCT ...)`、`SUM`、`AVG`、`MIN`、`MAX`。

## 6. HAVING：筛选聚合结果

```sql
SELECT resource_pool_id, COUNT(*) AS copies
FROM raw_usage
GROUP BY resource_pool_id
HAVING COUNT(*) > 1;
```

`WHERE` 在聚合前筛选行，`HAVING` 在聚合后筛选组。

## 7. 文本清洗

```sql
UPPER(REPLACE(TRIM(resource_pool_id), '_', '-'))
```

- `TRIM`：去两端空格；
- `UPPER`：转大写；
- `REPLACE`：替换字符；
- `NULLIF(value, '')`：空字符串转 NULL；
- `COALESCE(a, b)`：取第一个非空值。

## 8. 类型转换

```sql
TRY_CAST(gpu_count AS INTEGER)
TRY_CAST(net_cost_usd AS DOUBLE)
TRY_CAST(timestamp_utc AS TIMESTAMP)
```

`CAST` 失败会终止查询；`TRY_CAST` 失败返回 NULL，适合审计原始数据。

## 9. 时间处理

```sql
DATE_TRUNC('month', timestamp_utc)
EXTRACT(YEAR FROM timestamp_utc)
EXTRACT(HOUR FROM timestamp_utc)
```

月度分析前先确定使用月份还是发票月份。

## 10. JOIN

```sql
SELECT
  u.timestamp_utc,
  u.resource_pool_id,
  i.gpu_model,
  i.procurement_model
FROM clean_usage u
LEFT JOIN clean_inventory i
  ON u.resource_pool_id = i.resource_pool_id;
```

### JOIN 前后必须检查

```text
左表行数
右表连接键是否唯一
JOIN 后行数
关键金额/用量总计
未匹配行数
```

右表一个键出现多行时，JOIN 可能放大左表金额。

## 11. CTE

```sql
WITH monthly AS (
  SELECT invoice_month, SUM(net_cost_usd) AS cost
  FROM clean_billing
  GROUP BY invoice_month
)
SELECT * FROM monthly ORDER BY invoice_month;
```

CTE 用于把复杂查询拆成有名称的步骤。

## 12. 窗口函数

### 上一期数值

```sql
LAG(cost) OVER (ORDER BY month)
```

### 排名

```sql
ROW_NUMBER() OVER (
  PARTITION BY month
  ORDER BY cost DESC
)
```

### 运行累计

```sql
SUM(cost) OVER (
  ORDER BY month
  ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
)
```

## 13. 条件统计

```sql
COUNT(*) FILTER (WHERE gpu_utilization_pct IS NULL)
```

```sql
SUM(CASE WHEN charge_type = 'Credit' THEN net_cost_usd ELSE 0 END)
```

## 14. 安全除法

```sql
cost / NULLIF(business_volume, 0)
```

## 15. 导出结果

```sql
COPY (
  SELECT * FROM monthly_summary
)
TO 'outputs/analysis/monthly_summary.csv'
(HEADER, DELIMITER ',');
```

```sql
COPY clean_usage
TO 'outputs/clean/resource_usage.parquet'
(FORMAT PARQUET);
```

## 16. 调试顺序

查询结果异常时按顺序检查：

1. 单独运行每个 CTE；
2. 查看 JOIN 两边键的重复；
3. 比较 JOIN 前后行数；
4. 比较 JOIN 前后金额总计；
5. 检查过滤条件；
6. 检查 NULL；
7. 检查日期和单位；
8. 用少量 ID 手工追踪。

## 最小学习路径

```text
SELECT/FROM/LIMIT
→ WHERE/CASE
→ GROUP BY/聚合
→ JOIN
→ 日期函数
→ CTE
→ 窗口函数
→ 导出和核对
```
