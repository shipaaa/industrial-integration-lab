import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
REQUIRED_FIELDS = {
    "schema_version",
    "source_system",
    "event_id",
    "downtime_id",
    "event_type",
    "batch_id",
    "equipment_id",
    "reason_code",
    "occurred_at",
}


def read_records(name: str):
    records = []
    for line in (ROOT / "data" / "downtime" / name).read_text().splitlines():
        key, raw_value = line.split("|", 1)
        records.append((key, json.loads(raw_value)))
    return records


class DowntimeFixtureTests(unittest.TestCase):
    def test_primary_fixture_has_contract_and_exact_duplicate(self):
        records = read_records("events.txt")
        self.assertEqual(6, len(records))
        for key, value in records:
            self.assertEqual(REQUIRED_FIELDS, REQUIRED_FIELDS & value.keys())
            self.assertEqual(key, value["event_id"])
            self.assertEqual("1.0", value["schema_version"])
            self.assertEqual("MAINTENANCE_CMS", value["source_system"])

        duplicate = [value for key, value in records if key == "EVT-DT-003-END"]
        self.assertEqual(2, len(duplicate))
        self.assertEqual(duplicate[0], duplicate[1])

    def test_replay_corrects_original_event_id(self):
        primary = dict(read_records("events.txt"))
        replay = dict(read_records("replay.txt"))
        event_id = "EVT-DT-INVALID-START"
        self.assertIn(event_id, primary)
        self.assertIn(event_id, replay)
        self.assertEqual("UNMAPPED_REASON", primary[event_id]["reason_code"])
        self.assertEqual("PLANNED_CLEANING", replay[event_id]["reason_code"])
        self.assertEqual(
            primary[event_id]["downtime_id"], replay[event_id]["downtime_id"]
        )


if __name__ == "__main__":
    unittest.main()
