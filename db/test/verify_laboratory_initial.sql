DO $$
DECLARE
    v_run audit.load_run%ROWTYPE;
    v_count integer;
    v_status text;
BEGIN
    SELECT count(*) INTO v_count FROM ods.laboratory_result;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'Expected one accepted laboratory result, got %', v_count;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM ods.laboratory_result
        WHERE lab_result_id = 'LAB-001'
          AND batch_id = 'BATCH-001'
          AND result_version = 1
          AND result_status = 'PASS'
    ) THEN
        RAISE EXCEPTION 'Valid BATCH-001 laboratory result is missing';
    END IF;

    IF EXISTS (
        SELECT 1 FROM ods.laboratory_result WHERE lab_result_id = 'LAB-003'
    ) THEN
        RAISE EXCEPTION 'Invalid LAB-003 result reached ODS';
    END IF;

    SELECT * INTO v_run
    FROM audit.load_run
    WHERE entity_type = 'laboratory'
      AND source_object = 'lab_results_initial.csv'
    ORDER BY started_at DESC
    LIMIT 1;

    IF NOT FOUND
       OR v_run.status <> 'COMPLETED_WITH_REJECTIONS'
       OR v_run.received_count <> 1
       OR v_run.accepted_count <> 0
       OR v_run.rejected_count <> 1
       OR v_run.duplicate_count <> 0 THEN
        RAISE EXCEPTION 'Unexpected initial laboratory run accounting';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM rejected.record
        WHERE record_type = 'LABORATORY'
          AND source_record_id = 'LAB-003'
          AND replay_status = 'PENDING'
          AND error_text LIKE '%does not agree%'
    ) THEN
        RAISE EXCEPTION 'Pending LAB-003 status mismatch rejection is missing';
    END IF;

    SELECT laboratory_overall_status INTO v_status
    FROM dm.dm_batch_investigation
    WHERE batch_id = 'BATCH-001';

    IF v_status <> 'PASS' THEN
        RAISE EXCEPTION 'BATCH-001 expected laboratory PASS, got %', v_status;
    END IF;

    SELECT laboratory_overall_status INTO v_status
    FROM dm.dm_batch_investigation
    WHERE batch_id = 'BATCH-003';

    IF v_status IS NOT NULL THEN
        RAISE EXCEPTION 'Rejected BATCH-003 result must not set DM status';
    END IF;

    SELECT count(*) INTO v_count
    FROM control.reconciliation_result r
    JOIN audit.load_run l ON l.run_id = r.run_id
    WHERE l.entity_type = 'laboratory'
      AND r.status <> 'MATCHED';

    IF v_count <> 0 THEN
        RAISE EXCEPTION 'Found % mismatched laboratory reconciliations', v_count;
    END IF;
END;
$$;
