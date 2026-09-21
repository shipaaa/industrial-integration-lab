# Kafka downtime event runbook

## Purpose

Run the NiFi downtime process group, inspect its audit trail, and replay the
known invalid reason. The Python adapter remains only for the independent
database/Kafka contract test; NiFi is the demo path.

## Prerequisites

- Docker Desktop is running.
- Ports 5432 and 9092 are available.
- Reference data already exists; a new PostgreSQL volume loads it automatically.

## Full verification

```bash
make test
make test-downtime-kafka
make test-nifi-downtime
```

The Kafka test resets only these local topics:

- `plantbridge.downtime.events`
- `plantbridge.downtime.dlq`
- `plantbridge.downtime.replay`
- `plantbridge.downtime.receipts`

It then proves:

1. four start/end events are accepted into ODS;
2. the repeated BATCH-003 end is audited as `DUPLICATE`;
3. the unknown reason is stored in STG/rejected and published to the DLQ;
4. every delivery has a matched one-record reconciliation;
5. controlled replay marks the original rejection `REPLAYED`;
6. BATCH-003 has 7 downtime minutes and BATCH-002 has 10;
7. Kafka topic/partition/offset/timestamp are retained;
8. an offset is acknowledged by transactional publish only after the database
   outcome exists;
9. an end earlier than its start is rejected without closing the incident.

## Manual sequence

```bash
make start
make start-kafka
make migrate-downtime
make start-nifi
make test-nifi-downtime
```

`make test-nifi-downtime` resets only the local downtime tables and four
downtime topics. It leaves reference, telemetry, and laboratory ODS data intact.

## Inspection

```sql
SELECT * FROM dm.dm_downtime_incidents ORDER BY started_at;
SELECT batch_id, downtime_minutes
FROM dm.dm_batch_investigation
ORDER BY batch_id;
SELECT source_record_id, error_text, replay_status
FROM rejected.record
WHERE record_type = 'DOWNTIME';
SELECT topic_name, partition_id, offset_id, kafka_timestamp, processing_status
FROM stg.downtime_event_record
ORDER BY stg_downtime_event_record_id;
```

## Recovery boundaries

- Do not edit rejected payloads in place.
- Correct the source value and publish it to the replay topic with the original
  `event_id`.
- Do not close an incident manually in ODS; replay the missing or corrected end
  event.
- A Kafka or PostgreSQL technical failure is not a DLQ business rejection. Fix
  connectivity and restart the affected manual consumer. Its offset was not
  acknowledged until a transactional receipt or DLQ publish succeeded.
