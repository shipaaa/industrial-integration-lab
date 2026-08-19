DO $$
DECLARE
    v_run audit.load_run%ROWTYPE;
    v_count integer;
BEGIN
    SELECT count(*) INTO v_count FROM ods.laboratory_result;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'Expected one ODS laboratory result after NiFi primary load, got %', v_count;
    END IF;

    SELECT * INTO v_run
    FROM audit.load_run
    WHERE source_name = 'LAB_LIMS_NIFI'
      AND source_object = 'lab_results_valid.csv'
    ORDER BY started_at DESC
    LIMIT 1;

    IF NOT FOUND
       OR v_run.accepted_count <> 1
       OR v_run.rejected_count <> 0
       OR v_run.duplicate_count <> 0 THEN
        RAISE EXCEPTION 'Unexpected NiFi valid-file accounting';
    END IF;

    SELECT * INTO v_run
    FROM audit.load_run
    WHERE source_name = 'LAB_LIMS_NIFI'
      AND source_object = 'lab_results_initial.csv'
    ORDER BY started_at DESC
    LIMIT 1;

    IF NOT FOUND
       OR v_run.status <> 'COMPLETED_WITH_REJECTIONS'
       OR v_run.accepted_count <> 0
       OR v_run.rejected_count <> 1
       OR v_run.duplicate_count <> 0 THEN
        RAISE EXCEPTION 'Unexpected NiFi initial-file accounting';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM rejected.record
        WHERE record_type = 'LABORATORY'
          AND source_name = 'LAB_LIMS_NIFI'
          AND source_record_id = 'LAB-003'
          AND replay_status = 'PENDING'
    ) THEN
        RAISE EXCEPTION 'NiFi LAB-003 pending rejection is missing';
    END IF;

    SELECT count(*) INTO v_count
    FROM control.reconciliation_result r
    JOIN audit.load_run l ON l.run_id = r.run_id
    WHERE l.source_name = 'LAB_LIMS_NIFI'
      AND r.status <> 'MATCHED';

    IF v_count <> 0 THEN
        RAISE EXCEPTION 'Found % mismatched NiFi laboratory reconciliations', v_count;
    END IF;
END;
$$;
