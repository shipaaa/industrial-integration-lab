# ADR-004: NiFi telemetry flow deployment

- Status: Accepted
- Date: 2026-08-11

## Context

The telemetry API and PostgreSQL page transaction already have executable
contracts. The next slice must make their orchestration reproducible without
moving validation, deduplication, reconciliation, or watermark ownership into
NiFi.

Apache NiFi Registry was deprecated in February 2026. Adding it to this local
MVP would introduce another service whose planned replacement is a Git-based
Flow Registry Client.

## Decision

- Run a single Apache NiFi 2.10.0 node with HTTPS and single-user authentication.
- Keep the flow definition in `nifi/telemetry-flow.json` and provision it through
  the NiFi REST API with `scripts/bootstrap-nifi.py`.
- Keep environment-specific endpoints, credentials, page size, and retry count
  in a NiFi Parameter Context.
- Use a pinned PostgreSQL JDBC driver in the NiFi image.
- Let NiFi read the composite watermark, invoke the API, retry technical
  failures, call `ods.load_telemetry_page` once per page, and continue only after
  that database call succeeds.
- Limit API and database retries independently to three attempts. Exhausted
  retries and non-retryable failures enter the technical failure route.
- Keep the database function responsible for the page transaction, record-level
  rejection, reconciliation, and atomic watermark advancement.
- Do not deploy a separate NiFi Registry service for the MVP.

## Consequences

- A fresh environment can recreate the process group without manual canvas work.
- Flow configuration changes are reviewable in Git.
- NiFi provenance shows every API call, retry, database call, and page loop.
- The committed credentials are local-development values and must be replaced
  before any shared or production deployment.
- A changed specification requires an intentional NiFi flow-volume reset or a
  future migration mechanism; the bootstrap refuses to overwrite a different
  deployed specification.
