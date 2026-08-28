from calendar import monthrange
from math import ceil
from pathlib import Path

import pandas as pd


HORIZON_MONTHS = 6
SCENARIOS = {
    "Baseline": {"volume_factor": 1.0, "intensity_factor": 1.0},
    "HighGrowth": {"volume_factor": 1.2, "intensity_factor": 1.0},
    "Efficiency": {"volume_factor": 1.0, "intensity_factor": 0.9},
}


def _linear_prediction(values: list[float], future_step: int) -> float:
    x_mean = (len(values) - 1) / 2
    y_mean = sum(values) / len(values)
    denominator = sum((x - x_mean) ** 2 for x in range(len(values)))
    slope = (
        sum((x - x_mean) * (y - y_mean) for x, y in enumerate(values))
        / denominator
        if denominator
        else 0.0
    )
    intercept = y_mean - slope * x_mean
    return max(0.0, intercept + slope * future_step)


def select_forecast_model(history: pd.Series) -> tuple[str, float]:
    """用最后三个月滚动回测，在均值与线性趋势中选择MAE更低者。"""
    values = [float(value) for value in history]
    if len(values) < 6:
        return "moving_average_3m", float("nan")

    errors = {"moving_average_3m": [], "linear_trend": []}
    for index in range(len(values) - 3, len(values)):
        prior = values[:index]
        errors["moving_average_3m"].append(
            abs(values[index] - sum(prior[-3:]) / min(3, len(prior)))
        )
        linear_history = prior[-6:]
        errors["linear_trend"].append(
            abs(values[index] - _linear_prediction(linear_history, len(linear_history)))
        )

    mae = {model: sum(items) / len(items) for model, items in errors.items()}
    selected = min(mae, key=lambda model: (mae[model], model != "moving_average_3m"))
    return selected, mae[selected]


def forecast_values(history: pd.Series, model: str, horizon: int) -> list[float]:
    values = [float(value) for value in history]
    if model == "linear_trend":
        recent = values[-6:]
        return [
            _linear_prediction(recent, len(recent) + step)
            for step in range(horizon)
        ]

    predictions = []
    working = values.copy()
    for _ in range(horizon):
        prediction = max(0.0, sum(working[-3:]) / min(3, len(working)))
        predictions.append(prediction)
        working.append(prediction)
    return predictions


def calculate_capacity(
    forecast_volume: float,
    gpu_hours_per_unit: float,
    hours_in_month: int,
    spare_capacity_pct: float,
    peak_factor: float = 1.0,
) -> dict[str, float | int]:
    working = forecast_volume * gpu_hours_per_unit / hours_in_month
    peak_working = working * peak_factor
    required = peak_working / (1 - spare_capacity_pct / 100)
    return {
        "working_gpu_count": working,
        "peak_working_gpu_count": peak_working,
        "required_gpu_count": required,
        "planned_gpu_count": ceil(required),
    }


def build_monthly_history(usage: pd.DataFrame) -> pd.DataFrame:
    usage = usage.copy()
    usage["timestamp_utc"] = pd.to_datetime(usage["timestamp_utc"], utc=True)
    usage["history_month"] = usage["timestamp_utc"].dt.tz_localize(None).dt.to_period("M")
    hourly = (
        usage.groupby(
            [
                "team_id_normalized", "workload_type", "volume_unit",
                "history_month", "timestamp_utc",
            ],
            as_index=False,
        )
        .agg(
            business_volume=("business_volume", "sum"),
            active_gpu_count=("active_gpu_count", "sum"),
        )
    )
    return (
        hourly.groupby(
            ["team_id_normalized", "workload_type", "volume_unit", "history_month"],
            as_index=False,
        )
        .agg(
            business_volume=("business_volume", "sum"),
            active_gpu_hours=("active_gpu_count", "sum"),
            peak_active_gpu_count=("active_gpu_count", "max"),
            observed_hours=("timestamp_utc", "nunique"),
        )
        .sort_values(["team_id_normalized", "workload_type", "history_month"])
    )


def build_forecasts(
    monthly: pd.DataFrame, sla: pd.DataFrame, horizon: int = HORIZON_MONTHS
) -> tuple[pd.DataFrame, pd.DataFrame]:
    spare_by_team = (
        sla.groupby(["team_id_normalized", "workload_type"], as_index=False)
        ["min_spare_capacity_pct"]
        .max()
    )
    spare_lookup = {
        (row.team_id_normalized, row.workload_type): row.min_spare_capacity_pct
        for row in spare_by_team.itertuples()
    }

    volume_rows = []
    capacity_rows = []
    group_columns = ["team_id_normalized", "workload_type", "volume_unit"]
    for (team_id, workload_type, volume_unit), group in monthly.groupby(group_columns):
        group = group.sort_values("history_month")
        model, mae = select_forecast_model(group["business_volume"])
        recent_volume_mean = group.tail(3)["business_volume"].mean()
        mae_pct = 100 * mae / recent_volume_mean
        baseline = forecast_values(group["business_volume"], model, horizon)
        intensity = (
            group.tail(3)["active_gpu_hours"] / group.tail(3)["business_volume"]
        ).median()
        peak_factor = (
            group.tail(3)["peak_active_gpu_count"]
            / (
                group.tail(3)["active_gpu_hours"]
                / group.tail(3)["observed_hours"]
            )
        ).median()
        spare_pct = float(spare_lookup[(team_id, workload_type)])
        last_month = group["history_month"].max()

        for step, baseline_volume in enumerate(baseline, start=1):
            forecast_month = last_month + step
            hours = monthrange(forecast_month.year, forecast_month.month)[1] * 24
            for scenario, factors in SCENARIOS.items():
                predicted_volume = baseline_volume * factors["volume_factor"]
                adjusted_intensity = intensity * factors["intensity_factor"]
                capacity = calculate_capacity(
                    predicted_volume, adjusted_intensity, hours, spare_pct, peak_factor
                )
                common = {
                    "team_id": team_id,
                    "workload_type": workload_type,
                    "volume_unit": volume_unit,
                    "forecast_month": str(forecast_month),
                    "scenario": scenario,
                }
                volume_rows.append(
                    {
                        **common,
                        "predicted_business_volume": predicted_volume,
                        "forecast_model": model,
                        "backtest_mae": mae,
                        "backtest_mae_pct": mae_pct,
                    }
                )
                capacity_rows.append(
                    {
                        **common,
                        "gpu_hours_per_unit": adjusted_intensity,
                        "historical_peak_factor": peak_factor,
                        "min_spare_capacity_pct": spare_pct,
                        **capacity,
                    }
                )

    return pd.DataFrame(volume_rows), pd.DataFrame(capacity_rows)


def run_pipeline(
    input_dir: Path = Path("outputs/cleaned"),
    output_dir: Path = Path("outputs/forecast"),
) -> tuple[pd.DataFrame, pd.DataFrame]:
    usage = pd.read_csv(input_dir / "resource_usage.csv")
    sla = pd.read_csv(input_dir / "team_sla.csv")
    monthly = build_monthly_history(usage)
    volume_forecast, capacity_forecast = build_forecasts(monthly, sla)

    output_dir.mkdir(parents=True, exist_ok=True)
    volume_forecast.to_csv(output_dir / "business_volume_forecast.csv", index=False)
    capacity_forecast.to_csv(output_dir / "gpu_capacity_forecast.csv", index=False)
    return volume_forecast, capacity_forecast


if __name__ == "__main__":
    volume, capacity = run_pipeline()
    print(f"Business forecast rows: {len(volume)}")
    print(f"Capacity forecast rows: {len(capacity)}")
    print("Forecast files written to: outputs/forecast")
