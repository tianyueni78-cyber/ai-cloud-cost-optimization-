-- 成本归因：团队直接使用清洗后的归属；产品、GPU型号和资源池通过唯一资源清单补充。
-- 无资源池的共享费用保留在UNALLOCATED_SHARED，确保总账完整且不虚构分摊规则。

SET TimeZone = 'UTC';

CREATE OR REPLACE TEMP VIEW ledger_billing AS
SELECT *
FROM read_csv_auto('outputs/cleaned/cloud_billing.csv')
WHERE usage_start_date >= DATE '2025-08-01'
  AND usage_start_date < DATE '2026-08-01'
  AND charge_type IN ('Usage', 'Commitment', 'Credit', 'Adjustment', 'Support');

CREATE OR REPLACE TEMP VIEW clean_inventory AS
SELECT *
FROM read_csv_auto('outputs/cleaned/resource_inventory.csv');

CREATE OR REPLACE TEMP VIEW attributed_cost AS
SELECT
    billing.*,
    inventory.product_id_normalized,
    inventory.gpu_model,
    inventory.region,
    inventory.environment
FROM ledger_billing billing
LEFT JOIN clean_inventory inventory
  ON billing.resource_pool_id_normalized = inventory.resource_pool_id_normalized;

-- 1. 归因前后对账与直接归因覆盖率
SELECT
    COUNT(*) AS ledger_rows,
    ROUND(SUM(net_cost_usd), 2) AS ledger_cost_usd,
    COUNT(*) FILTER (WHERE product_id_normalized IS NULL) AS unallocated_rows,
    ROUND(SUM(net_cost_usd) FILTER (WHERE product_id_normalized IS NULL), 2) AS unallocated_cost_usd,
    ROUND(100 * COUNT(*) FILTER (WHERE product_id_normalized IS NOT NULL) / COUNT(*), 2) AS direct_row_coverage_pct,
    ROUND(100 * SUM(net_cost_usd) FILTER (WHERE product_id_normalized IS NOT NULL) / SUM(net_cost_usd), 2) AS direct_cost_coverage_pct
FROM attributed_cost;

-- 2. 团队成本；所有账单必须已有attributed_team_id
WITH team_cost AS (
    SELECT
        attributed_team_id AS team_id,
        SUM(net_cost_usd) AS total_cost_usd
    FROM attributed_cost
    GROUP BY attributed_team_id
)
SELECT
    team_id,
    ROUND(total_cost_usd, 2) AS total_cost_usd,
    ROUND(100 * total_cost_usd / SUM(total_cost_usd) OVER (), 2) AS cost_share_pct
FROM team_cost
ORDER BY total_cost_usd DESC;

-- 3. 产品成本；共享费用不强行分摊
WITH product_cost AS (
    SELECT
        COALESCE(product_id_normalized, 'UNALLOCATED_SHARED') AS product_id,
        SUM(net_cost_usd) AS total_cost_usd
    FROM attributed_cost
    GROUP BY product_id
)
SELECT
    product_id,
    ROUND(total_cost_usd, 2) AS total_cost_usd,
    ROUND(100 * total_cost_usd / SUM(total_cost_usd) OVER (), 2) AS cost_share_pct
FROM product_cost
ORDER BY total_cost_usd DESC;

-- 4. GPU型号成本；共享费用不强行分摊
WITH model_cost AS (
    SELECT
        COALESCE(gpu_model, 'UNALLOCATED_SHARED') AS gpu_model,
        SUM(net_cost_usd) AS total_cost_usd
    FROM attributed_cost
    GROUP BY gpu_model
)
SELECT
    gpu_model,
    ROUND(total_cost_usd, 2) AS total_cost_usd,
    ROUND(100 * total_cost_usd / SUM(total_cost_usd) OVER (), 2) AS cost_share_pct
FROM model_cost
ORDER BY total_cost_usd DESC;

-- 5. 成本最高的10个资源池
WITH pool_cost AS (
    SELECT
        resource_pool_id_normalized AS resource_pool_id,
        attributed_team_id AS team_id,
        product_id_normalized AS product_id,
        gpu_model,
        SUM(net_cost_usd) AS total_cost_usd
    FROM attributed_cost
    WHERE resource_pool_id_normalized IS NOT NULL
    GROUP BY 1, 2, 3, 4
)
SELECT
    resource_pool_id,
    team_id,
    product_id,
    gpu_model,
    ROUND(total_cost_usd, 2) AS total_cost_usd
FROM pool_cost
ORDER BY total_cost_usd DESC
LIMIT 10;

-- 6. 共享未分配费用的来源
SELECT
    charge_type,
    attributed_team_id AS team_id,
    COUNT(*) AS billing_rows,
    ROUND(SUM(net_cost_usd), 2) AS total_cost_usd
FROM attributed_cost
WHERE product_id_normalized IS NULL
GROUP BY 1, 2
ORDER BY charge_type, total_cost_usd DESC;

-- 7. 未使用承诺按团队归因，不计入总账成本
WITH unused_by_team AS (
    SELECT
        attributed_team_id AS team_id,
        SUM(net_cost_usd) FILTER (WHERE procurement_model = 'Reserved') AS reserved_unused_usd,
        SUM(net_cost_usd) FILTER (WHERE procurement_model = 'SavingsPlan') AS savings_plan_unused_usd,
        SUM(net_cost_usd) AS unused_commitment_usd
    FROM read_csv_auto('outputs/cleaned/cloud_billing.csv')
    WHERE usage_start_date >= DATE '2025-08-01'
      AND usage_start_date < DATE '2026-08-01'
      AND charge_type = 'UnusedCommitment'
    GROUP BY 1
)
SELECT
    team_id,
    ROUND(reserved_unused_usd, 2) AS reserved_unused_usd,
    ROUND(savings_plan_unused_usd, 2) AS savings_plan_unused_usd,
    ROUND(unused_commitment_usd, 2) AS unused_commitment_usd,
    ROUND(100 * unused_commitment_usd / SUM(unused_commitment_usd) OVER (), 2) AS unused_share_pct
FROM unused_by_team
ORDER BY unused_commitment_usd DESC;

-- 8. 连接验证：资源清单唯一，连接前后行数和金额必须保持一致
WITH source_total AS (
    SELECT COUNT(*) AS rows, SUM(net_cost_usd) AS cost FROM ledger_billing
), joined_total AS (
    SELECT COUNT(*) AS rows, SUM(net_cost_usd) AS cost FROM attributed_cost
)
SELECT
    joined_total.rows - source_total.rows AS row_difference,
    ROUND(joined_total.cost - source_total.cost, 2) AS cost_difference_usd
FROM source_total, joined_total;
