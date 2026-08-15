DO $$
DECLARE
    v_run audit.load_run%ROWTYPE;
    v_count integer;
BEGIN
    SELECT * INTO v_run
    FROM audit.load_run
    WHERE entity_type = 'laboratory'
      AND source_object = 'lab_results_corrected.csv'
    ORDER BY started_at DESC
    LIMIT 1;

    IF NOT FOUND
       OR v_run.received_count <> 1
       OR v_run.accepted_count <> 0
       OR v_run.rejected_count <> 0
       OR v_run.duplicate_count <> 1 THEN
        RAISE EXCEPTION 'Corrected file replay was not classified as duplicate';
    END IF;

    SELECT count(*) INTO v_count FROM ods.laboratory_result;
    IF v_count <> 2 THEN
        RAISE EXCEPTION 'Duplicate replay changed ODS count to %', v_count;
    END IF;

    SELECT count(*) INTO v_count
    FROM rejected.replay_history h
    JOIN rejected.record r ON r.rejected_record_id = h.rejected_record_id
    WHERE r.record_type = 'LABORATORY';

    IF v_count <> 1 THEN
        RAISE EXCEPTION 'Duplicate replay changed replay history count to %', v_count;
    END IF;
END;
$$;
