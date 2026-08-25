-- 目的：盘点五张原始数据表的规模和字段结构

-- 统计五张表的数据行数
SELECT 'resource_inventory' AS table_name, COUNT(*) AS row_count
FROM read_csv_auto('data/resource_inventory.csv')

UNION ALL

SELECT 'resource_usage', COUNT(*)
FROM read_csv_auto('data/resource_usage.csv')

UNION ALL

SELECT 'cloud_billing', COUNT(*)
FROM read_csv_auto('data/cloud_billing.csv')

UNION ALL

SELECT 'team_sla', COUNT(*)
FROM read_csv_auto('data/team_sla.csv')

UNION ALL

SELECT 'business_events', COUNT(*)
FROM read_csv_auto('data/business_events.csv');

-- 查看 GPU 使用表的字段结构
DESCRIBE
SELECT *
FROM read_csv_auto('data/resource_usage.csv');

-- 查看账单表的字段结构
DESCRIBE
SELECT *
FROM read_csv_auto('data/cloud_billing.csv');

-- 查看 SLA 表的字段结构
DESCRIBE
SELECT *
FROM read_csv_auto('data/team_sla.csv');

-- 查看业务事件表的字段结构
DESCRIBE
SELECT *
FROM read_csv_auto('data/business_events.csv');