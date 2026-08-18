#!/usr/bin/env bash
set -euo pipefail

plantbridge_project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plantbridge_deadline=$((SECONDS + 120))
plantbridge_state=""

while (( SECONDS < plantbridge_deadline )); do
  plantbridge_state="$(
    docker compose --project-directory "${plantbridge_project_dir}" exec -T postgres psql \
      --username plantbridge \
      --dbname plantbridge \
      --tuples-only \
      --no-align \
      --field-separator '|' \
      --command "
        SELECT
          (SELECT count(*) FROM ods.laboratory_result),
          (SELECT count(*) FROM rejected.record
           WHERE record_type = 'LABORATORY'
             AND source_name = 'LAB_LIMS_NIFI'
             AND source_record_id = 'LAB-003'
             AND replay_status = 'PENDING'),
          (SELECT count(*) FROM audit.load_run
           WHERE source_name = 'LAB_LIMS_NIFI');
      " | tr -d '[:space:]'
  )"

  IFS='|' read -r \
    plantbridge_ods_count \
    plantbridge_pending_count \
    plantbridge_run_count <<<"${plantbridge_state}"

  if [[ "${plantbridge_ods_count}" == "1" \
      && "${plantbridge_pending_count}" == "1" \
      && "${plantbridge_run_count}" -ge 2 ]]; then
    docker compose --project-directory "${plantbridge_project_dir}" exec -T postgres psql \
      --username plantbridge \
      --dbname plantbridge \
      --set ON_ERROR_STOP=1 \
      --file /db/test/verify_nifi_laboratory_initial.sql
    echo "NiFi laboratory primary load verified: valid accepted, LAB-003 rejected."
    exit 0
  fi
  sleep 2
done

echo "NiFi laboratory primary verification timed out. Last state: ${plantbridge_state}" >&2
exit 1
