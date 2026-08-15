SELECT ods.load_laboratory_file(
    jsonb_build_array(jsonb_build_object(
        'row_number', 2,
        'lab_result_id', 'LAB-003',
        'result_version', '1',
        'batch_id', 'BATCH-003',
        'test_code', 'MELT_FLOW_INDEX',
        'test_name', 'Melt Flow Index',
        'result_value', '18.2',
        'unit', 'g/10min',
        'min_limit', '10.0',
        'max_limit', '15.0',
        'result_status', 'FAIL',
        'tested_at', '2026-07-15T13:10:00Z'
    )),
    'LAB_LIMS',
    'lab_results_stale.csv',
    repeat('a', 64)
);

DO $$
DECLARE
    v_run audit.load_run%ROWTYPE;
BEGIN
    SELECT * INTO v_run
    FROM audit.load_run
    WHERE entity_type = 'laboratory'
      AND source_object = 'lab_results_stale.csv'
    ORDER BY started_at DESC
    LIMIT 1;

    IF NOT FOUND
       OR v_run.received_count <> 1
       OR v_run.accepted_count <> 0
       OR v_run.rejected_count <> 0
       OR v_run.duplicate_count <> 1 THEN
        RAISE EXCEPTION 'Stale laboratory version was not safely ignored';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM ods.laboratory_result
        WHERE lab_result_id = 'LAB-003'
          AND result_version = 2
          AND result_status = 'FAIL'
    ) THEN
        RAISE EXCEPTION 'Stale version overwrote current LAB-003';
    END IF;
END;
$$;
