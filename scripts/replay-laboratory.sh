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
    --command "SELECT rejected_record_id FROM rejected.record WHERE record_type = 'LABORATORY' AND source_record_id = 'LAB-003' AND replay_status = 'PENDING' ORDER BY rejected_at DESC LIMIT 1"
)"

if [[ -z "${plantbridge_rejected_record_id}" ]]; then
  echo "No pending LAB-003 laboratory rejection was found." >&2
  exit 1
fi

"${plantbridge_project_dir}/scripts/load-laboratory.sh" \
  "${plantbridge_project_dir}/data/laboratory/lab_results_corrected.csv" \
  "${plantbridge_rejected_record_id}"
