#!/usr/bin/env bash
set -euo pipefail

plantbridge_project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

docker compose --project-directory "${plantbridge_project_dir}" up \
  --detach --wait postgres kafka

"${plantbridge_project_dir}/scripts/apply-downtime-db.sh"

docker compose --project-directory "${plantbridge_project_dir}" exec -T postgres psql \
  --username plantbridge \
  --dbname plantbridge \
  --set ON_ERROR_STOP=1 \
  --file /db/test/reset_downtime.sql

"${plantbridge_project_dir}/scripts/reset-downtime-kafka.sh"
"${plantbridge_project_dir}/scripts/produce-downtime-events.sh"
python3 "${plantbridge_project_dir}/scripts/downtime_kafka_adapter.py" \
  --topic plantbridge.downtime.events --max-messages 6

docker compose --project-directory "${plantbridge_project_dir}" exec -T postgres psql \
  --username plantbridge \
  --dbname plantbridge \
  --set ON_ERROR_STOP=1 \
  --file /db/test/verify_downtime_initial.sql

python3 "${plantbridge_project_dir}/scripts/verify-downtime-dlq.py"

docker compose --project-directory "${plantbridge_project_dir}" exec -T postgres psql \
  --username plantbridge \
  --dbname plantbridge \
  --set ON_ERROR_STOP=1 \
  --file /db/test/test_downtime_order.sql

"${plantbridge_project_dir}/scripts/produce-downtime-replay.sh"
python3 "${plantbridge_project_dir}/scripts/downtime_kafka_adapter.py" \
  --topic plantbridge.downtime.replay --max-messages 2

docker compose --project-directory "${plantbridge_project_dir}" exec -T postgres psql \
  --username plantbridge \
  --dbname plantbridge \
  --set ON_ERROR_STOP=1 \
  --file /db/test/verify_downtime_replay.sql
