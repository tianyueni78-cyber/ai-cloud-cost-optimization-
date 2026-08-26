# SQL 实用导航

这份 README 不要求先学完 SQL。它只回答三个问题：

1. 我现在应该运行哪个文件？
2. 这个文件在整个分析流程中负责什么？
3. 换一个项目时，哪些方法能保留，哪些内容必须修改？

## 先看执行顺序

```text
认识一张表
  00_data_orientation.sql
        ↓
盘点全部数据源
  01_source_inventory.sql
        ↓
第一轮广度审计
  02_data_audit.sql
        ↓
对异常做详细统计
  03_data_audit_detail.sql
        ↓
结合业务解释异常
  04_data_audit_context.sql
        ↓
确定清洗处理规则
  05_data_audit_resolution.sql
        ↓
读取清洗数据，开始业务分析
  06_business_overview.sql
```

这不是说所有项目都必须有七个文件。这里把真实工作拆开，是为了保留“发现问题 → 定位问题 → 解释问题 → 决定处理”的证据链。

## 文件导航映射

| 文件 | 什么时候用 | 主要回答什么 | 输入数据 | 对应学习文档 |
|---|---|---|---|---|
| `00_data_orientation.sql` | 第一次打开数据时 | 字段是什么、样例长什么样、表有多大 | 原始数据 | `learning/03_data_orientation.md` |
| `01_source_inventory.sql` | 收到多张表后 | 有哪些表、各有多少行、结构和粒度是什么 | 原始数据 | `learning/03_data_orientation.md` |
| `02_data_audit.sql` | 认识数据之后 | 是否存在重复、空值、非法范围、格式和关联问题 | 原始数据 | `learning/04_data_audit.md` |
| `03_data_audit_detail.sql` | 第一轮发现问题后 | 每类异常有多少、属于哪种重复、标准化能改善多少 | 原始数据 | `learning/04_data_audit.md` |
| `04_data_audit_context.sql` | 数量已经知道，但不知道是否合理时 | 空值是否不适用、字段关系是否违反业务规则 | 原始数据 + 数据字典 | `learning/04_data_audit.md` |
| `05_data_audit_resolution.sql` | 准备写清洗规则前 | 哪些能保留、回填、去重，冲突记录选择哪条 | 原始数据 + 审计结论 | `learning/04_data_audit.md`、`05_data_cleaning.md` |
| `06_business_overview.sql` | 清洗和验证完成后 | 团队成本、采购结构、GPU利用率、负载和月度趋势 | `outputs/cleaned/` | `learning/06_sql_exploration.md` |

## 数据审计知识点对应哪些 SQL

| 通用审计维度 | 先看 | 需要深入时再看 |
|---|---|---|
| 完整性：空值 | `02` | `03`、`04` |
| 唯一性：主键和业务重复 | `02` | `03`、`05` |
| 有效性：类型、范围和枚举 | `02` | `04` |
| 一致性：ID和格式 | `02` | `03` |
| 可关联性：表间匹配率 | `02` | `03`、`05` |
| 及时性：日期范围和时区 | `02` | `03` |
| 业务规则：跨字段逻辑 | `04` | `05` |

记忆方式不是背编号，而是：

```text
02 扫描问题
03 量化问题
04 解释问题
05 决定怎样处理
```

## 怎样运行

先确认终端位于项目根目录：

```text
D:\CODEX\ai-cloud-cost-optimization-
```

通用命令：

```powershell
python run_sql.py sql/文件名.sql
```

例如：

```powershell
python run_sql.py sql/00_data_orientation.sql
python run_sql.py sql/06_business_overview.sql
```

不要在命令中写 Markdown 转义符。正确文件名是：

```text
06_business_overview.sql
```

不是：

```text
06\_business\_overview\.sql
```

## 原始数据还是清洗数据

| 任务 | 应该读取什么 | 原因 |
|---|---|---|
| 认识数据 | `data/*.csv` | 需要看到源系统原貌 |
| 数据审计 | `data/*.csv` | 不能让清洗提前隐藏问题 |
| 制定清洗规则 | `data/*.csv` + 审计结果 | 规则必须追溯到原始证据 |
| 正式业务分析 | `outputs/cleaned/*.csv` | 使用已经验证的统一键和去重结果 |

不要直接修改 `data/`。如果清洗规则改变，重新运行：

```powershell
python src/clean_data.py
```

## 换一个项目时怎样改

### 通常可以保留

- `DESCRIBE`、`LIMIT`、`COUNT` 的数据认识结构——通用教程：[认识数据](../learning/03_data_orientation.md)；项目实现：[00](00_data_orientation.sql)、[01](01_source_inventory.sql)。
- 空值、重复、范围、枚举和关联率的审计思路——通用教程：[数据审计](../learning/04_data_audit.md)；项目实现：[02](02_data_audit.sql)、[03](03_data_audit_detail.sql)、[04](04_data_audit_context.sql)、[05](05_data_audit_resolution.sql)。
- `GROUP BY`、占比、环比和窗口函数的分析方法——通用教程：[SQL探索](../learning/06_sql_exploration.md)；项目实现：[06](06_business_overview.sql)。
- “先原始数据审计，再清洗，再正式分析”的顺序——总流程：[端到端工作流](../learning/00_end_to_end_workflow.md)；清洗方法：[数据清洗](../learning/05_data_cleaning.md)。
- 清洗前后对账和总账归因核对——通用教程：[数据清洗](../learning/05_data_cleaning.md)、[成本归因](../learning/07_cost_attribution.md)；项目清洗实现：[clean_data.py](../src/clean_data.py)。

### 必须重新确认和替换

- 文件路径和表名；
- 一行数据的业务粒度；
- 主键和业务重复键；
- 允许为空的字段；
- 合法枚举、数值范围和跨字段规则；
- 表之间的关联键和生效日期；
- 指标单位、币种和时区；
- 总账纳入哪些费用；
- 分析维度和真正影响决策的 KPI。

不要因为另一个项目也有 `team_id`、`cost` 或 `status`，就默认它们与本项目含义相同。

## 常见问题和处理方法

### 1. `FileNotFoundError`

常见原因：

- SQL 文件没有创建或保存；
- 尚未执行 `git pull`；
- 终端不在项目根目录；
- 文件名复制时带了 `\_` 或 `\.`。

先检查：

```powershell
Get-ChildItem sql
```

### 2. `NoneType` 没有 `show`

`CREATE VIEW` 和 `SET` 等语句可能不返回表格。`run_sql.py` 必须先判断结果是否为 `None`，再调用 `.show()`。

### 3. PowerShell 把 `COUNT(*)` 中的 `*` 当成命令

这通常发生在复杂的 `python -c` 嵌套引号中。优先把查询写入 `.sql` 文件，再运行：

```powershell
python run_sql.py sql/文件名.sql
```

### 4. 终端用 `…` 隐藏列

把一张很宽的结果拆成多张窄表，或者采用：

```text
field_name | metric_value
```

这种纵向输出。不要根据被隐藏的列猜结果。

### 5. 空值很多，是否直接填 0

不能。先判断：

```text
字段不适用
还是
字段本应有值但采集失败
```

0是实际观测值，NULL是未知或不适用，两者业务含义不同。

### 6. 显示13个月，但数据明明是12个月

通常是UTC时间被本地时区转换后跨越月份边界。时间分析前明确设置：

```sql
SET TimeZone = 'UTC';
```

但真实项目应采用业务定义的时区，不是永远固定UTC。

### 7. 月度成本突然暴跌

先检查使用月份和发票月份是否混用。延迟入账、抵扣和调整可能出现在后续发票月，不能立即解释为业务成本下降。

### 8. 利用率低，是否直接回收资源

不能。还需检查SLA、备用容量、容灾角色、合同期限、任务峰值和GPU兼容性。

### 9. 不同业务量能否相加

只有单位和业务粒度可比较时才能汇总。`requests`、`jobs` 和 `k_pages` 不能直接相加或排名。

### 10. 总成本是否直接汇总所有费用类型

不一定。先定义总账范围，防止承诺费用、未使用承诺展示项、抵扣和调整被重复或遗漏计算。

## 最实用的使用方式

遇到新项目时，不要先复制全部 SQL。按下面顺序做：

1. 复制一种查询结构，例如字段、样例和行数检查。
2. 替换成新项目的表名和字段。
3. 写下新项目的一行粒度、主键、单位和时间字段。
4. 根据数据字典重写允许空值、范围和业务规则。
5. 每次只解决一个明确问题并验证结果。
6. 将项目特例写在 SQL 顶部，避免以后误当成通用规则。

如果不知道下一步运行哪个文件，回到本页的“文件导航映射”，按当前问题选择，不必背编号。
