# ADR-005: Laboratory correction versioning and replay

- Status: Accepted
- Date: 2026-08-12

## Context

Laboratory systems can resend the same file and can later correct a result.
The solution must prevent double counting, keep a reviewable correction trail,
and expose one unambiguous current result to downstream consumers.

## Decision

- One CSV file is processed by one PostgreSQL transaction with row-level error
  isolation.
- `file_checksum + row_number` identifies a delivery row.
- `lab_result_id` is the ODS business key and `result_version` controls updates.
- ODS stores only the highest accepted version of a result.
- Exact repeats and lower versions never overwrite ODS.
- A changed payload at the current version is rejected because corrections
  require a version increment.
- Controlled replay links a corrected load run to the original rejected record
  and marks that rejection `REPLAYED` only after the correction is accepted.
- STG, processing audit, rejected records, and replay history retain the full
  operational trail.

## Consequences

- Consumers query a compact current-state ODS table.
- Correction history remains reconstructable without duplicating old versions
  in ODS.
- The source must increment `result_version` for every material correction.
- A replay is explicit and auditable instead of silently editing a rejection.
