# 10｜Power BI 管理仪表盘

## 目标

把已经验证的分析表制作成管理层能快速阅读、分析人员能下钻的交互仪表盘。

## 软件、输入和输出

- 软件：Power BI Desktop（Windows）。
- 输入：`outputs/analysis/` 中稳定的汇总表，不建议直接加载全部原始小时记录作为第一版。
- 输出：`dashboard/ai_cloud_cost_dashboard.pbix` 和 `dashboard/images/` 截图。

## 开始前的条件

只有满足以下条件才进入 Power BI：

- 数据审计完成；
- 清洗规则稳定；
- 成本口径已核对；
- 主要指标已有 SQL 结果；
- 时间、团队、产品和资源维度明确。

Power BI 不是用来掩盖未完成的数据处理。

## A. 准备星型模型

建议输入表：

```text
事实表
├── fact_usage_monthly
├── fact_billing
└── fact_sla_performance

维度表
├── dim_date
├── dim_team
├── dim_product
├── dim_resource
├── dim_region
└── dim_procurement
```

事实表保存可汇总数字，维度表保存分类属性。尽量避免事实表之间直接多对多连接。

## B. 导入数据

1. 打开 Power BI Desktop。
2. 选择“获取数据”。
3. 选择 Text/CSV 或 Parquet。
4. 选择准备好的分析表。
5. 点击“转换数据”，先进入 Power Query。
6. 检查列类型、列名、空值和不需要的列。
7. 点击“关闭并应用”。

不要在 Power Query 中重复一套没有记录在 SQL/Python 中的复杂清洗逻辑。

## C. 建立关系

打开“模型视图”，检查：

- 维度表主键唯一；
- 维度到事实是一对多；
- 筛选方向通常为单向；
- 日期维度连接到正确的日期字段；
- 没有自动生成的错误关系；
- 不使用模糊的双向关系解决模型设计问题。

## D. 建立基础度量值

示例 DAX：

```DAX
Total Net Cost =
SUM(fact_billing[net_cost_usd])
```

```DAX
Active GPU Hours =
SUM(fact_usage_monthly[active_gpu_hours])
```

```DAX
Average GPU Utilization =
DIVIDE(
    SUM(fact_usage_monthly[utilization_weighted_sum]),
    SUM(fact_usage_monthly[allocated_gpu_hours])
)
```

```DAX
MoM Cost Growth =
VAR PreviousMonthCost =
    CALCULATE([Total Net Cost], DATEADD(dim_date[date], -1, MONTH))
RETURN
    DIVIDE([Total Net Cost] - PreviousMonthCost, PreviousMonthCost)
```

平均比例尽量使用加权分子和分母，不要对已经聚合的百分比再次简单平均。

## E. 页面设计

### 页面 1：Executive Overview

- 总净成本；
- 环比或同比；
- 预测差异；
- 可实现节省；
- 关键容量/SLA 风险；
- 月度成本趋势；
- 团队或产品成本结构。

### 页面 2：Cost Drivers

- 团队、产品、GPU、区域和采购方式；
- 成本与业务量对比；
- 单位成本趋势；
- 发票月份与使用月份切换。

### 页面 3：Capacity & SLA

- 利用率分布；
- 峰值容量；
- 延迟和可用性；
- 备用与故障恢复资源；
- 预测容量缺口。

### 页面 4：Optimization Actions

- 行动清单；
- 节省金额；
- 风险和难度；
- 负责人；
- 30/60/90 天计划。

## F. 视觉选择原则

| 问题 | 推荐视觉 |
|---|---|
| 时间趋势 | 折线图 |
| 分类比较 | 横向条形图 |
| 构成变化 | 堆积条形图或小倍图 |
| KPI 状态 | 卡片 + 明确比较基准 |
| 收益与风险 | 散点图或表格 |
| 详细行动 | 条件格式表格 |

不要用饼图展示十几个团队/资源，也不要为了“高级感”堆叠装饰图表。

## G. 验证仪表盘

- 卡片总成本与 SQL 控制表一致；
- 筛选后数字仍能核对；
- 没有重复关系导致金额放大；
- 时间筛选使用正确日期；
- 空值显示方式明确；
- 每个图表都能回答一个业务问题；
- 截图不含个人路径或敏感信息。

## H. GitHub 展示

GitHub 不能直接预览 `.pbix`。需要同时保存：

- `dashboard/ai_cloud_cost_dashboard.pbix`；
- `dashboard/images/executive_overview.png`；
- `dashboard/images/cost_drivers.png`；
- `dashboard/README.md`，说明页面、指标和刷新方式。

## 验收标准

- 数据模型以星型结构为主。
- 关键 KPI 是度量值而非手工数字。
- 总额与 SQL 结果一致。
- 管理层首页可在一分钟内读懂。
- 重要建议同时展示收益和风险。
- GitHub 有可直接浏览的截图。

## 建议提交

```powershell
git add dashboard/
git commit -m "dashboard: add executive cloud cost report"
git push
```
