# 12｜整理 GitHub 作品集

## 目标

将代码、分析、仪表盘和管理结论组织成招聘方能够快速理解、能够复核、能够运行的完整作品集。

## 软件与输入

- 软件：VS Code、Git、GitHub 浏览器。
- 输入：所有已完成阶段。
- 输出：更新后的根 `README.md`、清晰的仓库结构和完整提交历史。

## 作品集故事线

```text
真实业务问题
→ 有噪声的原始数据
→ 严谨的数据审计
→ 可重复的分析方法
→ 有约束的优化方案
→ 管理层仪表盘和行动建议
```

## A. 根 README 最终结构

1. 项目标题和一句话价值。
2. 业务背景。
3. 需要解决的决策问题。
4. 数据规模和数据关系。
5. 方法与工具。
6. 关键发现（完成分析后再写）。
7. 优化行动与预计影响。
8. 仪表盘截图。
9. 项目结构。
10. 复现步骤。
11. 限制和后续工作。

## B. 展示成果，不伪造成果

- 只写实际完成并核对的结果；
- 不使用预先生成的答案；
- 不夸大节省金额；
- 清楚说明数据为合成数据；
- 说明哪些部分由你完成、使用了哪些辅助工具；
- 保留错误修正和迭代记录，不必制造“一次成功”的假象。

## C. 整理文件

提交：

- SQL；
- Notebook；
- Markdown 报告；
- Power BI 文件；
- 仪表盘截图；
- 数据字典；
- 小规模可预览结果表。

不要提交：

- `.venv/`；
- 缓存；
- API 密钥；
- 个人绝对路径；
- 无法解释的临时文件；
- 可重新生成的大量中间文件。

## D. Notebook 发布前清理

- 从上到下重新运行；
- 删除无关测试单元格；
- 保留必要输出；
- 图表有标题、单位和来源；
- 不显示本地用户名和路径；
- Markdown 解释业务问题和结论；
- 代码运行顺序连续。

## E. 提交历史

推荐按业务成果提交：

```text
chore: configure local analysis environment
docs: map source data and business questions
analysis: complete source data audit
data: add reproducible cleaning pipeline
analysis: add cloud usage and cost exploration
analysis: build reconciled cost attribution model
forecast: add validated cost and capacity scenarios
analysis: propose risk-adjusted cloud cost actions
dashboard: add executive cloud cost report
report: publish executive recommendations
docs: finalize portfolio walkthrough
```

## F. GitHub 页面检查

逐项点击确认：

- README 内部链接可打开；
- 图片正常显示；
- 文件和目录大小写一致；
- SQL 有注释；
- Notebook 能在 GitHub 预览；
- 报告不是空文件；
- LICENSE 存在；
- 没有凭据和个人路径；
- 默认分支展示最新提交。

## G. 招聘方一分钟检查

让一个不了解项目的人在一分钟内回答：

- 公司遇到了什么问题？
- 你分析了什么数据？
- 你用了什么方法？
- 你发现了什么？
- 你建议做什么？
- 这体现了哪些岗位能力？

如果必须打开多个 Notebook 才能回答，README 还不够完整。

## 能力映射

| 项目成果 | 展示的能力 |
|---|---|
| 数据审计 | 数据质量、严谨性、问题定义 |
| SQL 文件 | 查询、建模、指标口径 |
| 成本归因 | 业务分析、财务意识、核对能力 |
| 预测 | 时间序列、假设管理、不确定性 |
| 优化方案 | 决策、风险、行动设计 |
| Power BI | 数据建模、DAX、可视化沟通 |
| 管理层摘要 | 商业表达和影响力 |

## 最终验收标准

- 新访客从 README 能理解完整故事。
- 所有关键数字可以追溯到代码。
- 仓库可按说明重新运行。
- 数据、代码、图表和报告口径一致。
- 提交历史反映真实学习过程。
- 项目没有泄露凭据或个人隐私。
