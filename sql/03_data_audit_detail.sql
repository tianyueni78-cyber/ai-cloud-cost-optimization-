-- 目的：补全第一轮被终端隐藏的结果，并复核 UTC 时间口径
--
-- 【迁移到其他项目】
-- 可复用：把宽表结果改成纵向窄表，对首轮发现的异常做数量和来源拆分。
-- 要替换：业务重复键、重点空值字段、数值指标、ID 关联键和时间字段。
-- 相同点：首轮做广度扫描，第二轮对已发现的问题做深度定位。
-- 不同点：异常需要按什么状态、类型、来源系统或业务场景分类。
-- 注意：时区会改变日期和月份边界，时间分析必须明确业务采用的时区。

SET TimeZone = 'UTC';

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

CREATE OR REPLACE VIEW raw_events AS
SELECT *
FROM read_csv_auto(
    'data/business_events.csv',
    all_varchar = true
);


-- 1. 汇总业务重复类型
WITH duplicate_groups AS (
    SELECT
        timestamp_utc,
        UPPER(REPLACE(TRIM(resource_pool_id), '_', '-')) AS pool_id,
        COUNT(*) AS row_count,
        COUNT(DISTINCT usage_record_id) AS distinct_record_ids
    FROM raw_usage
    GROUP BY 1, 2
    HAVING COUNT(*) > 1
)
SELECT
    COUNT(*) AS duplicate_business_keys,
    SUM(row_count - 1) AS extra_rows,
    COUNT(*) FILTER (
        WHERE distinct_record_ids = 1
    ) AS same_record_id_groups,
    COUNT(*) FILTER (
        WHERE distinct_record_ids > 1
    ) AS different_record_id_groups
FROM duplicate_groups;


-- 2. 纵向显示使用表关键字段空值
SELECT 'active_gpu_count' AS field_name, COUNT(*) AS missing_rows
FROM raw_usage
WHERE active_gpu_count IS NULL OR TRIM(active_gpu_count) = ''

UNION ALL

SELECT 'gpu_utilization_pct', COUNT(*)
FROM raw_usage
WHERE gpu_utilization_pct IS NULL OR TRIM(gpu_utilization_pct) = ''

UNION ALL

SELECT 'memory_utilization_pct', COUNT(*)
FROM raw_usage
WHERE memory_utilization_pct IS NULL
   OR TRIM(memory_utilization_pct) = ''

UNION ALL

SELECT 'p95_latency_ms', COUNT(*)
FROM raw_usage
WHERE p95_latency_ms IS NULL OR TRIM(p95_latency_ms) = ''

UNION ALL

SELECT 'queue_time_seconds', COUNT(*)
FROM raw_usage
WHERE queue_time_seconds IS NULL OR TRIM(queue_time_seconds) = ''

UNION ALL

SELECT 'availability_pct', COUNT(*)
FROM raw_usage
WHERE availability_pct IS NULL OR TRIM(availability_pct) = '';


-- 3. 纵向显示账单关键字段空值
SELECT 'resource_pool_id' AS field_name, COUNT(*) AS missing_rows
FROM raw_billing
WHERE resource_pool_id IS NULL OR TRIM(resource_pool_id) = ''

UNION ALL

SELECT 'team_id', COUNT(*)
FROM raw_billing
WHERE team_id IS NULL OR TRIM(team_id) = ''

UNION ALL

SELECT 'contract_id', COUNT(*)
FROM raw_billing
WHERE contract_id IS NULL OR TRIM(contract_id) = ''

UNION ALL

SELECT 'billed_gpu_hours', COUNT(*)
FROM raw_billing
WHERE billed_gpu_hours IS NULL OR TRIM(billed_gpu_hours) = ''

UNION ALL

SELECT 'unit_rate_usd', COUNT(*)
FROM raw_billing
WHERE unit_rate_usd IS NULL OR TRIM(unit_rate_usd) = '';


-- 4. 纵向显示使用指标范围
SELECT
    'allocated_gpu_count' AS metric,
    MIN(TRY_CAST(allocated_gpu_count AS DOUBLE)) AS minimum,
    MAX(TRY_CAST(allocated_gpu_count AS DOUBLE)) AS maximum
FROM raw_usage

UNION ALL

SELECT
    'active_gpu_count',
    MIN(TRY_CAST(active_gpu_count AS DOUBLE)),
    MAX(TRY_CAST(active_gpu_count AS DOUBLE))
FROM raw_usage

UNION ALL

SELECT
    'gpu_utilization_pct',
    MIN(TRY_CAST(gpu_utilization_pct AS DOUBLE)),
    MAX(TRY_CAST(gpu_utilization_pct AS DOUBLE))
FROM raw_usage

UNION ALL

SELECT
    'memory_utilization_pct',
    MIN(TRY_CAST(memory_utilization_pct AS DOUBLE)),
    MAX(TRY_CAST(memory_utilization_pct AS DOUBLE))
FROM raw_usage

UNION ALL

SELECT
    'p95_latency_ms',
    MIN(TRY_CAST(p95_latency_ms AS DOUBLE)),
    MAX(TRY_CAST(p95_latency_ms AS DOUBLE))
FROM raw_usage

UNION ALL

SELECT
    'queue_time_seconds',
    MIN(TRY_CAST(queue_time_seconds AS DOUBLE)),
    MAX(TRY_CAST(queue_time_seconds AS DOUBLE))
FROM raw_usage

UNION ALL

SELECT
    'availability_pct',
    MIN(TRY_CAST(availability_pct AS DOUBLE)),
    MAX(TRY_CAST(availability_pct AS DOUBLE))
FROM raw_usage;


-- 5. 比较使用表 ID 标准化前后的行级关联率
SELECT
    COUNT(*) AS total_usage_rows,
    COUNT(*) FILTER (
        WHERE exact_match.resource_pool_id IS NOT NULL
    ) AS exact_matched_rows,
    COUNT(*) FILTER (
        WHERE normalized_match.resource_pool_id IS NOT NULL
    ) AS normalized_matched_rows,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE exact_match.resource_pool_id IS NOT NULL
        ) / COUNT(*),
        2
    ) AS exact_match_rate_pct,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE normalized_match.resource_pool_id IS NOT NULL
        ) / COUNT(*),
        2
    ) AS normalized_match_rate_pct
FROM raw_usage usage
LEFT JOIN raw_inventory exact_match
    ON usage.resource_pool_id = exact_match.resource_pool_id
LEFT JOIN raw_inventory normalized_match
    ON UPPER(REPLACE(TRIM(usage.resource_pool_id), '_', '-'))
     = normalized_match.resource_pool_id;


-- 6. 比较账单 ID 标准化前后的行级关联率
WITH billing_with_pool AS (
    SELECT *
    FROM raw_billing
    WHERE resource_pool_id IS NOT NULL
      AND TRIM(resource_pool_id) <> ''
)
SELECT
    COUNT(*) AS billing_rows_with_pool,
    COUNT(*) FILTER (
        WHERE exact_match.resource_pool_id IS NOT NULL
    ) AS exact_matched_rows,
    COUNT(*) FILTER (
        WHERE normalized_match.resource_pool_id IS NOT NULL
    ) AS normalized_matched_rows,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE exact_match.resource_pool_id IS NOT NULL
        ) / COUNT(*),
        2
    ) AS exact_match_rate_pct,
    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE normalized_match.resource_pool_id IS NOT NULL
        ) / COUNT(*),
        2
    ) AS normalized_match_rate_pct
FROM billing_with_pool billing
LEFT JOIN raw_inventory exact_match
    ON billing.resource_pool_id = exact_match.resource_pool_id
LEFT JOIN raw_inventory normalized_match
    ON UPPER(REPLACE(TRIM(billing.resource_pool_id), '_', '-'))
     = normalized_match.resource_pool_id;


-- 7. 使用 UTC 重新检查时间范围
SELECT
    MIN(TRY_CAST(timestamp_utc AS TIMESTAMPTZ)) AS first_timestamp_utc,
    MAX(TRY_CAST(timestamp_utc AS TIMESTAMPTZ)) AS last_timestamp_utc,
    COUNT(
        DISTINCT DATE_TRUNC(
            'month',
            TRY_CAST(timestamp_utc AS TIMESTAMPTZ)
        )
    ) AS utc_months
FROM raw_usage;


-- 8. 查看缺少团队或产品的事件
SELECT
    event_id,
    event_type,
    start_timestamp_utc,
    team_id,
    product_id,
    region,
    event_description
FROM raw_events
WHERE team_id IS NULL
   OR TRIM(team_id) = ''
   OR product_id IS NULL
   OR TRIM(product_id) = '';
