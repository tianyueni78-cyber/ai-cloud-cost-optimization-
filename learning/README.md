# 学习入口

这里只负责告诉你**现在打开什么**，不重复讲教程。

## 推进项目

打开[数据分析九阶段填空模板](数据分析九阶段填空模板.md)，只完成当前阶段：

```text
1 业务理解 → 2 数据认识 → 3 数据审计 → 4 数据清洗
→ 5 探索分析 → 6 成本归因 → 7 原因分析 → 8 预测 → 9 优化
```

每一阶段都按“思路 → 模板 → 映射检查 → 代码骨架 → 避坑 → 完成标准”推进。

## 不知道为什么这样算

打开[指标与数据映射](指标与数据映射.md)，查完整公式、应用场景、表与字段、关联、时间、粒度和验证方法。

## 不理解按需、预留、节省计划和采购判断

打开[采购知识](采购知识/README.md)，先建立采购方式、费用类型、数据表职责和常见采购公式的知识树，再做采购分析题。

## 知道业务思路，但不会翻译成代码或判断代码对错

打开[代码翻译与自检](代码翻译与自检/README.md)，按这个顺序使用：

```text
SQL或Pandas翻译模板 → 固定自检程序 → 完整范例
```

里面有带就地注释的可复制代码：每个占位符旁直接说明要替换什么，并给出本项目字段示例。代码能运行后，必须再检查主键、公式、空值、JOIN、对账和时间口径。

## 只是不记得工具语法

- [SQL速查](references/sql_reference.md)
- [Pandas速查](references/pandas_reference.md)
- [Power BI速查](references/power_bi_reference.md)

这些是语法字典，不负责业务到代码的翻译；遇到具体语法问题时再查。

## 分析已经完成

打开[成果交付指南](成果交付指南.md)，依次制作Power BI、管理层摘要和GitHub作品集。

## 本项目常用命令

```powershell
# 运行指定SQL
python run_sql.py sql/00_data_orientation.sql

# 验证并生成清洗数据
python -m unittest discover -s tests -v
python src/clean_data.py
```

SQL文件的选择和顺序见 [SQL实用导航](../sql/README.md)。公司与字段规则见[公司背景](../docs/company_background.md)和[数据字典](../docs/data_dictionary.md)。
