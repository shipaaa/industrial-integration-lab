# ADR-003: Telemetry page transaction boundary

- Status: Accepted
- Date: 2026-08-10

## Context

NiFi receives telemetry as ordered API pages. A page may contain valid,
duplicate, and business-invalid records. Advancing the source watermark before
the page is durably accounted for can lose records after a failure.

## Decision

- One API page is processed by one PostgreSQL transaction.
- Each record is preserved in STG before business validation.
- Record-level business failures are isolated with a subtransaction and stored
  in `rejected.record`; they do not abort the page.
- Exact repeats are recorded as duplicates and do not create new ODS facts.
- The page watermark advances only after every received record is accepted,
  rejected, or identified as a duplicate.
- A system failure aborts the whole page transaction and leaves the previous
  watermark unchanged, allowing NiFi to retry the same page.

## Consequences

- A bad business record cannot block unrelated records in the same page.
- A failed database call cannot move the checkpoint past uncommitted data.
- Reconciliation is evaluated at API-page grain.
- NiFi calls one stable database function per page instead of one call per
  telemetry measurement.
