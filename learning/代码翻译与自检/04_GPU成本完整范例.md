# GPU 账单总成本：完整范例

这份范例演示怎样把“六定”接到代码和验证。它是完整示范，不是要求背诵的标准答案。

## 1. 先完成六定

| 项目 | 本例答案 |
|---|---|
| 业务问题 | 公司每月实际承担多少 GPU 净账单费用，采购结构怎样变化 |
| 主表 | `cloud_billing.csv` |
| 来源粒度 | 一条账单费用记录 |
| 输出粒度 | 公司 × 发票月；需要时再下钻采购方式 |
| 数值与公式 | 符合总账口径的 `net_cost_usd` 之和 |
| 费用口径 | 计入 Usage、Commitment、Credit、Adjustment、Support；UnusedCommitment 单独展示，不重复计入 |
| 主时间 | `usage_start_date` 至 `usage_end_date` 用于业务发生期间 |
| 辅助时间 | `invoice_month` 用于财务月度视图 |
| 初始关联 | 不需要；账单表已包含金额和采购方式 |

关键架构判断：先在账单事实表形成可信总额，再在确实需要 GPU 型号、资源池属性等维度时连接资源清单。

## 2. 把业务语言翻译成代码动作

| 业务语言 | 代码动作 |
|---|---|
| 把净成本加起来 | `SUM(net_cost_usd)` / `.sum()` |
| 只纳入总账费用类型 | `WHERE ... IN (...)` / `.isin(...)` |
| 分别看每个发票月 | `GROUP BY invoice_month` / `.groupby()` |
| 看采购结构 | 再增加 `procurement_model` 分组 |
| 高成本排在前面 | `ORDER BY total_cost_usd DESC` / `.sort_values()` |

## 3. SQL 主查询：公司月度成本

```sql
WITH clean_billing AS (
    SELECT *
    FROM read_csv_auto('outputs/cleaned/cloud_billing.csv')
),
included_cost AS (
    SELECT *
    FROM clean_billing
    WHERE charge_type IN (
        'Usage', 'Commitment', 'Credit', 'Adjustment', 'Support'
    )
)
SELECT
    invoice_month,
    ROUND(SUM(net_cost_usd), 2) AS total_cost_usd
FROM included_cost
GROUP BY invoice_month
ORDER BY invoice_month;
```

逐行翻译回业务语言：读取清洗账单 → 只留总账费用 → 按发票月分别看 → 加总净成本 → 按月份排列。

## 4. SQL 下钻：采购结构

```sql
WITH included_cost AS (
    SELECT *
    FROM read_csv_auto('outputs/cleaned/cloud_billing.csv')
    WHERE charge_type IN (
        'Usage', 'Commitment', 'Credit', 'Adjustment', 'Support'
    )
)
SELECT
    invoice_month,
    procurement_model,
    ROUND(SUM(net_cost_usd), 2) AS total_cost_usd
FROM included_cost
GROUP BY invoice_month, procurement_model
ORDER BY invoice_month, total_cost_usd DESC;
```

这里仍不需要资源清单，因为 `procurement_model` 已在账单表中。

## 5. SQL 独立验证

### A. 主键是否重复

```sql
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT billing_line_id) AS distinct_billing_lines,
    COUNT(*) - COUNT(DISTINCT billing_line_id) AS extra_rows
FROM read_csv_auto('outputs/cleaned/cloud_billing.csv');
```

期望：`extra_rows` 为 0；否则要先定位重复行。

### B. 金额公式是否成立

```sql
SELECT COUNT(*) AS violation_rows
FROM read_csv_auto('outputs/cleaned/cloud_billing.csv')
WHERE ABS(net_cost_usd - (gross_cost_usd - discount_usd)) > 0.01;
```

期望：违反行数为 0，或每个差异都有明确业务解释。

### C. 费用分类是否完整

```sql
SELECT
    charge_type,
    COUNT(*) AS billing_rows,
    ROUND(SUM(net_cost_usd), 2) AS subtotal_usd
FROM read_csv_auto('outputs/cleaned/cloud_billing.csv')
GROUP BY charge_type
ORDER BY charge_type;
```

检查已知类型是否都出现；`UnusedCommitment` 作为浪费信号单独观察，但不再次加入总成本。

### D. 小计是否回到总计

```sql
WITH detail AS (
    SELECT
        invoice_month,
        procurement_model,
        SUM(net_cost_usd) AS subtotal
    FROM read_csv_auto('outputs/cleaned/cloud_billing.csv')
    WHERE charge_type IN (
        'Usage', 'Commitment', 'Credit', 'Adjustment', 'Support'
    )
    GROUP BY invoice_month, procurement_model
),
monthly AS (
    SELECT
        invoice_month,
        SUM(net_cost_usd) AS total
    FROM read_csv_auto('outputs/cleaned/cloud_billing.csv')
    WHERE charge_type IN (
        'Usage', 'Commitment', 'Credit', 'Adjustment', 'Support'
    )
    GROUP BY invoice_month
)
SELECT
    d.invoice_month,
    SUM(d.subtotal) AS sum_of_subtotals,
    m.total AS grand_total,
    SUM(d.subtotal) - m.total AS difference
FROM detail d
JOIN monthly m USING (invoice_month)
GROUP BY d.invoice_month, m.total
ORDER BY d.invoice_month;
```

期望：每个月的 `difference` 为 0 或仅有可接受的浮点误差。

## 6. Pandas 等价实现

```python
import pandas as pd

billing = pd.read_csv(
    "outputs/cleaned/cloud_billing.csv",
    low_memory=False,
)

included_types = [
    "Usage", "Commitment", "Credit", "Adjustment", "Support"
]
included = billing.loc[
    billing["charge_type"].isin(included_types)
].copy()

monthly_cost = (
    included
    .groupby("invoice_month", dropna=False, as_index=False)
    .agg(total_cost_usd=("net_cost_usd", "sum"))
    .sort_values("invoice_month")
)

print(monthly_cost)
```

对应验证：

```python
# 主键重复
extra_rows = len(billing) - billing["billing_line_id"].nunique(dropna=False)

# 金额公式
formula_difference = (
    billing["net_cost_usd"]
    - (billing["gross_cost_usd"] - billing["discount_usd"])
).abs()
formula_violations = int(formula_difference.gt(0.01).sum())

# 分类小计回到总计
procurement_detail = (
    included
    .groupby(["invoice_month", "procurement_model"], dropna=False, as_index=False)
    .agg(subtotal=("net_cost_usd", "sum"))
)
subtotal_check = (
    procurement_detail.groupby("invoice_month", dropna=False)["subtotal"].sum()
    - included.groupby("invoice_month", dropna=False)["net_cost_usd"].sum()
)

print({
    "extra_rows": extra_rows,
    "formula_violations": formula_violations,
    "largest_reconciliation_difference": subtotal_check.abs().max(),
})
```

## 7. 什么时候才连接资源清单

当问题变成以下形式时才需要连接：

- 哪种 GPU 型号成本最高；
- 哪个资源池成本与利用率不匹配；
- 某账单费用属于哪个成本中心；
- 采购结构能否与当前资源容量相匹配。

连接前先确认账单表和资源清单的共同键、ID 标准化规则、资源有效期以及右表键唯一性；连接后验证总成本没有放大或丢失。

## 8. 最终自我解释

在采用结果前，应能不用代码回答：

1. 为什么主表是账单表而不是资源使用表；
2. 为什么基础总额不需要 JOIN；
3. 哪五类费用进入总额；
4. 为什么未使用承诺单独展示；
5. 如何证明结果没有重复、漏算或被 JOIN 放大；
6. 这个指标能支持采购结构判断，但为什么不能单独证明应该回收某个低利用率资源。

返回：[代码翻译与自检入口](README.md) · [固定自检程序](03_固定自检程序.md)
