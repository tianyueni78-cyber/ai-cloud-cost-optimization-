-- 第一轮业务概览：成本结构、GPU 资源、负载和月度趋势
-- 总账成本不重复计入 UnusedCommitment；业务量按单位分别汇总

SET TimeZone = 'UTC';

CREATE OR REPLACE TEMP VIEW clean_billing AS
SELECT * FROM read_csv_auto('outputs/cleaned/cloud_billing.csv');

CREATE OR REPLACE TEMP VIEW clean_usage AS
SELECT * FROM read_csv_auto('outputs/cleaned/resource_usage.csv');

CREATE OR REPLACE TEMP VIEW clean_inventory AS
SELECT * FROM read_csv_auto('outputs/cleaned/resource_inventory.csv');

-- 1. 各团队总成本：使用清洗后的归属团队
WITH team_cost AS (
    SELECT
        attributed_team_id AS team_id,
        SUM(net_cost_usd) AS total_cost_usd
    FROM clean_billing
    WHERE charge_type <> 'UnusedCommitment'
    GROUP BY attributed_team_id
)
SELECT
    team_id,
    ROUND(total_cost_usd, 2) AS total_cost_usd,
    ROUND(100 * total_cost_usd / SUM(total_cost_usd) OVER (), 2) AS cost_share_pct
FROM team_cost
ORDER BY total_cost_usd DESC;

-- 2. 各采购方式成本结构
WITH procurement_cost AS (
    SELECT
        procurement_model,
        COUNT(*) AS billing_rows,
        SUM(net_cost_usd) AS total_cost_usd
    FROM clean_billing
    WHERE charge_type <> 'UnusedCommitment'
    GROUP BY procurement_model
)
SELECT
    procurement_model,
    billing_rows,
    ROUND(total_cost_usd, 2) AS total_cost_usd,
    ROUND(100 * total_cost_usd / SUM(total_cost_usd) OVER (), 2) AS cost_share_pct
FROM procurement_cost
ORDER BY total_cost_usd DESC;

-- 3. 各 GPU 型号的清单数量与小时级平均利用率
WITH inventory_by_model AS (
    SELECT gpu_model, SUM(gpu_count) AS inventory_gpu_count
    FROM clean_inventory
    GROUP BY gpu_model
), usage_by_model AS (
    SELECT
        inventory.gpu_model,
        AVG(usage.gpu_utilization_pct) AS avg_gpu_utilization_pct
    FROM clean_usage usage
    INNER JOIN clean_inventory inventory
      ON usage.resource_pool_id_normalized = inventory.resource_pool_id_normalized
    GROUP BY inventory.gpu_model
)
SELECT
    inventory.gpu_model,
    inventory.inventory_gpu_count,
    ROUND(usage.avg_gpu_utilization_pct, 2) AS avg_gpu_utilization_pct
FROM inventory_by_model inventory
LEFT JOIN usage_by_model usage USING (gpu_model)
ORDER BY inventory.inventory_gpu_count DESC;

-- 4. 各负载类型业务量和利用率；不同单位绝不混加
SELECT
    workload_type,
    volume_unit,
    SUM(business_volume) AS total_business_volume,
    ROUND(AVG(gpu_utilization_pct), 2) AS avg_gpu_utilization_pct
FROM clean_usage
GROUP BY workload_type, volume_unit
ORDER BY workload_type, volume_unit;

-- 5. 发票月份成本趋势
SELECT
    invoice_month,
    ROUND(SUM(net_cost_usd), 2) AS total_cost_usd,
    ROUND(
        100 * (
            SUM(net_cost_usd)
            / LAG(SUM(net_cost_usd)) OVER (ORDER BY invoice_month)
            - 1
        ),
        2
    ) AS month_over_month_pct
FROM clean_billing
WHERE charge_type <> 'UnusedCommitment'
GROUP BY invoice_month
ORDER BY invoice_month;
