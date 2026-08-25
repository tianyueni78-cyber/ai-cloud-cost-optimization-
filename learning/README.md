# 项目制数据分析学习中心

这里不是一套要求你先学完再做项目的课程，而是一份可以边做作品集、边学习工具的操作手册。

## 学习原则

1. 每次只做当前阶段需要的知识，不提前背完整语法。
2. 先看示范，再亲自运行；不靠猜测完成任务。
3. 原始数据永远保持不变，所有处理都能通过代码复现。
4. 每个结论都保留查询、输出和业务解释。
5. 每完成一个阶段，就形成一个可展示的 Git 提交。

## 推荐顺序

| 顺序 | 文件 | 完成标志 |
|---:|---|---|
| 0 | [端到端工作流](00_end_to_end_workflow.md) | 知道项目从需求到汇报的完整路径 |
| 1 | [环境安装](01_environment_setup.md) | VS Code 能运行 Python 和 DuckDB |
| 2 | [业务理解](02_business_understanding.md) | 写出项目业务问题和限制 |
| 3 | [认识数据](03_data_orientation.md) | 说清五张表的一行代表什么及如何连接 |
| 4 | [数据审计](04_data_audit.md) | 完成可复现的数据质量检查 |
| 5 | [数据清洗](05_data_cleaning.md) | 建立不修改原始文件的干净数据层 |
| 6 | [SQL 探索分析](06_sql_exploration.md) | 用 SQL 回答基础经营问题 |
| 7 | [成本归因](07_cost_attribution.md) | 将成本归属到团队和产品 |
| 8 | [预测](08_forecasting.md) | 形成基线与三种情景预测 |
| 9 | [优化](09_optimization.md) | 提出带收益、条件和风险的行动方案 |
| 10 | [Power BI](10_power_bi_dashboard.md) | 完成可展示的管理仪表盘 |
| 11 | [管理层摘要](11_executive_summary.md) | 写出一页式决策材料 |
| 12 | [GitHub 作品集](12_github_portfolio.md) | README、截图、代码和报告形成完整故事 |

## 每阶段怎么使用

每份指南都按相同结构编写：

```text
业务目标 → 使用软件 → 输入文件 → 输出文件
       → 具体操作 → 必要知识 → 质量检查 → Git 提交
```

第一次阅读时不要试图记住全部内容。先完成“具体操作”，遇到不理解的语法，再打开 `references/` 中的对应参考手册。

## 参考手册

- [SQL 知识树](references/sql_reference.md)
- [Pandas 知识树](references/pandas_reference.md)
- [Power BI 知识树](references/power_bi_reference.md)
- [数据质量检查清单](references/data_quality_checklist.md)
- [阶段交付物检查清单](references/deliverables_checklist.md)

## 辅导方式

遇到问题时，请同时提供：

1. 当前所在阶段；
2. 运行的完整命令或代码；
3. 完整报错或输出；
4. 你希望得到的结果。

辅导将直接解释概念、提供可运行示范并带你解释输出，不要求你凭空猜答案。
