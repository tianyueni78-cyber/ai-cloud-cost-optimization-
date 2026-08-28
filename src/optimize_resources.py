from pathlib import Path
from math import ceil, floor

import pandas as pd


COMMITTED_MODELS = {"Reserved", "SavingsPlan"}
HORIZON_HOURS = 4416  # 2026-08-01 至 2027-02-01


def _add_action(actions: list[dict], **values) -> None:
    actions.append(
        {
            "action_id": f"OPT-{len(actions) + 1:03d}",
            "six_month_savings_usd": 0.0,
            "annualized_savings_usd": 0.0,
            "avoided_purchase_cost_usd": 0.0,
            **values,
        }
    )


def build_recommendations(
    inventory: pd.DataFrame,
    capacity_forecast: pd.DataFrame,
    horizon_hours: int = HORIZON_HOURS,
) -> pd.DataFrame:
    """按高增长容量线生成互斥的共享、按需释放和续约调整建议。"""
    forecast = capacity_forecast.loc[
        capacity_forecast["scenario"].eq("HighGrowth")
        & capacity_forecast["forecast_month"].eq("2027-01"),
        ["team_id", "workload_type", "planned_gpu_count"],
    ]
    required = {
        (row.team_id, row.workload_type): float(row.planned_gpu_count)
        for row in forecast.itertuples()
    }
    grouped = (
        inventory.groupby(
            [
                "team_id_normalized", "workload_type", "region", "gpu_model",
                "procurement_model", "effective_hourly_rate_usd",
            ],
            as_index=False,
        )["gpu_count"]
        .sum()
    )

    buckets = []
    for (team, workload), team_rows in grouped.groupby(
        ["team_id_normalized", "workload_type"]
    ):
        current_total = float(team_rows["gpu_count"].sum())
        required_total = required[(team, workload)]
        for (region, model), model_rows in team_rows.groupby(["region", "gpu_model"]):
            current = float(model_rows["gpu_count"].sum())
            model_required = required_total * current / current_total
            procurement = {
                row.procurement_model: {
                    "count": float(row.gpu_count),
                    "rate": float(row.effective_hourly_rate_usd),
                }
                for row in model_rows.itertuples()
            }
            buckets.append(
                {
                    "team": team,
                    "workload": workload,
                    "region": region,
                    "model": model,
                    "surplus": max(0.0, current - model_required),
                    "deficit": max(0.0, model_required - current),
                    "procurement": procurement,
                }
            )

    actions = []
    donor_order = ["Owned", "Reserved", "SavingsPlan", "OnDemand"]
    for receiver in [bucket for bucket in buckets if bucket["deficit"] > 0]:
        for donor in buckets:
            compatible = (
                donor["team"] != receiver["team"]
                and donor["workload"] == receiver["workload"]
                and donor["region"] == receiver["region"]
                and donor["model"] == receiver["model"]
                and donor["surplus"] > 0
            )
            if not compatible:
                continue
            quantity = floor(min(receiver["deficit"], donor["surplus"]))
            if quantity <= 0:
                continue
            source_model = next(
                (
                    model for model in donor_order
                    if donor["procurement"].get(model, {}).get("count", 0) > 0
                ),
                "Mixed",
            )
            available = donor["procurement"].get(source_model, {}).get("count", quantity)
            quantity = floor(min(quantity, available))
            donor["procurement"][source_model]["count"] -= quantity
            donor["surplus"] -= quantity
            receiver["deficit"] -= quantity
            receiver_rate = max(
                (
                    item["rate"] for model, item in receiver["procurement"].items()
                    if model == "OnDemand"
                ),
                default=max(item["rate"] for item in receiver["procurement"].values()),
            )
            _add_action(
                actions,
                action_type="ShareCapacity",
                source_team=donor["team"],
                target_team=receiver["team"],
                workload_type=donor["workload"],
                region=donor["region"],
                gpu_model=donor["model"],
                procurement_model=source_model,
                gpu_count=quantity,
                timing="ValidateThenExecute",
                avoided_purchase_cost_usd=quantity * receiver_rate * horizon_hours,
                rationale="同区域、同型号、同负载的富余容量可优先覆盖预测缺口",
            )

    for bucket in buckets:
        remaining = bucket["surplus"]
        on_demand = bucket["procurement"].get("OnDemand")
        if remaining > 0 and on_demand and on_demand["count"] > 0:
            quantity = floor(min(remaining, on_demand["count"]))
            if quantity <= 0:
                quantity = 0
            else:
                _add_action(
                    actions,
                    action_type="ReleaseOnDemand",
                    source_team=bucket["team"], target_team="",
                    workload_type=bucket["workload"], region=bucket["region"],
                    gpu_model=bucket["model"], procurement_model="OnDemand",
                    gpu_count=quantity, timing="ImmediateAfterValidation",
                    six_month_savings_usd=quantity * on_demand["rate"] * horizon_hours,
                    annualized_savings_usd=quantity * on_demand["rate"] * 8760,
                    rationale="高增长容量线以上的按需容量可停止续用",
                )
                remaining -= quantity

        for procurement_model in ["SavingsPlan", "Reserved"]:
            item = bucket["procurement"].get(procurement_model)
            if remaining <= 0 or not item or item["count"] <= 0:
                continue
            quantity = floor(min(remaining, item["count"]))
            if quantity <= 0:
                continue
            _add_action(
                actions,
                action_type="RightSizeAtRenewal",
                source_team=bucket["team"], target_team="",
                workload_type=bucket["workload"], region=bucket["region"],
                gpu_model=bucket["model"], procurement_model=procurement_model,
                gpu_count=quantity, timing="AtRenewal",
                annualized_savings_usd=quantity * item["rate"] * 8760,
                rationale="合同期内不假设可取消，仅在续约时降低承诺量",
            )
            remaining -= quantity

    for bucket in [bucket for bucket in buckets if bucket["deficit"] > 0]:
        rate = max(item["rate"] for item in bucket["procurement"].values())
        _add_action(
            actions,
            action_type="CapacityGap",
            source_team="", target_team=bucket["team"],
            workload_type=bucket["workload"], region=bucket["region"],
            gpu_model=bucket["model"], procurement_model="ToBeDecided",
            gpu_count=ceil(bucket["deficit"]), timing="Before2027-01",
            rationale=f"共享后仍有高增长情景缺口；按当前最高费率估算成本上限 {rate:.4f}/GPU小时",
        )

    result = pd.DataFrame(actions)
    if not result.empty:
        money_columns = [
            "six_month_savings_usd", "annualized_savings_usd",
            "avoided_purchase_cost_usd",
        ]
        result[money_columns] = result[money_columns].round(2)
        result["gpu_count"] = result["gpu_count"].round(2)
    return result


def add_risk_assessment(
    recommendations: pd.DataFrame,
    sla: pd.DataFrame,
    volume_forecast: pd.DataFrame,
) -> pd.DataFrame:
    result = recommendations.copy()
    error_lookup = (
        volume_forecast.loc[
            volume_forecast["scenario"].eq("Baseline")
            & volume_forecast["forecast_month"].eq("2027-01")
        ]
        .set_index(["team_id", "workload_type"])["backtest_mae_pct"]
        .to_dict()
    )
    sla_group = sla.groupby(["team_id_normalized", "workload_type"])

    risks = []
    reasons = []
    for row in result.itertuples():
        teams = [team for team in [row.source_team, row.target_team] if team]
        high_sla = False
        forecast_error = 0.0
        for team in teams:
            key = (team, row.workload_type)
            if key in sla_group.groups:
                rules = sla_group.get_group(key)
                high_sla = high_sla or rules["priority_tier"].isin(["P0", "P1"]).any()
                high_sla = high_sla or (~rules["interruptible_allowed"].astype(bool)).any()
            forecast_error = max(forecast_error, float(error_lookup.get(key, 0)))
        if high_sla or forecast_error > 15:
            risks.append("High")
        elif forecast_error > 5 or row.action_type == "ShareCapacity":
            risks.append("Medium")
        else:
            risks.append("Low")
        reasons.append(
            f"SLA敏感={'是' if high_sla else '否'}；回测误差上限={forecast_error:.2f}%"
        )
    result["risk_level"] = risks
    result["risk_reason"] = reasons
    result["confidence"] = result["risk_level"].map(
        {"Low": "High", "Medium": "Medium", "High": "Low"}
    )
    return result


def run_pipeline(
    cleaned_dir: Path = Path("outputs/cleaned"),
    forecast_dir: Path = Path("outputs/forecast"),
    output_dir: Path = Path("outputs/optimization"),
) -> pd.DataFrame:
    inventory = pd.read_csv(cleaned_dir / "resource_inventory.csv")
    sla = pd.read_csv(cleaned_dir / "team_sla.csv")
    capacity = pd.read_csv(forecast_dir / "gpu_capacity_forecast.csv")
    volume = pd.read_csv(forecast_dir / "business_volume_forecast.csv")
    recommendations = build_recommendations(inventory, capacity)
    recommendations = add_risk_assessment(recommendations, sla, volume)
    output_dir.mkdir(parents=True, exist_ok=True)
    recommendations.to_csv(output_dir / "recommendations.csv", index=False)
    return recommendations


if __name__ == "__main__":
    result = run_pipeline()
    print(f"Optimization recommendations: {len(result)}")
    print("Recommendations written to: outputs/optimization/recommendations.csv")
