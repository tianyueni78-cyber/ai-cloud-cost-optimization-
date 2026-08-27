-- 成本基线：先算准总额，再按时间和采购方式拆分。
-- 本文件只读取清洗后的账单表，不连接维表，避免JOIN放大金额。

SET TimeZone = 'UTC';

CREATE OR REPLACE TEMP VIEW baseline_billing AS
SELECT *
FROM read_csv_auto('outputs/cleaned/cloud_billing.csv')
WHERE usage_start_date >= DATE '2025-08-01'
  AND usage_start_date < DATE '2026-08-01';

-- 1. 十二个月总成本与闲置承诺成本
SELECT
    ROUND(SUM(net_cost_usd) FILTER (
        WHERE charge_type IN ('Usage', 'Commitment', 'Credit', 'Adjustment', 'Support')
    ), 2) AS gpu_total_cost_usd,
    ROUND(SUM(net_cost_usd) FILTER (
        WHERE charge_type = 'UnusedCommitment'
    ), 2) AS unused_commitment_usd,
    COUNT(*) AS billing_rows
FROM baseline_billing;

-- 2. 业务使用月份成本趋势
WITH monthly_cost AS (
    SELECT
        STRFTIME(usage_start_date, '%Y-%m') AS usage_month,
        SUM(net_cost_usd) FILTER (
            WHERE charge_type IN ('Usage', 'Commitment', 'Credit', 'Adjustment', 'Support')
        ) AS total_cost_usd,
        SUM(net_cost_usd) FILTER (
            WHERE charge_type = 'UnusedCommitment'
        ) AS unused_commitment_usd
    FROM baseline_billing
    GROUP BY usage_month
)
SELECT
    usage_month,
    ROUND(total_cost_usd, 2) AS total_cost_usd,
    ROUND(unused_commitment_usd, 2) AS unused_commitment_usd,
    ROUND(
        100 * (total_cost_usd / LAG(total_cost_usd) OVER (ORDER BY usage_month) - 1),
        2
    ) AS month_over_month_pct
FROM monthly_cost
ORDER BY usage_month;

-- 3. 财务发票月份趋势；允许出现观察期之后的延迟入账月份
SELECT
    invoice_month,
    ROUND(SUM(net_cost_usd) FILTER (
        WHERE charge_type IN ('Usage', 'Commitment', 'Credit', 'Adjustment', 'Support')
    ), 2) AS total_cost_usd
FROM baseline_billing
GROUP BY invoice_month
ORDER BY invoice_month;

-- 4. 采购方式成本结构
WITH procurement_cost AS (
    SELECT
        procurement_model,
        SUM(net_cost_usd) AS total_cost_usd
    FROM baseline_billing
    WHERE charge_type IN ('Usage', 'Commitment', 'Credit', 'Adjustment', 'Support')
    GROUP BY procurement_model
)
SELECT
    procurement_model,
    ROUND(total_cost_usd, 2) AS total_cost_usd,
    ROUND(100 * total_cost_usd / SUM(total_cost_usd) OVER (), 2) AS cost_share_pct
FROM procurement_cost
ORDER BY total_cost_usd DESC;

-- 5. 费用类型对账；UnusedCommitment只展示，不进入总成本
SELECT
    charge_type,
    COUNT(*) AS billing_rows,
    ROUND(SUM(net_cost_usd), 2) AS net_cost_usd,
    charge_type IN ('Usage', 'Commitment', 'Credit', 'Adjustment', 'Support') AS included_in_total
FROM baseline_billing
GROUP BY charge_type
ORDER BY charge_type;

-- 6. 基线验证：主键、金额公式和观察期
SELECT
    COUNT(*) - COUNT(DISTINCT billing_line_id_normalized) AS duplicate_billing_lines,
    COUNT(*) FILTER (
        WHERE ABS(net_cost_usd - (gross_cost_usd - discount_usd)) > 0.01
    ) AS inconsistent_amount_rows,
    MIN(usage_start_date) AS first_usage_date,
    MAX(usage_end_date) AS last_usage_date
FROM baseline_billing;
