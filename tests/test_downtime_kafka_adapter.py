import importlib.util
import json
from pathlib import Path
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "downtime_kafka_adapter.py"
SPEC = importlib.util.spec_from_file_location("downtime_kafka_adapter", SCRIPT)
ADAPTER = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(ADAPTER)


class DowntimeKafkaAdapterTests(unittest.TestCase):
    def test_console_consumer_metadata_is_parsed(self):
        payload = {
            "event_id": "EVT-1",
            "event_type": "DOWNTIME_STARTED",
        }
        line = "Partition:0|Offset:42|EVT-1|" + json.dumps(payload)
        record = ADAPTER.parse_consumer_line(line)
        self.assertEqual(0, record["partition"])
        self.assertEqual(42, record["offset"])
        self.assertEqual("EVT-1", record["key"])
        self.assertEqual(payload, record["payload"])

    def test_console_consumer_requires_metadata_labels(self):
        with self.assertRaises(ValueError):
            ADAPTER.parse_consumer_line('0|Offset:1|EVT-1|{"event_id":"EVT-1"}')

    def test_consumer_ignores_cli_summary_line(self):
        completed = type(
            "Completed",
            (),
            {
                "stdout": (
                    'Partition:0|Offset:0|EVT-1|{"event_id":"EVT-1"}\n'
                    "Processed a total of 1 messages\n"
                )
            },
        )()
        original_run = ADAPTER.run
        ADAPTER.run = lambda command: completed
        try:
            records = ADAPTER.consume(ADAPTER.EVENTS_TOPIC, 1)
        finally:
            ADAPTER.run = original_run
        self.assertEqual(1, len(records))
        self.assertEqual("EVT-1", records[0]["key"])

    def test_dollar_quote_rejects_reserved_tag(self):
        with self.assertRaises(ValueError):
            ADAPTER.dollar_quote("bad$plantbridge_payload$value", "payload")


if __name__ == "__main__":
    unittest.main()
