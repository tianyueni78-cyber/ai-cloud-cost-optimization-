# Power BI 项目知识树与速查

## Power BI 的四个工作区

```text
Power Query：导入和轻量转换
模型视图：建立表关系
DAX：创建可动态计算的度量值
报表视图：制作图表和交互
```

## 1. Power Query

本项目常用操作：

- 设置正确数据类型；
- 重命名列；
- 删除明确不需要的列；
- 合并查询；
- 追加查询；
- 创建日期字段；
- 查看错误和空值；
- 设置数据源路径。

原则：复杂、关键清洗尽量留在 SQL/Python，Power Query 只做导入所需的透明转换。

## 2. 数据模型

```text
维度表（1） ───────── （多）事实表
```

常见维度：日期、团队、产品、资源、区域、采购方式。

检查：

- “一”端键唯一；
- 关系方向通常单向；
- 不要随意启用多对多；
- 不要让两张事实表直接相连；
- 建立独立日期表；
- 隐藏仅用于关系的技术键。

## 3. 计算列与度量值

- 计算列：逐行计算并存储，适合分类和固定属性。
- 度量值：根据筛选上下文动态计算，适合 KPI 和汇总。

本项目的成本、业务量、利用率和增长率通常应创建为度量值。

## 4. 常用 DAX

```DAX
Total Cost = SUM(fact_billing[net_cost_usd])
```

```DAX
Cost per Unit = DIVIDE([Total Cost], [Business Volume])
```

```DAX
Previous Month Cost =
CALCULATE([Total Cost], DATEADD(dim_date[date], -1, MONTH))
```

```DAX
MoM Growth =
DIVIDE([Total Cost] - [Previous Month Cost], [Previous Month Cost])
```

```DAX
Cost Share =
DIVIDE(
    [Total Cost],
    CALCULATE([Total Cost], ALL(dim_team[team_id]))
)
```

## 5. 筛选上下文

同一个度量值会随着以下内容变化：

- 页面筛选器；
- 切片器；
- 图表行列；
- 视觉交互；
- DAX 中的 `CALCULATE`。

理解筛选上下文比背大量 DAX 函数更重要。

## 6. 图表选择

- 趋势：折线图；
- 排名：横向条形图；
- 构成：堆积条形图；
- 单一 KPI：卡片；
- 收益与风险：散点图；
- 行动清单：矩阵或表格；
- 多指标详细趋势：小倍图。

## 7. 条件格式

用于：

- 成本增长；
- SLA 风险；
- 容量缺口；
- 优化优先级；
- 预测差异。

颜色必须有明确含义，并避免仅靠红绿色区分状态。

## 8. 验证方法

在 Power BI 中建立“控制页面”，显示：

- 总成本；
- 总 GPU 小时；
- 数据最早和最晚日期；
- 资源池数量；
- 未匹配行数。

将这些数字与 SQL 控制表逐一比较。

## 9. GitHub 交付

- `.pbix`：源文件；
- `.png`：每个主要页面截图；
- `dashboard/README.md`：页面说明、指标定义和刷新方式；
- 如文件过大，记录下载方式。

## 最小学习路径

```text
获取数据
→ Power Query 类型检查
→ 星型模型和关系
→ 基础度量值
→ 时间度量值
→ 页面布局
→ 交互和筛选
→ SQL 核对
→ 截图与发布
```
