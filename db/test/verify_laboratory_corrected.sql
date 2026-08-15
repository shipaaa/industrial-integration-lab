DO $$
DECLARE
    v_count integer;
    v_status text;
BEGIN
    SELECT count(*) INTO v_count FROM ods.laboratory_result;
    IF v_count <> 2 THEN
        RAISE EXCEPTION 'Expected two current laboratory results, got %', v_count;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM ods.laboratory_result
        WHERE lab_result_id = 'LAB-003'
          AND result_version = 2
          AND batch_id = 'BATCH-003'
          AND test_code = 'MELT_FLOW_INDEX'
          AND result_value = 18.2
          AND min_limit = 10.0
          AND max_limit = 15.0
          AND result_status = 'FAIL'
    ) THEN
        RAISE EXCEPTION 'Corrected LAB-003 version is missing from ODS';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM rejected.record
        WHERE record_type = 'LABORATORY'
          AND source_record_id = 'LAB-003'
          AND replay_status = 'REPLAYED'
    ) THEN
        RAISE EXCEPTION 'Original LAB-003 rejection was not closed by replay';
    END IF;

    SELECT count(*) INTO v_count
    FROM rejected.replay_history h
    JOIN rejected.record r ON r.rejected_record_id = h.rejected_record_id
    JOIN audit.load_run l ON l.run_id = h.replay_run_id
    WHERE r.record_type = 'LABORATORY'
      AND r.source_record_id = 'LAB-003'
      AND h.outcome = 'ACCEPTED'
      AND l.source_object = 'lab_results_corrected.csv';

    IF v_count <> 1 THEN
        RAISE EXCEPTION 'Expected one accepted LAB-003 replay history row, got %', v_count;
    END IF;

    SELECT laboratory_overall_status INTO v_status
    FROM dm.dm_batch_investigation
    WHERE batch_id = 'BATCH-003';

    IF v_status <> 'FAIL' THEN
        RAISE EXCEPTION 'BATCH-003 expected laboratory FAIL, got %', v_status;
    END IF;
END;
$$;

SELECT
    batch_id,
    laboratory_overall_status,
    process_deviation_count
FROM dm.dm_batch_investigation
WHERE batch_id IN ('BATCH-001', 'BATCH-003')
ORDER BY batch_id;
