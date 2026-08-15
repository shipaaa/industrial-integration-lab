# Laboratory CSV load and replay runbook

## Purpose

Use this procedure to load laboratory CSV files, inspect rejected rows, and
apply a corrected version without editing historical records.

## Initial load

```bash
make migrate-laboratory
make load-laboratory-valid
make load-laboratory-initial
```

The initial BATCH-003 row is expected to finish as
`COMPLETED_WITH_REJECTIONS`. Inspect it with:

```sql
SELECT rejected_record_id, source_object, source_record_id,
       error_text, replay_status
FROM rejected.record
WHERE record_type = 'LABORATORY'
ORDER BY rejected_at DESC;
```

## Controlled replay

The corrected CSV must retain `lab_result_id`, increment `result_version`, and
fix the rejected business rule. For the deterministic MVP fixture run:

```bash
make replay-laboratory
make verify-laboratory
```

`replay-laboratory` selects the latest pending LAB-003 rejection and passes its
ID with `lab_results_corrected.csv`. A successful database transaction:

1. stores version 2 as the current ODS result;
2. changes the original rejection from `PENDING` to `REPLAYED`;
3. writes an `ACCEPTED` row to `rejected.replay_history`;
4. changes BATCH-003 laboratory status in the investigation mart to `FAIL`.

## Safety checks

- Never edit or delete the original rejected payload.
- Do not reuse a version number for changed content.
- A repeated file is expected to produce `DUPLICATE`, not another ODS row.
- A lower version is stale and cannot overwrite the current result.
- Investigate any `MISMATCHED` row in `control.reconciliation_result` before
  continuing with another file.

The full reproducible exercise is `make test-laboratory-db`.
