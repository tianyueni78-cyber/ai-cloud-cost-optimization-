import unittest

import pandas as pd

from src.clean_data import (
    add_normalized_ids,
    build_quality_summary,
    clean_billing,
    clean_usage,
    convert_types,
    normalize_id,
    validate_cleaned,
)


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


class TypeConversionTest(unittest.TestCase):
    def test_adds_normalized_ids_for_all_five_tables(self):
        fixtures = {
            "resource_usage": pd.DataFrame({
                "usage_record_id": ["ur_001"],
                "resource_pool_id": [" gpu_001 "],
                "team_id": ["team_fmt"],
                "product_id": ["prd_shared"],
            }),
            "cloud_billing": pd.DataFrame({
                "billing_line_id": ["bill_001"],
                "resource_pool_id": ["gpu_001"],
                "team_id": [pd.NA],
                "contract_id": [pd.NA],
            }),
            "resource_inventory": pd.DataFrame({
                "resource_pool_id": ["gpu_001"],
                "team_id": ["team_fmt"],
                "product_id": ["prd_shared"],
                "contract_id": [pd.NA],
                "cost_center": ["cc_410"],
            }),
            "team_sla": pd.DataFrame({
                "sla_id": ["sla_001"],
                "team_id": ["team_fmt"],
                "product_id": ["prd_shared"],
            }),
            "business_events": pd.DataFrame({
                "event_id": ["evt_001"],
                "team_id": [pd.NA],
                "product_id": [pd.NA],
            }),
        }

        for table_name, fixture in fixtures.items():
            with self.subTest(table_name=table_name):
                result = add_normalized_ids(table_name, fixture)
                for column in fixture.columns:
                    self.assertIn(f"{column}_normalized", result.columns)

    def test_converts_dates_numbers_utc_and_boolean_without_filling_zero(self):
        usage = convert_types("resource_usage", pd.DataFrame({
            "timestamp_utc": ["2025-08-01T00:00:00Z"],
            "gpu_utilization_pct": [""],
        }))
        inventory = convert_types("resource_inventory", pd.DataFrame({
            "start_date": ["2025-08-01"],
            "gpu_count": ["8"],
        }))
        sla = convert_types("team_sla", pd.DataFrame({
            "interruptible_allowed": ["true"],
        }))

        self.assertEqual(str(usage["timestamp_utc"].dtype), "datetime64[us, UTC]")
        self.assertTrue(pd.isna(usage.loc[0, "gpu_utilization_pct"]))
        self.assertTrue(pd.api.types.is_datetime64_any_dtype(inventory["start_date"]))
        self.assertTrue(pd.api.types.is_numeric_dtype(inventory["gpu_count"]))
        self.assertEqual(str(sla["interruptible_allowed"].dtype), "boolean")
        self.assertTrue(sla.loc[0, "interruptible_allowed"])


class ValidationTest(unittest.TestCase):
    @staticmethod
    def valid_tables():
        return {
            "resource_usage": pd.DataFrame({
                "timestamp_utc": ["2025-08-01T00:00:00Z"],
                "resource_pool_id_normalized": ["GPU-001"],
            }),
            "cloud_billing": pd.DataFrame({
                "resource_pool_id_normalized": ["GPU-001"],
                "attributed_team_id": ["TEAM-FMT"],
            }),
            "resource_inventory": pd.DataFrame({
                "resource_pool_id_normalized": ["GPU-001"],
            }),
        }

    def test_rejects_duplicate_usage_business_key(self):
        tables = self.valid_tables()
        tables["resource_usage"] = pd.concat(
            [tables["resource_usage"], tables["resource_usage"]],
            ignore_index=True,
        )
        with self.assertRaisesRegex(ValueError, "业务键仍有重复"):
            validate_cleaned(tables)

    def test_rejects_missing_billing_attribution(self):
        tables = self.valid_tables()
        tables["cloud_billing"].loc[0, "attributed_team_id"] = pd.NA
        with self.assertRaisesRegex(ValueError, "归属团队仍有空值"):
            validate_cleaned(tables)

    def test_rejects_unmatched_billing_pool(self):
        tables = self.valid_tables()
        tables["cloud_billing"].loc[0, "resource_pool_id_normalized"] = "GPU-999"
        with self.assertRaisesRegex(ValueError, "资源池无法关联"):
            validate_cleaned(tables)

    def test_builds_quality_summary_with_required_columns(self):
        result = build_quality_summary(
            before={"resource_usage": 10},
            after={"resource_usage": 8},
            rule_stats={"exact_duplicate_rows_removed": 2},
        )
        self.assertEqual(
            list(result.columns),
            [
                "table_name", "rows_before", "rows_after", "rows_removed",
                "metric_name", "metric_value",
            ],
        )
        self.assertEqual(result.loc[0, "rows_removed"], 2)


if __name__ == "__main__":
    unittest.main()
