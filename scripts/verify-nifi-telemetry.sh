#!/usr/bin/env bash
set -euo pipefail

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
      && "${plantbridge_nifi_run_count}" -ge 1 \
      && "${plantbridge_mismatch_count}" == "0" ]]; then
    echo "NiFi telemetry flow verified: 24 measurements, watermark TEL-0024, ${plantbridge_nifi_run_count} NiFi load run(s)."
    exit 0
  fi
  sleep 2
done

echo "NiFi telemetry verification timed out. Last state: ${plantbridge_state}" >&2
exit 1
