#!/usr/bin/env python3
import csv
import json
import sys
from pathlib import Path


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


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: laboratory-csv-to-json.py CSV_FILE")

    csv_path = Path(sys.argv[1])
    with csv_path.open(encoding="utf-8", newline="") as source:
        reader = csv.DictReader(source)
        if reader.fieldnames != EXPECTED_COLUMNS:
            raise SystemExit(
                f"{csv_path.name}: expected header {','.join(EXPECTED_COLUMNS)}"
            )

        rows = []
        for row_number, row in enumerate(reader, start=2):
            if None in row:
                raise SystemExit(f"{csv_path.name}:{row_number}: too many columns")
            rows.append({"row_number": row_number, **row})

    print(json.dumps(rows, separators=(",", ":")))


if __name__ == "__main__":
    main()
