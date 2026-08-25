import unittest

import pandas as pd

from src.clean_data import clean_billing, clean_usage, normalize_id


class CleaningRulesTest(unittest.TestCase):
    @staticmethod
    def usage_fixture():
        return pd.DataFrame(
            [
                {
                    "usage_record_id": "UR-001",
                    "timestamp_utc": "2025-08-01T00:00:00Z",
                    "resource_pool_id": "gpu_001",
                    "gpu_utilization_pct": 50.0,
                    "p95_latency_ms": pd.NA,
                },
                {
                    "usage_record_id": "UR-001",
                    "timestamp_utc": "2025-08-01T00:00:00Z",
                    "resource_pool_id": "gpu_001",
                    "gpu_utilization_pct": 50.0,
                    "p95_latency_ms": pd.NA,
                },
                {
                    "usage_record_id": "UR-002",
                    "timestamp_utc": "2025-08-01T01:00:00Z",
                    "resource_pool_id": "GPU-002",
                    "gpu_utilization_pct": 63.9,
                    "p95_latency_ms": pd.NA,
                },
                {
                    "usage_record_id": "UR-002-R",
                    "timestamp_utc": "2025-08-01T01:00:00Z",
                    "resource_pool_id": "GPU-002",
                    "gpu_utilization_pct": 64.1,
                    "p95_latency_ms": pd.NA,
                },
            ]
        )

    def test_normalize_id_preserves_missing_values(self):
        values = pd.Series([" gpu_001 ", "team-fmt", pd.NA], dtype="string")

        result = normalize_id(values)

        self.assertEqual(result.iloc[0], "GPU-001")
        self.assertEqual(result.iloc[1], "TEAM-FMT")
        self.assertTrue(pd.isna(result.iloc[2]))

    def test_clean_usage_removes_exact_duplicates_and_keeps_revision(self):
        cleaned, stats = clean_usage(self.usage_fixture())

        self.assertEqual(len(cleaned), 2)
        revised = cleaned.loc[
            cleaned["usage_record_id"].str.endswith("-R")
        ].iloc[0]
        self.assertEqual(revised["gpu_utilization_pct"], 64.1)
        self.assertTrue(pd.isna(revised["p95_latency_ms"]))
        self.assertEqual(stats["exact_duplicate_rows_removed"], 1)
        self.assertEqual(stats["superseded_rows_removed"], 1)

    def test_clean_billing_attributes_team_without_overwriting_source(self):
        inventory = pd.DataFrame(
            {
                "resource_pool_id": ["GPU-001", "GPU-002"],
                "team_id": ["TEAM-FMT", "TEAM-SRCH"],
            }
        )
        billing = pd.DataFrame(
            {
                "billing_line_id": ["BILL-001", "BILL-002"],
                "resource_pool_id": ["gpu_001", "GPU-002"],
                "team_id": [" team-fmt ", pd.NA],
                "contract_id": [pd.NA, "CTR-002"],
            }
        )

        cleaned, stats = clean_billing(billing, inventory)

        self.assertEqual(cleaned["attributed_team_id"].tolist(), [
            "TEAM-FMT",
            "TEAM-SRCH",
        ])
        self.assertEqual(cleaned["team_attribution_source"].tolist(), [
            "billing",
            "inventory",
        ])
        self.assertTrue(pd.isna(cleaned.loc[1, "team_id"]))
        self.assertEqual(stats["team_ids_inferred_from_inventory"], 1)


if __name__ == "__main__":
    unittest.main()
