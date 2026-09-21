\set ON_ERROR_STOP on

DO $$
DECLARE
    v_count bigint;
BEGIN
    SELECT count(*) INTO v_count
    FROM stg.downtime_event_record
    WHERE kafka_timestamp IS NULL;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'Expected every STG downtime record to retain Kafka timestamp, missing %', v_count;
    END IF;

    SELECT count(*) INTO v_count
    FROM ods.downtime_event
    WHERE source_timestamp IS NULL;
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'Expected every accepted downtime event to retain Kafka timestamp, missing %', v_count;
    END IF;

    SELECT count(*) INTO v_count
    FROM stg.downtime_event_record
    WHERE topic_name = 'plantbridge.downtime.events';
    IF v_count <> 6 THEN
        RAISE EXCEPTION 'Expected 6 primary deliveries, got %', v_count;
    END IF;

    SELECT count(*) INTO v_count
    FROM stg.downtime_event_record
    WHERE topic_name = 'plantbridge.downtime.replay';
    IF v_count <> 2 THEN
        RAISE EXCEPTION 'Expected 2 replay deliveries, got %', v_count;
    END IF;

    SELECT count(*) INTO v_count
    FROM control.reconciliation_result reconciliation
    JOIN audit.load_run run USING (run_id)
    WHERE run.entity_type = 'downtime_event'
      AND reconciliation.status <> 'MATCHED';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'Expected all downtime reconciliations MATCHED, got % failures', v_count;
    END IF;
END;
$$;
