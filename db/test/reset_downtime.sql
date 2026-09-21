\set ON_ERROR_STOP on

DELETE FROM rejected.replay_history history
USING rejected.record rejected
WHERE history.rejected_record_id = rejected.rejected_record_id
  AND rejected.record_type = 'DOWNTIME';

DELETE FROM control.reconciliation_result reconciliation
USING audit.load_run run
WHERE reconciliation.run_id = run.run_id
  AND run.entity_type = 'downtime_event';

DELETE FROM audit.record_processing
WHERE record_type = 'DOWNTIME';

DELETE FROM rejected.record
WHERE record_type = 'DOWNTIME';

DELETE FROM stg.downtime_event_record;

DELETE FROM audit.load_run
WHERE entity_type = 'downtime_event';

DELETE FROM ods.downtime_incident;
DELETE FROM ods.downtime_event;
