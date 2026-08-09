# ADR-002: Telemetry watermark and pagination

- Status: Accepted
- Date: 2026-08-09
- Decision owner: Project architect

## Context

Telemetry records can share the same `updated_at` value. A timestamp-only
watermark can skip records when a page boundary splits such a group.

## Decision

- The incremental position is the tuple `(updated_at, source_record_id)`.
- Results are ordered by that tuple in ascending order.
- Both parts of the watermark are exclusive: the next request returns tuples
  greater than the supplied tuple.
- `after_record_id` is valid only together with `updated_since`.
- The response returns the last tuple as `next_watermark` when records exist.
- NiFi will persist both values in `control.watermark` after a successful page.

The effective filter is:

```text
updated_at > updated_since
OR
(updated_at = updated_since AND source_record_id > after_record_id)
```

## Consequences

- A page boundary cannot lose records that share an update timestamp.
- A repeated request returns the same deterministic page.
- Consumers must treat the two watermark fields as one checkpoint.
- ODS uniqueness by `source_record_id` still protects against overlapping reads
  and deliberately simulated duplicate delivery.
