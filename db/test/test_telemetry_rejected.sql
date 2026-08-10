SELECT ods.load_telemetry_page(
    jsonb_build_object(
        'records', jsonb_build_array(
            jsonb_build_object(
                'source_record_id', 'TEL-INVALID-EQUIPMENT',
                'batch_id', 'BATCH-003',
                'equipment_id', 'EXT-UNKNOWN',
                'parameter_code', 'melt_temperature_c',
                'value', 200.0,
                'unit', 'degC',
                'measured_at', '2026-07-15T11:00:00Z',
                'updated_at', '2026-07-16T14:00:00Z'
            )
        ),
        'record_count', 1,
        'has_more', false,
        'next_watermark', jsonb_build_object(
            'updated_at', '2026-07-16T14:00:00Z',
            'source_record_id', 'TEL-INVALID-EQUIPMENT'
        )
    ),
    'EXTRUDER_SCADA_INVALID_TEST',
    'telemetry invalid equipment integration test'
);

DO $$
DECLARE
    v_run audit.load_run%ROWTYPE;
    v_error_text text;
BEGIN
    SELECT * INTO v_run
    FROM audit.load_run
    WHERE source_name = 'EXTRUDER_SCADA_INVALID_TEST'
    ORDER BY started_at DESC
    LIMIT 1;

    IF v_run.received_count <> 1
       OR v_run.accepted_count <> 0
       OR v_run.rejected_count <> 1
       OR v_run.duplicate_count <> 0
       OR v_run.status <> 'COMPLETED_WITH_REJECTIONS' THEN
        RAISE EXCEPTION 'Invalid-equipment record was not rejected correctly';
    END IF;

    SELECT error_text INTO v_error_text
    FROM rejected.record
    WHERE run_id = v_run.run_id
      AND source_record_id = 'TEL-INVALID-EQUIPMENT';

    IF v_error_text NOT LIKE 'Equipment EXT-UNKNOWN does not match batch BATCH-003%' THEN
        RAISE EXCEPTION 'Unexpected rejection reason: %', v_error_text;
    END IF;
END;
$$;

SELECT source_record_id, error_code, error_text, replay_status
FROM rejected.record
WHERE source_name = 'EXTRUDER_SCADA_INVALID_TEST'
ORDER BY rejected_at DESC
LIMIT 1;
