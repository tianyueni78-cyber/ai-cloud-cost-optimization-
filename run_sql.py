from pathlib import Path
import sys

import duckdb


# 从命令行读取 SQL 文件路径；没有提供时使用默认文件
sql_file = sys.argv[1] if len(sys.argv) > 1 else "sql/00_data_orientation.sql"
sql_text = Path(sql_file).read_text(encoding="utf-8")

# 依次执行文件中的每条 SQL
for statement in sql_text.split(";"):
    if statement.strip():
        result = duckdb.sql(statement)

        # CREATE VIEW 等语句不返回表格，只有查询结果才显示
        if result is not None:
            result.show()