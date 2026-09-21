import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC_PATH = ROOT / "nifi" / "downtime-flow.json"
ADAPTER_SQL_PATH = ROOT / "db" / "init" / "09_nifi_downtime_adapter.sql"


class NifiDowntimeFlowSpecificationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.spec = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
        cls.processors = {item["key"]: item for item in cls.spec["processors"]}
        cls.connections = {tuple(item) for item in cls.spec["connections"]}

    def test_specification_and_component_keys_are_unique(self) -> None:
        self.assertEqual(self.spec["schema_version"], "1.0")
        self.assertEqual(self.spec["nifi_version"], "2.10.0")
        keys = [item["key"] for item in self.spec["processors"]]
        self.assertEqual(len(keys), len(set(keys)))

    def test_primary_and_replay_consumers_are_separate_manual_triggers(self) -> None:
        primary = self.processors["consume_primary"]
        replay = self.processors["consume_replay"]
        self.assertEqual(
            set(self.spec["flow"]["manual_triggers"]),
            {primary["name"], replay["name"]},
        )
        self.assertNotEqual(
            primary["properties"]["Group ID"], replay["properties"]["Group ID"]
        )
        self.assertNotEqual(
            primary["properties"]["Topics"], replay["properties"]["Topics"]
        )

    def test_offsets_are_acknowledged_only_after_database_outcome(self) -> None:
        for key in ("consume_primary", "consume_replay"):
            self.assertEqual(
                self.processors[key]["properties"]["Commit Offsets"], "false"
            )
        for key in ("publish_receipt", "publish_dlq"):
            publish = self.processors[key]
            self.assertEqual(publish["properties"]["Transactions Enabled"], "true")
            self.assertEqual(publish["properties"]["acks"], "all")
        self.assertIn(
            ("load_database", "success", "extract_result"), self.connections
        )
        self.assertIn(
            ("route_outcome", "accepted_or_duplicate", "build_receipt"),
            self.connections,
        )
        self.assertIn(("route_outcome", "rejected", "build_dlq"), self.connections)

    def test_kafka_metadata_reaches_database_contract(self) -> None:
        properties = self.processors["prepare_sql"]["properties"]
        self.assertEqual(properties["sql.args.2.value"], "${kafka.topic}")
        self.assertEqual(properties["sql.args.3.value"], "${kafka.partition}")
        self.assertEqual(properties["sql.args.4.value"], "${kafka.offset}")
        self.assertEqual(properties["sql.args.6.value"], "${kafka.timestamp}")
        query = self.processors["load_database"]["properties"]["SQL Query"]
        self.assertIn("ods.load_downtime_kafka_record", query)

    def test_database_and_kafka_failures_have_bounded_retries(self) -> None:
        for load, retry in (
            ("load_database", "retry_database"),
            ("publish_receipt", "retry_receipt"),
            ("publish_dlq", "retry_dlq"),
        ):
            self.assertIn((load, "failure", retry), self.connections)
            self.assertIn((retry, "retries_exceeded", "technical_failure"), self.connections)

    def test_dlq_retains_original_delivery_and_rejection_link(self) -> None:
        envelope = self.processors["build_dlq"]["properties"]["Replacement Value"]
        for field in (
            "original_topic",
            "original_partition",
            "original_offset",
            "original_timestamp",
            "original_payload",
            "rejected_record_id",
            "correlation_id",
            "error_code",
            "error_text",
        ):
            self.assertIn(f'"{field}"', envelope)

    def test_database_password_is_sensitive(self) -> None:
        parameters = {
            item["name"]: item
            for item in self.spec["parameter_context"]["parameters"]
        }
        self.assertTrue(parameters["PostgreSQL Password"]["sensitive"])


class NifiDowntimeDatabaseAdapterTest(unittest.TestCase):
    def test_adapter_keeps_postgresql_as_business_authority(self) -> None:
        sql = ADAPTER_SQL_PATH.read_text(encoding="utf-8")
        self.assertIn("ods.load_downtime_event", sql)
        self.assertIn("replay_status = 'PENDING'", sql)
        self.assertIn("kafka_timestamp", sql)
        self.assertNotIn("Unknown downtime reason_code", sql)


if __name__ == "__main__":
    unittest.main()
