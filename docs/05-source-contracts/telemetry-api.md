# Telemetry REST API contract v1

## Endpoint

```http
GET /telemetry
```

Query parameters:

| Parameter | Type | Default | Purpose |
|---|---|---:|---|
| `updated_since` | ISO 8601 timestamp | none | First part of the exclusive watermark |
| `after_record_id` | string | none | Tie-breaker for an equal `updated_at` |
| `page_size` | integer, 1–100 | 20 | Maximum business records in a page |
| `scenario` | enum | `normal` | Simulate `timeout`, `http_500`, or `duplicate` |
| `delay_seconds` | number, 0–30 | 5 | Delay used by the timeout scenario |

`after_record_id` without `updated_since` returns HTTP 422. Records are ordered
by `(updated_at, source_record_id)` and the supplied watermark is exclusive.

## Record

```json
{
  "source_record_id": "TEL-0001",
  "batch_id": "BATCH-001",
  "equipment_id": "EXT-01",
  "parameter_code": "melt_temperature_c",
  "value": 191.2,
  "unit": "degC",
  "measured_at": "2026-07-15T05:30:00Z",
  "updated_at": "2026-07-16T13:00:00Z"
}
```

Required identifiers must be non-empty. `value` is numeric. Both timestamps
must include a UTC offset. Unknown record fields are ignored by the consumer.

## Successful response

```json
{
  "records": [],
  "record_count": 0,
  "has_more": false,
  "next_watermark": null
}
```

`record_count` includes a deliberately repeated record in the `duplicate`
scenario. `next_watermark` is calculated from the underlying ordered page, not
from the injected duplicate.

## Simulation behaviour

- `normal`: returns the deterministic page.
- `timeout`: waits for `delay_seconds`, then returns the normal page. A client
  timeout can therefore exercise retry without changing source state.
- `http_500`: returns HTTP 500 and no business records.
- `duplicate`: repeats the first record of a non-empty page with the same
  `source_record_id`.

The simulator is intentionally stateless: the same request produces the same
result.
