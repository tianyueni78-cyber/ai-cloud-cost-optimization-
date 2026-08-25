# 04｜数据审计：具体怎么做

## 目标

用 DuckDB 和 SQL 系统检查五张原始表是否完整、唯一、有效、一致、可关联且及时，并把证据写入 `reports/data_audit.md`。

## 软件、输入和输出

- 软件：VS Code、DuckDB；暂时不需要 Power BI。
- 输入：`data/resource_usage.csv`、`cloud_billing.csv`、`team_sla.csv`、`resource_inventory.csv`、`business_events.csv`。
- SQL：`sql/01_data_audit.sql`。
- 报告：`reports/data_audit.md`。

## 审计思维顺序

```text
文件存在吗
→ 结构正确吗
→ 行是否完整
→ 主键是否唯一
→ 字段值是否有效
→ 五张表是否一致
→ 时间是否及时
→ 问题会影响哪个分析
```

不要上来就删除异常。审计阶段的工作是发现、量化、分类和解释影响。

## A. 建立可重复查询入口

在 `sql/01_data_audit.sql` 开头创建视图：

```sql
SET TimeZone = 'UTC';

CREATE OR REPLACE VIEW raw_inventory AS
SELECT * FROM read_csv_auto('data/resource_inventory.csv', all_varchar = true);

CREATE OR REPLACE VIEW raw_usage AS
SELECT * FROM read_csv_auto('data/resource_usage.csv', all_varchar = true);

CREATE OR REPLACE VIEW raw_billing AS
SELECT * FROM read_csv_auto('data/cloud_billing.csv', all_varchar = true);

CREATE OR REPLACE VIEW raw_sla AS
SELECT * FROM read_csv_auto('data/team_sla.csv', all_varchar = true);

CREATE OR REPLACE VIEW raw_events AS
SELECT * FROM read_csv_auto('data/business_events.csv', all_varchar = true);
```

审计时先将会话时区设为 UTC，再按文本读取，可以避免本机时区改变月度边界，也可以防止工具自动转换后掩盖原始格式问题。

## B. 文件和结构检查

对每张表检查：

```sql
DESCRIBE raw_inventory;
SELECT COUNT(*) AS row_count FROM raw_inventory;
SELECT * FROM raw_inventory LIMIT 10;
```

将实际列名与 `docs/data_dictionary.md` 对照，记录缺列、多列和类型推断风险。

## C. 完整性：检查空值

空字符串和真正的 NULL 都要统计：

```sql
SELECT
  COUNT(*) AS total_rows,
  COUNT(*) FILTER (WHERE resource_pool_id IS NULL OR TRIM(resource_pool_id) = '') AS missing_resource_pool_id,
  COUNT(*) FILTER (WHERE gpu_utilization_pct IS NULL OR TRIM(gpu_utilization_pct) = '') AS missing_gpu_utilization,
  COUNT(*) FILTER (WHERE availability_pct IS NULL OR TRIM(availability_pct) = '') AS missing_availability
FROM raw_usage;
```

检查每个空值前先查看数据字典的“允许为空”。允许为空不代表不需要记录，而是要判断空值是否符合业务情景。

## D. 唯一性：检查重复

### 主键重复

```sql
SELECT usage_record_id, COUNT(*) AS copies
FROM raw_usage
GROUP BY usage_record_id
HAVING COUNT(*) > 1
ORDER BY copies DESC;
```

### 业务重复

不同记录 ID 也可能描述同一资源池同一小时：

```sql
SELECT
  timestamp_utc,
  UPPER(REPLACE(TRIM(resource_pool_id), '_', '-')) AS normalized_pool_id,
  COUNT(*) AS copies,
  COUNT(DISTINCT usage_record_id) AS distinct_record_ids
FROM raw_usage
GROUP BY 1, 2
HAVING COUNT(*) > 1
ORDER BY copies DESC;
```

不要立即执行 `SELECT DISTINCT *`。它只能处理完全相同的行，不能替你定义业务重复。

## E. 有效性：检查字段范围和枚举

### 枚举值

```sql
SELECT DISTINCT procurement_model
FROM raw_inventory
ORDER BY 1;
```

与数据字典规定的值比较。

### 数值范围

```sql
SELECT
  MIN(TRY_CAST(gpu_utilization_pct AS DOUBLE)) AS min_gpu_util,
  MAX(TRY_CAST(gpu_utilization_pct AS DOUBLE)) AS max_gpu_util,
  MIN(TRY_CAST(availability_pct AS DOUBLE)) AS min_availability,
  MAX(TRY_CAST(availability_pct AS DOUBLE)) AS max_availability
FROM raw_usage;
```

使用 `TRY_CAST`：转换失败时返回 NULL，不会让整条查询终止。还要单独统计转换失败数量。

## F. 一致性：检查 ID 格式

```sql
SELECT resource_pool_id, COUNT(*) AS rows
FROM raw_usage
WHERE resource_pool_id <> UPPER(REPLACE(TRIM(resource_pool_id), '_', '-'))
GROUP BY resource_pool_id
ORDER BY rows DESC;
```

先观察格式变化，再定义标准化表达式：

```sql
UPPER(REPLACE(TRIM(resource_pool_id), '_', '-'))
```

标准化只能处理格式差异，不能修复真正错误的 ID。

## G. 可关联性：检查外键覆盖率

```sql
WITH usage_ids AS (
  SELECT DISTINCT UPPER(REPLACE(TRIM(resource_pool_id), '_', '-')) AS pool_id
  FROM raw_usage
),
inventory_ids AS (
  SELECT DISTINCT resource_pool_id AS pool_id
  FROM raw_inventory
)
SELECT
  COUNT(*) AS usage_distinct_ids,
  COUNT(*) FILTER (WHERE i.pool_id IS NOT NULL) AS matched_ids,
  COUNT(*) FILTER (WHERE i.pool_id IS NULL) AS unmatched_ids
FROM usage_ids u
LEFT JOIN inventory_ids i USING (pool_id);
```

同时比较标准化前后的关联率。报告中要写清“为什么提高”，而不是只展示最终数字。

## H. 时间范围与及时性

```sql
SELECT
  MIN(TRY_CAST(timestamp_utc AS TIMESTAMP)) AS first_hour,
  MAX(TRY_CAST(timestamp_utc AS TIMESTAMP)) AS last_hour,
  COUNT(DISTINCT DATE_TRUNC('month', TRY_CAST(timestamp_utc AS TIMESTAMP))) AS months
FROM raw_usage;
```

账单检查使用月份与发票月份：

```sql
SELECT
  SUBSTR(usage_end_date, 1, 7) AS usage_month,
  invoice_month,
  COUNT(*) AS lines,
  SUM(TRY_CAST(net_cost_usd AS DOUBLE)) AS net_cost
FROM raw_billing
GROUP BY 1, 2
ORDER BY 1, 2;
```

## I. 账单算术检查

```sql
SELECT COUNT(*) AS inconsistent_lines
FROM raw_billing
WHERE ABS(
  TRY_CAST(net_cost_usd AS DOUBLE)
  - (TRY_CAST(gross_cost_usd AS DOUBLE) - TRY_CAST(discount_usd AS DOUBLE))
) > 0.01;
```

算术正确不等于业务口径正确。还要阅读不同 `charge_type` 的定义。

## J. 记录审计发现

`reports/data_audit.md` 每项使用统一格式：

```markdown
### 问题名称

- 检查对象：
- 检查方法：
- 证据：
- 影响范围：
- 可能影响的分析：
- 建议处理：
- 是否阻断后续工作：
```

## 问题分级

- 阻断：无法确定主键、金额或时间，后续结果可能整体错误。
- 重要：影响部分关联、趋势或归因，需要明确处理。
- 可接受噪声：业务允许且不会误导主要结论，但需要记录。

## 验收标准

- 五张表均检查结构、空值、重复、枚举、范围和时间。
- 至少测试三组关键表关系。
- 记录标准化前后的关联率。
- 账单等式和时间错位得到检查。
- 报告只陈述有证据的问题，不把怀疑写成事实。
- 原始 CSV 没有被修改。

## 建议提交

```powershell
git add sql/01_data_audit.sql reports/data_audit.md
git commit -m "analysis: complete source data audit"
git push
```
