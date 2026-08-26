-- 目的：认识资源清单的结构、内容和数据量
--
-- 【迁移到其他项目】
-- 可复用：DESCRIBE 看结构、LIMIT 看样例、COUNT 看规模、GROUP BY 看分类分布。
-- 要替换：CSV 路径、表名，以及最后用于分组的业务维度字段。
-- 先确认：一行代表什么、候选主键是什么、日期和金额使用什么单位。
-- 注意：这一步只认识数据，不判断异常，也不修改数据。

-- 查看字段名称和数据类型
DESCRIBE
SELECT *
FROM read_csv_auto('data/resource_inventory.csv');

-- 查看前 10 行，了解实际记录长什么样
SELECT *
FROM read_csv_auto('data/resource_inventory.csv')
LIMIT 10;

-- 统计资源清单的总行数
SELECT COUNT(*) AS row_count
FROM read_csv_auto('data/resource_inventory.csv');

-------------------------------------------------------

-- 按团队统计资源池数量和 GPU 总数
SELECT
    team_id,
    COUNT(*) AS resource_pool_count,
    SUM(gpu_count) AS total_gpu_count
FROM read_csv_auto('data/resource_inventory.csv')
GROUP BY team_id
ORDER BY total_gpu_count DESC;

-- 按 GPU 型号统计资源池数量和 GPU 总数
SELECT
    gpu_model,
    COUNT(*) AS resource_pool_count,
    SUM(gpu_count) AS total_gpu_count
FROM read_csv_auto('data/resource_inventory.csv')
GROUP BY gpu_model
ORDER BY total_gpu_count DESC;

-- 查看采购方式和工作负载的组合
SELECT
    procurement_model,
    workload_type,
    COUNT(*) AS resource_pool_count,
    SUM(gpu_count) AS total_gpu_count
FROM read_csv_auto('data/resource_inventory.csv')
GROUP BY procurement_model, workload_type
ORDER BY procurement_model, workload_type;
