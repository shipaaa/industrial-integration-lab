#!/usr/bin/env bash
set -euo pipefail

plantbridge_project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 -m unittest discover \
  --start-directory "${plantbridge_project_dir}/tests" \
  --verbose

docker compose --project-directory "${plantbridge_project_dir}" up \
  --detach --build --wait postgres source-simulator kafka nifi

"${plantbridge_project_dir}/scripts/apply-telemetry-db.sh"
"${plantbridge_project_dir}/scripts/apply-laboratory-db.sh"
"${plantbridge_project_dir}/scripts/apply-downtime-db.sh"
"${plantbridge_project_dir}/scripts/bootstrap-kafka.sh"
"${plantbridge_project_dir}/scripts/bootstrap-nifi.py" \
  --stop-trigger "Trigger Telemetry Poll"
"${plantbridge_project_dir}/scripts/bootstrap-nifi-laboratory.sh"
"${plantbridge_project_dir}/scripts/bootstrap-nifi-downtime.sh"

docker compose --project-directory "${plantbridge_project_dir}" exec -T postgres psql \
  --username plantbridge \
  --dbname plantbridge \
  --set ON_ERROR_STOP=1 \
  --file /db/test/reset_telemetry.sql

"${plantbridge_project_dir}/scripts/load-reference.sh"
"${plantbridge_project_dir}/scripts/verify-reference.sh"

"${plantbridge_project_dir}/scripts/bootstrap-nifi.py" --run-once
"${plantbridge_project_dir}/scripts/verify-nifi-telemetry.sh"
"${plantbridge_project_dir}/scripts/replay-nifi-telemetry.sh"
"${plantbridge_project_dir}/scripts/bootstrap-nifi.py" \
  --stop-trigger "Trigger Telemetry Poll"

"${plantbridge_project_dir}/scripts/test-nifi-laboratory.sh"
PLANTBRIDGE_SKIP_STACK_START=1 \
  "${plantbridge_project_dir}/scripts/test-nifi-downtime.sh"

docker compose --project-directory "${plantbridge_project_dir}" exec -T postgres psql \
  --username plantbridge \
  --dbname plantbridge \
  --set ON_ERROR_STOP=1 \
  --file /db/test/verify_mvp.sql

echo "MVP smoke passed: reference, telemetry, laboratory, downtime, replay, idempotency, reconciliation, BATCH-003 dossier."
