from pathlib import Path

import pandas as pd


ID_COLUMNS = {
    "resource_usage": ["usage_record_id", "resource_pool_id", "team_id", "product_id"],
    "cloud_billing": ["billing_line_id", "resource_pool_id", "team_id", "contract_id"],
    "resource_inventory": [
        "resource_pool_id", "team_id", "product_id", "contract_id", "cost_center"
    ],
    "team_sla": ["sla_id", "team_id", "product_id"],
    "business_events": ["event_id", "team_id", "product_id"],
}

NUMERIC_COLUMNS = {
    "resource_usage": [
        "allocated_gpu_count", "active_gpu_count", "gpu_utilization_pct",
        "memory_utilization_pct", "business_volume", "p95_latency_ms",
        "queue_time_seconds", "availability_pct",
    ],
    "cloud_billing": [
        "billed_gpu_hours", "unit_rate_usd", "gross_cost_usd",
        "discount_usd", "net_cost_usd",
    ],
    "resource_inventory": [
        "gpu_count", "hourly_list_price_usd", "effective_hourly_rate_usd",
    ],
    "team_sla": [
        "availability_target_pct", "p95_latency_target_ms",
        "max_queue_time_seconds", "min_spare_capacity_pct", "rto_minutes",
    ],
    "business_events": [],
}

DATE_COLUMNS = {
    "resource_usage": [],
    "cloud_billing": ["usage_start_date", "usage_end_date"],
    "resource_inventory": ["start_date", "end_date"],
    "team_sla": ["effective_from", "effective_to"],
    "business_events": [],
}

UTC_TIMESTAMP_COLUMNS = {
    "resource_usage": ["timestamp_utc"],
    "cloud_billing": ["recorded_at"],
    "resource_inventory": [],
    "team_sla": [],
    "business_events": ["start_timestamp_utc", "end_timestamp_utc"],
}

TABLE_NAMES = [
    "resource_usage",
    "cloud_billing",
    "resource_inventory",
    "team_sla",
    "business_events",
]


def normalize_id(series: pd.Series) -> pd.Series:
    """统一 ID 格式，同时保留缺失值。"""
    return (
        series.astype("string")
        .str.strip()
        .str.upper()
        .str.replace("_", "-", regex=False)
    )


def add_normalized_ids(table_name: str, df: pd.DataFrame) -> pd.DataFrame:
    """为数据字典中的 ID 新增标准化列，不覆盖原字段。"""
    result = df.copy()
    for column in ID_COLUMNS[table_name]:
        if column in result:
            result[f"{column}_normalized"] = normalize_id(result[column])
    return result


def convert_types(table_name: str, df: pd.DataFrame) -> pd.DataFrame:
    """按照数据字典转换数值、日期、UTC 时间和布尔字段。"""
    result = df.copy()
    for column in NUMERIC_COLUMNS[table_name]:
        if column in result:
            result[column] = pd.to_numeric(result[column], errors="coerce")
    for column in DATE_COLUMNS[table_name]:
        if column in result:
            result[column] = pd.to_datetime(result[column], errors="coerce")
    for column in UTC_TIMESTAMP_COLUMNS[table_name]:
        if column in result:
            result[column] = pd.to_datetime(result[column], errors="coerce", utc=True)
    if table_name == "team_sla" and "interruptible_allowed" in result:
        result["interruptible_allowed"] = (
            result["interruptible_allowed"]
            .astype("string")
            .str.strip()
            .str.lower()
            .map({"true": True, "false": False})
            .astype("boolean")
        )
    return result


def clean_usage(df: pd.DataFrame) -> tuple[pd.DataFrame, dict[str, int]]:
    """清洗使用记录：删除完全重复，并用 -R 修订行替代原始行。"""
    cleaned = df.copy()
    cleaned["usage_record_id_normalized"] = normalize_id(
        cleaned["usage_record_id"]
    )
    cleaned["resource_pool_id_normalized"] = normalize_id(
        cleaned["resource_pool_id"]
    )

    rows_before = len(cleaned)
    cleaned = cleaned.drop_duplicates()
    exact_removed = rows_before - len(cleaned)

    business_key = ["timestamp_utc", "resource_pool_id_normalized"]
    is_revision = cleaned["usage_record_id_normalized"].str.endswith("-R")
    has_revision = is_revision.groupby(
        [cleaned[column] for column in business_key]
    ).transform("any")
    superseded = has_revision & ~is_revision
    superseded_removed = int(superseded.sum())
    cleaned = cleaned.loc[~superseded].reset_index(drop=True)

    stats = {
        "exact_duplicate_rows_removed": exact_removed,
        "superseded_rows_removed": superseded_removed,
    }
    return cleaned, stats


def clean_billing(
    billing: pd.DataFrame,
    inventory: pd.DataFrame,
) -> tuple[pd.DataFrame, dict[str, int]]:
    """标准化账单 ID，并在团队标签缺失时从资源清单推导。"""
    cleaned = billing.copy()
    for column in ("billing_line_id", "resource_pool_id", "team_id", "contract_id"):
        if column in cleaned:
            cleaned[f"{column}_normalized"] = normalize_id(cleaned[column])

    lookup = inventory[["resource_pool_id", "team_id"]].copy()
    lookup["resource_pool_id_normalized"] = normalize_id(
        lookup["resource_pool_id"]
    )
    lookup["inventory_team_id"] = normalize_id(lookup["team_id"])
    lookup = lookup[["resource_pool_id_normalized", "inventory_team_id"]]

    cleaned = cleaned.merge(
        lookup,
        on="resource_pool_id_normalized",
        how="left",
        validate="many_to_one",
    )
    missing_source_team = cleaned["team_id_normalized"].isna()
    cleaned["attributed_team_id"] = cleaned["team_id_normalized"].combine_first(
        cleaned["inventory_team_id"]
    )
    cleaned["team_attribution_source"] = "billing"
    cleaned.loc[missing_source_team, "team_attribution_source"] = "inventory"
    inferred_count = int(
        (missing_source_team & cleaned["inventory_team_id"].notna()).sum()
    )
    cleaned = cleaned.drop(columns="inventory_team_id")

    return cleaned, {"team_ids_inferred_from_inventory": inferred_count}


def validate_cleaned(tables: dict[str, pd.DataFrame]) -> None:
    """写出前验证清洗后的关键业务不变量。"""
    usage = tables["resource_usage"]
    business_key = ["timestamp_utc", "resource_pool_id_normalized"]
    if usage.duplicated(business_key).any():
        raise ValueError("清洗后使用表业务键仍有重复")

    billing = tables["cloud_billing"]
    if billing["attributed_team_id"].isna().any():
        raise ValueError("清洗后账单归属团队仍有空值")

    inventory_pools = set(
        tables["resource_inventory"]["resource_pool_id_normalized"].dropna()
    )
    billing_pools = set(billing["resource_pool_id_normalized"].dropna())
    if billing_pools - inventory_pools:
        raise ValueError("清洗后仍有账单资源池无法关联资源清单")


def build_quality_summary(
    before: dict[str, int],
    after: dict[str, int],
    rule_stats: dict[str, int],
) -> pd.DataFrame:
    """生成表级行数和规则处理数量汇总。"""
    rows = [
        {
            "table_name": table_name,
            "rows_before": rows_before,
            "rows_after": after[table_name],
            "rows_removed": rows_before - after[table_name],
            "metric_name": "rows_removed",
            "metric_value": rows_before - after[table_name],
        }
        for table_name, rows_before in before.items()
    ]
    rows.extend(
        {
            "table_name": "pipeline",
            "rows_before": pd.NA,
            "rows_after": pd.NA,
            "rows_removed": pd.NA,
            "metric_name": metric_name,
            "metric_value": metric_value,
        }
        for metric_name, metric_value in rule_stats.items()
    )
    return pd.DataFrame(rows, columns=[
        "table_name", "rows_before", "rows_after", "rows_removed",
        "metric_name", "metric_value",
    ])


def run_pipeline(input_dir: Path, output_dir: Path) -> pd.DataFrame:
    """读取五张原始表，验证并写出清洗结果。"""
    input_dir = Path(input_dir).resolve()
    output_dir = Path(output_dir).resolve()
    if input_dir == output_dir:
        raise ValueError("输入目录和输出目录不能相同")

    input_paths = {
        table_name: input_dir / f"{table_name}.csv"
        for table_name in TABLE_NAMES
    }
    missing_files = [str(path) for path in input_paths.values() if not path.is_file()]
    if missing_files:
        raise FileNotFoundError("缺少输入文件：" + ", ".join(missing_files))

    raw_tables = {
        table_name: pd.read_csv(path, low_memory=False)
        for table_name, path in input_paths.items()
    }
    rows_before = {name: len(table) for name, table in raw_tables.items()}

    prepared = {
        name: add_normalized_ids(name, convert_types(name, table))
        for name, table in raw_tables.items()
    }
    cleaned_usage, usage_stats = clean_usage(prepared["resource_usage"])
    cleaned_billing, billing_stats = clean_billing(
        prepared["cloud_billing"],
        prepared["resource_inventory"],
    )
    cleaned_tables = {
        **prepared,
        "resource_usage": cleaned_usage,
        "cloud_billing": cleaned_billing,
    }
    validate_cleaned(cleaned_tables)

    rows_after = {name: len(table) for name, table in cleaned_tables.items()}
    summary = build_quality_summary(
        rows_before,
        rows_after,
        {**usage_stats, **billing_stats},
    )

    output_dir.mkdir(parents=True, exist_ok=True)
    for table_name, table in cleaned_tables.items():
        table.to_csv(output_dir / f"{table_name}.csv", index=False)
    summary.to_csv(output_dir / "quality_summary.csv", index=False)
    return summary


def format_output_message(output_dir: Path) -> str:
    """返回兼容 Windows 基础终端编码的完成提示。"""
    relative_output = "/".join(Path(output_dir).parts[-2:])
    return f"Cleaned files written to: {relative_output}"


def main() -> None:
    project_root = Path(__file__).resolve().parents[1]
    output_dir = project_root / "outputs" / "cleaned"
    summary = run_pipeline(project_root / "data", output_dir)
    print(summary.to_string(index=False))
    print(f"\n{format_output_message(output_dir)}")


if __name__ == "__main__":
    main()
