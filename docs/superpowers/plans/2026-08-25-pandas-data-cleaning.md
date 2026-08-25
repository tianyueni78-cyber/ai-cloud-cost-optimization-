# Pandas 数据清洗实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 创建一个可重复执行的 Pandas 清洗程序，清洗五张原始 CSV、验证审计规则，并输出五张清洗表和质量汇总。

**Architecture:** 使用单个 `src/clean_data.py` 保存少量纯转换函数和命令行入口。核心规则先用内存 DataFrame 单元测试；完整运行从 `data/` 只读数据，在所有验证通过后统一写入 `outputs/cleaned/`。

**Tech Stack:** Python 3、Pandas 3、标准库 `pathlib`、`unittest`、`tempfile`

**Spec:** `docs/superpowers/specs/2026-08-25-pandas-data-cleaning-design.md`

## Global Constraints

- 清洗全部五张原始 CSV。
- 不修改 `data/` 中的任何文件。
- 大体积衍生 CSV 只写入已被 Git 忽略的 `outputs/cleaned/`。
- 原始 ID 字段保留，标准化结果写入新增字段。
- 不把结构性空值或遥测空值填成 0。
- 不增加 Pandas 之外的新依赖。
- 本阶段不计算成本、SLA 或优化结论。

---

## 文件结构

- 创建 `src/clean_data.py`：转换函数、完整数据管道、验证和命令行入口。
- 创建 `tests/test_clean_data.py`：使用标准库 `unittest` 测试清洗规则。
- 创建 `notes/07_pandas_data_cleaning.md`：记录实际命令、输出和结果解释。
- 修改 `learning/05_data_cleaning.md`：加入本项目实际入口和输出说明，不重复学习笔记中的运行结果。
- 修改 `README.md`：在项目目录和运行方式中列出清洗程序、测试和输出目录。

---

### Task 1：锁定 ID、去重和团队归属规则

**Files:**
- Create: `tests/test_clean_data.py`
- Create: `src/clean_data.py`

**Interfaces:**
- Produces: `normalize_id(series: pd.Series) -> pd.Series`
- Produces: `clean_usage(df: pd.DataFrame) -> tuple[pd.DataFrame, dict[str, int]]`
- Produces: `clean_billing(billing: pd.DataFrame, inventory: pd.DataFrame) -> tuple[pd.DataFrame, dict[str, int]]`

- [ ] **Step 1: 创建包目录并写 ID 标准化失败测试**

在 `tests/test_clean_data.py` 中导入 Pandas、`unittest` 和待实现函数，构造包含空格、大小写、下划线及空值的 Series，并断言结果为 `GPU-001`、`TEAM-FMT` 和缺失值。

```python
class CleaningRulesTest(unittest.TestCase):
    def test_normalize_id_preserves_missing_values(self):
        values = pd.Series([" gpu_001 ", "team-fmt", pd.NA], dtype="string")
        result = normalize_id(values)
        self.assertEqual(result.iloc[0], "GPU-001")
        self.assertEqual(result.iloc[1], "TEAM-FMT")
        self.assertTrue(pd.isna(result.iloc[2]))
```

- [ ] **Step 2: 运行测试并确认因模块尚不存在而失败**

Run: `python -m unittest tests.test_clean_data.CleaningRulesTest.test_normalize_id_preserves_missing_values -v`

Expected: FAIL/ERROR，明确显示无法导入 `src.clean_data` 或 `normalize_id`。

- [ ] **Step 3: 实现最小 ID 标准化函数**

在 `src/clean_data.py` 中使用 Pandas 字符串方法实现：

```python
def normalize_id(series: pd.Series) -> pd.Series:
    return series.astype("string").str.strip().str.upper().str.replace("_", "-", regex=False)
```

- [ ] **Step 4: 运行测试并确认通过**

Run: `python -m unittest tests.test_clean_data.CleaningRulesTest.test_normalize_id_preserves_missing_values -v`

Expected: 1 test，OK。

- [ ] **Step 5: 写使用表去重失败测试**

测试数据包含：两条完全相同 ID、一个原始 ID 与一个 `-R` 修订 ID。断言清洗后只保留两条业务记录，修订组保留 `-R` 且 GPU 利用率为修订值，原始空值仍为空。

```python
def test_clean_usage_removes_exact_duplicates_and_keeps_revision(self):
    cleaned, stats = clean_usage(self.usage_fixture())
    self.assertEqual(len(cleaned), 2)
    revised = cleaned.loc[cleaned["usage_record_id"].str.endswith("-R")].iloc[0]
    self.assertEqual(revised["gpu_utilization_pct"], 64.1)
    self.assertTrue(pd.isna(revised["p95_latency_ms"]))
    self.assertEqual(stats["exact_duplicate_rows_removed"], 1)
    self.assertEqual(stats["superseded_rows_removed"], 1)
```

- [ ] **Step 6: 运行使用表测试并确认失败**

Run: `python -m unittest tests.test_clean_data.CleaningRulesTest.test_clean_usage_removes_exact_duplicates_and_keeps_revision -v`

Expected: FAIL/ERROR，因为 `clean_usage` 尚未实现。

- [ ] **Step 7: 实现最小使用表清洗**

实现顺序固定为：新增标准化 ID → 按 `usage_record_id` 完全去重 → 生成修订优先级 → 按 `timestamp_utc + resource_pool_id_normalized` 排序并保留优先级最高的一行 → 删除临时优先级列。返回清洗表和两项删除数量。

- [ ] **Step 8: 运行使用表测试并确认通过**

Run: `python -m unittest tests.test_clean_data.CleaningRulesTest.test_clean_usage_removes_exact_duplicates_and_keeps_revision -v`

Expected: 1 test，OK。

- [ ] **Step 9: 写账单归属失败测试**

测试账单中一行已有团队、一行团队为空但资源池可关联。断言已有团队优先，缺失团队从清单回填，来源分别为 `billing` 和 `inventory`，原始 `team_id` 的空值仍保留。

- [ ] **Step 10: 运行账单测试并确认失败**

Run: `python -m unittest tests.test_clean_data.CleaningRulesTest.test_clean_billing_attributes_team_without_overwriting_source -v`

Expected: FAIL/ERROR，因为 `clean_billing` 尚未实现。

- [ ] **Step 11: 实现最小账单归属函数**

为账单和资源清单生成标准化资源池、团队和合同 ID；以标准化资源池左连接清单团队；使用账单标准化团队优先、清单团队回填 `attributed_team_id`；使用 Pandas 布尔赋值生成来源字段，不覆盖原始 `team_id`。

- [ ] **Step 12: 运行 Task 1 全部测试**

Run: `python -m unittest tests.test_clean_data -v`

Expected: 所有 Task 1 测试通过，无 warning 和 traceback。

- [ ] **Step 13: 提交核心规则**

```powershell
git add src/clean_data.py tests/test_clean_data.py
git commit -m "feat: add core pandas cleaning rules"
```

---

### Task 2：实现五表类型转换、验证和质量汇总

**Files:**
- Modify: `src/clean_data.py`
- Modify: `tests/test_clean_data.py`

**Interfaces:**
- Consumes: `normalize_id`、`clean_usage`、`clean_billing`
- Produces: `add_normalized_ids(table_name: str, df: pd.DataFrame) -> pd.DataFrame`
- Produces: `convert_types(table_name: str, df: pd.DataFrame) -> pd.DataFrame`
- Produces: `validate_cleaned(tables: dict[str, pd.DataFrame]) -> None`
- Produces: `build_quality_summary(before: dict[str, int], after: dict[str, int], rule_stats: dict[str, int]) -> pd.DataFrame`

- [ ] **Step 1: 写五表 ID 与类型转换失败测试**

以每张表一行小样本测试：所有现有 `*_id` 字段均增加对应的 `*_normalized` 字段；UTC 字段为 `datetime64[ns, UTC]`，日期字段为日期时间类型，数值字段为数值类型，`interruptible_allowed` 为 Pandas nullable boolean，空字符串转换为缺失值而不是 0。

- [ ] **Step 2: 运行类型测试并确认失败**

Run: `python -m unittest tests.test_clean_data.TypeConversionTest -v`

Expected: FAIL/ERROR，因为 `add_normalized_ids` 和 `convert_types` 尚未实现。

- [ ] **Step 3: 实现显式字段映射**

在 `src/clean_data.py` 中定义四个常量映射：`ID_COLUMNS`、`NUMERIC_COLUMNS`、`DATE_COLUMNS`、`UTC_TIMESTAMP_COLUMNS`。`add_normalized_ids` 遍历当前表的 ID 映射并调用 `normalize_id`，例如 `resource_pool_id` 生成 `resource_pool_id_normalized`；`convert_types` 只转换映射中存在于当前 DataFrame 的列。数值用 `pd.to_numeric(errors="coerce")`，日期用 `pd.to_datetime(errors="coerce")`，UTC 时间增加 `utc=True`。

- [ ] **Step 4: 运行类型测试并确认通过**

Run: `python -m unittest tests.test_clean_data.TypeConversionTest -v`

Expected: 全部通过。

- [ ] **Step 5: 写验证失败测试**

分别构造：清洗后仍有重复业务键、账单归属团队为空、非空账单资源池无法关联清单。断言 `validate_cleaned` 对每类输入抛出带明确中文信息的 `ValueError`。

- [ ] **Step 6: 运行验证测试并确认失败**

Run: `python -m unittest tests.test_clean_data.ValidationTest -v`

Expected: FAIL/ERROR，因为 `validate_cleaned` 尚未实现。

- [ ] **Step 7: 实现写出前验证**

验证使用表标准化业务键无重复、账单 `attributed_team_id` 无空值、账单非空标准化资源池均存在于资源清单。只抛出异常，不自动修复验证失败的数据。

- [ ] **Step 8: 写质量汇总失败测试**

传入固定的清洗前后行数和规则统计，断言汇总包含 `table_name`、`rows_before`、`rows_after`、`rows_removed`、`metric_name`、`metric_value`。

- [ ] **Step 9: 实现并验证质量汇总**

Run: `python -m unittest tests.test_clean_data -v`

Expected: Task 1 与 Task 2 的全部测试通过。

- [ ] **Step 10: 提交类型、验证和汇总功能**

```powershell
git add src/clean_data.py tests/test_clean_data.py
git commit -m "feat: validate five-table cleaning pipeline"
```

---

### Task 3：实现命令行管道并运行完整数据

**Files:**
- Modify: `src/clean_data.py`
- Modify: `tests/test_clean_data.py`

**Interfaces:**
- Consumes: Task 1 和 Task 2 的全部接口
- Produces: `run_pipeline(input_dir: Path, output_dir: Path) -> pd.DataFrame`
- Produces: 命令 `python src/clean_data.py`

- [ ] **Step 1: 写临时目录端到端失败测试**

使用 `tempfile.TemporaryDirectory` 建立小型 `data/` 与 `outputs/cleaned/`。写入五张最小 CSV，调用 `run_pipeline`，断言五张清洗 CSV 和 `quality_summary.csv` 存在，同时输入文件内容未改变。

- [ ] **Step 2: 运行端到端测试并确认失败**

Run: `python -m unittest tests.test_clean_data.PipelineTest -v`

Expected: FAIL/ERROR，因为 `run_pipeline` 尚未实现。

- [ ] **Step 3: 实现最小管道**

`run_pipeline` 检查五张输入是否存在且输入、输出路径不同；读取五表并记录行数；完成类型转换、ID 标准化、使用表去重和账单归属；调用 `validate_cleaned`；创建输出目录；写出六张 CSV；返回质量汇总。命令行入口默认使用项目根目录下的 `data/` 与 `outputs/cleaned/`。

- [ ] **Step 4: 运行全部自动测试**

Run: `python -m unittest discover -s tests -v`

Expected: 全部测试通过，0 failures，0 errors。

- [ ] **Step 5: 在完整数据上运行清洗**

Run: `python src/clean_data.py`

Expected: 程序打印五张表清洗前后行数、完全重复删除 139、修订旧行删除 120、账单团队从资源清单回填 42，并显示输出目录。

- [ ] **Step 6: 用 DuckDB 独立复核输出**

Run: `python -c "import duckdb; print(duckdb.sql(\"SELECT COUNT(*) FROM read_csv_auto('outputs/cleaned/resource_usage.csv')\").fetchall())"`

Expected: 使用表为 506,640 行，即 `506,899 - 139 - 120`。

- [ ] **Step 7: 检查 Git 状态**

Run: `git status --short`

Expected: `outputs/` 不出现；只显示尚未提交的代码、测试或文档。

- [ ] **Step 8: 提交可执行管道**

```powershell
git add src/clean_data.py tests/test_clean_data.py
git commit -m "feat: add reproducible five-table cleaning pipeline"
```

---

### Task 4：记录学习过程并更新作品集入口

**Files:**
- Create: `notes/07_pandas_data_cleaning.md`
- Modify: `learning/05_data_cleaning.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: `python -m unittest discover -s tests -v` 和 `python src/clean_data.py` 的真实输出
- Produces: 面向学习者和招聘方的可复现运行说明

- [ ] **Step 1: 写增量学习笔记**

记录目的、使用文件、运行命令、清洗前后行数、每条规则的结果说明、失败测试与修复过程、学到的 Pandas 方法及下一步。不得复制前四轮数据审计内容。

- [ ] **Step 2: 更新学习指南**

在 `learning/05_data_cleaning.md` 中加入本项目命令、程序结构和输出字段解释；通用知识保留在学习指南，真实运行结果只放笔记。

- [ ] **Step 3: 更新 README**

在目录结构中加入 `src/clean_data.py`、`tests/test_clean_data.py`、清洗设计与计划；在快速开始中加入测试和清洗命令，并说明 `outputs/` 不上传 GitHub。

- [ ] **Step 4: 验证文档与仓库状态**

Run: `git diff --check`

Expected: 无输出，退出码 0。

Run: `python -m unittest discover -s tests -v`

Expected: 全部测试通过。

- [ ] **Step 5: 提交文档**

```powershell
git add README.md learning/05_data_cleaning.md notes/07_pandas_data_cleaning.md
git commit -m "docs: document pandas cleaning workflow"
```

---

## 最终验收

- `python -m unittest discover -s tests -v`：0 failures、0 errors。
- `python src/clean_data.py`：成功生成六张输出文件。
- 清洗使用表行数为 506,640。
- 账单归属团队无空值，且资源清单回填数为 42。
- `data/` 的 Git 差异为空。
- `git diff --check` 无格式错误。
- Git 提交中不包含 `outputs/` 下的大体积文件。
