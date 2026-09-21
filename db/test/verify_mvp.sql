\set ON_ERROR_STOP on

DO $$
DECLARE
    v_count bigint;
    v_text text;
    v_minutes numeric;
BEGIN
    SELECT count(*) INTO v_count FROM ods.plant;
    IF v_count <> 1 THEN RAISE EXCEPTION 'MVP: expected 1 plant, got %', v_count; END IF;
    SELECT count(*) INTO v_count FROM ods.production_line;
    IF v_count <> 1 THEN RAISE EXCEPTION 'MVP: expected 1 line, got %', v_count; END IF;
    SELECT count(*) INTO v_count FROM ods.equipment;
    IF v_count <> 1 THEN RAISE EXCEPTION 'MVP: expected 1 equipment, got %', v_count; END IF;
    SELECT count(*) INTO v_count FROM ods.material;
    IF v_count <> 2 THEN RAISE EXCEPTION 'MVP: expected 2 materials, got %', v_count; END IF;
    SELECT count(*) INTO v_count FROM ods.production_batch;
    IF v_count <> 3 THEN RAISE EXCEPTION 'MVP: expected 3 batches, got %', v_count; END IF;

    SELECT count(*) INTO v_count FROM ods.telemetry_measurement;
    IF v_count <> 24 THEN RAISE EXCEPTION 'MVP: expected 24 telemetry measurements, got %', v_count; END IF;
    SELECT watermark_record_id INTO v_text
    FROM control.watermark WHERE source_name = 'EXTRUDER_SCADA';
    IF v_text IS DISTINCT FROM 'TEL-0024' THEN
        RAISE EXCEPTION 'MVP: expected telemetry watermark TEL-0024, got %', v_text;
    END IF;

    SELECT laboratory_overall_status INTO v_text
    FROM dm.dm_batch_investigation WHERE batch_id = 'BATCH-003';
    IF v_text IS DISTINCT FROM 'FAIL' THEN
        RAISE EXCEPTION 'MVP: expected BATCH-003 laboratory status FAIL, got %', v_text;
    END IF;

    SELECT count(*) INTO v_count
    FROM dm.dm_batch_process_deviations
    WHERE batch_id = 'BATCH-003'
      AND parameter_code = 'melt_temperature_c';
    IF v_count < 1 THEN
        RAISE EXCEPTION 'MVP: BATCH-003 temperature deviation is missing';
    END IF;

    SELECT downtime_minutes INTO v_minutes
    FROM dm.dm_batch_investigation WHERE batch_id = 'BATCH-003';
    IF v_minutes <> 7 THEN
        RAISE EXCEPTION 'MVP: expected BATCH-003 downtime_minutes=7, got %', v_minutes;
    END IF;

    SELECT count(*) INTO v_count FROM ods.laboratory_result;
    IF v_count <> 2 THEN RAISE EXCEPTION 'MVP: laboratory ODS grew after duplicate replay: %', v_count; END IF;
    SELECT count(*) INTO v_count FROM ods.downtime_event;
    IF v_count <> 6 THEN RAISE EXCEPTION 'MVP: downtime ODS grew after duplicate delivery: %', v_count; END IF;

    SELECT count(*) INTO v_count
    FROM audit.record_processing
    WHERE record_type = 'TELEMETRY' AND outcome = 'DUPLICATE';
    IF v_count < 24 THEN RAISE EXCEPTION 'MVP: expected at least 24 telemetry duplicate outcomes, got %', v_count; END IF;
    SELECT count(*) INTO v_count
    FROM audit.record_processing
    WHERE record_type = 'LABORATORY' AND outcome = 'DUPLICATE';
    IF v_count < 2 THEN RAISE EXCEPTION 'MVP: expected at least 2 laboratory duplicate outcomes, got %', v_count; END IF;
    SELECT count(*) INTO v_count
    FROM audit.record_processing
    WHERE record_type = 'DOWNTIME' AND outcome = 'DUPLICATE';
    IF v_count <> 1 THEN RAISE EXCEPTION 'MVP: expected 1 downtime duplicate outcome, got %', v_count; END IF;

    SELECT count(*) INTO v_count
    FROM rejected.replay_history history
    JOIN rejected.record rejected USING (rejected_record_id)
    WHERE rejected.record_type IN ('LABORATORY', 'DOWNTIME')
      AND history.outcome = 'ACCEPTED'
      AND rejected.replay_status = 'REPLAYED';
    IF v_count <> 2 THEN
        RAISE EXCEPTION 'MVP: expected accepted replay links for laboratory and downtime, got %', v_count;
    END IF;

    SELECT count(*) INTO v_count
    FROM control.reconciliation_result
    WHERE status <> 'MATCHED';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'MVP: expected all reconciliation results MATCHED, got % failures', v_count;
    END IF;
END;
$$;

SELECT
    batch_id,
    laboratory_overall_status,
    process_deviation_count,
    downtime_minutes
FROM dm.dm_batch_investigation
WHERE batch_id = 'BATCH-003';

SELECT
    (SELECT count(*) FROM ods.telemetry_measurement) AS telemetry_measurements,
    (SELECT watermark_record_id FROM control.watermark WHERE source_name = 'EXTRUDER_SCADA') AS telemetry_watermark,
    (SELECT count(*) FROM ods.laboratory_result) AS laboratory_results,
    (SELECT count(*) FROM ods.downtime_event) AS downtime_events,
    (SELECT count(*) FROM control.reconciliation_result WHERE status <> 'MATCHED') AS reconciliation_failures;
