#!/usr/bin/env bash
set -euo pipefail

plantbridge_project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

docker compose --project-directory "${plantbridge_project_dir}" up \
  --detach --wait postgres

"${plantbridge_project_dir}/scripts/apply-downtime-db.sh"

for plantbridge_sql_file in \
  reset_downtime.sql \
  load_downtime_fixture.sql \
  verify_downtime_initial.sql \
  test_downtime_order.sql \
  replay_downtime_fixture.sql \
  verify_downtime_replay.sql
do
  docker compose --project-directory "${plantbridge_project_dir}" exec -T postgres psql \
    --username plantbridge \
    --dbname plantbridge \
    --set ON_ERROR_STOP=1 \
    --file "/db/test/${plantbridge_sql_file}"
done
