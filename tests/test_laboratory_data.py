import csv
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LAB_DIR = ROOT / "data" / "laboratory"
EXPECTED_COLUMNS = [
    "lab_result_id",
    "result_version",
    "batch_id",
    "test_code",
    "test_name",
    "result_value",
    "unit",
    "min_limit",
    "max_limit",
    "result_status",
    "tested_at",
]


def read_fixture(name: str) -> dict[str, str]:
    with (LAB_DIR / name).open(encoding="utf-8", newline="") as source:
        reader = csv.DictReader(source)
        if reader.fieldnames != EXPECTED_COLUMNS:
            raise AssertionError(f"{name}: unexpected CSV header")
        rows = list(reader)
    if len(rows) != 1:
        raise AssertionError(f"{name}: expected exactly one data row")
    return rows[0]


class LaboratoryDataContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.valid = read_fixture("lab_results_valid.csv")
        cls.initial = read_fixture("lab_results_initial.csv")
        cls.corrected = read_fixture("lab_results_corrected.csv")

    def test_valid_fixture_status_matches_limits(self) -> None:
        value = float(self.valid["result_value"])
        self.assertLessEqual(float(self.valid["min_limit"]), value)
        self.assertLessEqual(value, float(self.valid["max_limit"]))
        self.assertEqual(self.valid["result_status"], "PASS")

    def test_initial_batch_003_fixture_has_status_error(self) -> None:
        value = float(self.initial["result_value"])
        self.assertGreater(value, float(self.initial["max_limit"]))
        self.assertEqual(self.initial["result_status"], "PASS")

    def test_correction_keeps_identity_and_increments_version(self) -> None:
        self.assertEqual(
            self.initial["lab_result_id"], self.corrected["lab_result_id"]
        )
        self.assertEqual(self.initial["batch_id"], "BATCH-003")
        self.assertEqual(self.corrected["batch_id"], "BATCH-003")
        self.assertGreater(
            int(self.corrected["result_version"]),
            int(self.initial["result_version"]),
        )
        self.assertEqual(self.corrected["result_status"], "FAIL")


if __name__ == "__main__":
    unittest.main()
