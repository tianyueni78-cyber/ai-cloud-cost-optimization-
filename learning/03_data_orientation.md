# 03｜认识数据、字段和表关系

## 本阶段通用公式

```text
文件/表清单 + 字段结构 + 行粒度 + 主键 + 外键 + 时间范围 + 单位
= 可用的数据地图
```

| 固定部分：每张表都检查 | 变化部分：由数据决定 |
|---|---|
| 行数、列数、字段名和推断类型 | 文件格式、编码和读取工具 |
| 前几行样例和一行的业务含义 | 表的实际粒度：订单、小时、客户等 |
| 候选主键与重复可能性 | 单字段主键还是复合主键 |
| 可以连接到哪些表 | 连接字段、格式差异和生效期条件 |
| 日期范围、刷新频率和单位 | 时区、币种、百分比及业务单位 |

标准 SQL 模块通常只有三类：`DESCRIBE` 看结构、`LIMIT` 看样例、`COUNT/MIN/MAX/COUNT DISTINCT` 看规模与范围。换数据时 SQL 结构相同，替换的是表名、字段名和业务粒度。

标准输出是数据清单和关系图；完成标准是能够用一句话解释每张表的一行，并能画出主外键关系。此阶段只认识数据，不判断异常，也不清洗。

## 目标

在分析前确认五张表的一行代表什么、主键是什么、如何连接，以及单位能否直接比较。

## 使用软件与输入

- 软件：VS Code、DuckDB。
- 输入：`data/*.csv`、`docs/data_dictionary.md`。
- 输出：`reports/data_inventory.md` 和 `sql/00_data_orientation.sql`。

## 操作步骤

### 1. 创建 SQL 文件

新建 `sql/00_data_orientation.sql`，先写：

```sql
DESCRIBE SELECT *
FROM read_csv_auto('data/resource_inventory.csv');

SELECT *
FROM read_csv_auto('data/resource_inventory.csv')
LIMIT 10;
```

`DESCRIBE` 查看列名和 DuckDB 推断的数据类型；`LIMIT 10` 只看少量实际记录。

### 2. 对五张表重复结构检查

每张表记录：

| 内容 | 要写什么 |
|---|---|
| 文件名 | 完整路径 |
| 行粒度 | 一行代表什么 |
| 候选主键 | 哪些字段理论上应识别一条记录 |
| 时间字段 | 小时、日期、使用月份还是发票月份 |
| 金额/单位 | USD、GPU 小时、请求、作业或千页 |
| 可能关联键 | 与哪些表通过什么字段连接 |

### 3. 查看行数

```sql
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
```

### 4. 画出表关系

```text
resource_inventory
  ├── resource_pool_id ── resource_usage
  └── resource_pool_id ── cloud_billing

team_sla
  └── team_id + product_id + workload_type + region + 生效日期
      └── resource_usage / resource_inventory

business_events
  └── team_id + product_id + region + 事件时间
      └── resource_usage / cloud_billing
```

表关系不是看到相同列名就直接 JOIN。还要检查：

- 两边是否唯一；
- ID 格式是否一致；
- 是否需要时间生效条件；
- 关联后行数是否增加；
- 空值是否代表无法归属。

### 5. 区分主键和外键

- 主键：在本表中识别一行，例如 `resource_pool_id`。
- 外键：指向另一张表的标识，例如使用表中的 `resource_pool_id`。
- 业务键：由多个字段共同定义的业务关系，例如团队、产品、负载、区域和生效日期。

### 6. 检查单位

`business_volume` 的单位由 `volume_unit` 决定：

- `requests`：请求数；
- `jobs`：训练作业数；
- `k_pages`：千页。

这些单位不能直接相加，也不能共用同一个单位成本分母。

## 数据认识知识树

```text
表格
├── 行粒度：一行代表什么
├── 列：属性或指标
├── 主键：识别一行
├── 外键：连接其他表
├── 数据类型：文本、数字、日期、布尔值
├── 单位：USD、%、GPU 小时、请求等
└── 时间口径：发生时间、使用期间、发票月份、记录时间
```

## 验收标准

- 五张表都有行粒度说明。
- 每个字段的含义能在数据字典中找到。
- 能画出主要表关系。
- 能解释为什么不能只看到同名字段就 JOIN。
- 能指出三种 `volume_unit` 不能直接相加。

## 建议提交

```powershell
git add sql/00_data_orientation.sql reports/data_inventory.md
git commit -m "docs: map source data and relationships"
git push
```
