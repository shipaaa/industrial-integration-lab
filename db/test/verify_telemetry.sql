DO $$
DECLARE
    v_count integer;
    v_value numeric;
    v_min numeric;
    v_max numeric;
    v_watermark_value text;
    v_watermark_record_id text;
BEGIN
    SELECT count(*) INTO v_count FROM ods.telemetry_measurement;
    IF v_count <> 24 THEN
        RAISE EXCEPTION 'Expected 24 telemetry measurements, got %', v_count;
    END IF;

    SELECT count(*) INTO v_count
    FROM ods.telemetry_measurement
    WHERE is_deviation;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'Expected 1 process deviation, got %', v_count;
    END IF;

    SELECT measured_value, min_value, max_value
    INTO v_value, v_min, v_max
    FROM ods.telemetry_measurement
    WHERE source_record_id = 'TEL-0021'
      AND batch_id = 'BATCH-003'
      AND parameter_code = 'melt_temperature_c'
      AND is_deviation;

    IF NOT FOUND OR v_value <> 214 OR v_min <> 180 OR v_max <> 205 THEN
        RAISE EXCEPTION 'BATCH-003 temperature deviation is incorrect';
    END IF;

    SELECT process_deviation_count INTO v_count
    FROM dm.dm_batch_investigation
    WHERE batch_id = 'BATCH-003';
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'BATCH-003 dossier expected 1 deviation, got %', v_count;
    END IF;

    SELECT watermark_value, watermark_record_id
    INTO v_watermark_value, v_watermark_record_id
    FROM control.watermark
    WHERE source_name = 'EXTRUDER_SCADA';

    IF v_watermark_value::timestamptz <> '2026-07-16T13:00:05Z'::timestamptz
       OR v_watermark_record_id <> 'TEL-0024' THEN
        RAISE EXCEPTION 'Unexpected composite watermark: %, %',
            v_watermark_value, v_watermark_record_id;
    END IF;

    SELECT count(*) INTO v_count
    FROM control.reconciliation_result r
    JOIN audit.load_run l ON l.run_id = r.run_id
    WHERE l.entity_type = 'telemetry'
      AND r.status <> 'MATCHED';
    IF v_count <> 0 THEN
        RAISE EXCEPTION 'Found % mismatched telemetry reconciliations', v_count;
    END IF;
END;
$$;

SELECT *
FROM dm.dm_batch_process_deviations
ORDER BY batch_id, measured_at;

SELECT batch_id, material_id, process_deviation_count
FROM dm.dm_batch_investigation
WHERE batch_id = 'BATCH-003';
