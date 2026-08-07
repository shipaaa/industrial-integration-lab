# ADR-001: Integration responsibility boundaries

## Context

PlantBridge must demonstrate 4 source channels, safe replay, idempotency,
traceability, rejected-record handling, and reconciliation without turning the
MVP into a large custom application.

## Decision

- Apache NiFi owns source connectivity, scheduling, routing, retry, correlation
  enrichment, rejected/DLQ routing, and calls to the database ingestion contract.
- PostgreSQL owns transactional staging, business-rule validation, idempotent
  upserts, result versioning, reconciliation, and investigation data marts.
- The FastAPI source simulator owns source behaviour only. It must not perform
  target-side validation or transformation.
- Kafka runs as a single KRaft broker for the MVP.
- DDS is reserved as a schema but is not populated in the first version. The MVP
  path is STG to ODS to DM.

## Consequences

- A replay can use the same database contract as the original delivery.
- Validation and deduplication are transactionally close to the target data and
  can be integration-tested independently of the NiFi UI.
- NiFi flows stay small enough to inspect during a 10–15 minute demonstration.
- Database procedures are part of the integration API and must be versioned and
  backward-compatible within an MVP release.

## Bootstrap convention

Until the first NiFi process group is committed, `scripts/load-reference.sh`
acts only as a contract-test adapter. It invokes the same PostgreSQL function
that NiFi will call and is not considered a production ingestion path.
