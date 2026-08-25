# 05｜数据清洗与干净数据层

## 目标

把审计中确认的问题转成明确、可重复、可验证的清洗规则，同时保留原始数据和处理痕迹。

## 软件、输入和输出

- 软件：VS Code、Python/Pandas；DuckDB 用于独立复核结果。
- 输入：`data/*.csv` 和 `reports/data_audit.md`。
- 清洗程序：`src/clean_data.py`。
- 自动测试：`tests/test_clean_data.py`。
- 本地输出：`outputs/cleaned/*.csv`，不提交 Git。

## 本项目的实际执行方式

先运行测试，再运行清洗：

```powershell
python -m unittest discover -s tests -v
python src/clean_data.py
```

程序依次执行：

1. 读取五张原始 CSV。
2. 转换日期、UTC 时间、数值和布尔类型。
3. 新增标准化 ID，不覆盖原始字段。
4. 删除完全重复记录，并让 `-R` 修订记录优先。
5. 为团队标签缺失的账单生成归属团队和归属来源。
6. 验证业务键、资源池关联和团队归属。
7. 验证全部通过后才写出五张清洗表和质量汇总。

输出中的新增字段包括：

- `*_normalized`：标准化 ID；
- `attributed_team_id`：最终用于成本归属的团队；
- `team_attribution_source`：团队来自账单还是资源清单。

## 先建立规则表

在清洗文件开头记录：

| 问题 | 规则 | 原始值是否保留 | 验证方式 |
|---|---|---|---|
| ID 大小写和分隔符 | `TRIM`、转大写、`_` 改为 `-` | 是 | 标准化后关联率 |
| 时间文本 | 转换为 UTC TIMESTAMP | 是 | 转换失败数量 |
| 数字文本 | 使用 `TRY_CAST` | 是 | 转换失败数量和范围 |
| 完全重复 | 按全部字段或记录 ID标记 | 是 | 删除前后行数 |
| 业务重复 | 按业务键和保留优先级处理 | 是 | 每个键保留一行 |
| 空值 | 按业务含义保留、填充或排除 | 是 | 各列空值变化 |

不要写“清洗异常数据”这种无法执行的规则。

## A. 使用 DuckDB 建立干净视图

```sql
CREATE OR REPLACE VIEW clean_inventory AS
SELECT
  UPPER(REPLACE(TRIM(resource_pool_id), '_', '-')) AS resource_pool_id,
  UPPER(REPLACE(TRIM(team_id), '_', '-')) AS team_id,
  UPPER(REPLACE(TRIM(product_id), '_', '-')) AS product_id,
  workload_type,
  gpu_model,
  TRY_CAST(gpu_count AS INTEGER) AS gpu_count,
  region,
  cloud_provider,
  procurement_model,
  NULLIF(TRIM(contract_id), '') AS contract_id,
  TRY_CAST(start_date AS DATE) AS start_date,
  TRY_CAST(NULLIF(end_date, '') AS DATE) AS end_date,
  TRY_CAST(hourly_list_price_usd AS DOUBLE) AS hourly_list_price_usd,
  TRY_CAST(effective_hourly_rate_usd AS DOUBLE) AS effective_hourly_rate_usd,
  failover_role,
  environment,
  cost_center
FROM read_csv_auto('data/resource_inventory.csv', all_varchar = true);
```

核心方法：

- `TRIM`：删除文本两端空格；
- `UPPER`：统一大写；
- `REPLACE`：统一分隔符；
- `NULLIF(value, '')`：把空字符串变为 NULL；
- `TRY_CAST`：安全转换数据类型。

## B. 处理重复时保留判断依据

示例框架：

```sql
WITH ranked AS (
  SELECT
    *,
    ROW_NUMBER() OVER (
      PARTITION BY usage_record_id
      ORDER BY
        CASE telemetry_status WHEN 'complete' THEN 1 WHEN 'late' THEN 2 ELSE 3 END,
        timestamp_utc
    ) AS keep_rank
  FROM clean_usage_before_dedup
)
SELECT * EXCLUDE (keep_rank)
FROM ranked
WHERE keep_rank = 1;
```

这只是方法示范。实际 `PARTITION BY` 字段和优先顺序必须来自审计结论。

## C. 空值处理决策

对每个字段只允许以下选择之一：

1. 保留 NULL：不知道就是不知道。
2. 排除记录：仅在该指标计算中排除，并报告样本损失。
3. 业务规则填充：必须有文档或可靠字段支持。
4. 统计填充：只用于合适的模型输入，并记录方法。

禁止把所有数值空值统一填 0。利用率为空和利用率为 0 是两个不同事实。

## D. 什么时候使用 Pandas

SQL 更适合：

- 类型转换；
- 字符串标准化；
- 去重；
- 表连接；
- 大型 CSV 汇总。

Pandas 更适合：

- 复杂的行级规则；
- 需要逐步检查的时间序列；
- 预测前特征处理；
- Python 图表和模型接口。

常用 Pandas 示例：

```python
import pandas as pd

inventory = pd.read_csv("data/resource_inventory.csv", dtype="string")
inventory["resource_pool_id_clean"] = (
    inventory["resource_pool_id"]
    .str.strip()
    .str.upper()
    .str.replace("_", "-", regex=False)
)
inventory["gpu_count_num"] = pd.to_numeric(inventory["gpu_count"], errors="coerce")
```

## E. 为什么本项目先输出 CSV

Parquet 更快、更小并能保存数据类型，但还需要额外的 Parquet 引擎。当前阶段继续使用 CSV，便于直接查看和导入 Power BI，也不增加依赖。数据量或读取耗时真正成为问题时再切换 Parquet。

```text
outputs/cleaned/
├── resource_usage.csv
├── cloud_billing.csv
├── resource_inventory.csv
├── team_sla.csv
├── business_events.csv
└── quality_summary.csv
```

## F. 清洗后必须重新验证

比较清洗前后：

- 行数；
- 主键唯一性；
- 空值数量；
- 类型转换失败数；
- 关联成功率；
- 关键金额和用量总计；
- 时间范围。

清洗不能让总成本或业务量在没有解释的情况下变化。

## 清洗知识树

```text
标准化
├── 文本：TRIM / UPPER / REPLACE
├── 空值：NULLIF / IS NULL
├── 类型：TRY_CAST / to_datetime
├── 重复：业务键 + ROW_NUMBER
├── 关联：标准化键 + 覆盖率
└── 输出：CSV + 质量汇总 + 可重复脚本
```

## 验收标准

- 每个清洗动作都能对应审计问题。
- 原始值或原始文件仍然存在。
- 清洗规则可以从头重新运行。
- 去重规则说明保留哪一行以及原因。
- 金额和用量变化得到核对。
- `outputs/` 没有提交 Git。

## 建议提交

提交代码、测试和文档，不提交 `outputs/` 中的衍生数据。
