# AI Cloud Cost Optimization

一个基于虚拟 B2B AI 公司的端到端云成本分析作品集。

本项目模拟一家同时运行模型训练与在线推理业务的 AI 公司。项目将从原始云资源使用、账单、资源清单、SLA 和业务事件数据出发，完成数据审计、成本归因、趋势预测、资源优化、仪表盘设计和管理层汇报。

> 项目状态：已完成数据准备、数据审计和 Pandas 清洗管道，正在进入 SQL 探索分析。

快速入口：[学习入口](learning/README.md) · [九阶段模板](learning/数据分析九阶段填空模板.md) · [指标与数据映射](learning/指标与数据映射.md) · [代码翻译与自检](learning/代码翻译与自检/README.md) · [公司背景](docs/company_background.md) · [数据字典](docs/data_dictionary.md) · [工作模拟练习册](workbook.md)

## 业务背景

虚拟公司向企业客户提供企业搜索、智能客服、文档智能和托管模型端点服务。

公司拥有七个业务与技术团队，在两个云区域运行 A100、H100 和 L40S 等 GPU 资源，工作负载同时覆盖：

- 模型训练
- 在线推理
- 批量推理
- 检索与重排
- 内容安全
- 应用研究

各团队具有不同的业务增长速度、SLA、资源使用模式和采购策略。云资源采用 Reserved、Savings Plan、On-demand 和自有容量等多种方式采购。

## 项目目标

本项目将回答以下业务问题：

1. 当前云资源和账单数据是否完整、准确并可用于决策？
2. 云成本应如何归因到团队、产品和工作负载？
3. 成本增长来自业务增长、资源效率下降，还是采购方式不合理？
4. 哪些低利用率资源可以优化，哪些必须因 SLA 或容灾要求保留？
5. Reserved 和 On-demand 的组合是否合理？
6. 未来业务增长需要多少 GPU 容量和预算？
7. 如何在控制成本的同时满足性能、容量和 SLA 要求？
8. 如何向管理层清晰说明节省机会、风险和实施顺序？

## 数据集

项目使用连续 12 个月的模拟业务数据，时间范围为 2025-08-01 至 2026-07-31。

| 文件 | 内容 |
|---|---|
| `resource_usage.csv` | 小时级 GPU 使用率、资源分配、吞吐量、延迟和可用性 |
| `cloud_billing.csv` | 云账单、承诺费用、On-demand 费用、抵扣和调整项 |
| `team_sla.csv` | 团队、产品和工作负载的 SLA 与关键等级 |
| `resource_inventory.csv` | GPU 类型、数量、区域、归属、采购方式和生命周期 |
| `business_events.csv` | 产品发布、客户上线、训练任务、事故和采购事件 |

数据为合成数据，不包含真实公司、客户或云账户信息。数据中保留了现实业务常见的数据质量问题和运营噪声。

## 分析流程

项目分为七个阶段：

1. Data Audit
2. SQL Analysis
3. Cost Attribution
4. Forecasting
5. Optimization
6. Dashboard
7. Executive Summary

每个阶段都将保留分析假设、处理方法、验证过程和业务解释，而不仅展示最终图表。

## 项目结构

```text
ai-cloud-cost-optimization/
├── data/
│   ├── sample/                   # GitHub 快速预览用的小样本
│   ├── resource_usage.csv        # 小时级 GPU 使用与业务量数据
│   ├── cloud_billing.csv         # 云账单与采购费用明细
│   ├── team_sla.csv              # 团队 SLA 与业务关键等级
│   ├── resource_inventory.csv    # GPU 资源池与采购信息
│   ├── business_events.csv       # 业务、技术和采购事件
│   ├── manifest.md               # 文件行数、大小与校验值
│   └── README.md                 # 数据目录使用说明
├── docs/
│   ├── company_background.md     # 完整公司与业务背景
│   └── data_dictionary.md        # 字段定义、单位与业务规则
├── learning/
│   ├── README.md                 # 唯一学习入口
│   ├── 数据分析九阶段填空模板.md  # 思路、模板、避坑和完成标准
│   ├── 指标与数据映射.md          # 场景、完整公式和数据映射
│   ├── 代码翻译与自检/            # SQL、Pandas模板、自检程序和完整范例
│   ├── 成果交付指南.md            # Power BI、管理摘要和作品集
│   └── references/               # SQL、Pandas、Power BI 按需速查
├── sql/                          # 你完成的 SQL 查询
├── notebooks/                    # 清洗、归因、预测与优化分析
├── src/
│   └── clean_data.py             # 五表 Pandas 清洗管道
├── tests/
│   └── test_clean_data.py        # 清洗规则自动测试
├── outputs/                      # 本地清洗结果，不上传 GitHub
├── dashboard/                    # Power BI 文件与仪表盘截图
├── reports/
│   ├── data_inventory.md         # 五张原始数据表盘点
│   └── data_audit.md             # 数据审计报告
├── workbook.md                   # 七阶段工作模拟练习册
├── README.md                     # 作品集首页
└── LICENSE                       # MIT 许可证
```

完整数据已经保存在 `data/`；`data/sample/` 中的同名文件用于在 GitHub 页面快速预览。

## 运行数据清洗

```powershell
python -m unittest discover -s tests -v
python src/clean_data.py
```

第一条命令验证清洗规则，第二条命令在 `outputs/cleaned/` 生成五张清洗 CSV 和 `quality_summary.csv`。原始 `data/` 不会被修改，`outputs/` 不上传 GitHub。

## 项目进度

- [x] 准备业务背景和原始数据
- [x] 完成数据字典
- [x] 完成数据质量审计
- [x] 建立 Pandas 数据清洗管道
- [ ] 完成 SQL 探索分析
- [ ] 建立成本归因模型
- [ ] 完成成本与容量预测
- [ ] 制定优化方案
- [ ] 创建管理仪表盘
- [ ] 完成管理层摘要

## 分析原则

- 不把低利用率直接等同于资源浪费。
- 同时考虑成本、业务量、性能、SLA 和容量风险。
- 明确区分事实、假设和建议。
- 所有关键结论都应能够追溯到原始数据。
- 优化建议需说明预计收益、实施条件和潜在风险。

## 技术工具

具体工具将在分析过程中根据任务需要选择，预计包括：

- SQL
- Python / Pandas
- Jupyter Notebook
- Power BI、Tableau 或其他可视化工具
- Git 和 GitHub

## 免责声明

本项目中的公司、团队、资源、合同、业务事件和账单数据均为虚构或合成内容，仅用于学习和作品展示，不代表任何真实企业的经营情况。

## License

本项目采用 [MIT License](LICENSE)。
