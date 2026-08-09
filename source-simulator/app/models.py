from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


NonEmptyString = Annotated[str, Field(min_length=1)]
Scenario = Literal["normal", "timeout", "http_500", "duplicate"]


class TelemetryRecord(BaseModel):
    model_config = ConfigDict(extra="ignore")

    source_record_id: NonEmptyString
    batch_id: NonEmptyString
    equipment_id: NonEmptyString
    parameter_code: NonEmptyString
    value: float
    unit: NonEmptyString
    measured_at: datetime
    updated_at: datetime

    @field_validator("measured_at", "updated_at")
    @classmethod
    def require_timezone(cls, value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("timestamp must include a UTC offset")
        return value


class Watermark(BaseModel):
    updated_at: datetime
    source_record_id: NonEmptyString


class TelemetryPage(BaseModel):
    records: list[TelemetryRecord]
    record_count: int
    has_more: bool
    next_watermark: Watermark | None
