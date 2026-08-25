# 07｜Pandas 五表数据清洗

## 目的

把数据审计得到的规则实现为可重复运行、自动验证的 Pandas 清洗管道，同时保护原始数据。

## 使用的软件和文件

- Python 3 与 Pandas 3；
- `src/clean_data.py`：清洗程序；
- `tests/test_clean_data.py`：清洗规则测试；
- `data/*.csv`：五张只读原始表；
- `outputs/cleaned/`：本地清洗结果。

## 输入

```powershell
python -m unittest discover -s tests -v
python src/clean_data.py
```

独立复核使用表行数：

```powershell
python -c "import duckdb; print(duckdb.execute('SELECT COUNT(*) FROM read_csv_auto(?)', ['outputs/cleaned/resource_usage.csv']).fetchall())"
```

## 输出

自动测试共 11 个，结果为：

```text
Ran 11 tests
OK
```

质量汇总：

| 表或规则 | 清洗前 | 清洗后 | 处理数量 |
|---|---:|---:|---:|
| resource_usage | 506,899 | 506,640 | 删除 259 |
| cloud_billing | 1,209 | 1,209 | 0 |
| resource_inventory | 58 | 58 | 0 |
| team_sla | 14 | 14 | 0 |
| business_events | 27 | 27 | 0 |
| 完全重复 | — | — | 139 |
| 被修订的原始行 | — | — | 120 |
| 从资源清单推导团队 | — | — | 42 |

DuckDB 独立读取清洗后的使用表，得到 `506640` 行，与质量汇总一致。

## 结果说明

- 只有使用表减少行数，减少量完全由两条已审计规则解释。
- 其余四张表不删除业务记录，只进行类型转换、ID 标准化或新增归属字段。
- 42 条账单只新增可追溯的归属团队，原始空 `team_id` 没有被覆盖。
- 遥测空值和结构性空值没有填成 0。
- 程序先验证业务键、团队归属和资源池关联，再写出结果。
- `outputs/` 被 Git 忽略，GitHub 保存的是可复现过程，而不是重复存放大体积衍生文件。

## 测试先行过程

每条核心规则都先经历失败测试，再写最小实现：

1. ID 标准化测试先因 `src.clean_data` 不存在而失败，实现后通过。
2. 使用表去重测试先因 `clean_usage` 不存在而失败，实现后通过。
3. 账单归属测试先因 `clean_billing` 不存在而失败，实现后通过。
4. 类型、验证、质量汇总和完整管道同样先失败后实现。

完整运行还发现一个与数据无关的 Windows 终端问题：项目绝对路径包含中文，而执行环境使用 `cp1252` 编码，打印绝对路径时抛出 `UnicodeEncodeError`。最终提示改为稳定的相对路径 `outputs/cleaned`，并新增含中文路径的回归测试。

## 我学到的 Pandas 方法

- `.astype("string").str.strip().str.upper()`：标准化文本；
- `.str.replace("_", "-", regex=False)`：统一 ID 分隔符；
- `pd.to_numeric(..., errors="coerce")`：把合法数字转换为数值，非法值转为空；
- `pd.to_datetime(..., utc=True)`：统一 UTC 时间；
- `.drop_duplicates()`：删除完全重复行；
- `.groupby(...).transform("any")`：把组级判断返回到每一行；
- `.combine_first()`：仅在原值为空时采用后备字段；
- `.merge(..., validate="many_to_one")`：连接时同时验证资源清单键唯一。

## 下一步

从 `outputs/cleaned/` 读取清洗数据，开始 SQL 探索分析；第一步建立团队、产品、月份和费用类型的基础成本视图。
