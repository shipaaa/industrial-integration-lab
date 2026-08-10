#!/usr/bin/env bash
set -euo pipefail

./scripts/apply-telemetry-db.sh
./scripts/load-telemetry.sh
./scripts/verify-telemetry.sh
./scripts/load-telemetry.sh

docker compose exec -T postgres psql \
  --username plantbridge \
  --dbname plantbridge \
  --set ON_ERROR_STOP=1 \
  --file /db/test/verify_telemetry_replay.sql

docker compose exec -T postgres psql \
  --username plantbridge \
  --dbname plantbridge \
  --set ON_ERROR_STOP=1 \
  --file /db/test/test_telemetry_rejected.sql
