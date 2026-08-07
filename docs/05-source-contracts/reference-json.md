# Reference JSON contract v1

Each reference file is a UTF-8 JSON document with this envelope:

```json
{
  "schema_version": "1.0",
  "source_system": "MES_MASTER",
  "extracted_at": "2026-07-16T00:00:00Z",
  "records": []
}
```

Unknown envelope and record fields are ignored. Required fields are validated
by entity. Timestamps use ISO 8601 with an explicit UTC offset.

| Entity | Business key | Required relationships |
|---|---|---|
| plant | `plant_id` | none |
| line | `line_id` | `plant_id` |
| equipment | `equipment_id` | `line_id` |
| material | `material_id` | none |
| batch | `batch_id` | `material_id`, `line_id`, `equipment_id` |

Material records contain four `parameter_ranges`. A range contains
`parameter_code`, `unit`, `min_value`, and `max_value`; the minimum must not be
greater than the maximum.

The source filename and each original record are retained in STG. ODS
idempotency uses the business key plus a canonical JSONB SHA-256 checksum.
