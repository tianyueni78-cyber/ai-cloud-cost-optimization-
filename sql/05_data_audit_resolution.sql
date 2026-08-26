-- 第四轮数据审计：为剩余异常确定处理规则
-- 运行：python run_sql.py sql/05_data_audit_resolution.sql
--
-- 【迁移到其他项目】
-- 可复用：关联质量状态解释空值、用权威维表回填归属、比较冲突记录内容。
-- 要替换：状态优先级、权威数据源、合同规则、修订记录的识别方式和保留规则。
-- 本项目特例：ID 后缀 -R 表示修订版；其他项目绝不能默认沿用这一规则。
-- 注意：只有证据证明哪条更新或更权威时才能删除冲突记录，不能随便保留第一行。
-- 完成标准：每类异常都有可解释、可执行、可验证的处理规则。

CREATE OR REPLACE TEMP VIEW raw_usage AS
SELECT * FROM read_csv_auto('data/resource_usage.csv', all_varchar = true);

CREATE OR REPLACE TEMP VIEW raw_billing AS
SELECT * FROM read_csv_auto('data/cloud_billing.csv', all_varchar = true);

CREATE OR REPLACE TEMP VIEW raw_inventory AS
SELECT * FROM read_csv_auto('data/resource_inventory.csv', all_varchar = true);

-- 1. 遥测指标空值是否集中在 partial 或 late 状态
SELECT
    telemetry_status,
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(gpu_utilization_pct), '') IS NULL) AS missing_gpu_util,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(memory_utilization_pct), '') IS NULL) AS missing_memory_util
FROM raw_usage
GROUP BY telemetry_status
ORDER BY telemetry_status;

SELECT
    telemetry_status,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(availability_pct), '') IS NULL) AS missing_availability,
    COUNT(*) FILTER (
        WHERE NULLIF(TRIM(gpu_utilization_pct), '') IS NULL
           OR NULLIF(TRIM(memory_utilization_pct), '') IS NULL
           OR NULLIF(TRIM(availability_pct), '') IS NULL
    ) AS rows_missing_any_core_metric
FROM raw_usage
GROUP BY telemetry_status
ORDER BY telemetry_status;

-- 2. 团队缺失账单能否通过资源池关联到资源清单
WITH missing_team AS (
    SELECT
        billing.*,
        inventory.team_id AS inferred_team_id
    FROM raw_billing billing
    LEFT JOIN raw_inventory inventory
      ON UPPER(REPLACE(TRIM(billing.resource_pool_id), '_', '-'))
       = UPPER(REPLACE(TRIM(inventory.resource_pool_id), '_', '-'))
    WHERE NULLIF(TRIM(billing.team_id), '') IS NULL
)
SELECT
    charge_type,
    procurement_model,
    COUNT(*) AS missing_team_rows,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(resource_pool_id), '') IS NULL) AS also_missing_pool,
    COUNT(*) FILTER (WHERE inferred_team_id IS NOT NULL) AS inferable_from_inventory
FROM missing_team
GROUP BY charge_type, procurement_model
ORDER BY charge_type, procurement_model;

-- 3. 合同 ID 是否符合采购方式：Reserved 和 SavingsPlan 应有合同
SELECT
    procurement_model,
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(contract_id), '') IS NULL) AS missing_contract,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(contract_id), '') IS NOT NULL) AS present_contract
FROM raw_billing
GROUP BY procurement_model
ORDER BY procurement_model;

SELECT 'committed_purchase_missing_contract' AS check_name, COUNT(*) AS violation_rows
FROM raw_billing
WHERE procurement_model IN ('Reserved', 'SavingsPlan')
  AND NULLIF(TRIM(contract_id), '') IS NULL
UNION ALL
SELECT 'noncontract_purchase_has_contract', COUNT(*)
FROM raw_billing
WHERE procurement_model IN ('Owned', 'OnDemand')
  AND NULLIF(TRIM(contract_id), '') IS NOT NULL;

-- 4. 不同记录 ID 的业务重复是否具有相同内容
WITH duplicate_groups AS (
    SELECT
        timestamp_utc,
        UPPER(REPLACE(TRIM(resource_pool_id), '_', '-')) AS normalized_pool_id
    FROM raw_usage
    GROUP BY 1, 2
    HAVING COUNT(DISTINCT usage_record_id) > 1
), duplicate_rows AS (
    SELECT
        usage.timestamp_utc,
        UPPER(REPLACE(TRIM(usage.resource_pool_id), '_', '-')) AS normalized_pool_id,
        usage.usage_record_id,
        usage.telemetry_status,
        HASH(CONCAT_WS('|',
            UPPER(REPLACE(TRIM(usage.team_id), '_', '-')),
            UPPER(REPLACE(TRIM(usage.product_id), '_', '-')),
            usage.workload_type, usage.allocated_gpu_count, usage.active_gpu_count,
            usage.gpu_utilization_pct, usage.memory_utilization_pct,
            usage.business_volume, usage.volume_unit, usage.p95_latency_ms,
            usage.queue_time_seconds, usage.availability_pct, usage.telemetry_status
        )) AS payload_hash
    FROM raw_usage usage
    INNER JOIN duplicate_groups groups
      ON usage.timestamp_utc = groups.timestamp_utc
     AND UPPER(REPLACE(TRIM(usage.resource_pool_id), '_', '-')) = groups.normalized_pool_id
), classified AS (
    SELECT
        timestamp_utc,
        normalized_pool_id,
        COUNT(*) AS row_count,
        COUNT(DISTINCT payload_hash) AS distinct_payloads,
        COUNT(DISTINCT telemetry_status) AS distinct_statuses
    FROM duplicate_rows
    GROUP BY 1, 2
)
SELECT
    COUNT(*) AS different_id_groups,
    COUNT(*) FILTER (WHERE distinct_payloads = 1) AS identical_payload_groups,
    COUNT(*) FILTER (WHERE distinct_payloads > 1) AS conflicting_payload_groups,
    COUNT(*) FILTER (WHERE distinct_statuses > 1) AS mixed_status_groups
FROM classified;

-- 5. 对内容不同的业务重复，查看遥测状态组合和数量
WITH duplicate_rows AS (
    SELECT
        timestamp_utc,
        UPPER(REPLACE(TRIM(resource_pool_id), '_', '-')) AS normalized_pool_id,
        usage_record_id,
        telemetry_status,
        HASH(CONCAT_WS('|',
            UPPER(REPLACE(TRIM(team_id), '_', '-')),
            UPPER(REPLACE(TRIM(product_id), '_', '-')),
            workload_type, allocated_gpu_count, active_gpu_count,
            gpu_utilization_pct, memory_utilization_pct, business_volume,
            volume_unit, p95_latency_ms, queue_time_seconds,
            availability_pct, telemetry_status
        )) AS payload_hash
    FROM raw_usage
), conflicting_groups AS (
    SELECT timestamp_utc, normalized_pool_id
    FROM duplicate_rows
    GROUP BY 1, 2
    HAVING COUNT(*) > 1
       AND COUNT(DISTINCT payload_hash) > 1
       AND COUNT(DISTINCT usage_record_id) > 1
), group_statuses AS (
    SELECT
        rows.timestamp_utc,
        rows.normalized_pool_id,
        STRING_AGG(
            DISTINCT rows.telemetry_status,
            ' + ' ORDER BY rows.telemetry_status
        ) AS status_combination
    FROM duplicate_rows rows
    INNER JOIN conflicting_groups groups USING (timestamp_utc, normalized_pool_id)
    GROUP BY rows.timestamp_utc, rows.normalized_pool_id
)
SELECT status_combination, COUNT(*) AS group_count
FROM group_statuses
GROUP BY status_combination
ORDER BY group_count DESC;
