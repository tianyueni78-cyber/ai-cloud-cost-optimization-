import unittest

import pandas as pd

from src.optimize_resources import build_recommendations


class OptimizationRulesTest(unittest.TestCase):
    @staticmethod
    def forecast(rows):
        return pd.DataFrame(
            [
                {
                    "team_id": team,
                    "workload_type": workload,
                    "forecast_month": "2027-01",
                    "scenario": "HighGrowth",
                    "planned_gpu_count": required,
                }
                for team, workload, required in rows
            ]
        )

    def test_releases_only_on_demand_surplus_as_immediate_savings(self):
        inventory = pd.DataFrame(
            [{
                "team_id_normalized": "TEAM-A", "workload_type": "Inference",
                "region": "r1", "gpu_model": "A100", "procurement_model": "OnDemand",
                "gpu_count": 10, "effective_hourly_rate_usd": 2.0,
            }]
        )

        result = build_recommendations(
            inventory, self.forecast([("TEAM-A", "Inference", 6)]), horizon_hours=100
        )

        action = result.iloc[0]
        self.assertEqual(action["action_type"], "ReleaseOnDemand")
        self.assertEqual(action["gpu_count"], 4)
        self.assertEqual(action["six_month_savings_usd"], 800)

    def test_committed_surplus_is_deferred_to_renewal(self):
        inventory = pd.DataFrame(
            [{
                "team_id_normalized": "TEAM-A", "workload_type": "Training",
                "region": "r1", "gpu_model": "H100", "procurement_model": "Reserved",
                "gpu_count": 8, "effective_hourly_rate_usd": 3.0,
            }]
        )

        result = build_recommendations(
            inventory, self.forecast([("TEAM-A", "Training", 5)]), horizon_hours=100
        )

        action = result.iloc[0]
        self.assertEqual(action["action_type"], "RightSizeAtRenewal")
        self.assertEqual(action["timing"], "AtRenewal")
        self.assertEqual(action["six_month_savings_usd"], 0)
        self.assertEqual(action["annualized_savings_usd"], 3 * 3 * 8760)

    def test_shared_capacity_is_not_also_released(self):
        inventory = pd.DataFrame(
            [
                {
                    "team_id_normalized": "TEAM-DONOR", "workload_type": "Batch",
                    "region": "r1", "gpu_model": "A100", "procurement_model": "Owned",
                    "gpu_count": 10, "effective_hourly_rate_usd": 1.0,
                },
                {
                    "team_id_normalized": "TEAM-NEED", "workload_type": "Batch",
                    "region": "r1", "gpu_model": "A100", "procurement_model": "OnDemand",
                    "gpu_count": 5, "effective_hourly_rate_usd": 2.0,
                },
            ]
        )
        forecast = self.forecast(
            [("TEAM-DONOR", "Batch", 6), ("TEAM-NEED", "Batch", 9)]
        )

        result = build_recommendations(inventory, forecast, horizon_hours=100)

        sharing = result.loc[result["action_type"].eq("ShareCapacity")].iloc[0]
        self.assertEqual(sharing["gpu_count"], 4)
        self.assertEqual(sharing["avoided_purchase_cost_usd"], 800)
        self.assertFalse(result["action_type"].eq("ReleaseOnDemand").any())

    def test_all_recommended_gpu_actions_use_whole_units(self):
        inventory = pd.DataFrame(
            [
                {
                    "team_id_normalized": "TEAM-A", "workload_type": "Batch",
                    "region": "r1", "gpu_model": "A100", "procurement_model": "OnDemand",
                    "gpu_count": 3, "effective_hourly_rate_usd": 2.0,
                },
                {
                    "team_id_normalized": "TEAM-A", "workload_type": "Batch",
                    "region": "r1", "gpu_model": "H100", "procurement_model": "Reserved",
                    "gpu_count": 7, "effective_hourly_rate_usd": 3.0,
                },
            ]
        )

        result = build_recommendations(
            inventory, self.forecast([("TEAM-A", "Batch", 5)]), horizon_hours=100
        )

        self.assertTrue(result["gpu_count"].map(lambda value: float(value).is_integer()).all())


if __name__ == "__main__":
    unittest.main()
