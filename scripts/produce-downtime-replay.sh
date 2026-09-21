#!/usr/bin/env bash
set -euo pipefail

plantbridge_project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

docker compose --project-directory "${plantbridge_project_dir}" exec -T kafka \
  /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server kafka:19092 \
  --topic plantbridge.downtime.replay \
  --reader-property parse.key=true \
  --reader-property 'key.separator=|' \
  < "${plantbridge_project_dir}/data/downtime/replay.txt"
