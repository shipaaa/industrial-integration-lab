# Downtime Kafka source-to-target mapping

| Source | STG | ODS event | ODS incident | Rule |
|---|---|---|---|---|
| Kafka key | `message_key` | — | — | Must equal `event_id` |
| topic | `topic_name` | `source_topic` | — | Preserved verbatim |
| partition | `partition_id` | `source_partition` | — | Non-negative integer |
| offset | `offset_id` | `source_offset` | — | Non-negative integer |
| JSON value | `payload` | — | — | Preserved verbatim |
| `event_id` | `source_record_id` | `event_id` | start/end event ID | ODS idempotency key |
| `downtime_id` | payload | `downtime_id` | `downtime_id` | Incident correlation key |
| `event_type` | payload | `event_type` | status transition | START opens; END completes |
| `batch_id` | payload | `batch_id` | `batch_id` | FK to production batch |
| `equipment_id` | payload | `equipment_id` | `equipment_id` | Must match batch |
| `reason_code` | payload | `reason_code` | `reason_code` | FK to reason dictionary |
| `occurred_at` | payload | `occurred_at` | start/end timestamp | Must include offset |

Every delivery creates one `audit.load_run`, one STG row, one processing audit
row, and one reconciliation result. Rejected deliveries also create one
`rejected.record`; successful controlled replay adds replay history.
