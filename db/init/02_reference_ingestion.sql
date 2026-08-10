CREATE OR REPLACE FUNCTION ods.load_reference_document(
    p_entity_type text,
    p_document jsonb,
    p_source_object text
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    v_run_id uuid := gen_random_uuid();
    v_record jsonb;
    v_record_id text;
    v_correlation_id uuid;
    v_checksum char(64);
    v_stg_record_id bigint;
    v_received integer := 0;
    v_accepted integer := 0;
    v_rejected integer := 0;
    v_duplicate integer := 0;
    v_is_duplicate boolean;
    v_range jsonb;
BEGIN
    IF p_entity_type NOT IN ('plants', 'lines', 'equipment', 'materials', 'batches') THEN
        RAISE EXCEPTION 'Unsupported reference entity type: %', p_entity_type;
    END IF;

    IF p_document->>'schema_version' <> '1.0'
       OR jsonb_typeof(p_document->'records') <> 'array' THEN
        RAISE EXCEPTION 'Invalid reference envelope for %', p_source_object;
    END IF;

    INSERT INTO audit.load_run (
        run_id, source_name, source_object, entity_type, status
    ) VALUES (
        v_run_id,
        COALESCE(NULLIF(p_document->>'source_system', ''), 'UNKNOWN'),
        p_source_object,
        p_entity_type,
        'RUNNING'
    );

    FOR v_record IN SELECT value FROM jsonb_array_elements(p_document->'records')
    LOOP
        v_received := v_received + 1;
        v_correlation_id := gen_random_uuid();
        v_checksum := encode(digest(v_record::text, 'sha256'), 'hex');
        v_record_id := CASE p_entity_type
            WHEN 'plants' THEN v_record->>'plant_id'
            WHEN 'lines' THEN v_record->>'line_id'
            WHEN 'equipment' THEN v_record->>'equipment_id'
            WHEN 'materials' THEN v_record->>'material_id'
            WHEN 'batches' THEN v_record->>'batch_id'
        END;

        INSERT INTO stg.reference_record (
            run_id, source_name, source_object, entity_type, source_record_id,
            payload, correlation_id, checksum, processing_status
        ) VALUES (
            v_run_id,
            COALESCE(NULLIF(p_document->>'source_system', ''), 'UNKNOWN'),
            p_source_object,
            p_entity_type,
            v_record_id,
            v_record,
            v_correlation_id,
            v_checksum,
            'RECEIVED'
        ) RETURNING stg_record_id INTO v_stg_record_id;

        BEGIN
            IF COALESCE(v_record_id, '') = '' THEN
                RAISE EXCEPTION USING
                    ERRCODE = '23502',
                    MESSAGE = format('Missing business key for entity %s', p_entity_type);
            END IF;

            v_is_duplicate := CASE p_entity_type
                WHEN 'plants' THEN EXISTS (
                    SELECT 1 FROM ods.plant WHERE plant_id = v_record_id AND source_checksum = v_checksum
                )
                WHEN 'lines' THEN EXISTS (
                    SELECT 1 FROM ods.production_line WHERE line_id = v_record_id AND source_checksum = v_checksum
                )
                WHEN 'equipment' THEN EXISTS (
                    SELECT 1 FROM ods.equipment WHERE equipment_id = v_record_id AND source_checksum = v_checksum
                )
                WHEN 'materials' THEN EXISTS (
                    SELECT 1 FROM ods.material WHERE material_id = v_record_id AND source_checksum = v_checksum
                )
                WHEN 'batches' THEN EXISTS (
                    SELECT 1 FROM ods.production_batch WHERE batch_id = v_record_id AND source_checksum = v_checksum
                )
            END;

            IF v_is_duplicate THEN
                UPDATE stg.reference_record
                SET processing_status = 'DUPLICATE'
                WHERE stg_record_id = v_stg_record_id;

                INSERT INTO audit.record_processing (
                    run_id, record_type, stg_reference_record_id,
                    correlation_id, outcome, detail
                ) VALUES (
                    v_run_id, 'REFERENCE', v_stg_record_id, v_correlation_id,
                    'DUPLICATE', 'Business key and source checksum already loaded'
                );
                v_duplicate := v_duplicate + 1;
                CONTINUE;
            END IF;

            CASE p_entity_type
                WHEN 'plants' THEN
                    INSERT INTO ods.plant (
                        plant_id, plant_name, timezone, source_checksum
                    ) VALUES (
                        v_record_id,
                        v_record->>'plant_name',
                        v_record->>'timezone',
                        v_checksum
                    )
                    ON CONFLICT (plant_id) DO UPDATE SET
                        plant_name = EXCLUDED.plant_name,
                        timezone = EXCLUDED.timezone,
                        source_checksum = EXCLUDED.source_checksum,
                        updated_at = clock_timestamp();

                WHEN 'lines' THEN
                    INSERT INTO ods.production_line (
                        line_id, plant_id, line_name, source_checksum
                    ) VALUES (
                        v_record_id,
                        v_record->>'plant_id',
                        v_record->>'line_name',
                        v_checksum
                    )
                    ON CONFLICT (line_id) DO UPDATE SET
                        plant_id = EXCLUDED.plant_id,
                        line_name = EXCLUDED.line_name,
                        source_checksum = EXCLUDED.source_checksum,
                        updated_at = clock_timestamp();

                WHEN 'equipment' THEN
                    INSERT INTO ods.equipment (
                        equipment_id, line_id, equipment_name,
                        equipment_type, source_checksum
                    ) VALUES (
                        v_record_id,
                        v_record->>'line_id',
                        v_record->>'equipment_name',
                        v_record->>'equipment_type',
                        v_checksum
                    )
                    ON CONFLICT (equipment_id) DO UPDATE SET
                        line_id = EXCLUDED.line_id,
                        equipment_name = EXCLUDED.equipment_name,
                        equipment_type = EXCLUDED.equipment_type,
                        source_checksum = EXCLUDED.source_checksum,
                        updated_at = clock_timestamp();

                WHEN 'materials' THEN
                    IF jsonb_typeof(v_record->'parameter_ranges') <> 'array'
                       OR jsonb_array_length(v_record->'parameter_ranges') = 0 THEN
                        RAISE EXCEPTION 'Material % has no parameter ranges', v_record_id;
                    END IF;

                    INSERT INTO ods.material (
                        material_id, material_name, grade, source_checksum
                    ) VALUES (
                        v_record_id,
                        v_record->>'material_name',
                        v_record->>'grade',
                        v_checksum
                    )
                    ON CONFLICT (material_id) DO UPDATE SET
                        material_name = EXCLUDED.material_name,
                        grade = EXCLUDED.grade,
                        source_checksum = EXCLUDED.source_checksum,
                        updated_at = clock_timestamp();

                    DELETE FROM ods.material_parameter_range
                    WHERE material_id = v_record_id;

                    FOR v_range IN SELECT value FROM jsonb_array_elements(v_record->'parameter_ranges')
                    LOOP
                        INSERT INTO ods.material_parameter_range (
                            material_id, parameter_code, unit, min_value, max_value
                        ) VALUES (
                            v_record_id,
                            v_range->>'parameter_code',
                            v_range->>'unit',
                            (v_range->>'min_value')::numeric,
                            (v_range->>'max_value')::numeric
                        );
                    END LOOP;

                WHEN 'batches' THEN
                    IF (v_record->>'ended_at')::timestamptz <= (v_record->>'started_at')::timestamptz THEN
                        RAISE EXCEPTION 'Batch % end must be after start', v_record_id;
                    END IF;

                    INSERT INTO ods.production_batch (
                        batch_id, material_id, line_id, equipment_id,
                        started_at, ended_at, status, source_checksum
                    ) VALUES (
                        v_record_id,
                        v_record->>'material_id',
                        v_record->>'line_id',
                        v_record->>'equipment_id',
                        (v_record->>'started_at')::timestamptz,
                        (v_record->>'ended_at')::timestamptz,
                        v_record->>'status',
                        v_checksum
                    )
                    ON CONFLICT (batch_id) DO UPDATE SET
                        material_id = EXCLUDED.material_id,
                        line_id = EXCLUDED.line_id,
                        equipment_id = EXCLUDED.equipment_id,
                        started_at = EXCLUDED.started_at,
                        ended_at = EXCLUDED.ended_at,
                        status = EXCLUDED.status,
                        source_checksum = EXCLUDED.source_checksum,
                        updated_at = clock_timestamp();
            END CASE;

            UPDATE stg.reference_record
            SET processing_status = 'ACCEPTED'
            WHERE stg_record_id = v_stg_record_id;

            INSERT INTO audit.record_processing (
                run_id, record_type, stg_reference_record_id,
                correlation_id, outcome, detail
            ) VALUES (
                v_run_id, 'REFERENCE', v_stg_record_id, v_correlation_id,
                'ACCEPTED', 'Validated and upserted into ODS'
            );
            v_accepted := v_accepted + 1;

        EXCEPTION WHEN OTHERS THEN
            UPDATE stg.reference_record
            SET processing_status = 'REJECTED',
                error_code = SQLSTATE,
                error_text = SQLERRM
            WHERE stg_record_id = v_stg_record_id;

            INSERT INTO rejected.record (
                run_id, record_type, stg_reference_record_id,
                source_name, source_object,
                entity_type, source_record_id, payload, correlation_id,
                error_code, error_text
            ) VALUES (
                v_run_id,
                'REFERENCE',
                v_stg_record_id,
                COALESCE(NULLIF(p_document->>'source_system', ''), 'UNKNOWN'),
                p_source_object,
                p_entity_type,
                v_record_id,
                v_record,
                v_correlation_id,
                SQLSTATE,
                SQLERRM
            );

            INSERT INTO audit.record_processing (
                run_id, record_type, stg_reference_record_id,
                correlation_id, outcome, detail
            ) VALUES (
                v_run_id, 'REFERENCE', v_stg_record_id, v_correlation_id,
                'REJECTED', SQLSTATE || ': ' || SQLERRM
            );
            v_rejected := v_rejected + 1;
        END;
    END LOOP;

    UPDATE audit.load_run
    SET finished_at = clock_timestamp(),
        status = CASE WHEN v_rejected > 0
            THEN 'COMPLETED_WITH_REJECTIONS'
            ELSE 'COMPLETED'
        END,
        received_count = v_received,
        accepted_count = v_accepted,
        rejected_count = v_rejected,
        duplicate_count = v_duplicate
    WHERE run_id = v_run_id;

    RETURN v_run_id;
EXCEPTION WHEN OTHERS THEN
    UPDATE audit.load_run
    SET finished_at = clock_timestamp(),
        status = 'FAILED',
        error_text = SQLSTATE || ': ' || SQLERRM
    WHERE run_id = v_run_id;
    RAISE;
END;
$$;
