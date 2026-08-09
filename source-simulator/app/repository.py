import json
import os
from pathlib import Path

from .models import TelemetryRecord


DEFAULT_DATA_PATH = Path(__file__).resolve().parents[2] / "data" / "telemetry.json"


class TelemetryRepository:
    def __init__(self, data_path: str | Path | None = None) -> None:
        configured_path = data_path or os.getenv("TELEMETRY_DATA_PATH") or DEFAULT_DATA_PATH
        self._data_path = Path(configured_path)
        self._records = self._load_records()

    def _load_records(self) -> list[TelemetryRecord]:
        with self._data_path.open(encoding="utf-8") as source:
            document = json.load(source)

        if document.get("schema_version") != "1.0":
            raise ValueError("Unsupported telemetry fixture schema_version")

        records = [TelemetryRecord.model_validate(item) for item in document["records"]]
        identifiers = [item.source_record_id for item in records]
        if len(identifiers) != len(set(identifiers)):
            raise ValueError("Telemetry source_record_id values must be unique")

        return sorted(records, key=lambda item: (item.updated_at, item.source_record_id))

    @property
    def records(self) -> tuple[TelemetryRecord, ...]:
        return tuple(self._records)
