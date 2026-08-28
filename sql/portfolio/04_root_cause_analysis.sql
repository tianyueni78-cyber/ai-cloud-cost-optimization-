-- 原因分析：把团队月度成本与同单位业务量、利用率、采购结构、SLA代理指标和事件对齐。
-- 本文件只识别证据一致的关联，不把时间重合直接写成因果。

SET TimeZone = 'UTC';

CREATE OR REPLACE TEMP VIEW clean_billing AS
SELECT * FROM read_csv_auto('outputs/cleaned/cloud_billing.csv');

CREATE OR REPLACE TEMP VIEW clean_usage AS
SELECT * FROM read_csv_auto('outputs/cleaned/resource_usage.csv');

CREATE OR REPLACE TEMP VIEW clean_inventory AS
SELECT * FROM read_csv_auto('outputs/cleaned/resource_inventory.csv');

CREATE OR REPLACE TEMP VIEW clean_sla AS
SELECT * FROM read_csv_auto('outputs/cleaned/team_sla.csv');

CREATE OR REPLACE TEMP VIEW clean_events AS
SELECT * FROM read_csv_auto('outputs/cleaned/business_events.csv');

-- 1. 单位安全检查：每个团队实际使用哪些负载与业务量单位
SELECT
    team_id_normalized AS team_id,
    workload_type,
    volume_unit,
    COUNT(*) AS usage_rows
FROM clean_usage
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;

CREATE OR REPLACE TEMP VIEW monthly_team_cost AS
SELECT
    billing.attributed_team_id AS team_id,
    STRFTIME(billing.usage_start_date, '%Y-%m') AS usage_month,
    inventory.workload_type,
    SUM(billing.net_cost_usd) AS total_cost_usd
FROM clean_billing billing
INNER JOIN clean_inventory inventory
  ON billing.resource_pool_id_normalized = inventory.resource_pool_id_normalized
WHERE billing.usage_start_date >= DATE '2025-08-01'
  AND billing.usage_start_date < DATE '2026-08-01'
  AND billing.charge_type IN ('Usage', 'Commitment', 'Credit', 'Adjustment', 'Support')
GROUP BY 1, 2, 3;

CREATE OR REPLACE TEMP VIEW monthly_team_usage AS
SELECT
    team_id_normalized AS team_id,
    STRFTIME(timestamp_utc, '%Y-%m') AS usage_month,
    workload_type,
    volume_unit,
    SUM(business_volume) AS business_volume,
    SUM(gpu_utilization_pct * allocated_gpu_count)
        FILTER (WHERE gpu_utilization_pct IS NOT NULL)
        / NULLIF(SUM(allocated_gpu_count) FILTER (WHERE gpu_utilization_pct IS NOT NULL), 0)
        AS weighted_gpu_utilization_pct,
    100 * SUM(active_gpu_count) / NULLIF(SUM(allocated_gpu_count), 0)
        AS active_capacity_pct,
    100 * COUNT(gpu_utilization_pct) / COUNT(*) AS gpu_metric_coverage_pct
FROM clean_usage
GROUP BY 1, 2, 3, 4;

CREATE OR REPLACE TEMP VIEW monthly_team_panel AS
WITH panel AS (
    SELECT
        usage.team_id,
        usage.usage_month,
        usage.workload_type,
        usage.volume_unit,
        cost.total_cost_usd,
        usage.business_volume,
        cost.total_cost_usd / NULLIF(usage.business_volume, 0) AS unit_cost_usd,
        cost.total_cost_usd
            / DAY(LAST_DAY(STRPTIME(usage.usage_month, '%Y-%m')))
            AS daily_cost_usd,
        usage.weighted_gpu_utilization_pct,
        usage.active_capacity_pct,
        usage.gpu_metric_coverage_pct
    FROM monthly_team_usage usage
    INNER JOIN monthly_team_cost cost USING (team_id, usage_month, workload_type)
), changes AS (
    SELECT
        *,
        100 * (total_cost_usd / LAG(total_cost_usd) OVER (
            PARTITION BY team_id, workload_type, volume_unit ORDER BY usage_month
        ) - 1) AS cost_mom_pct,
        100 * (business_volume / LAG(business_volume) OVER (
            PARTITION BY team_id, workload_type, volume_unit ORDER BY usage_month
        ) - 1) AS volume_mom_pct,
        100 * (unit_cost_usd / LAG(unit_cost_usd) OVER (
            PARTITION BY team_id, workload_type, volume_unit ORDER BY usage_month
        ) - 1) AS unit_cost_mom_pct,
        100 * (daily_cost_usd / LAG(daily_cost_usd) OVER (
            PARTITION BY team_id, workload_type, volume_unit ORDER BY usage_month
        ) - 1) AS daily_cost_mom_pct
    FROM panel
)
SELECT * FROM changes;

-- 2. 团队年度趋势：成本增长、业务增长和利用率必须一起看
SELECT
    team_id,
    workload_type,
    volume_unit,
    ROUND(100 * (ARG_MAX(total_cost_usd, usage_month) / ARG_MIN(total_cost_usd, usage_month) - 1), 2)
        AS cost_growth_pct,
    ROUND(100 * (ARG_MAX(business_volume, usage_month) / ARG_MIN(business_volume, usage_month) - 1), 2)
        AS volume_growth_pct,
    ROUND(100 * (
        ARG_MAX(unit_cost_usd, usage_month) / ARG_MIN(unit_cost_usd, usage_month) - 1
    ), 2) AS unit_cost_growth_pct,
    ROUND(AVG(weighted_gpu_utilization_pct), 2) AS avg_weighted_gpu_utilization_pct
FROM monthly_team_panel
GROUP BY 1, 2, 3
ORDER BY cost_growth_pct DESC;

-- 3. 表面异常：原始月成本增幅超过5%，但业务量没有同步增长。
-- 同时输出日均成本环比，用于识别不同月份天数造成的日历效应。
SELECT
    team_id,
    usage_month,
    workload_type,
    ROUND(cost_mom_pct, 2) AS cost_mom_pct,
    ROUND(daily_cost_mom_pct, 2) AS daily_cost_mom_pct,
    ROUND(volume_mom_pct, 2) AS volume_mom_pct,
    ROUND(unit_cost_mom_pct, 2) AS unit_cost_mom_pct,
    ROUND(weighted_gpu_utilization_pct, 2) AS weighted_gpu_utilization_pct
FROM monthly_team_panel
WHERE cost_mom_pct > 5
  AND volume_mom_pct <= 0
ORDER BY cost_mom_pct DESC;

-- 3.1 对异常月份及其上月按采购方式和GPU型号拆解
WITH flagged AS (
    SELECT team_id, usage_month, workload_type
    FROM monthly_team_panel
    WHERE cost_mom_pct > 5
      AND volume_mom_pct <= 0
), comparison_months AS (
    SELECT team_id, usage_month, workload_type FROM flagged
    UNION
    SELECT
        team_id,
        STRFTIME(STRPTIME(usage_month, '%Y-%m') - INTERVAL 1 MONTH, '%Y-%m'),
        workload_type
    FROM flagged
)
SELECT
    billing.attributed_team_id AS team_id,
    STRFTIME(billing.usage_start_date, '%Y-%m') AS usage_month,
    inventory.workload_type,
    billing.procurement_model,
    inventory.gpu_model,
    ROUND(SUM(billing.net_cost_usd), 2) AS total_cost_usd
FROM clean_billing billing
INNER JOIN clean_inventory inventory
  ON billing.resource_pool_id_normalized = inventory.resource_pool_id_normalized
INNER JOIN comparison_months months
  ON billing.attributed_team_id = months.team_id
 AND STRFTIME(billing.usage_start_date, '%Y-%m') = months.usage_month
 AND inventory.workload_type = months.workload_type
WHERE billing.charge_type IN ('Usage', 'Commitment', 'Credit', 'Adjustment', 'Support')
GROUP BY 1, 2, 3, 4, 5
ORDER BY team_id, usage_month, total_cost_usd DESC;

-- 4. GPU型号：成本与利用率并列，不用单一指标下结论
WITH model_cost AS (
    SELECT
        inventory.gpu_model,
        SUM(billing.net_cost_usd) AS total_cost_usd
    FROM clean_billing billing
    INNER JOIN clean_inventory inventory
      ON billing.resource_pool_id_normalized = inventory.resource_pool_id_normalized
    WHERE billing.usage_start_date >= DATE '2025-08-01'
      AND billing.usage_start_date < DATE '2026-08-01'
      AND billing.charge_type IN ('Usage', 'Commitment', 'Credit', 'Adjustment', 'Support')
    GROUP BY 1
), model_usage AS (
    SELECT
        inventory.gpu_model,
        SUM(usage.gpu_utilization_pct * usage.allocated_gpu_count)
            FILTER (WHERE usage.gpu_utilization_pct IS NOT NULL)
            / NULLIF(SUM(usage.allocated_gpu_count)
                FILTER (WHERE usage.gpu_utilization_pct IS NOT NULL), 0)
            AS weighted_gpu_utilization_pct,
        100 * SUM(usage.active_gpu_count) / NULLIF(SUM(usage.allocated_gpu_count), 0)
            AS active_capacity_pct
    FROM clean_usage usage
    INNER JOIN clean_inventory inventory
      ON usage.resource_pool_id_normalized = inventory.resource_pool_id_normalized
    GROUP BY 1
)
SELECT
    model_cost.gpu_model,
    ROUND(model_cost.total_cost_usd, 2) AS total_cost_usd,
    ROUND(model_usage.weighted_gpu_utilization_pct, 2) AS weighted_gpu_utilization_pct,
    ROUND(model_usage.active_capacity_pct, 2) AS active_capacity_pct
FROM model_cost
INNER JOIN model_usage USING (gpu_model)
ORDER BY total_cost_usd DESC;

-- 5. SLA代理风险：用于保护决策，不作为正式SLA结算结果
WITH usage_sla AS (
    SELECT
        usage.team_id_normalized AS team_id,
        STRFTIME(usage.timestamp_utc, '%Y-%m') AS usage_month,
        usage.workload_type,
        usage.availability_pct,
        usage.p95_latency_ms,
        usage.queue_time_seconds,
        sla.availability_target_pct,
        sla.p95_latency_target_ms,
        sla.max_queue_time_seconds
    FROM clean_usage usage
    INNER JOIN clean_inventory inventory
      ON usage.resource_pool_id_normalized = inventory.resource_pool_id_normalized
    INNER JOIN clean_sla sla
      ON usage.team_id_normalized = sla.team_id_normalized
     AND usage.product_id_normalized = sla.product_id_normalized
     AND usage.workload_type = sla.workload_type
     AND inventory.region = sla.region
     AND CAST(usage.timestamp_utc AS DATE) >= sla.effective_from
     AND (
        NULLIF(TRIM(CAST(sla.effective_to AS VARCHAR)), '') IS NULL
        OR CAST(usage.timestamp_utc AS DATE) <= TRY_CAST(sla.effective_to AS DATE)
     )
), monthly_proxy AS (
    SELECT
        team_id,
        usage_month,
        workload_type,
        AVG(availability_pct) AS avg_availability_pct,
        MAX(availability_target_pct) AS availability_target_pct,
        QUANTILE_CONT(p95_latency_ms, 0.95) AS p95_of_hourly_p95_ms,
        MAX(p95_latency_target_ms) AS p95_latency_target_ms,
        MAX(queue_time_seconds) AS max_queue_time_seconds,
        MAX(max_queue_time_seconds) AS queue_target_seconds
    FROM usage_sla
    GROUP BY 1, 2, 3
)
SELECT
    team_id,
    COUNT(*) FILTER (
        WHERE availability_target_pct IS NOT NULL
          AND avg_availability_pct < availability_target_pct
    ) AS availability_risk_months,
    COUNT(*) FILTER (
        WHERE p95_latency_target_ms IS NOT NULL
          AND p95_of_hourly_p95_ms > p95_latency_target_ms
    ) AS latency_risk_months,
    COUNT(*) FILTER (
        WHERE queue_target_seconds IS NOT NULL
          AND max_queue_time_seconds > queue_target_seconds
    ) AS queue_risk_months
FROM monthly_proxy
GROUP BY 1
ORDER BY 1;

-- 6. 业务事件：只提供异常月份解释线索，不直接证明因果
SELECT
    STRFTIME(start_timestamp_utc, '%Y-%m') AS event_month,
    COALESCE(team_id_normalized, 'COMPANY_OR_REGION') AS team_id,
    event_type,
    severity,
    expected_impact,
    event_description
FROM clean_events
ORDER BY event_month, team_id, event_type;

-- 7. 面板完整性：每个团队每月应只有一行业务量口径
SELECT
    COUNT(*) AS panel_rows,
    COUNT(DISTINCT team_id || '|' || usage_month || '|' || workload_type)
        AS distinct_team_month_workloads,
    COUNT(*) - COUNT(DISTINCT team_id || '|' || usage_month || '|' || workload_type)
        AS duplicate_panel_rows,
    COUNT(*) FILTER (WHERE total_cost_usd IS NULL OR business_volume IS NULL) AS incomplete_rows
FROM monthly_team_panel;
