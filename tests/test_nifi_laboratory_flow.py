import hashlib
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC_PATH = ROOT / "nifi" / "laboratory-flow.json"
ADAPTER_SQL_PATH = ROOT / "db" / "init" / "07_nifi_laboratory_adapter.sql"
LAB_DIR = ROOT / "data" / "laboratory"


class NifiLaboratoryFlowSpecificationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.spec = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
        cls.processors = {item["key"]: item for item in cls.spec["processors"]}
        cls.connections = {
            tuple(connection) for connection in cls.spec["connections"]
        }

    def test_specification_and_component_keys_are_unique(self) -> None:
        self.assertEqual(self.spec["schema_version"], "1.0")
        self.assertEqual(self.spec["nifi_version"], "2.10.0")
        keys = [item["key"] for item in self.spec["processors"]]
        self.assertEqual(len(keys), len(set(keys)))

    def test_all_connections_reference_known_processors(self) -> None:
        relationships_by_type = {
            "GenerateFlowFile": {"success"},
            "SplitJson": {"split", "original", "failure"},
            "EvaluateJsonPath": {"matched", "unmatched", "failure"},
            "FetchFile": {"success", "not.found", "permission.denied", "failure"},
            "CryptographicHashContent": {"success", "failure"},
            "ExtractText": {"matched", "unmatched"},
            "RouteOnAttribute": {"valid", "normal", "replay", "unmatched"},
            "ConvertRecord": {"success", "failure"},
            "UpdateAttribute": {"success"},
            "ExecuteSQL": {"success", "failure"},
            "RetryFlowFile": {"retry", "retries_exceeded", "failure"},
            "LogAttribute": {"success"},
        }
        for source, relationship, destination in self.spec["connections"]:
            self.assertIn(source, self.processors)
            self.assertIn(destination, self.processors)
            processor_type = self.processors[source]["type"].rsplit(".", 1)[-1]
            self.assertIn(
                relationship.casefold(),
                relationships_by_type[processor_type],
                f"{source}: {relationship}",
            )

    def test_triggers_are_manual_and_separate_primary_from_replay(self) -> None:
        primary = self.processors["trigger_primary"]
        replay = self.processors["trigger_replay"]

        for trigger in (primary, replay):
            self.assertEqual(trigger["scheduling_period"], "1 day")

        self.assertEqual(
            set(self.spec["flow"]["manual_triggers"]),
            {primary["name"], replay["name"]},
        )

        primary_manifest = json.loads(primary["properties"]["Custom Text"])
        replay_manifest = json.loads(replay["properties"]["Custom Text"])
        self.assertEqual(
            {item["filename"] for item in primary_manifest},
            {"lab_results_valid.csv", "lab_results_initial.csv"},
        )
        self.assertTrue(all(item["replay_mode"] == "false" for item in primary_manifest))
        self.assertEqual(
            [item["filename"] for item in replay_manifest],
            ["lab_results_corrected.csv"],
        )
        self.assertEqual(replay_manifest[0]["replay_mode"], "true")

    def test_csv_is_hashed_and_header_checked_before_conversion(self) -> None:
        self.assertIn(("fetch_file", "success", "hash_file"), self.connections)
        self.assertIn(("hash_file", "success", "extract_header"), self.connections)
        self.assertIn(
            ("extract_header", "matched", "set_header_contract"),
            self.connections,
        )
        self.assertIn(
            ("set_header_contract", "success", "validate_header"),
            self.connections,
        )
        self.assertIn(("validate_header", "valid", "convert_csv"), self.connections)
        self.assertEqual(
            self.processors["prepare_normal"]["properties"]["sql.args.4.value"],
            "${'content_SHA-256'}",
        )

    def test_database_calls_are_parameterized_and_replay_requires_pending_reject(self) -> None:
        normal_sql = self.processors["load_normal"]["properties"]["SQL Query"]
        replay_sql = self.processors["load_replay"]["properties"]["SQL Query"]
        self.assertEqual(
            normal_sql,
            "SELECT ods.load_laboratory_csv(?::jsonb, ?::text, ?::text, ?::text)",
        )
        self.assertIn("replay_status = 'PENDING'", replay_sql)
        self.assertIn("COALESCE", replay_sql)
        self.assertIn(", -1)", replay_sql)

    def test_database_failures_have_bounded_independent_retries(self) -> None:
        self.assertIn(("load_normal", "failure", "retry_normal"), self.connections)
        self.assertIn(("retry_normal", "retries_exceeded", "failure"), self.connections)
        self.assertIn(("load_replay", "failure", "retry_replay"), self.connections)
        self.assertIn(("retry_replay", "retries_exceeded", "failure"), self.connections)

    def test_sensitive_database_password_is_a_parameter(self) -> None:
        parameters = {
            item["name"]: item
            for item in self.spec["parameter_context"]["parameters"]
        }
        self.assertTrue(parameters["PostgreSQL Password"]["sensitive"])

    def test_mounted_fixtures_have_distinct_sha256_values(self) -> None:
        checksums = {
            hashlib.sha256(path.read_bytes()).hexdigest()
            for path in LAB_DIR.glob("*.csv")
        }
        self.assertEqual(len(checksums), 3)


class NifiLaboratoryDatabaseAdapterTest(unittest.TestCase):
    def test_adapter_adds_physical_csv_row_numbers(self) -> None:
        sql = ADAPTER_SQL_PATH.read_text(encoding="utf-8")
        self.assertIn("WITH ORDINALITY", sql)
        self.assertIn("source_row.ordinality + 1", sql)
        self.assertIn("ods.load_laboratory_file", sql)


if __name__ == "__main__":
    unittest.main()
