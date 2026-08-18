#!/usr/bin/env bash
set -euo pipefail

plantbridge_project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plantbridge_deadline=$((SECONDS + 120))

while (( SECONDS < plantbridge_deadline )); do
  plantbridge_duplicate_runs="$(
    docker compose --project-directory "${plantbridge_project_dir}" exec -T postgres psql \
      --username plantbridge \
      --dbname plantbridge \
      --tuples-only \
      --no-align \
      --command "
        SELECT count(*)
        FROM audit.load_run
        WHERE source_name = 'LAB_LIMS_NIFI'
          AND source_object IN ('lab_results_valid.csv', 'lab_results_initial.csv')
          AND duplicate_count = 1;
      " | tr -d '[:space:]'
  )"

  if [[ "${plantbridge_duplicate_runs}" -ge 2 ]]; then
    docker compose --project-directory "${plantbridge_project_dir}" exec -T postgres psql \
      --username plantbridge \
      --dbname plantbridge \
      --set ON_ERROR_STOP=1 \
      --file /db/test/verify_nifi_laboratory_duplicate.sql
    echo "NiFi laboratory idempotency verified: repeated primary files are duplicates."
    exit 0
  fi
  sleep 2
done

echo "NiFi laboratory duplicate verification timed out." >&2
exit 1
