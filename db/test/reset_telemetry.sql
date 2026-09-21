\set ON_ERROR_STOP on

DELETE FROM rejected.replay_history history
USING rejected.record rejected
WHERE history.rejected_record_id = rejected.rejected_record_id
  AND rejected.record_type = 'TELEMETRY';

DELETE FROM control.reconciliation_result reconciliation
USING audit.load_run run
WHERE reconciliation.run_id = run.run_id
  AND run.entity_type = 'telemetry';

DELETE FROM audit.record_processing
WHERE record_type = 'TELEMETRY';

DELETE FROM rejected.record
WHERE record_type = 'TELEMETRY';

DELETE FROM stg.telemetry_record;

DELETE FROM audit.load_run
WHERE entity_type = 'telemetry';

DELETE FROM control.watermark
WHERE source_name = 'EXTRUDER_SCADA';

DELETE FROM ods.telemetry_measurement;
