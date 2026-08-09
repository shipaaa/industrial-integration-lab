import asyncio
from datetime import datetime
from typing import Annotated

from fastapi import FastAPI, HTTPException, Query

from .models import Scenario, TelemetryPage, Watermark
from .repository import TelemetryRepository


app = FastAPI(title="PlantBridge Source Simulator", version="1.0.0")
repository = TelemetryRepository()


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/telemetry", response_model=TelemetryPage)
async def get_telemetry(
    updated_since: datetime | None = None,
    after_record_id: str | None = None,
    page_size: Annotated[int, Query(ge=1, le=100)] = 20,
    scenario: Scenario = "normal",
    delay_seconds: Annotated[float, Query(ge=0, le=30)] = 5,
) -> TelemetryPage:
    if after_record_id is not None and updated_since is None:
        raise HTTPException(
            status_code=422,
            detail="after_record_id requires updated_since",
        )
    if updated_since is not None and (
        updated_since.tzinfo is None or updated_since.utcoffset() is None
    ):
        raise HTTPException(
            status_code=422,
            detail="updated_since must include a UTC offset",
        )
    if scenario == "http_500":
        raise HTTPException(status_code=500, detail="Simulated source failure")
    if scenario == "timeout":
        await asyncio.sleep(delay_seconds)

    watermark_id = after_record_id or ""
    eligible = [
        record
        for record in repository.records
        if updated_since is None
        or (record.updated_at, record.source_record_id)
        > (updated_since, watermark_id)
    ]
    page_records = eligible[:page_size]
    has_more = len(eligible) > page_size

    next_watermark = None
    if page_records:
        last_record = page_records[-1]
        next_watermark = Watermark(
            updated_at=last_record.updated_at,
            source_record_id=last_record.source_record_id,
        )

    response_records = list(page_records)
    if scenario == "duplicate" and response_records:
        response_records.append(response_records[0])

    return TelemetryPage(
        records=response_records,
        record_count=len(response_records),
        has_more=has_more,
        next_watermark=next_watermark,
    )
