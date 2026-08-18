# ADR-006: Controlled NiFi laboratory replay

- Status: Accepted
- Date: 2026-08-15

## Context

The corrected BATCH-003 file must not be ingested before the original invalid
row has been rejected and reviewed. Starting a process group normally starts
all schedulable source processors, which would make an automatic correction
possible during provisioning or restart.

## Decision

- Primary loading and correction replay are separate `GenerateFlowFile`
  triggers in one Laboratory CSV process group.
- Both triggers are declared as manual in the source-controlled flow spec.
- Bootstrap starts every downstream processor individually but leaves manual
  triggers stopped.
- Primary and replay triggers run only through an explicit NiFi `RUN_ONCE` API
  request.
- The primary manifest contains only the valid and initial files.
- The replay manifest contains only the corrected file.
- Replay resolves the latest pending rejection for the corrected
  `lab_result_id`; no pending rejection makes the database transaction fail.

## Consequences

- Provisioning or restarting NiFi cannot silently apply the correction.
- The operator can capture the rejected state before authorizing replay.
- Primary re-execution remains safe because the database records repeated file
  rows as duplicates.
- Adding another correction scenario requires an explicit manifest and replay
  selection rule.
