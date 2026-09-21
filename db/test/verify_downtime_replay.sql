\set ON_ERROR_STOP on

DO $$
DECLARE
    v_count bigint;
    v_minutes numeric;
BEGIN
    SELECT count(*) INTO v_count FROM ods.downtime_event;
    IF v_count <> 6 THEN
        RAISE EXCEPTION 'Expected 6 accepted events after replay, got %', v_count;
    END IF;

    SELECT downtime_minutes INTO v_minutes
    FROM dm.dm_batch_investigation WHERE batch_id = 'BATCH-001';
    IF v_minutes <> 3 THEN
        RAISE EXCEPTION 'Expected BATCH-001 downtime_minutes=3, got %', v_minutes;
    END IF;

    SELECT count(*) INTO v_count
    FROM rejected.record
    WHERE record_type = 'DOWNTIME'
      AND source_record_id = 'EVT-DT-INVALID-START'
      AND replay_status = 'REPLAYED';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'Expected original downtime rejection to be REPLAYED, got %', v_count;
    END IF;

    SELECT count(*) INTO v_count
    FROM rejected.replay_history history
    JOIN rejected.record rejected USING (rejected_record_id)
    WHERE rejected.record_type = 'DOWNTIME'
      AND history.outcome = 'ACCEPTED';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'Expected one accepted downtime replay link, got %', v_count;
    END IF;
END;
$$;
