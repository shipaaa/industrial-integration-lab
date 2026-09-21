# MVP acceptance and demo runbook

## Acceptance command

Prerequisites: Docker Desktop is running; ports 5432, 8000, 8443, and 9092 are
available; Python 3.9 or newer is installed.

```bash
make test-mvp
```

Expected final line:

```text
MVP smoke passed: reference, telemetry, laboratory, downtime, replay, idempotency, reconciliation, BATCH-003 dossier.
```

The command resets only local test data for telemetry, laboratory, downtime,
and the four downtime topics. It does not remove Docker volumes or unrelated
files.

## Acceptance checklist

- Static contract tests pass.
- Reference cardinality is 1 plant, 1 line, 1 equipment item, 2 materials, and
  3 batches.
- Telemetry has 24 ODS measurements and watermark `TEL-0024` after safe replay.
- Laboratory correction replay links to the rejected LAB-003 record and leaves
  BATCH-003 status `FAIL`.
- BATCH-003 contains an above-limit `melt_temperature_c` measurement.
- Downtime keeps Kafka topic/partition/offset/timestamp, sends the unknown
  reason to DLQ, links its corrected replay, and reports 7 BATCH-003 minutes.
- Repeated telemetry, laboratory, and downtime deliveries do not increase ODS.
- Every reconciliation result is `MATCHED`.

## Verification SQL

```sql
SELECT batch_id, laboratory_overall_status,
       process_deviation_count, downtime_minutes
FROM dm.dm_batch_investigation
WHERE batch_id = 'BATCH-003';

SELECT source_record_id, parameter_code, measured_value,
       min_value, max_value, deviation_type
FROM dm.dm_batch_process_deviations
WHERE batch_id = 'BATCH-003';

SELECT topic_name, partition_id, offset_id, kafka_timestamp,
       source_record_id, processing_status
FROM stg.downtime_event_record
ORDER BY stg_downtime_event_record_id;

SELECT record_type, source_record_id, replay_status, error_text
FROM rejected.record
ORDER BY rejected_at;

SELECT status, count(*)
FROM control.reconciliation_result
GROUP BY status;
```

## Recovery after a technical failure

1. Restore Docker Desktop, PostgreSQL, Kafka, or NiFi connectivity.
2. Run `docker compose up --detach --wait postgres source-simulator kafka nifi`.
3. Run `make bootstrap-nifi` to validate the Git-managed flows.
4. For a full deterministic recovery check, rerun `make test-mvp`.

Do not edit ODS or rejected payloads manually. Database and Kafka technical
failures use bounded NiFi retries; downtime offsets are acknowledged only after
the database result and transactional receipt/DLQ publish succeed. Redelivery is
safe because PostgreSQL owns idempotency.

## 10–15 minute demo

1. Show the four source contracts and explain that reference JSON uses the
   documented shell-loader limitation.
2. Run `make test-mvp` and point out each channel as it completes.
3. Open NiFi at `https://localhost:8443/nifi/` and show the telemetry,
   laboratory, and downtime process groups.
4. Show the downtime primary/replay consumers, PostgreSQL outcome routing,
   bounded retries, receipt path, and DLQ path.
5. Run the verification SQL above and finish on the BATCH-003 dossier: `FAIL`,
   one temperature deviation, and 7 downtime minutes.

## Known MVP limitations

- Reference ingestion remains a shell loader that calls the PostgreSQL contract.
- Kafka is a single local broker and NiFi is a single local node.
- Credentials are development-only; production security and hardening are out
  of scope.
- There is no NiFi Registry, full DDS, frontend, BI layer, Kubernetes, or
  production observability stack.
