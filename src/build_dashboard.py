import json
from pathlib import Path

import pandas as pd


LEDGER_CHARGES = {"Usage", "Commitment", "Credit", "Adjustment", "Support"}


def summarize_dashboard(
    billing: pd.DataFrame,
    inventory: pd.DataFrame,
    capacity: pd.DataFrame,
    recommendations: pd.DataFrame,
) -> dict:
    billing = billing.copy()
    billing["usage_start_date"] = pd.to_datetime(billing["usage_start_date"])
    billing["usage_month"] = billing["usage_start_date"].dt.strftime("%Y-%m")
    ledger = billing.loc[billing["charge_type"].isin(LEDGER_CHARGES)]
    unused = billing.loc[billing["charge_type"].eq("UnusedCommitment")]

    high_growth = capacity.loc[
        capacity["scenario"].eq("HighGrowth")
        & capacity["forecast_month"].eq(capacity["forecast_month"].max())
    ]
    kpis = {
        "total_cost_usd": round(float(ledger["net_cost_usd"].sum()), 2),
        "unused_commitment_usd": round(float(unused["net_cost_usd"].sum()), 2),
        "current_gpu_count": int(inventory["gpu_count"].sum()),
        "high_growth_gpu_need": int(high_growth["planned_gpu_count"].sum()),
        "six_month_savings_usd": round(
            float(recommendations["six_month_savings_usd"].sum()), 2
        ),
        "annualized_savings_usd": round(
            float(recommendations["annualized_savings_usd"].sum()), 2
        ),
        "avoided_purchase_cost_usd": round(
            float(recommendations["avoided_purchase_cost_usd"].sum()), 2
        ),
    }

    monthly_cost = (
        ledger.groupby("usage_month", as_index=False)["net_cost_usd"]
        .sum()
        .rename(columns={"net_cost_usd": "cost_usd"})
        .round(2)
        .to_dict("records")
    )
    monthly_team_cost = (
        ledger.groupby(["usage_month", "attributed_team_id"], as_index=False)[
            "net_cost_usd"
        ]
        .sum()
        .rename(
            columns={"attributed_team_id": "team_id", "net_cost_usd": "cost_usd"}
        )
        .round(2)
        .to_dict("records")
    )
    team_cost = (
        ledger.groupby("attributed_team_id", as_index=False)["net_cost_usd"]
        .sum()
        .rename(columns={"attributed_team_id": "team_id", "net_cost_usd": "cost_usd"})
        .sort_values("cost_usd", ascending=False)
        .round(2)
        .to_dict("records")
    )
    capacity_summary = (
        capacity.groupby(["forecast_month", "scenario"], as_index=False)[
            "planned_gpu_count"
        ]
        .sum()
        .to_dict("records")
    )
    optimization = (
        recommendations.groupby("action_type", as_index=False)
        .agg(
            gpu_count=("gpu_count", "sum"),
            six_month_savings_usd=("six_month_savings_usd", "sum"),
            annualized_savings_usd=("annualized_savings_usd", "sum"),
            avoided_purchase_cost_usd=("avoided_purchase_cost_usd", "sum"),
        )
        .round(2)
        .to_dict("records")
    )
    risk = (
        recommendations.groupby("risk_level", as_index=False)
        .size()
        .rename(columns={"size": "action_count"})
        .to_dict("records")
    )
    top_actions = (
        recommendations.assign(
            displayed_value=lambda frame: frame[
                [
                    "six_month_savings_usd", "annualized_savings_usd",
                    "avoided_purchase_cost_usd",
                ]
            ].max(axis=1)
        )
        .sort_values("displayed_value", ascending=False)
        .head(8)[
            [
                "action_type", "source_team", "target_team", "gpu_model",
                "gpu_count", "risk_level", "displayed_value",
            ]
        ]
        .round(2)
        .to_dict("records")
    )
    return {
        "kpis": kpis,
        "monthly_cost": monthly_cost,
        "monthly_team_cost": monthly_team_cost,
        "team_cost": team_cost,
        "capacity": capacity_summary,
        "optimization": optimization,
        "risk": risk,
        "top_actions": top_actions,
    }


def run_pipeline(
    cleaned_dir: Path = Path("outputs/cleaned"),
    forecast_dir: Path = Path("outputs/forecast"),
    optimization_dir: Path = Path("outputs/optimization"),
    output_file: Path = Path("dashboard/dashboard_data.js"),
) -> dict:
    summary = summarize_dashboard(
        pd.read_csv(cleaned_dir / "cloud_billing.csv"),
        pd.read_csv(cleaned_dir / "resource_inventory.csv"),
        pd.read_csv(forecast_dir / "gpu_capacity_forecast.csv"),
        pd.read_csv(optimization_dir / "recommendations.csv"),
    )
    output_file.parent.mkdir(parents=True, exist_ok=True)
    output_file.write_text(
        "window.DASHBOARD_DATA = "
        + json.dumps(summary, ensure_ascii=False, separators=(",", ":"))
        + ";\n",
        encoding="utf-8",
    )
    return summary


if __name__ == "__main__":
    data = run_pipeline()
    print(f"Dashboard total cost: ${data['kpis']['total_cost_usd']:,.2f}")
    print("Dashboard data written to: dashboard/dashboard_data.js")
