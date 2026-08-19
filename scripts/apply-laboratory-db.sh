#!/usr/bin/env bash
set -euo pipefail

docker compose exec -T postgres psql \
  --username plantbridge \
  --dbname plantbridge \
  --set ON_ERROR_STOP=1 \
  --file /docker-entrypoint-initdb.d/06_laboratory_ingestion.sql

docker compose exec -T postgres psql \
  --username plantbridge \
  --dbname plantbridge \
  --set ON_ERROR_STOP=1 \
  --file /docker-entrypoint-initdb.d/07_nifi_laboratory_adapter.sql
