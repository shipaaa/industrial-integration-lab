# NiFi laboratory CSV flow runbook

## Start and provision

Docker Desktop must be running. Start the environment and provision both the
telemetry and laboratory process groups:

```bash
make start-nifi
```

The `Laboratory CSV Ingestion` group has two manual triggers. Bootstrap starts
all downstream processors but deliberately leaves both triggers stopped.
Provisioning therefore does not load or replay a file.

The source-controlled CSV fixtures are mounted read-only at
`/opt/nifi/laboratory`. NiFi verifies the exact header, calculates the SHA-256
of the original file, converts CSV records to a JSON array, and calls the
PostgreSQL file transaction with prepared SQL parameters.

## Primary load

Start only the valid and initial files:

```bash
make load-nifi-laboratory
```

The command requests one run of `Trigger Laboratory Primary Load` and waits
until:

- `lab_results_valid.csv` is accepted;
- `lab_results_initial.csv` is rejected for its inconsistent `PASS` status;
- LAB-003 has one pending rejected record;
- both file reconciliations are matched.

## Controlled correction replay

After reviewing the pending LAB-003 rejection, run:

```bash
make replay-nifi-laboratory
```

The replay script refuses to start when no pending NiFi LAB-003 rejection
exists. NiFi loads only `lab_results_corrected.csv`; the SQL call resolves the
latest pending rejection and passes its ID to the database replay contract.
Successful verification proves version 2 is current, replay history is linked,
and the BATCH-003 dossier status is `FAIL`.

## Complete reproducible test

```bash
make test-nifi-laboratory
```

This test deletes only laboratory test state, then performs primary load,
controlled replay, and a second primary load. The last step proves that both
repeated source files are audited as duplicates without changing ODS or replay
history.

## Failure triage

1. Inspect `Log Laboratory Technical Failure` and its provenance lineage.
2. Confirm the CSV directory is mounted read-only in the NiFi container.
3. Inspect the exact-header and SHA-256 attributes in provenance.
4. Inspect `audit.load_run`, `stg.laboratory_record`, `rejected.record`, and
   `control.reconciliation_result` in PostgreSQL.
5. Fix the technical problem and rerun the appropriate manual trigger.

Do not start the correction trigger merely to clear a technical queue. Replay
is a business-controlled operation and requires an existing pending rejection.
