#!/usr/bin/env bash
set -euo pipefail

plantbridge_project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for plantbridge_topic in \
  plantbridge.downtime.events \
  plantbridge.downtime.dlq \
  plantbridge.downtime.replay
do
  docker compose --project-directory "${plantbridge_project_dir}" exec -T kafka \
    /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server kafka:19092 \
    --delete \
    --if-exists \
    --topic "${plantbridge_topic}"
done

for plantbridge_attempt in $(seq 1 30)
do
  if "${plantbridge_project_dir}/scripts/bootstrap-kafka.sh" >/dev/null 2>&1
  then
    "${plantbridge_project_dir}/scripts/bootstrap-kafka.sh"
    exit 0
  fi
  sleep 1
done

echo "Downtime topics were not recreated after reset" >&2
exit 1
