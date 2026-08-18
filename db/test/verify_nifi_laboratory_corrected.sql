DO $$
DECLARE
    v_run audit.load_run%ROWTYPE;
    v_count integer;
    v_status text;
BEGIN
    SELECT count(*) INTO v_count FROM ods.laboratory_result;
    IF v_count <> 2 THEN
        RAISE EXCEPTION 'Expected two ODS laboratory results after NiFi replay, got %', v_count;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM ods.laboratory_result
        WHERE lab_result_id = 'LAB-003'
          AND result_version = 2
          AND result_status = 'FAIL'
    ) THEN
        RAISE EXCEPTION 'NiFi corrected LAB-003 version is missing';
    END IF;

    SELECT * INTO v_run
    FROM audit.load_run
    WHERE source_name = 'LAB_LIMS_NIFI'
      AND source_object = 'lab_results_corrected.csv'
    ORDER BY started_at DESC
    LIMIT 1;

    IF NOT FOUND
       OR v_run.accepted_count <> 1
       OR v_run.rejected_count <> 0
       OR v_run.duplicate_count <> 0 THEN
        RAISE EXCEPTION 'Unexpected NiFi corrected-file accounting';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM rejected.replay_history h
        JOIN rejected.record r ON r.rejected_record_id = h.rejected_record_id
        JOIN audit.load_run l ON l.run_id = h.replay_run_id
        WHERE r.source_name = 'LAB_LIMS_NIFI'
          AND r.source_record_id = 'LAB-003'
          AND r.replay_status = 'REPLAYED'
          AND h.outcome = 'ACCEPTED'
          AND l.source_name = 'LAB_LIMS_NIFI'
          AND l.source_object = 'lab_results_corrected.csv'
    ) THEN
        RAISE EXCEPTION 'Accepted NiFi LAB-003 replay history is missing';
    END IF;

    SELECT laboratory_overall_status INTO v_status
    FROM dm.dm_batch_investigation
    WHERE batch_id = 'BATCH-003';

    IF v_status <> 'FAIL' THEN
        RAISE EXCEPTION 'BATCH-003 expected laboratory FAIL after NiFi replay, got %', v_status;
    END IF;
END;
$$;

SELECT
    batch_id,
    laboratory_overall_status,
    process_deviation_count
FROM dm.dm_batch_investigation
WHERE batch_id = 'BATCH-003';
