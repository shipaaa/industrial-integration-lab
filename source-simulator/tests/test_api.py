from fastapi.testclient import TestClient

from app.main import app
from app.repository import TelemetryRepository


client = TestClient(app)


def test_fixture_contains_expected_mvp_data() -> None:
    records = TelemetryRepository().records

    assert len(records) == 24
    assert {item.batch_id for item in records} == {"BATCH-001", "BATCH-002", "BATCH-003"}
    assert {item.parameter_code for item in records} == {
        "melt_temperature_c",
        "melt_pressure_bar",
        "screw_speed_rpm",
        "power_kw",
    }
    deviation = next(item for item in records if item.source_record_id == "TEL-0021")
    assert deviation.batch_id == "BATCH-003"
    assert deviation.value == 214.0


def test_pagination_does_not_skip_equal_timestamps() -> None:
    first = client.get("/telemetry", params={"page_size": 3})
    assert first.status_code == 200
    first_page = first.json()
    assert [item["source_record_id"] for item in first_page["records"]] == [
        "TEL-0001",
        "TEL-0002",
        "TEL-0003",
    ]

    watermark = first_page["next_watermark"]
    second = client.get(
        "/telemetry",
        params={
            "page_size": 3,
            "updated_since": watermark["updated_at"],
            "after_record_id": watermark["source_record_id"],
        },
    )
    assert second.status_code == 200
    assert [item["source_record_id"] for item in second.json()["records"]] == [
        "TEL-0004",
        "TEL-0005",
        "TEL-0006",
    ]


def test_after_record_id_requires_timestamp() -> None:
    response = client.get("/telemetry", params={"after_record_id": "TEL-0003"})
    assert response.status_code == 422


def test_http_500_scenario() -> None:
    response = client.get("/telemetry", params={"scenario": "http_500"})
    assert response.status_code == 500


def test_duplicate_scenario_repeats_stable_record_id() -> None:
    response = client.get(
        "/telemetry",
        params={"scenario": "duplicate", "page_size": 2},
    )
    payload = response.json()
    identifiers = [item["source_record_id"] for item in payload["records"]]
    assert identifiers == ["TEL-0001", "TEL-0002", "TEL-0001"]
    assert payload["record_count"] == 3
    assert payload["next_watermark"]["source_record_id"] == "TEL-0002"


def test_timeout_scenario_can_complete_without_delay() -> None:
    response = client.get(
        "/telemetry",
        params={"scenario": "timeout", "delay_seconds": 0, "page_size": 1},
    )
    assert response.status_code == 200
    assert response.json()["record_count"] == 1
