#!/usr/bin/env bash
set -euo pipefail

plantbridge_project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plantbridge_active_trigger=""

plantbridge_stop_active_trigger() {
  if [[ -n "${plantbridge_active_trigger}" ]]; then
    "${plantbridge_project_dir}/scripts/bootstrap-nifi-downtime.sh" \
      --stop-trigger "${plantbridge_active_trigger}" >/dev/null 2>&1 || true
  fi
}
trap plantbridge_stop_active_trigger EXIT

plantbridge_wait_for_stg_count() {
  local plantbridge_expected_count="$1"
  local plantbridge_count="0"
  for plantbridge_attempt in $(seq 1 60)
  do
    plantbridge_count="$(
      docker compose --project-directory "${plantbridge_project_dir}" exec -T postgres psql \
        --username plantbridge \
        --dbname plantbridge \
        --no-align \
        --tuples-only \
        --set ON_ERROR_STOP=1 \
        --command "SELECT count(*) FROM stg.downtime_event_record" \
      | tr -d '[:space:]'
    )"
    if [[ "${plantbridge_count}" == "${plantbridge_expected_count}" ]]; then
      return 0
    fi
    sleep 1
  done
  echo "Timed out waiting for ${plantbridge_expected_count} downtime STG records; got ${plantbridge_count}" >&2
  return 1
}

docker compose --project-directory "${plantbridge_project_dir}" up \
  --detach --build --wait postgres kafka nifi
"${plantbridge_project_dir}/scripts/apply-downtime-db.sh"
"${plantbridge_project_dir}/scripts/bootstrap-nifi-downtime.sh"

docker compose --project-directory "${plantbridge_project_dir}" exec -T postgres psql \
  --username plantbridge \
  --dbname plantbridge \
  --set ON_ERROR_STOP=1 \
  --file /db/test/reset_downtime.sql
"${plantbridge_project_dir}/scripts/reset-downtime-kafka.sh"

"${plantbridge_project_dir}/scripts/produce-downtime-events.sh"
plantbridge_active_trigger="Consume Downtime Primary Events"
"${plantbridge_project_dir}/scripts/bootstrap-nifi-downtime.sh" \
  --start-trigger "${plantbridge_active_trigger}"
plantbridge_wait_for_stg_count 6
"${plantbridge_project_dir}/scripts/bootstrap-nifi-downtime.sh" \
  --stop-trigger "${plantbridge_active_trigger}"
plantbridge_active_trigger=""

docker compose --project-directory "${plantbridge_project_dir}" exec -T postgres psql \
  --username plantbridge \
  --dbname plantbridge \
  --set ON_ERROR_STOP=1 \
  --file /db/test/verify_downtime_initial.sql
python3 "${plantbridge_project_dir}/scripts/verify-downtime-dlq.py"

"${plantbridge_project_dir}/scripts/produce-downtime-replay.sh"
plantbridge_active_trigger="Consume Downtime Replay Events"
"${plantbridge_project_dir}/scripts/bootstrap-nifi-downtime.sh" \
  --start-trigger "${plantbridge_active_trigger}"
plantbridge_wait_for_stg_count 8
"${plantbridge_project_dir}/scripts/bootstrap-nifi-downtime.sh" \
  --stop-trigger "${plantbridge_active_trigger}"
plantbridge_active_trigger=""

docker compose --project-directory "${plantbridge_project_dir}" exec -T postgres psql \
  --username plantbridge \
  --dbname plantbridge \
  --set ON_ERROR_STOP=1 \
  --file /db/test/verify_downtime_replay.sql \
  --file /db/test/verify_nifi_downtime.sql
python3 "${plantbridge_project_dir}/scripts/verify-downtime-receipts.py"

echo "NiFi downtime E2E passed: primary, duplicate, DLQ, replay, receipts, lineage, reconciliation."
