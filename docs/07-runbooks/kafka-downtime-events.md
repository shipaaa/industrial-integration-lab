# Kafka downtime event runbook

## Purpose

Run the local downtime event contract, inspect its audit trail, and replay the
known invalid reason. The Python adapter is temporary: it proves the broker and
database boundary before the NiFi consumer process group is added.

## Prerequisites

- Docker Desktop is running.
- Ports 5432 and 9092 are available.
- Reference data already exists; a new PostgreSQL volume loads it automatically.

## Full verification

```bash
make test
make test-downtime-kafka
```

The Kafka test resets only these local topics:

- `plantbridge.downtime.events`
- `plantbridge.downtime.dlq`
- `plantbridge.downtime.replay`

It then proves:

1. four start/end events are accepted into ODS;
2. the repeated BATCH-003 end is audited as `DUPLICATE`;
3. the unknown reason is stored in STG/rejected and published to the DLQ;
4. every delivery has a matched one-record reconciliation;
5. controlled replay marks the original rejection `REPLAYED`;
6. BATCH-003 has 7 downtime minutes and BATCH-002 has 10;
7. an end earlier than its start is rejected without closing the incident.

## Manual sequence

```bash
make start
make start-kafka
make migrate-downtime
make load-downtime-kafka
make replay-downtime-kafka
```

Use `make load-downtime-kafka` only after the primary topic is empty or after a
test reset: the temporary consumer intentionally reads from the beginning to
exercise database idempotency. NiFi offset management is part of the next
orchestration slice.

## Inspection

```sql
SELECT * FROM dm.dm_downtime_incidents ORDER BY started_at;
SELECT batch_id, downtime_minutes
FROM dm.dm_batch_investigation
ORDER BY batch_id;
SELECT source_record_id, error_text, replay_status
FROM rejected.record
WHERE record_type = 'DOWNTIME';
```

## Recovery boundaries

- Do not edit rejected payloads in place.
- Correct the source value and publish it to the replay topic with the original
  `event_id`.
- Do not close an incident manually in ODS; replay the missing or corrected end
  event.
- A Kafka or PostgreSQL technical failure is not a DLQ business rejection. Fix
  connectivity and rerun consumption so the database remains the outcome
  authority.
