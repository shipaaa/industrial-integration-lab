# Downtime Kafka contract v1

## Topics

| Topic | Purpose |
|---|---|
| `plantbridge.downtime.events` | Primary downtime start and end events |
| `plantbridge.downtime.dlq` | Rejected event envelopes for investigation |
| `plantbridge.downtime.replay` | Corrected events approved for replay |

Topics have one partition in the local MVP so the fixture order is
deterministic. This does not replace correlation and business-order checks.

## Kafka record

The record key is the event's `event_id`. The value is UTF-8 JSON:

```json
{
  "schema_version": "1.0",
  "source_system": "MAINTENANCE_CMS",
  "event_id": "EVT-DT-003-START",
  "downtime_id": "DT-003",
  "event_type": "DOWNTIME_STARTED",
  "batch_id": "BATCH-003",
  "equipment_id": "EXT-01",
  "reason_code": "MATERIAL_JAM",
  "occurred_at": "2026-07-15T10:40:00Z"
}
```

| Field | Rule |
|---|---|
| `schema_version` | Required; exactly `1.0` |
| `source_system` | Required; exactly `MAINTENANCE_CMS` |
| `event_id` | Required immutable event key; must equal Kafka key |
| `downtime_id` | Required incident correlation key |
| `event_type` | `DOWNTIME_STARTED` or `DOWNTIME_ENDED` |
| `batch_id` | Required; must exist in ODS |
| `equipment_id` | Required; must exist and match the batch |
| `reason_code` | Required; must exist in `ods.downtime_reason` |
| `occurred_at` | ISO 8601 timestamp with UTC offset |

Unknown fields are allowed for forward-compatible additive changes. Missing or
invalid required fields are rejected.

## Identity, ordering, and replay

- `event_id` plus canonical payload checksum identifies an exact repeat.
- The first accepted start creates an open incident.
- The matching end must use the same incident attributes and occur at or after
  the start.
- An end without an open start and a second start for the same incident are
  rejected.
- The DLQ value wraps the original Kafka metadata, payload, rejection ID, and
  validation error. It is not an alternative system of record.
- A corrected replay keeps the original `event_id`; the replay consumer passes
  the pending rejection ID into the database transaction.

## Deterministic MVP scenario

- `DT-003`: `MATERIAL_JAM` during BATCH-003 from 10:40 to 10:47 — 7 minutes.
- `DT-002`: `PLANNED_CLEANING` during BATCH-002 from 08:10 to 08:20 — 10 minutes.
- The `DT-003` end is delivered twice and the second attempt is a duplicate.
- `DT-REPLAY` first uses unknown reason `UNMAPPED_REASON`, is rejected and sent
  to the DLQ, then is corrected to `PLANNED_CLEANING` and replayed.
