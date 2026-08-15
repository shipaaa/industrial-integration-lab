#!/usr/bin/env bash
set -euo pipefail

plantbridge_project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plantbridge_csv_file="${1:-}"
plantbridge_rejected_record_id="${2:-}"

if [[ -z "${plantbridge_csv_file}" || ! -f "${plantbridge_csv_file}" ]]; then
  echo "usage: $0 CSV_FILE [REJECTED_RECORD_ID]" >&2
  exit 2
fi

plantbridge_rows_json="$(
  python3 "${plantbridge_project_dir}/scripts/laboratory-csv-to-json.py" \
    "${plantbridge_csv_file}"
)"
plantbridge_file_checksum="$(shasum -a 256 "${plantbridge_csv_file}" | awk '{print $1}')"
plantbridge_source_object="$(basename "${plantbridge_csv_file}")"

docker compose --project-directory "${plantbridge_project_dir}" exec -T postgres psql \
  --username plantbridge \
  --dbname plantbridge \
  --set ON_ERROR_STOP=1 \
  --set source_name="LAB_LIMS" \
  --set source_object="${plantbridge_source_object}" \
  --set file_checksum="${plantbridge_file_checksum}" \
  --set rejected_record_id="${plantbridge_rejected_record_id}" \
  --set rows_json="${plantbridge_rows_json}" <<'SQL'
SELECT ods.load_laboratory_file(
    :'rows_json'::jsonb,
    :'source_name',
    :'source_object',
    :'file_checksum',
    NULLIF(:'rejected_record_id', '')::bigint
) AS run_id;
SQL
