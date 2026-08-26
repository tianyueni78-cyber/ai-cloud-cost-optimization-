# SQL 翻译模板

这份手册解决一个问题：已经知道业务上要做什么，怎样把它翻译成 SQL。先选“动作”，再复制对应模板；不需要从空白页开始，也不需要背字段名。

## 一、业务语言到 SQL 动作

| 业务语言 | SQL 动作 | 主要结构 |
|---|---|---|
| 一共有多少费用 | 求和 | `SUM()` |
| 只看某个范围 | 筛选 | `WHERE` |
| 分别看每月、团队或采购方式 | 分组 | `GROUP BY` |
| 比较高低、找前几名 | 排序 | `ORDER BY` |
| 计算记录数或对象数 | 计数 | `COUNT()`、`COUNT(DISTINCT ...)` |
| 把两张表的信息放在一起 | 关联 | `JOIN ... ON ...` |
| 给记录分类 | 条件判断 | `CASE WHEN` |
| 比较本月和上月 | 窗口计算 | `LAG() OVER (...)` |
| 检查是否重复 | 唯一性验证 | `COUNT(*)` 对比 `COUNT(DISTINCT ...)` |

## 二、先认识数据

```sql
-- 看字段与 DuckDB 推断的数据类型
DESCRIBE SELECT *
FROM 【表或读取表达式】; -- 替换为要认识的数据；例：read_csv_auto('data/cloud_billing.csv')

-- 看样例，不一次输出整张表
SELECT *
FROM 【表或读取表达式】 -- 同上
LIMIT 【样例行数】;     -- 替换为少量行数；例：10

-- 看总行数
SELECT COUNT(*) AS row_count
FROM 【表或读取表达式】; -- 同上
```

## 三、求和、筛选、分组

### 1. 只求总额

```sql
SELECT
    SUM(【数值字段】) AS 【指标别名】 -- 数值字段例：net_cost_usd；别名例：total_cost_usd
FROM 【主表】;                        -- 替换为指标事实表；例：clean_billing
```

### 2. 求指定范围的总额

```sql
SELECT
    SUM(【数值字段】) AS 【指标别名】
FROM 【主表】
WHERE 【筛选字段】 IN (【允许值列表】); -- 字段例：charge_type；值例：'Usage', 'Commitment'
```

常用筛选写法：

```sql
WHERE 【字段】 = 【单个值】
WHERE 【字段】 IN (【值1】, 【值2】)
WHERE 【日期字段】 >= DATE '【开始日期】' AND 【日期字段】 < DATE '【结束日期】'
WHERE 【字段】 IS NULL
WHERE 【字段】 IS NOT NULL
```

日期结束边界优先使用“下一周期起点之前”，避免漏掉结束日带时间的记录。

### 3. 按维度分别看

```sql
SELECT
    【分组字段】,                        -- 替换为“按什么分别看”；例：invoice_month
    SUM(【数值字段】) AS 【指标别名】     -- 例：SUM(net_cost_usd) AS total_cost_usd
FROM 【主表】
WHERE 【筛选条件】                       -- 没有筛选时删除整行
GROUP BY 【分组字段】
ORDER BY 【排序字段】 【ASC或DESC】;       -- 时间通常 ASC，排名通常 DESC
```

规则：`SELECT` 中没有被聚合的字段，通常都要出现在 `GROUP BY` 中。

## 四、计数、去重与比例

```sql
SELECT
    COUNT(*) AS row_count,                         -- 记录数
    COUNT(DISTINCT 【对象ID】) AS object_count,     -- 不同对象数；例：billing_line_id
    SUM(【分子字段】) / NULLIF(SUM(【分母字段】), 0) AS ratio
                                                    -- NULLIF 防止分母为0
FROM 【主表】;
```

不要把“记录数”和“对象数”混用：一笔业务可能对应多条记录。

## 五、分类与空值

```sql
SELECT
    CASE
        WHEN 【条件1】 THEN 【标签1】 -- 例：gpu_utilization_pct < 20 THEN '低利用率'
        WHEN 【条件2】 THEN 【标签2】
        ELSE 【其他标签】
    END AS 【分类字段名】
FROM 【主表】;
```

```sql
SELECT
    COUNT(*) FILTER (WHERE 【字段】 IS NULL) AS missing_rows,
    ROUND(100.0 * COUNT(*) FILTER (WHERE 【字段】 IS NULL) / COUNT(*), 2) AS missing_pct
FROM 【主表】;
```

空值不是自动等于 0；先判断它代表未采集、不适用、延迟还是错误。

## 六、重复检查

```sql
SELECT
    【候选主键】,                  -- 单字段例：billing_line_id；多字段用逗号列出
    COUNT(*) AS duplicate_count
FROM 【主表】
GROUP BY 【候选主键】
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;
```

业务主键是多字段时，`GROUP BY` 必须使用完整组合，不能只检查其中一个字段。

## 七、表关联

```sql
SELECT
    l.*,
    r.【需要补充的字段】 -- 例：gpu_model
FROM 【左表】 AS l       -- 通常放必须保留的事实表；例：clean_billing
LEFT JOIN 【右表】 AS r  -- 通常放维度或补充信息；例：clean_inventory
    ON l.【左关联键】 = r.【右关联键】; -- 例：resource_pool_id_norm
```

选择：

- `LEFT JOIN`：左表记录必须全部保留；成本归因通常先用它。
- `INNER JOIN`：只保留双方匹配记录；可能漏掉未匹配费用。

关联前必须确认右表关联键在目标粒度上唯一，否则一条费用会匹配多行并放大金额。

## 八、时间与环比

```sql
WITH monthly AS (
    SELECT
        【月份字段】,                         -- 例：invoice_month
        SUM(【数值字段】) AS metric_value     -- 例：net_cost_usd
    FROM 【主表】
    WHERE 【筛选条件】
    GROUP BY 【月份字段】
)
SELECT
    【月份字段】,
    metric_value,
    LAG(metric_value) OVER (ORDER BY 【月份字段】) AS previous_value,
    ROUND(
        100.0 * (metric_value - LAG(metric_value) OVER (ORDER BY 【月份字段】))
        / NULLIF(LAG(metric_value) OVER (ORDER BY 【月份字段】), 0),
        2
    ) AS change_pct
FROM monthly
ORDER BY 【月份字段】;
```

时间字段必须来自当前指标的事实表。账单指标通常先用使用期间或发票月；小时级资源状态才用遥测时间。

## 九、SQL 语法自查

执行顺序可以先记成：

```text
FROM/JOIN → WHERE → GROUP BY → HAVING → SELECT → ORDER BY → LIMIT
```

写出来的常见顺序是：

```text
SELECT → FROM/JOIN → WHERE → GROUP BY → HAVING → ORDER BY → LIMIT
```

运行报错时按顺序检查：

1. 字符串是否用单引号；
2. 字段之间是否缺逗号；
3. 括号和引号是否成对；
4. 表名、字段名是否真实存在；
5. 非聚合字段是否放进 `GROUP BY`；
6. 日期、数字和文本类型是否一致；
7. `WHERE` 是否错误使用聚合结果——聚合结果应使用 `HAVING`。

下一步：[Pandas 翻译模板](02_Pandas翻译模板.md) · [固定自检程序](03_固定自检程序.md)
