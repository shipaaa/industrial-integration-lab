#!/usr/bin/env bash
set -euo pipefail

restore_nifi_schedule() {
  ./scripts/bootstrap-nifi.py >/dev/null 2>&1 || true
}
trap restore_nifi_schedule EXIT

plantbridge_runs_before="$(docker compose exec -T postgres psql \
  --username plantbridge \
  --dbname plantbridge \
  --tuples-only \
  --no-align \
  --command "
    SELECT count(*)
    FROM audit.load_run
    WHERE source_name = 'EXTRUDER_SCADA'
      AND source_object = 'GET /telemetry';
  " | tr -d '[:space:]')"

docker compose exec -T postgres psql \
  --username plantbridge \
  --dbname plantbridge \
  --set ON_ERROR_STOP=1 \
  --command "DELETE FROM control.watermark WHERE source_name = 'EXTRUDER_SCADA';" \
  >/dev/null

./scripts/bootstrap-nifi.py --run-once

plantbridge_expected_runs=$((plantbridge_runs_before + 3))
plantbridge_deadline=$((SECONDS + 120))
plantbridge_state=""

while (( SECONDS < plantbridge_deadline )); do
  plantbridge_state="$(docker compose exec -T postgres psql \
    --username plantbridge \
    --dbname plantbridge \
    --tuples-only \
    --no-align \
    --field-separator '|' \
    --command "
      SELECT
        (SELECT count(*) FROM ods.telemetry_measurement),
        COALESCE((
          SELECT watermark_record_id
          FROM control.watermark
          WHERE source_name = 'EXTRUDER_SCADA'
        ), ''),
        (SELECT count(*)
         FROM audit.load_run
         WHERE source_name = 'EXTRUDER_SCADA'
           AND source_object = 'GET /telemetry'),
        (SELECT count(*)
         FROM control.reconciliation_result r
         JOIN audit.load_run l ON l.run_id = r.run_id
         WHERE l.source_name = 'EXTRUDER_SCADA'
           AND l.source_object = 'GET /telemetry'
           AND r.status <> 'MATCHED');
    " | tr -d '[:space:]')"

  IFS='|' read -r \
    plantbridge_measurement_count \
    plantbridge_watermark_record_id \
    plantbridge_nifi_run_count \
    plantbridge_mismatch_count <<<"${plantbridge_state}"

  if [[ "${plantbridge_measurement_count}" == "24" \
      && "${plantbridge_watermark_record_id}" == "TEL-0024" \
      && "${plantbridge_nifi_run_count}" -ge "${plantbridge_expected_runs}" \
      && "${plantbridge_mismatch_count}" == "0" ]]; then
    echo "NiFi replay verified: three pages accounted for, ODS stayed at 24, watermark returned to TEL-0024."
    exit 0
  fi
  sleep 2
done

echo "NiFi replay verification timed out. Last state: ${plantbridge_state}" >&2
exit 1
