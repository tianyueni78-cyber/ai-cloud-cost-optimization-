# 01｜环境安装与项目启动

## 目标

在 Windows 上建立最小分析环境，使 VS Code 能运行 Python、DuckDB SQL 和 Jupyter Notebook。

## 需要的软件

| 软件 | 必需时间 | 用途 |
|---|---|---|
| Git | 现在 | 下载和提交 GitHub 项目 |
| VS Code | 现在 | 统一编辑器 |
| Python 3.13（64 位） | 现在 | 运行 DuckDB、Pandas 和 Notebook |
| DuckDB Python 包 | 现在 | 直接用 SQL 查询 CSV |
| Power BI Desktop | 阶段 10 | 最后制作仪表盘，现在不装也可以 |

## 操作步骤

### A. 检查 Git 和 Python

打开 Windows Terminal 或 PowerShell：

```powershell
git --version
python --version
```

正常结果应分别显示版本号。如果提示“无法识别”，再安装对应软件，不要继续执行后续命令。

### B. 克隆仓库

选择一个专门保存项目的目录：

```powershell
git clone https://github.com/tianyueni78-cyber/ai-cloud-cost-optimization-.git
cd ai-cloud-cost-optimization-
```

不要下载 ZIP 后直接工作。Git clone 才能保留版本历史并方便推送。

### C. 用 VS Code 打开整个项目

```powershell
code .
```

如果 `code` 命令不可用，可打开 VS Code，选择“文件 → 打开文件夹”，选择仓库根目录。不要只打开单个 CSV。

### D. 安装 VS Code 扩展

打开左侧 Extensions，安装 Microsoft 发布的：

- Python
- Jupyter

### E. 创建项目虚拟环境

在 VS Code 顶部菜单选择“终端 → 新建终端”，运行：

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
```

终端提示符前出现 `(.venv)` 表示激活成功。虚拟环境用于把本项目的软件与其他项目隔离。

### F. 安装项目工具

```powershell
python -m pip install --upgrade pip
python -m pip install duckdb pandas jupyter matplotlib seaborn
```

这里的 DuckDB 是 Python 软件包，不需要创建服务器、用户或密码。

### G. 验证安装

```powershell
python -c "import duckdb, pandas; print(duckdb.sql('SELECT 42 AS answer').fetchall()); print(pandas.__version__)"
```

正常结果应包含 `[(42,)]` 和一个 Pandas 版本号。

### H. 验证能读取项目数据

```powershell
python -c "import duckdb; duckdb.sql(\"SELECT COUNT(*) AS rows FROM read_csv_auto('data/resource_inventory.csv')\").show()"
```

输出应出现 `rows` 列和一个大于 0 的行数。

## 需要创建的项目设置

在根目录建立 `.gitignore`，至少忽略：

```gitignore
.venv/
__pycache__/
.ipynb_checkpoints/
outputs/
*.duckdb
```

## 知识树

```text
项目环境
├── Git：版本历史和远端同步
├── VS Code：编辑器
├── Python：运行时
├── venv：项目隔离环境
├── pip：安装 Python 软件包
├── DuckDB：SQL 查询引擎
└── Jupyter：交互式分析文档
```

## 验收标准

- `git --version` 和 `python --version` 有结果。
- VS Code 打开的是仓库根目录。
- 终端显示 `(.venv)`。
- DuckDB 能返回 `42`。
- DuckDB 能读取 `resource_inventory.csv`。
- `.venv/` 没有出现在 Git 待提交列表中。

## 建议提交

只提交 `.gitignore`，不要提交 `.venv`：

```powershell
git add .gitignore
git commit -m "chore: configure local analysis environment"
git push
```
