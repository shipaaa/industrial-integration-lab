DELETE FROM rejected.replay_history
WHERE rejected_record_id IN (
    SELECT rejected_record_id
    FROM rejected.record
    WHERE record_type = 'LABORATORY'
);

DELETE FROM rejected.record
WHERE record_type = 'LABORATORY';

DELETE FROM audit.record_processing
WHERE record_type = 'LABORATORY';

DELETE FROM control.reconciliation_result
WHERE run_id IN (
    SELECT run_id
    FROM audit.load_run
    WHERE entity_type = 'laboratory'
);

DELETE FROM stg.laboratory_record;

DELETE FROM audit.load_run
WHERE entity_type = 'laboratory';

DELETE FROM ods.laboratory_result;
