import unittest

import pandas as pd

from src.build_dashboard import summarize_dashboard


class DashboardSummaryTest(unittest.TestCase):
    def test_summary_uses_ledger_forecast_and_optimization_rules(self):
        billing = pd.DataFrame(
            [
                {
                    "usage_start_date": "2026-01-01", "charge_type": "Usage",
                    "net_cost_usd": 100, "attributed_team_id": "TEAM-A",
                },
                {
                    "usage_start_date": "2026-01-01", "charge_type": "Credit",
                    "net_cost_usd": -10, "attributed_team_id": "TEAM-A",
                },
                {
                    "usage_start_date": "2026-01-01", "charge_type": "UnusedCommitment",
                    "net_cost_usd": 40, "attributed_team_id": "TEAM-A",
                },
            ]
        )
        inventory = pd.DataFrame({"gpu_count": [10]})
        capacity = pd.DataFrame(
            [
                {
                    "forecast_month": "2027-01", "scenario": "HighGrowth",
                    "planned_gpu_count": 8,
                }
            ]
        )
        recommendations = pd.DataFrame(
            [
                {
                    "action_type": "ReleaseOnDemand", "gpu_count": 2,
                    "six_month_savings_usd": 30, "annualized_savings_usd": 60,
                    "avoided_purchase_cost_usd": 0, "risk_level": "Low",
                    "source_team": "TEAM-A", "target_team": "",
                    "gpu_model": "A100",
                }
            ]
        )

        summary = summarize_dashboard(billing, inventory, capacity, recommendations)

        self.assertEqual(summary["kpis"]["total_cost_usd"], 90)
        self.assertEqual(summary["kpis"]["unused_commitment_usd"], 40)
        self.assertEqual(summary["kpis"]["current_gpu_count"], 10)
        self.assertEqual(summary["kpis"]["high_growth_gpu_need"], 8)
        self.assertEqual(summary["kpis"]["six_month_savings_usd"], 30)


if __name__ == "__main__":
    unittest.main()
