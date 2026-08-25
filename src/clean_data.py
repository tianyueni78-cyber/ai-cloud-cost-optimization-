import pandas as pd


def normalize_id(series: pd.Series) -> pd.Series:
    """统一 ID 格式，同时保留缺失值。"""
    return (
        series.astype("string")
        .str.strip()
        .str.upper()
        .str.replace("_", "-", regex=False)
    )


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
