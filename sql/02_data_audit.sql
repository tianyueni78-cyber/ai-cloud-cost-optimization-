-- ============================================================
-- Data Audit
-- 目的：检查主键重复、关键字段空值、数值范围、ID 格式和关联率
-- 原则：只审计，不修改原始 CSV
-- ============================================================
-- 【迁移到其他项目】
-- 可复用：完整性、唯一性、有效性、一致性、关联率和时间范围六类检查。
-- 要替换：候选主键、业务重复键、必填字段、合法范围、枚举值和关联字段。
-- 要重写：ID 标准化规则和跨字段业务公式；它们不能从本项目照搬。
-- 注意：先按原始文本读取可避免自动转换掩盖问题；审计阶段不删除记录。
-- 输出口径：每个问题都要有异常数量、样例、业务影响和后续处理状态。


-- ------------------------------------------------------------
-- 1. 建立原始数据视图
-- 全部按文本读取，避免自动类型转换掩盖源数据问题
-- ------------------------------------------------------------

CREATE OR REPLACE VIEW raw_inventory AS
SELECT *
FROM read_csv_auto(
    'data/resource_inventory.csv',
    all_varchar = true
);

CREATE OR REPLACE VIEW raw_usage AS
SELECT *
FROM read_csv_auto(
    'data/resource_usage.csv',
    all_varchar = true
);

CREATE OR REPLACE VIEW raw_billing AS
SELECT *
FROM read_csv_auto(
    'data/cloud_billing.csv',
    all_varchar = true
);

CREATE OR REPLACE VIEW raw_sla AS
SELECT *
FROM read_csv_auto(
    'data/team_sla.csv',
    all_varchar = true
);

CREATE OR REPLACE VIEW raw_events AS
SELECT *
FROM read_csv_auto(
    'data/business_events.csv',
    all_varchar = true
);


-- ------------------------------------------------------------
-- 2. 检查五张表的主键重复
-- duplicate_key_groups 表示出现重复的主键数量
-- ------------------------------------------------------------

SELECT
    'resource_inventory' AS table_name,
    'resource_pool_id' AS key_name,
    COUNT(*) AS duplicate_key_groups
FROM (
    SELECT resource_pool_id
    FROM raw_inventory
    GROUP BY resource_pool_id
    HAVING COUNT(*) > 1
)

UNION ALL

SELECT
    'resource_usage',
    'usage_record_id',
    COUNT(*)
FROM (
    SELECT usage_record_id
    FROM raw_usage
    GROUP BY usage_record_id
    HAVING COUNT(*) > 1
)

UNION ALL

SELECT
    'cloud_billing',
    'billing_line_id',
    COUNT(*)
FROM (
    SELECT billing_line_id
    FROM raw_billing
    GROUP BY billing_line_id
    HAVING COUNT(*) > 1
)

UNION ALL

SELECT
    'team_sla',
    'sla_id',
    COUNT(*)
FROM (
    SELECT sla_id
    FROM raw_sla
    GROUP BY sla_id
    HAVING COUNT(*) > 1
)

UNION ALL

SELECT
    'business_events',
    'event_id',
    COUNT(*)
FROM (
    SELECT event_id
    FROM raw_events
    GROUP BY event_id
    HAVING COUNT(*) > 1
);


-- ------------------------------------------------------------
-- 3. 检查使用记录的业务重复
-- 同一资源池、同一小时出现多条记录时，需要进一步判断
-- ------------------------------------------------------------

SELECT
    timestamp_utc,
    UPPER(REPLACE(TRIM(resource_pool_id), '_', '-')) AS normalized_pool_id,
    COUNT(*) AS row_count,
    COUNT(DISTINCT usage_record_id) AS distinct_record_ids
FROM raw_usage
GROUP BY
    timestamp_utc,
    UPPER(REPLACE(TRIM(resource_pool_id), '_', '-'))
HAVING COUNT(*) > 1
ORDER BY row_count DESC
LIMIT 20;


-- ------------------------------------------------------------
-- 4. 检查资源清单关键字段空值
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (
        WHERE resource_pool_id IS NULL
           OR TRIM(resource_pool_id) = ''
    ) AS missing_resource_pool_id,
    COUNT(*) FILTER (
        WHERE team_id IS NULL
           OR TRIM(team_id) = ''
    ) AS missing_team_id,
    COUNT(*) FILTER (
        WHERE gpu_model IS NULL
           OR TRIM(gpu_model) = ''
    ) AS missing_gpu_model,
    COUNT(*) FILTER (
        WHERE gpu_count IS NULL
           OR TRIM(gpu_count) = ''
    ) AS missing_gpu_count,
    COUNT(*) FILTER (
        WHERE procurement_model IS NULL
           OR TRIM(procurement_model) = ''
    ) AS missing_procurement_model
FROM raw_inventory;


-- ------------------------------------------------------------
-- 5. 检查资源使用表关键字段空值
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (
        WHERE usage_record_id IS NULL
           OR TRIM(usage_record_id) = ''
    ) AS missing_usage_record_id,
    COUNT(*) FILTER (
        WHERE timestamp_utc IS NULL
           OR TRIM(timestamp_utc) = ''
    ) AS missing_timestamp,
    COUNT(*) FILTER (
        WHERE resource_pool_id IS NULL
           OR TRIM(resource_pool_id) = ''
    ) AS missing_resource_pool_id,
    COUNT(*) FILTER (
        WHERE active_gpu_count IS NULL
           OR TRIM(active_gpu_count) = ''
    ) AS missing_active_gpu_count,
    COUNT(*) FILTER (
        WHERE gpu_utilization_pct IS NULL
           OR TRIM(gpu_utilization_pct) = ''
    ) AS missing_gpu_utilization,
    COUNT(*) FILTER (
        WHERE memory_utilization_pct IS NULL
           OR TRIM(memory_utilization_pct) = ''
    ) AS missing_memory_utilization,
    COUNT(*) FILTER (
        WHERE availability_pct IS NULL
           OR TRIM(availability_pct) = ''
    ) AS missing_availability
FROM raw_usage;


-- ------------------------------------------------------------
-- 6. 检查账单关键字段空值
-- 资源池、团队和合同字段业务上允许部分为空，仍需统计
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (
        WHERE billing_line_id IS NULL
           OR TRIM(billing_line_id) = ''
    ) AS missing_billing_line_id,
    COUNT(*) FILTER (
        WHERE resource_pool_id IS NULL
           OR TRIM(resource_pool_id) = ''
    ) AS missing_resource_pool_id,
    COUNT(*) FILTER (
        WHERE team_id IS NULL
           OR TRIM(team_id) = ''
    ) AS missing_team_id,
    COUNT(*) FILTER (
        WHERE contract_id IS NULL
           OR TRIM(contract_id) = ''
    ) AS missing_contract_id,
    COUNT(*) FILTER (
        WHERE net_cost_usd IS NULL
           OR TRIM(net_cost_usd) = ''
    ) AS missing_net_cost
FROM raw_billing;


-- ------------------------------------------------------------
-- 7. 检查 SLA 和事件关键字段空值
-- ------------------------------------------------------------

SELECT
    'team_sla' AS table_name,
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (
        WHERE sla_id IS NULL OR TRIM(sla_id) = ''
    ) AS missing_primary_id,
    COUNT(*) FILTER (
        WHERE team_id IS NULL OR TRIM(team_id) = ''
    ) AS missing_team_id,
    COUNT(*) FILTER (
        WHERE product_id IS NULL OR TRIM(product_id) = ''
    ) AS missing_product_id
FROM raw_sla

UNION ALL

SELECT
    'business_events',
    COUNT(*),
    COUNT(*) FILTER (
        WHERE event_id IS NULL OR TRIM(event_id) = ''
    ),
    COUNT(*) FILTER (
        WHERE team_id IS NULL OR TRIM(team_id) = ''
    ),
    COUNT(*) FILTER (
        WHERE product_id IS NULL OR TRIM(product_id) = ''
    )
FROM raw_events;


-- ------------------------------------------------------------
-- 8. 检查主要数值范围
-- TRY_CAST 转换失败时返回 NULL，不会终止查询
-- ------------------------------------------------------------

SELECT
    MIN(TRY_CAST(allocated_gpu_count AS DOUBLE)) AS min_allocated_gpu,
    MAX(TRY_CAST(allocated_gpu_count AS DOUBLE)) AS max_allocated_gpu,
    MIN(TRY_CAST(active_gpu_count AS DOUBLE)) AS min_active_gpu,
    MAX(TRY_CAST(active_gpu_count AS DOUBLE)) AS max_active_gpu,
    MIN(TRY_CAST(gpu_utilization_pct AS DOUBLE)) AS min_gpu_utilization,
    MAX(TRY_CAST(gpu_utilization_pct AS DOUBLE)) AS max_gpu_utilization,
    MIN(TRY_CAST(memory_utilization_pct AS DOUBLE)) AS min_memory_utilization,
    MAX(TRY_CAST(memory_utilization_pct AS DOUBLE)) AS max_memory_utilization,
    MIN(TRY_CAST(availability_pct AS DOUBLE)) AS min_availability,
    MAX(TRY_CAST(availability_pct AS DOUBLE)) AS max_availability
FROM raw_usage;


-- ------------------------------------------------------------
-- 9. 检查类型转换失败
-- 字段非空但无法转换时计为失败
-- ------------------------------------------------------------

SELECT
    COUNT(*) FILTER (
        WHERE TRIM(gpu_utilization_pct) <> ''
          AND TRY_CAST(gpu_utilization_pct AS DOUBLE) IS NULL
    ) AS invalid_gpu_utilization,
    COUNT(*) FILTER (
        WHERE TRIM(memory_utilization_pct) <> ''
          AND TRY_CAST(memory_utilization_pct AS DOUBLE) IS NULL
    ) AS invalid_memory_utilization,
    COUNT(*) FILTER (
        WHERE TRIM(timestamp_utc) <> ''
          AND TRY_CAST(timestamp_utc AS TIMESTAMPTZ) IS NULL
    ) AS invalid_timestamp
FROM raw_usage;


-- ------------------------------------------------------------
-- 10. 检查账单金额关系
-- 正常规则：net_cost = gross_cost - discount
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS inconsistent_billing_lines
FROM raw_billing
WHERE ABS(
    TRY_CAST(net_cost_usd AS DOUBLE)
    - (
        TRY_CAST(gross_cost_usd AS DOUBLE)
        - TRY_CAST(discount_usd AS DOUBLE)
    )
) > 0.01;


-- ------------------------------------------------------------
-- 11. 检查资源池和团队 ID 格式
-- 标准格式：去空格、转大写、下划线改为连字符
-- ------------------------------------------------------------

SELECT
    'resource_usage.resource_pool_id' AS field_name,
    COUNT(*) AS nonstandard_rows
FROM raw_usage
WHERE resource_pool_id
    <> UPPER(REPLACE(TRIM(resource_pool_id), '_', '-'))

UNION ALL

SELECT
    'resource_usage.team_id',
    COUNT(*)
FROM raw_usage
WHERE team_id
    <> UPPER(REPLACE(TRIM(team_id), '_', '-'))

UNION ALL

SELECT
    'cloud_billing.resource_pool_id',
    COUNT(*)
FROM raw_billing
WHERE resource_pool_id IS NOT NULL
  AND TRIM(resource_pool_id) <> ''
  AND resource_pool_id
      <> UPPER(REPLACE(TRIM(resource_pool_id), '_', '-'))

UNION ALL

SELECT
    'cloud_billing.team_id',
    COUNT(*)
FROM raw_billing
WHERE team_id IS NOT NULL
  AND TRIM(team_id) <> ''
  AND team_id
      <> UPPER(REPLACE(TRIM(team_id), '_', '-'));


-- ------------------------------------------------------------
-- 12. 检查使用表与资源清单的资源池关联率
-- 使用标准化后的 ID 连接
-- ------------------------------------------------------------

WITH usage_ids AS (
    SELECT DISTINCT
        UPPER(REPLACE(TRIM(resource_pool_id), '_', '-')) AS pool_id
    FROM raw_usage
    WHERE resource_pool_id IS NOT NULL
      AND TRIM(resource_pool_id) <> ''
),
inventory_ids AS (
    SELECT DISTINCT
        UPPER(REPLACE(TRIM(resource_pool_id), '_', '-')) AS pool_id
    FROM raw_inventory
)
SELECT
    COUNT(*) AS usage_distinct_pool_ids,
    COUNT(*) FILTER (
        WHERE inventory_ids.pool_id IS NOT NULL
    ) AS matched_pool_ids,
    COUNT(*) FILTER (
        WHERE inventory_ids.pool_id IS NULL
    ) AS unmatched_pool_ids,
    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE inventory_ids.pool_id IS NOT NULL
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS match_rate_pct
FROM usage_ids
LEFT JOIN inventory_ids USING (pool_id);


-- ------------------------------------------------------------
-- 13. 检查账单与资源清单的资源池关联率
-- 只检查账单中非空的资源池 ID
-- ------------------------------------------------------------

WITH billing_ids AS (
    SELECT DISTINCT
        UPPER(REPLACE(TRIM(resource_pool_id), '_', '-')) AS pool_id
    FROM raw_billing
    WHERE resource_pool_id IS NOT NULL
      AND TRIM(resource_pool_id) <> ''
),
inventory_ids AS (
    SELECT DISTINCT
        UPPER(REPLACE(TRIM(resource_pool_id), '_', '-')) AS pool_id
    FROM raw_inventory
)
SELECT
    COUNT(*) AS billing_distinct_pool_ids,
    COUNT(*) FILTER (
        WHERE inventory_ids.pool_id IS NOT NULL
    ) AS matched_pool_ids,
    COUNT(*) FILTER (
        WHERE inventory_ids.pool_id IS NULL
    ) AS unmatched_pool_ids,
    ROUND(
        100.0
        * COUNT(*) FILTER (
            WHERE inventory_ids.pool_id IS NOT NULL
        )
        / NULLIF(COUNT(*), 0),
        2
    ) AS match_rate_pct
FROM billing_ids
LEFT JOIN inventory_ids USING (pool_id);


-- ------------------------------------------------------------
-- 14. 检查使用数据的时间范围
-- ------------------------------------------------------------

SELECT
    MIN(TRY_CAST(timestamp_utc AS TIMESTAMPTZ)) AS first_timestamp,
    MAX(TRY_CAST(timestamp_utc AS TIMESTAMPTZ)) AS last_timestamp,
    COUNT(
        DISTINCT DATE_TRUNC(
            'month',
            TRY_CAST(timestamp_utc AS TIMESTAMPTZ)
        )
    ) AS distinct_months
FROM raw_usage;
