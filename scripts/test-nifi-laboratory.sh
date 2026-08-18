#!/usr/bin/env bash
set -euo pipefail

plantbridge_project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${plantbridge_project_dir}/scripts/apply-laboratory-db.sh"
"${plantbridge_project_dir}/scripts/bootstrap-nifi-laboratory.sh"

docker compose --project-directory "${plantbridge_project_dir}" exec -T postgres psql \
  --username plantbridge \
  --dbname plantbridge \
  --set ON_ERROR_STOP=1 \
  --file /db/test/reset_laboratory.sql

"${plantbridge_project_dir}/scripts/run-nifi-laboratory-primary.sh"
"${plantbridge_project_dir}/scripts/verify-nifi-laboratory-initial.sh"
"${plantbridge_project_dir}/scripts/replay-nifi-laboratory.sh"
"${plantbridge_project_dir}/scripts/verify-nifi-laboratory.sh"
"${plantbridge_project_dir}/scripts/run-nifi-laboratory-primary.sh"
"${plantbridge_project_dir}/scripts/verify-nifi-laboratory-duplicate.sh"
