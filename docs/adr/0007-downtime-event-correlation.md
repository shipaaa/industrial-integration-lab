# ADR-007: Downtime event correlation and replay

- Status: Accepted
- Date: 2026-08-20

## Context

A downtime incident arrives as two Kafka messages. Delivery can be repeated,
messages can be invalid, and a corrected message may be replayed later. The
database must calculate duration without losing the original delivery trail.

## Decision

- `DOWNTIME_STARTED` and `DOWNTIME_ENDED` are separate immutable events.
- `event_id` is the idempotency key; the Kafka record key must equal it.
- `downtime_id` correlates the start and end of one incident.
- An end event is accepted only for an existing open incident and cannot be
  earlier than its start.
- Batch, equipment, reason, and source must agree across both events.
- An exact `event_id` replay is audited as `DUPLICATE`; a changed payload with
  the same `event_id` is rejected.
- Unknown reason codes and other business-invalid messages are preserved in
  STG and rejected storage and are eligible for the Kafka DLQ.
- Controlled replay links a corrected message to its pending rejection and
  marks it `REPLAYED` only after successful acceptance.
- Only completed incidents contribute to `downtime_minutes`.

## Consequences

- ODS holds immutable accepted events plus the assembled incident state.
- Open incidents are visible but do not inflate analytical duration.
- Consumers must preserve Kafka topic, partition, offset, key, and payload.
- Replay is explicit and auditable rather than an update to rejected data.
