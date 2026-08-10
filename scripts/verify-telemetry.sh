#!/usr/bin/env bash
set -euo pipefail

docker compose exec -T postgres psql \
  --username plantbridge \
  --dbname plantbridge \
  --set ON_ERROR_STOP=1 \
  --file /db/test/verify_telemetry.sql
