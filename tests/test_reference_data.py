import json
import unittest
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
REFERENCE_DIR = ROOT / "data" / "reference"


def load_document(name: str) -> dict[str, Any]:
    with (REFERENCE_DIR / name).open(encoding="utf-8") as source:
        document = json.load(source)
    if document.get("schema_version") != "1.0":
        raise AssertionError(f"{name}: unsupported schema_version")
    if not document.get("source_system"):
        raise AssertionError(f"{name}: source_system is required")
    if not isinstance(document.get("records"), list):
        raise AssertionError(f"{name}: records must be an array")
    return document


class ReferenceDataContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.plants = load_document("plants.json")["records"]
        cls.lines = load_document("lines.json")["records"]
        cls.equipment = load_document("equipment.json")["records"]
        cls.materials = load_document("materials.json")["records"]
        cls.batches = load_document("batches.json")["records"]

    def test_mvp_cardinality(self) -> None:
        self.assertEqual(len(self.plants), 1)
        self.assertEqual(len(self.lines), 1)
        self.assertEqual(len(self.equipment), 1)
        self.assertEqual(len(self.materials), 2)
        self.assertEqual(len(self.batches), 3)

    def test_business_keys_are_unique(self) -> None:
        for records, key in (
            (self.plants, "plant_id"),
            (self.lines, "line_id"),
            (self.equipment, "equipment_id"),
            (self.materials, "material_id"),
            (self.batches, "batch_id"),
        ):
            values = [record[key] for record in records]
            self.assertEqual(len(values), len(set(values)), key)

    def test_relationships_resolve(self) -> None:
        plant_ids = {record["plant_id"] for record in self.plants}
        line_ids = {record["line_id"] for record in self.lines}
        equipment_ids = {record["equipment_id"] for record in self.equipment}
        material_ids = {record["material_id"] for record in self.materials}

        self.assertTrue(all(line["plant_id"] in plant_ids for line in self.lines))
        self.assertTrue(all(item["line_id"] in line_ids for item in self.equipment))
        self.assertTrue(all(batch["line_id"] in line_ids for batch in self.batches))
        self.assertTrue(all(batch["equipment_id"] in equipment_ids for batch in self.batches))
        self.assertTrue(all(batch["material_id"] in material_ids for batch in self.batches))

    def test_material_ranges_are_valid_and_complete(self) -> None:
        expected_parameters = {
            "melt_temperature_c",
            "melt_pressure_bar",
            "screw_speed_rpm",
            "power_kw",
        }
        for material in self.materials:
            ranges = material["parameter_ranges"]
            self.assertEqual(
                {item["parameter_code"] for item in ranges},
                expected_parameters,
            )
            for item in ranges:
                self.assertLessEqual(item["min_value"], item["max_value"])

    def test_batch_003_is_the_investigation_batch(self) -> None:
        batch = next(record for record in self.batches if record["batch_id"] == "BATCH-003")
        self.assertEqual(batch["material_id"], "MAT-PE-01")
        self.assertEqual(batch["equipment_id"], "EXT-01")
        self.assertLess(batch["started_at"], batch["ended_at"])


if __name__ == "__main__":
    unittest.main()
