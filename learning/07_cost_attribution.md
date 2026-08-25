# 07｜成本归因

## 目标

将账单费用可靠地分配到团队、产品、区域和工作负载，并明确共享成本和承诺成本的处理口径。

## 软件、输入和输出

- 软件：DuckDB、VS Code；敏感性分析可使用 Pandas/Jupyter。
- 输入：清洗后的账单、使用、库存和 SLA。
- SQL：`sql/07_cost_attribution.sql`。
- Notebook：`notebooks/02_cost_attribution.ipynb`。
- 输出：月度归因表及口径说明。

## 归因顺序

```text
确认账单总额
→ 分类费用
→ 直接归属
→ 处理共享费用
→ 处理承诺口径
→ 计算单位成本
→ 与原账单核对
→ 做敏感性分析
```

## A. 先定义总账口径

建立费用类型表：

| 费用类型 | 是否进入总账成本 | 如何归属 |
|---|---|---|
| `Usage` | 是 | 优先按资源池直接归属 |
| `Credit` | 是 | 按业务背景或团队标签抵减 |
| `Adjustment` | 是 | 按使用期间和原费用归属 |
| `Support` | 是 | 按选定驱动因素分摊 |
| `UnusedCommitment` | 视定义而定 | 管理分析口径，防止重复计入 |

不能先把所有 `net_cost_usd` 相加，再思考口径。

## B. 直接归属

```sql
SELECT
  b.invoice_month,
  COALESCE(i.team_id, b.team_id, 'UNALLOCATED') AS attributed_team_id,
  COALESCE(i.product_id, 'UNALLOCATED') AS attributed_product_id,
  SUM(b.net_cost_usd) AS direct_cost_usd
FROM clean_billing b
LEFT JOIN clean_inventory i
  ON b.resource_pool_id = i.resource_pool_id
WHERE b.charge_type IN ('Usage', 'Credit', 'Adjustment')
GROUP BY 1, 2, 3;
```

使用 `COALESCE` 前要确定字段优先级，并保留无法归属的 `UNALLOCATED`，不要静默丢弃。

## C. 共享费用分摊

共享费用可能使用以下驱动因素：

- 活跃 GPU 小时；
- 分配 GPU 小时；
- 可比较业务量；
- 请求量；
- 团队直接成本；
- 固定比例。

通用公式：

```text
团队分摊额 = 共享费用 × 团队驱动量 ÷ 所有团队驱动量
```

选择驱动因素时回答：它是否代表资源消耗或业务责任？不能只因为数据方便就使用。

## D. 处理共享平台资源

`PRD-SHARED` 不能直接当成最终产品。可建立“共享平台 → 产品”的二次分摊：

1. 汇总各产品对平台的实际使用驱动；
2. 计算产品占比；
3. 分配平台成本；
4. 保留驱动量和分配比例；
5. 核对分配前后总额相等。

## E. 计算单位成本

分别计算，不混合单位：

```text
推理单位成本 = 推理可归属成本 ÷ 请求数
训练单位成本 = 训练可归属成本 ÷ 作业数或 GPU 小时
文档单位成本 = 文档成本 ÷ 千页数
```

单位成本必须注明是否包含共享费用、支持费、抵扣和承诺闲置口径。

## F. 核对控制表

建立控制表：

| 月份 | 原账单成本 | 已归属成本 | 未归属成本 | 差额 |
|---|---:|---:|---:|---:|

要求：

```text
原账单成本 = 已归属成本 + 未归属成本
```

允许的差异只能来自公开舍入规则。

## G. 敏感性分析

至少比较两种共享费用分配方式，观察：

- 哪些团队成本变化最大；
- 单位成本排序是否改变；
- 管理建议是否依赖某个主观规则。

## 知识树

```text
成本归因
├── 总账口径
├── 直接成本
├── 共享成本
├── 分摊驱动因素
├── 承诺与闲置口径
├── 单位成本
├── 未归属成本
└── 总额核对与敏感性
```

## 验收标准

- 明确哪些 `charge_type` 进入总成本。
- 分摊规则具有业务解释。
- 归因总额与原账单核对。
- 未归属费用没有被删除。
- 不同业务量单位分别计算单位成本。
- 至少完成一次敏感性比较。

## 建议提交

```powershell
git add sql/07_cost_attribution.sql notebooks/02_cost_attribution.ipynb
git commit -m "analysis: build reconciled cost attribution model"
git push
```
