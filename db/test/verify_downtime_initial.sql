\set ON_ERROR_STOP on

DO $$
DECLARE
    v_count bigint;
    v_minutes numeric;
BEGIN
    SELECT count(*) INTO v_count FROM ods.downtime_event;
    IF v_count <> 4 THEN
        RAISE EXCEPTION 'Expected 4 accepted downtime events, got %', v_count;
    END IF;

    SELECT count(*) INTO v_count FROM ods.downtime_incident WHERE status = 'COMPLETED';
    IF v_count <> 2 THEN
        RAISE EXCEPTION 'Expected 2 completed downtime incidents, got %', v_count;
    END IF;

    SELECT downtime_minutes INTO v_minutes
    FROM dm.dm_batch_investigation WHERE batch_id = 'BATCH-003';
    IF v_minutes <> 7 THEN
        RAISE EXCEPTION 'Expected BATCH-003 downtime_minutes=7, got %', v_minutes;
    END IF;

    SELECT downtime_minutes INTO v_minutes
    FROM dm.dm_batch_investigation WHERE batch_id = 'BATCH-002';
    IF v_minutes <> 10 THEN
        RAISE EXCEPTION 'Expected BATCH-002 downtime_minutes=10, got %', v_minutes;
    END IF;

    SELECT count(*) INTO v_count
    FROM audit.record_processing
    WHERE record_type = 'DOWNTIME' AND outcome = 'DUPLICATE';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'Expected 1 audited duplicate, got %', v_count;
    END IF;

    SELECT count(*) INTO v_count
    FROM rejected.record
    WHERE record_type = 'DOWNTIME'
      AND source_record_id = 'EVT-DT-INVALID-START'
      AND replay_status = 'PENDING'
      AND error_text LIKE 'Unknown downtime reason_code:%';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'Expected one pending unknown-reason rejection, got %', v_count;
    END IF;

    SELECT count(*) INTO v_count
    FROM control.reconciliation_result reconciliation
    JOIN audit.load_run run USING (run_id)
    WHERE run.entity_type = 'downtime_event'
      AND reconciliation.status = 'MATCHED';
    IF v_count <> 6 THEN
        RAISE EXCEPTION 'Expected 6 matched downtime reconciliations, got %', v_count;
    END IF;
END;
$$;
