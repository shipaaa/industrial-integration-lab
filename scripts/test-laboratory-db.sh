#!/usr/bin/env bash
set -euo pipefail

plantbridge_project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${plantbridge_project_dir}/scripts/apply-laboratory-db.sh"

docker compose --project-directory "${plantbridge_project_dir}" exec -T postgres psql \
  --username plantbridge \
  --dbname plantbridge \
  --set ON_ERROR_STOP=1 \
  --file /db/test/reset_laboratory.sql

"${plantbridge_project_dir}/scripts/load-laboratory.sh" \
  "${plantbridge_project_dir}/data/laboratory/lab_results_valid.csv"
"${plantbridge_project_dir}/scripts/load-laboratory.sh" \
  "${plantbridge_project_dir}/data/laboratory/lab_results_initial.csv"

docker compose --project-directory "${plantbridge_project_dir}" exec -T postgres psql \
  --username plantbridge \
  --dbname plantbridge \
  --set ON_ERROR_STOP=1 \
  --file /db/test/verify_laboratory_initial.sql

"${plantbridge_project_dir}/scripts/replay-laboratory.sh"
"${plantbridge_project_dir}/scripts/verify-laboratory.sh"

"${plantbridge_project_dir}/scripts/load-laboratory.sh" \
  "${plantbridge_project_dir}/data/laboratory/lab_results_corrected.csv"

docker compose --project-directory "${plantbridge_project_dir}" exec -T postgres psql \
  --username plantbridge \
  --dbname plantbridge \
  --set ON_ERROR_STOP=1 \
  --file /db/test/verify_laboratory_duplicate.sql

docker compose --project-directory "${plantbridge_project_dir}" exec -T postgres psql \
  --username plantbridge \
  --dbname plantbridge \
  --set ON_ERROR_STOP=1 \
  --file /db/test/test_laboratory_stale.sql
