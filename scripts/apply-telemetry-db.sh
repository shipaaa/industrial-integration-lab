#!/usr/bin/env bash
set -euo pipefail

docker compose exec -T postgres psql \
  --username plantbridge \
  --dbname plantbridge \
  --set ON_ERROR_STOP=1 \
  --file /docker-entrypoint-initdb.d/05_telemetry_ingestion.sql

docker compose exec -T postgres psql \
  --username plantbridge \
  --dbname plantbridge \
  --set ON_ERROR_STOP=1 \
  --file /docker-entrypoint-initdb.d/02_reference_ingestion.sql
