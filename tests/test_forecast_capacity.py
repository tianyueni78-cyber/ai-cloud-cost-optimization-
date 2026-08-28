import unittest

import pandas as pd

from src.forecast_capacity import calculate_capacity, select_forecast_model


class ForecastModelTest(unittest.TestCase):
    def test_selects_linear_trend_for_steady_growth(self):
        history = pd.Series([100, 110, 120, 130, 140, 150, 160, 170, 180])

        model, mae = select_forecast_model(history)

        self.assertEqual(model, "linear_trend")
        self.assertAlmostEqual(mae, 0.0)

    def test_capacity_includes_hours_and_spare_requirement(self):
        result = calculate_capacity(
            forecast_volume=7200,
            gpu_hours_per_unit=0.1,
            hours_in_month=720,
            spare_capacity_pct=20,
        )

        self.assertAlmostEqual(result["working_gpu_count"], 1.0)
        self.assertAlmostEqual(result["required_gpu_count"], 1.25)
        self.assertEqual(result["planned_gpu_count"], 2)

    def test_capacity_applies_observed_peak_factor_before_spare(self):
        result = calculate_capacity(
            forecast_volume=7200,
            gpu_hours_per_unit=0.1,
            hours_in_month=720,
            spare_capacity_pct=20,
            peak_factor=2.0,
        )

        self.assertAlmostEqual(result["working_gpu_count"], 1.0)
        self.assertAlmostEqual(result["peak_working_gpu_count"], 2.0)
        self.assertAlmostEqual(result["required_gpu_count"], 2.5)
        self.assertEqual(result["planned_gpu_count"], 3)


if __name__ == "__main__":
    unittest.main()
