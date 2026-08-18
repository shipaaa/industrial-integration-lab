#!/usr/bin/env bash
set -euo pipefail

plantbridge_project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plantbridge_rejected_record_id="$(
  docker compose --project-directory "${plantbridge_project_dir}" exec -T postgres psql \
    --username plantbridge \
    --dbname plantbridge \
    --tuples-only \
    --no-align \
    --set ON_ERROR_STOP=1 \
    --command "SELECT rejected_record_id FROM rejected.record WHERE record_type = 'LABORATORY' AND source_name = 'LAB_LIMS_NIFI' AND source_record_id = 'LAB-003' AND replay_status = 'PENDING' ORDER BY rejected_at DESC LIMIT 1" \
  | tr -d '[:space:]'
)"

if [[ -z "${plantbridge_rejected_record_id}" ]]; then
  echo "No pending NiFi LAB-003 rejection was found; correction replay was not started." >&2
  exit 1
fi

echo "Requesting NiFi correction replay for rejected record ${plantbridge_rejected_record_id}."
"${plantbridge_project_dir}/scripts/bootstrap-nifi-laboratory.sh" \
  --run-once \
  --trigger "Trigger Laboratory Correction Replay"
