-- 目的：盘点五张原始数据表的规模和字段结构
--
-- 【迁移到其他项目】
-- 可复用：用 UNION ALL 汇总多张表行数，并逐表查看字段结构和时间范围。
-- 要替换：项目实际拥有的文件清单、路径、主日期字段和表粒度说明。
-- 相同点：任何项目都要形成“表名—行数—字段—粒度—时间范围”清单。
-- 不同点：表的数量、关联方式、刷新频率以及合理的数据规模。
-- 注意：行数多不代表信息多，必须同时记录每张表一行的业务含义。

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
