# 06｜使用 SQL 探索业务

## 本阶段通用公式

```text
总量 → 趋势 → 结构 → 效率 → 分布/异常 → 业务切片
= 探索性分析
```

| 固定分析模块 | 常用计算 | 随项目变化的变量 |
|---|---|---|
| 总量 | `SUM`、`COUNT`、`COUNT DISTINCT` | 核心规模指标 |
| 趋势 | 按日/周/月分组，`LAG` 算增长率 | 时间粒度、基准期、季节性 |
| 结构 | 分类金额 ÷ 总金额 | 团队、产品、渠道、费用类型等维度 |
| 效率 | 投入 ÷ 产出或产出 ÷ 投入 | 单位成本、转化率、利用率等公式 |
| 分布和异常 | 分位数、极值、同比/环比偏离 | 异常阈值与业务容忍度 |
| 业务切片 | 时间 × 维度 × 指标 | 哪些切片能影响决策 |

换数据时，`GROUP BY`、聚合、窗口函数和占比公式基本不变；变化的是指标口径、可比较单位、分组维度和时间粒度。先做公司全貌，再逐层下钻，不能一开始只找异常。

标准输入是通过验证的清洗层；标准输出是可复现 SQL 和事实表。完成标准是能回答“发生了什么、发生在哪里、何时开始”，但此阶段还不能把相关性直接写成原因。

## 目标

在数据质量和清洗规则稳定后，用 SQL 回答成本、使用、业务量、采购和 SLA 的基础问题。

## 软件、输入和输出

- 软件：VS Code、DuckDB。
- 输入：清洗视图或 `outputs/cleaned/*.csv`。
- SQL：`sql/03_usage_analysis.sql`、`04_cost_analysis.sql`、`05_sla_analysis.sql`、`06_event_analysis.sql`。
- 输出：`outputs/analysis/` 中的汇总结果和报告中的图表来源表。

## 分析顺序

不要直接找“异常”。先建立公司全貌：

```text
总量 → 时间趋势 → 结构占比 → 单位效率 → 服务表现 → 事件解释
```

## A. 建立月度使用汇总

```sql
SELECT
  DATE_TRUNC('month', timestamp_utc) AS usage_month,
  team_id,
  product_id,
  workload_type,
  SUM(active_gpu_count) AS active_gpu_hours,
  AVG(gpu_utilization_pct) AS avg_gpu_utilization_pct,
  SUM(business_volume) AS business_volume
FROM clean_usage
GROUP BY 1, 2, 3, 4
ORDER BY 1, 2, 3, 4;
```

注意：只有相同 `volume_unit` 的业务量才能汇总。正确做法通常是在 `GROUP BY` 中加入 `volume_unit`。

## B. 建立月度账单汇总

先明确使用月份还是发票月份：

```sql
SELECT
  invoice_month,
  charge_type,
  procurement_model,
  SUM(net_cost_usd) AS net_cost_usd
FROM clean_billing
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;
```

处理 `UnusedCommitment` 前必须阅读数据字典，避免与总账成本重复相加。

## C. 计算增长率

```sql
WITH monthly AS (
  SELECT
    invoice_month,
    SUM(net_cost_usd) AS monthly_cost
  FROM clean_billing
  WHERE charge_type <> 'UnusedCommitment'
  GROUP BY 1
)
SELECT
  invoice_month,
  monthly_cost,
  LAG(monthly_cost) OVER (ORDER BY invoice_month) AS previous_month_cost,
  monthly_cost / NULLIF(LAG(monthly_cost) OVER (ORDER BY invoice_month), 0) - 1 AS month_over_month_growth
FROM monthly
ORDER BY invoice_month;
```

`NULLIF(..., 0)` 防止除以零。

## D. 分析成本结构

常用维度：

- 团队；
- 产品；
- 区域；
- GPU 型号；
- 采购方式；
- 工作负载；
- 费用类型。

每次只增加一个维度，检查总成本能否与公司汇总核对。不要一次 JOIN 全部五张表。

## E. 计算单位成本

单位成本基本形式：

```text
可归属成本 ÷ 同一范围、同一期间、同一单位的业务量
```

必须同时满足：

- 成本与业务量时间口径一致；
- 团队或产品范围一致；
- `volume_unit` 一致；
- 共享费用分配规则明确；
- 分母不为零。

## F. 检查 SLA

连接 SLA 时必须考虑：

```text
team_id
+ product_id
+ workload_type
+ region
+ timestamp 位于 effective_from 和 effective_to 之间
```

然后比较实际值与目标值，而不是只看平均值。在线 SLA 通常需要按月或按事件窗口统计。

## G. 结合业务事件

使用事件表回答：

- 指标变化发生在事件之前、期间还是之后？
- 影响范围是否匹配团队、产品和区域？
- 变化是短期峰值还是持续趋势？
- 是否存在多个事件重叠？

事件只能提供解释线索，不能单凭时间接近就证明因果关系。

## H. 每条查询的注释模板

```sql
-- 业务问题：
-- 指标口径：
-- 时间口径：
-- 排除项：
-- 预期粒度：
-- 核对方式：
```

## SQL 探索知识树

```text
基础查询
├── SELECT / WHERE / CASE
├── GROUP BY / HAVING
├── SUM / AVG / COUNT
├── JOIN
├── 日期函数
├── CTE
└── 窗口函数 LAG / ROW_NUMBER / SUM OVER
```

## 验收标准

- 公司总成本与各维度成本能够核对。
- 不同业务量单位没有混加。
- JOIN 前后检查了行数和总额。
- 月度趋势明确时间口径。
- 重要变化至少提出两种可能解释并寻找证据。
- SQL 文件包含业务问题和指标注释。

## 建议提交

```powershell
git add sql/
git commit -m "analysis: add cloud usage and cost exploration"
git push
```
