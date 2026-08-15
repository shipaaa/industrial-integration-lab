# Laboratory CSV contract v1

## Delivery

One UTF-8 CSV file is one atomic load unit. The first line is the header and
every following line is one laboratory result version. Files use commas as
delimiters and must contain the columns below in the documented order.

```csv
lab_result_id,result_version,batch_id,test_code,test_name,result_value,unit,min_limit,max_limit,result_status,tested_at
LAB-003,2,BATCH-003,MELT_FLOW_INDEX,Melt Flow Index,18.2,g/10min,10.0,15.0,FAIL,2026-07-15T13:10:00Z
```

| Column | Type | Rule |
|---|---|---|
| `lab_result_id` | string | Required; stable business key across corrections |
| `result_version` | integer | Required; positive and strictly increases for a correction |
| `batch_id` | string | Required; must exist in `ods.production_batch` |
| `test_code` | string | Required |
| `test_name` | string | Required |
| `result_value` | decimal | Required |
| `unit` | string | Required |
| `min_limit` | decimal | Required; must not exceed `max_limit` |
| `max_limit` | decimal | Required |
| `result_status` | enum | `PASS` when value is within inclusive limits, otherwise `FAIL` |
| `tested_at` | ISO 8601 timestamp | Required; must include a UTC offset |

Unknown columns and malformed CSV structure are rejected by the file adapter
before the database call. Business-invalid rows are preserved in STG and
`rejected.record`; they do not block valid rows from the same file.

## Identity and correction

- Delivery identity is the SHA-256 file checksum plus the physical CSV row
  number (the first data row is row 2).
- The ODS business key is `lab_result_id`.
- An exact delivery repeat is audited as `DUPLICATE`.
- A lower version cannot overwrite the current ODS row and is audited as a
  stale duplicate.
- A changed payload with the current version is rejected; a correction must
  increment `result_version`.
- A higher valid version replaces the current ODS row. Previous attempts stay
  available in STG, audit, rejected records, and replay history.

## MVP fixtures

- `lab_results_valid.csv`: valid BATCH-001 moisture result.
- `lab_results_initial.csv`: BATCH-003 Melt Flow Index is outside its limits,
  but is incorrectly marked `PASS`; the row is rejected.
- `lab_results_corrected.csv`: the same result at version 2 is marked `FAIL`
  and is used to close the pending rejection through controlled replay.
