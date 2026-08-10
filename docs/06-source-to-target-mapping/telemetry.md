# Telemetry source-to-target mapping

| Source field | STG | ODS | Rule |
|---|---|---|---|
| `source_record_id` | `source_record_id` | `source_record_id` | Required; ODS business key |
| `batch_id` | payload | `batch_id` | Batch must exist |
| `equipment_id` | payload | `equipment_id` | Must exist and match the batch equipment |
| `parameter_code` | payload | `parameter_code` | Must have a range for the batch material |
| `value` | payload | `measured_value` | Must be numeric |
| `unit` | payload | `unit` | Must equal the configured range unit |
| `measured_at` | payload | `measured_at` | Must include an offset and fall inside the batch window |
| `updated_at` | payload | `source_updated_at` | Must include an offset; first watermark component |
| calculated | checksum | `source_checksum` | SHA-256 of canonical JSONB text |
| calculated | `correlation_id` | — | Generated for each delivery attempt |
| calculated | — | `is_deviation` | Value outside configured material range |

The API page `next_watermark.updated_at` is stored in
`control.watermark.watermark_value`; `next_watermark.source_record_id` is stored
in `control.watermark.watermark_record_id` after the page is reconciled.
