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
             AND replay_status = 'REPLAYED'),
          (SELECT count(*) FROM rejected.replay_history h
           JOIN rejected.record r ON r.rejected_record_id = h.rejected_record_id
           WHERE r.source_name = 'LAB_LIMS_NIFI'
             AND h.outcome = 'ACCEPTED'),
          (SELECT laboratory_overall_status
           FROM dm.dm_batch_investigation
           WHERE batch_id = 'BATCH-003');
      " | tr -d '[:space:]'
  )"

  if [[ "${plantbridge_state}" == "2|1|1|FAIL" ]]; then
    docker compose --project-directory "${plantbridge_project_dir}" exec -T postgres psql \
      --username plantbridge \
      --dbname plantbridge \
      --set ON_ERROR_STOP=1 \
      --file /db/test/verify_nifi_laboratory_corrected.sql
    echo "NiFi laboratory replay verified: LAB-003 version 2 accepted and dossier status is FAIL."
    exit 0
  fi
  sleep 2
done

echo "NiFi laboratory replay verification timed out. Last state: ${plantbridge_state}" >&2
exit 1
