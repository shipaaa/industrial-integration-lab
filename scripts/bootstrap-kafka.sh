#!/usr/bin/env bash
set -euo pipefail

plantbridge_project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plantbridge_bootstrap_server="kafka:19092"

for plantbridge_topic in \
  plantbridge.downtime.events \
  plantbridge.downtime.dlq \
  plantbridge.downtime.replay
do
  docker compose --project-directory "${plantbridge_project_dir}" exec -T kafka \
    /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server "${plantbridge_bootstrap_server}" \
    --create \
    --if-not-exists \
    --topic "${plantbridge_topic}" \
    --partitions 1 \
    --replication-factor 1
done

docker compose --project-directory "${plantbridge_project_dir}" exec -T kafka \
  /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server "${plantbridge_bootstrap_server}" \
  --list
