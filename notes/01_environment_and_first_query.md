# 01｜环境配置与第一次 SQL 查询

## 1. 项目环境配置

### 目的

为项目建立独立 Python 环境，并确认 DuckDB、Pandas 和项目 CSV 可以正常使用。

### 使用的软件和文件

- PowerShell
- VS Code
- Python 虚拟环境 `.venv`
- DuckDB
- Pandas
- `data/resource_inventory.csv`

### 输入

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install duckdb pandas jupyter matplotlib seaborn
```

验证 DuckDB 和 Pandas：

```powershell
python -c "import duckdb, pandas; print(duckdb.sql('SELECT 42 AS answer').fetchall()); print(pandas.__version__)"
```

### 输出

```text
[(42,)]
3.0.5
```

### 结果说明

- `[(42,)]` 表示 DuckDB 能正常执行 SQL。
- `3.0.5` 是当前虚拟环境中的 Pandas 版本。
- 终端提示符出现 `(.venv)`，说明项目虚拟环境已经激活。
- 同时出现 `(base)` 表示 Conda 基础环境也处于激活状态；当前 `.venv` 排在前面，不影响本项目运行。

### 遇到的问题和解决方法

第一次在 PowerShell 中执行带嵌套引号的 Python 命令时，引号和反斜杠造成了解析错误。改用参数化文件路径后成功：

```powershell
python -c "import duckdb; print(duckdb.execute('SELECT COUNT(*) FROM read_csv_auto(?)', ['data/resource_inventory.csv']).fetchall())"
```

关键经验：SQL 中的 `*` 和字段名中的 `_` 不需要添加反斜杠。

## 2. 建立 Git 忽略规则

### 目的

防止虚拟环境、缓存和可重复生成的中间文件进入 Git 仓库。

### 输入文件

在项目根目录创建 `.gitignore`：

```gitignore
.venv/
__pycache__/
.ipynb_checkpoints/
outputs/
*.duckdb
```

### 输出

执行：

```powershell
git status --short
```

结果只显示：

```text
?? .gitignore
```

### 结果说明

- `??` 表示 `.gitignore` 是尚未加入 Git 的新文件。
- `.venv/` 没有出现，说明忽略规则生效。

## 3. 第一次 SQL 查询

### 目的

认识资源清单的字段、样例和总行数。

### 使用的文件

- SQL：`sql/00_data_orientation.sql`
- 执行器：`run_sql.py`
- 数据：`data/resource_inventory.csv`

### SQL 输入

```sql
-- 目的：认识资源清单的结构、内容和数据量

-- 查看字段名称和数据类型
DESCRIBE
SELECT *
FROM read_csv_auto('data/resource_inventory.csv');

-- 查看前 10 行，了解实际记录长什么样
SELECT *
FROM read_csv_auto('data/resource_inventory.csv')
LIMIT 10;

-- 统计资源清单的总行数
SELECT COUNT(*) AS row_count
FROM read_csv_auto('data/resource_inventory.csv');
```

### Python 执行器

```python
from pathlib import Path

import duckdb


sql_text = Path("sql/00_data_orientation.sql").read_text(encoding="utf-8")

for statement in sql_text.split(";"):
    if statement.strip():
        duckdb.sql(statement).show()
```

运行命令：

```powershell
python run_sql.py
```

### 关键输出

- 表结构：17 个字段。
- 数据样例：显示前 10 个资源池。
- 总行数：58。
- `gpu_count` 被推断为 `BIGINT`。
- GPU 价格字段被推断为 `DOUBLE`。
- `start_date` 被推断为 `DATE`。
- `end_date` 被推断为 `VARCHAR`。

### 结果说明

- `resource_inventory.csv` 一行代表一个 GPU 资源池。
- `58` 表示公司资源清单中共有 58 个资源池，不代表只有 58 张 GPU；GPU 数量需要汇总 `gpu_count`。
- DuckDB 输出中的 `…` 表示终端宽度不足而隐藏了部分列，不代表数据缺失。
- `DESCRIBE` 中的 `null = YES` 表示 CSV 没有数据库非空约束，不代表每一列实际存在空值。
- `end_date` 被推断为文本，需要在数据审计阶段检查该列内容及日期转换情况。

### 学到的 SQL 知识

- `DESCRIBE`：查看查询结果的字段和类型。
- `SELECT *`：选择全部字段。
- `FROM`：指定数据来源。
- `read_csv_auto`：让 DuckDB 读取并推断 CSV。
- `LIMIT 10`：只显示前 10 行。
- `COUNT(*)`：统计总行数。
- `AS row_count`：给结果列命名。

## 下一步

继续在 `sql/00_data_orientation.sql` 中统计：

- 每个团队的资源池和 GPU 数量；
- 每种 GPU 型号的资源数量；
- 采购方式与工作负载的组合。

## 4. 资源分布查询

### 新增操作

PowerShell 当前进程允许执行本地激活脚本，然后激活虚拟环境：

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
.venv\Scripts\Activate.ps1
```

`-Scope Process` 只影响当前 PowerShell 窗口，关闭窗口后失效，不会永久修改整个系统的执行策略。

在 `sql/00_data_orientation.sql` 中新增三组汇总：

```sql
-- 按团队统计资源池数量和 GPU 总数
SELECT
    team_id,
    COUNT(*) AS resource_pool_count,
    SUM(gpu_count) AS total_gpu_count
FROM read_csv_auto('data/resource_inventory.csv')
GROUP BY team_id
ORDER BY total_gpu_count DESC;

-- 按 GPU 型号统计资源池数量和 GPU 总数
SELECT
    gpu_model,
    COUNT(*) AS resource_pool_count,
    SUM(gpu_count) AS total_gpu_count
FROM read_csv_auto('data/resource_inventory.csv')
GROUP BY gpu_model
ORDER BY total_gpu_count DESC;

-- 查看采购方式和工作负载的组合
SELECT
    procurement_model,
    workload_type,
    COUNT(*) AS resource_pool_count,
    SUM(gpu_count) AS total_gpu_count
FROM read_csv_auto('data/resource_inventory.csv')
GROUP BY procurement_model, workload_type
ORDER BY procurement_model, workload_type;
```

### 关键输出

#### 团队资源

| 团队 | 资源池数 | GPU 总数 |
|---|---:|---:|
| `TEAM-MIP` | 10 | 200 |
| `TEAM-SRCH` | 9 | 168 |
| `TEAM-DOC` | 8 | 160 |
| `TEAM-FMT` | 8 | 136 |
| `TEAM-TRUST` | 7 | 128 |
| `TEAM-CONV` | 9 | 120 |
| `TEAM-RES` | 7 | 104 |

#### GPU 型号

| GPU 型号 | 资源池数 | GPU 总数 |
|---|---:|---:|
| `A100-40GB` | 16 | 356 |
| `L40S-48GB` | 14 | 248 |
| `A100-80GB` | 15 | 232 |
| `H100-80GB` | 13 | 180 |

#### 采购方式汇总

| 采购方式 | 资源池数 | GPU 总数 |
|---|---:|---:|
| `OnDemand` | 16 | 272 |
| `Owned` | 10 | 180 |
| `Reserved` | 19 | 316 |
| `SavingsPlan` | 13 | 248 |

#### 工作负载汇总

| 工作负载 | 资源池数 | GPU 总数 |
|---|---:|---:|
| `Batch` | 17 | 288 |
| `Inference` | 27 | 492 |
| `Training` | 14 | 236 |

### 结果说明

- 公司共有 58 个资源池、1,016 张 GPU；资源池数和 GPU 张数不是同一个指标。
- `TEAM-MIP` 的 GPU 数量最多，`TEAM-RES` 最少；这里只描述资源配置，尚不能判断使用效率或资源是否合理。
- `A100-40GB` 数量最多，`H100-80GB` 数量最少；数量不代表成本大小，因为型号单价不同。
- `Reserved` 的 GPU 数量最多；是否买多需要结合实际使用、合同和 SLA，不能只根据库存判断。
- `Inference` 的 GPU 数量最多；这符合在线服务需要持续容量和备用空间的业务特点，但后续仍需用使用表验证。
- 团队汇总、GPU 型号汇总和采购/负载汇总的 GPU 总数都等于 1,016，形成了第一次交叉核对。

### 新学到的 SQL

- `GROUP BY`：按一个或多个分类字段分组。
- `COUNT(*)`：统计每组有多少行；这里代表资源池数量。
- `SUM(gpu_count)`：累计每组包含的 GPU 张数。
- `ORDER BY ... DESC`：按结果从大到小排序。
- 同一份数据从不同维度汇总后，总量应当能够相互核对。

### 操作说明

同一个 `run_sql.py` 被执行多次，因此终端重复显示了前面的查询结果。这只是查询被重复运行，不代表 CSV 中的数据发生重复。

## 更新后的下一步

完成五张源表的行数、字段数量和行粒度盘点，建立 `reports/data_inventory.md`，再进入正式数据审计。
