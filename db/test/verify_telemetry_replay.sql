DO $$
DECLARE
    v_run audit.load_run%ROWTYPE;
    v_count integer;
BEGIN
    SELECT * INTO v_run
    FROM audit.load_run
    WHERE source_name = 'EXTRUDER_SCADA'
      AND entity_type = 'telemetry'
    ORDER BY started_at DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Telemetry replay load run is missing';
    END IF;

    IF v_run.received_count <> 24
       OR v_run.accepted_count <> 0
       OR v_run.rejected_count <> 0
       OR v_run.duplicate_count <> 24 THEN
        RAISE EXCEPTION 'Unexpected replay counts: received %, accepted %, rejected %, duplicate %',
            v_run.received_count,
            v_run.accepted_count,
            v_run.rejected_count,
            v_run.duplicate_count;
    END IF;

    SELECT count(*) INTO v_count FROM ods.telemetry_measurement;
    IF v_count <> 24 THEN
        RAISE EXCEPTION 'Replay changed ODS telemetry count to %', v_count;
    END IF;
END;
$$;

SELECT source_object, received_count, accepted_count, rejected_count, duplicate_count
FROM audit.load_run
WHERE entity_type = 'telemetry'
ORDER BY started_at;
