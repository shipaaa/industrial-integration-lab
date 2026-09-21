# Demo evidence checklist

This checklist defines the minimum portfolio evidence for the demo-ready MVP.
Capture the evidence only after `make test-mvp` passes on `main` or on a branch
created directly from the tagged MVP.

## Capture rules

- Use the deterministic MVP fixtures without adding new records.
- Keep credentials, tokens, local usernames, and unrelated applications out of
  every image.
- Show enough context to identify the component and result, but crop empty UI.
- Store images in `docs/assets/demo/` using the filenames below.
- Do not edit database rows or rejected payloads to improve the screenshots.

## Required screenshots

### 01 — NiFi process-group overview

Filename: `01-nifi-process-groups.png`

Show the NiFi root canvas with these three Git-managed process groups visible:

- Telemetry API Ingestion;
- Laboratory CSV Ingestion;
- Downtime Kafka Ingestion.

Acceptance: no invalid-component warning is visible.

### 02 — Telemetry orchestration

Filename: `02-telemetry-flow.png`

Open `Telemetry API Ingestion` and show the path from the API request through
the PostgreSQL load and pagination decision.

Acceptance: the screenshot makes the watermark, retry, database load, and
pagination path distinguishable.

### 03 — Laboratory replay

Filename: `03-laboratory-replay-flow.png`

Open `Laboratory CSV Ingestion` and show both manual triggers, the shared CSV
validation path, normal load, correction replay, and bounded retries.

Acceptance: primary and replay entry points are both visible.

### 04 — Downtime Kafka flow

Filename: `04-downtime-kafka-flow.png`

Open `Downtime Kafka Ingestion` and show primary/replay consumers, PostgreSQL
outcome routing, receipt publish, DLQ publish, and technical retry paths.

Acceptance: the consumer-to-database-to-receipt/DLQ path is readable in one
frame or in two adjacent frames with no missing middle section.

### 05 — Full MVP smoke result

Filename: `05-mvp-smoke-result.png`

Run:

```bash
make test-mvp
```

Capture the final terminal section containing:

- 42 passing static tests;
- the successful NiFi downtime E2E line;
- the final BATCH-003 row;
- `24`, `TEL-0024`, `2`, `6`, and `0` in the summary;
- the final `MVP smoke passed` line.

### 06 — BATCH-003 investigation dossier

Filename: `06-batch-003-dossier.png`

Run:

```bash
docker compose exec -T postgres psql \
  --username plantbridge \
  --dbname plantbridge \
  --command "
    SELECT batch_id, laboratory_overall_status,
           process_deviation_count, downtime_minutes
    FROM dm.dm_batch_investigation
    WHERE batch_id = 'BATCH-003';

    SELECT source_record_id, parameter_code, measured_value,
           min_value, max_value, deviation_type
    FROM dm.dm_batch_process_deviations
    WHERE batch_id = 'BATCH-003';
  "
```

Acceptance: BATCH-003 is `FAIL`, has one process deviation, 7 downtime minutes,
and an above-limit `melt_temperature_c` measurement.

### 07 — Rejection and replay lineage

Filename: `07-rejection-replay-lineage.png`

Run:

```bash
docker compose exec -T postgres psql \
  --username plantbridge \
  --dbname plantbridge \
  --command "
    SELECT r.record_type, r.source_record_id, r.replay_status,
           h.outcome AS replay_outcome
    FROM rejected.record r
    JOIN rejected.replay_history h USING (rejected_record_id)
    WHERE r.record_type IN ('LABORATORY', 'DOWNTIME')
    ORDER BY r.record_type;
  "
```

Acceptance: both the laboratory and downtime corrections show `REPLAYED` and
an `ACCEPTED` replay outcome.

## Final verification

Before committing screenshots:

```bash
make test-mvp
git status --short
```

Only this checklist, the intended images, and the corresponding README links
should be tracked. The unrelated `digitized_photos/` directory must remain
untracked and untouched.
