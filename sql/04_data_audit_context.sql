-- 第三轮数据审计：解释空值、验证业务约束、判断重复记录性质
-- 运行：python run_sql.py sql/04_data_audit_context.sql
--
-- 【迁移到其他项目】
-- 可复用：把异常按业务类型分组，并检查跨字段约束、枚举和重复内容差异。
-- 要替换：负载/费用分类字段、允许为空规则、金额符号和业务约束公式。
-- 相同点：空值必须区分“不适用”和“本应有值但丢失”。
-- 不同点：哪些场景不适用、哪些正负号合理、哪些字段组合必须成立。
-- 注意：总空值数量不能直接决定清洗方式，必须结合数据字典和业务上下文。

SET TimeZone = 'UTC';

CREATE OR REPLACE TEMP VIEW raw_usage AS
SELECT * FROM read_csv_auto('data/resource_usage.csv', all_varchar = true);

CREATE OR REPLACE TEMP VIEW raw_billing AS
SELECT * FROM read_csv_auto('data/cloud_billing.csv', all_varchar = true);

CREATE OR REPLACE TEMP VIEW raw_inventory AS
SELECT * FROM read_csv_auto('data/resource_inventory.csv', all_varchar = true);

CREATE OR REPLACE TEMP VIEW raw_sla AS
SELECT * FROM read_csv_auto('data/team_sla.csv', all_varchar = true);

-- 1. 按负载类型解释使用表空值：同一个空值在不同业务中含义不同
SELECT
    workload_type,
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(p95_latency_ms), '') IS NULL) AS missing_p95,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(queue_time_seconds), '') IS NULL) AS missing_queue
FROM raw_usage
GROUP BY workload_type
ORDER BY workload_type;

SELECT
    workload_type,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(gpu_utilization_pct), '') IS NULL) AS missing_gpu_util,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(memory_utilization_pct), '') IS NULL) AS missing_memory_util,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(availability_pct), '') IS NULL) AS missing_availability
FROM raw_usage
GROUP BY workload_type
ORDER BY workload_type;

-- 2. 按费用类型解释账单空值：固定费、抵扣和支持费不一定有 GPU 小时或单价
SELECT
    charge_type,
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(resource_pool_id), '') IS NULL) AS missing_pool,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(team_id), '') IS NULL) AS missing_team
FROM raw_billing
GROUP BY charge_type
ORDER BY charge_type;

SELECT
    charge_type,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(contract_id), '') IS NULL) AS missing_contract,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(billed_gpu_hours), '') IS NULL) AS missing_gpu_hours,
    COUNT(*) FILTER (WHERE NULLIF(TRIM(unit_rate_usd), '') IS NULL) AS missing_unit_rate
FROM raw_billing
GROUP BY charge_type
ORDER BY charge_type;

-- 3. 检查数值之间的业务约束，不只看单列最小值和最大值
SELECT 'active_gpu_exceeds_allocated' AS check_name, COUNT(*) AS violation_rows
FROM raw_usage
WHERE TRY_CAST(active_gpu_count AS DOUBLE) > TRY_CAST(allocated_gpu_count AS DOUBLE)
UNION ALL
SELECT 'negative_business_volume', COUNT(*)
FROM raw_usage WHERE TRY_CAST(business_volume AS DOUBLE) < 0
UNION ALL
SELECT 'usage_percentage_outside_0_100', COUNT(*)
FROM raw_usage
WHERE TRY_CAST(gpu_utilization_pct AS DOUBLE) NOT BETWEEN 0 AND 100
   OR TRY_CAST(memory_utilization_pct AS DOUBLE) NOT BETWEEN 0 AND 100
   OR TRY_CAST(availability_pct AS DOUBLE) NOT BETWEEN 0 AND 100;

SELECT 'nonpositive_inventory_gpu_count' AS check_name, COUNT(*) AS violation_rows
FROM raw_inventory WHERE TRY_CAST(gpu_count AS DOUBLE) <= 0
UNION ALL
SELECT 'nonpositive_effective_rate', COUNT(*)
FROM raw_inventory WHERE TRY_CAST(effective_hourly_rate_usd AS DOUBLE) <= 0
UNION ALL
SELECT 'effective_rate_above_list_price', COUNT(*)
FROM raw_inventory
WHERE TRY_CAST(effective_hourly_rate_usd AS DOUBLE) > TRY_CAST(hourly_list_price_usd AS DOUBLE);

-- 4. 检查账单金额符号和公式；Credit 应为负数，折扣不应为负数
SELECT 'credit_not_negative' AS check_name, COUNT(*) AS violation_rows
FROM raw_billing
WHERE charge_type = 'Credit' AND TRY_CAST(net_cost_usd AS DOUBLE) >= 0
UNION ALL
SELECT 'negative_discount', COUNT(*)
FROM raw_billing WHERE TRY_CAST(discount_usd AS DOUBLE) < 0
UNION ALL
SELECT 'net_cost_formula_error', COUNT(*)
FROM raw_billing
WHERE ABS(
    TRY_CAST(gross_cost_usd AS DOUBLE)
    - TRY_CAST(discount_usd AS DOUBLE)
    - TRY_CAST(net_cost_usd AS DOUBLE)
) > 0.02;

-- 5. 列出实际枚举值：与数据字典逐项核对，避免隐藏拼写变体
SELECT 'usage.workload_type' AS field_name, workload_type AS field_value, COUNT(*) AS row_count
FROM raw_usage GROUP BY workload_type
UNION ALL
SELECT 'usage.telemetry_status', telemetry_status, COUNT(*)
FROM raw_usage GROUP BY telemetry_status
UNION ALL
SELECT 'billing.charge_type', charge_type, COUNT(*)
FROM raw_billing GROUP BY charge_type
UNION ALL
SELECT 'billing.procurement_model', procurement_model, COUNT(*)
FROM raw_billing GROUP BY procurement_model
ORDER BY field_name, field_value;

-- 6. 检查 SLA 数值和日期是否可解析、是否在合理范围
SELECT 'invalid_effective_to' AS check_name, COUNT(*) AS violation_rows
FROM raw_sla
WHERE NULLIF(TRIM(effective_to), '') IS NOT NULL
  AND TRY_CAST(effective_to AS DATE) IS NULL
UNION ALL
SELECT 'availability_target_outside_0_100', COUNT(*)
FROM raw_sla
WHERE TRY_CAST(availability_target_pct AS DOUBLE) NOT BETWEEN 0 AND 100
UNION ALL
SELECT 'spare_capacity_outside_0_100', COUNT(*)
FROM raw_sla
WHERE TRY_CAST(min_spare_capacity_pct AS DOUBLE) NOT BETWEEN 0 AND 100
UNION ALL
SELECT 'negative_sla_target', COUNT(*)
FROM raw_sla
WHERE TRY_CAST(p95_latency_target_ms AS DOUBLE) < 0
   OR TRY_CAST(max_queue_time_seconds AS DOUBLE) < 0
   OR TRY_CAST(rto_minutes AS DOUBLE) < 0;

-- 7. 判断重复记录 ID 的内容是否完全一致
WITH repeated_ids AS (
    SELECT
        usage_record_id,
        COUNT(*) AS row_count,
        COUNT(DISTINCT HASH(CONCAT_WS('|',
            timestamp_utc, resource_pool_id, team_id, product_id, workload_type,
            allocated_gpu_count, active_gpu_count, gpu_utilization_pct,
            memory_utilization_pct, business_volume, volume_unit,
            p95_latency_ms, queue_time_seconds, availability_pct, telemetry_status
        ))) AS distinct_payloads
    FROM raw_usage
    GROUP BY usage_record_id
    HAVING COUNT(*) > 1
)
SELECT
    COUNT(*) AS repeated_id_groups,
    COUNT(*) FILTER (WHERE distinct_payloads = 1) AS identical_payload_groups,
    COUNT(*) FILTER (WHERE distinct_payloads > 1) AS conflicting_payload_groups
FROM repeated_ids;
