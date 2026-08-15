# Laboratory CSV source-to-target mapping

| CSV field | STG | ODS | Rule |
|---|---|---|---|
| `lab_result_id` | `source_record_id` and payload | `lab_result_id` | Required; ODS business key |
| `result_version` | payload | `result_version` | Positive integer; only a higher version may update ODS |
| `batch_id` | payload | `batch_id` | Batch must exist |
| `test_code` | payload | `test_code` | Required |
| `test_name` | payload | `test_name` | Required |
| `result_value` | payload | `result_value` | Numeric |
| `unit` | payload | `unit` | Required |
| `min_limit` | payload | `min_limit` | Numeric; must be at most `max_limit` |
| `max_limit` | payload | `max_limit` | Numeric |
| `result_status` | payload | `result_status` | Must agree with value and inclusive limits |
| `tested_at` | payload | `tested_at` | Timestamp with UTC offset |
| calculated | `file_checksum` | `source_file_checksum` | SHA-256 of the complete source file |
| calculated | `row_number` | `source_row_number` | Physical CSV row number |
| calculated | `checksum` | `source_checksum` | SHA-256 of canonical JSONB row text |
| calculated | `correlation_id` | — | Generated for each delivery attempt |

`dm.dm_batch_investigation.laboratory_overall_status` is `FAIL` when any
current result for the batch failed, `PASS` when results exist and all passed,
and `NULL` when the batch has no laboratory results.
