CREATE TABLE IF NOT EXISTS stg.telemetry_record (
    stg_telemetry_record_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_id uuid NOT NULL REFERENCES audit.load_run(run_id),
    source_name text NOT NULL,
    source_object text NOT NULL,
    source_record_id text,
    payload jsonb NOT NULL,
    correlation_id uuid NOT NULL,
    checksum char(64) NOT NULL,
    ingestion_ts timestamptz NOT NULL DEFAULT clock_timestamp(),
    processing_status text NOT NULL
        CHECK (processing_status IN ('RECEIVED', 'ACCEPTED', 'REJECTED', 'DUPLICATE')),
    error_code text,
    error_text text
);

CREATE INDEX IF NOT EXISTS ix_stg_telemetry_record_correlation
    ON stg.telemetry_record(correlation_id);

CREATE TABLE IF NOT EXISTS ods.telemetry_measurement (
    source_record_id text PRIMARY KEY,
    batch_id text NOT NULL REFERENCES ods.production_batch(batch_id),
    equipment_id text NOT NULL REFERENCES ods.equipment(equipment_id),
    parameter_code text NOT NULL,
    measured_value numeric NOT NULL,
    unit text NOT NULL,
    measured_at timestamptz NOT NULL,
    source_updated_at timestamptz NOT NULL,
    min_value numeric NOT NULL,
    max_value numeric NOT NULL,
    is_deviation boolean NOT NULL,
    source_checksum char(64) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CHECK (min_value <= max_value)
);

CREATE INDEX IF NOT EXISTS ix_telemetry_measurement_batch_time
    ON ods.telemetry_measurement(batch_id, measured_at);

ALTER TABLE control.watermark
    ADD COLUMN IF NOT EXISTS watermark_record_id text;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'audit'
          AND table_name = 'record_processing'
          AND column_name = 'stg_record_id'
    ) THEN
        ALTER TABLE audit.record_processing
            RENAME COLUMN stg_record_id TO stg_reference_record_id;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'rejected'
          AND table_name = 'record'
          AND column_name = 'stg_record_id'
    ) THEN
        ALTER TABLE rejected.record
            RENAME COLUMN stg_record_id TO stg_reference_record_id;
    END IF;
END;
$$;

ALTER TABLE audit.record_processing
    ADD COLUMN IF NOT EXISTS record_type text,
    ADD COLUMN IF NOT EXISTS stg_telemetry_record_id bigint;

UPDATE audit.record_processing
SET record_type = 'REFERENCE'
WHERE record_type IS NULL;

ALTER TABLE audit.record_processing
    ALTER COLUMN record_type SET NOT NULL,
    ALTER COLUMN stg_reference_record_id DROP NOT NULL;

ALTER TABLE rejected.record
    ADD COLUMN IF NOT EXISTS record_type text,
    ADD COLUMN IF NOT EXISTS stg_telemetry_record_id bigint;

UPDATE rejected.record
SET record_type = 'REFERENCE'
WHERE record_type IS NULL;

ALTER TABLE rejected.record
    ALTER COLUMN record_type SET NOT NULL,
    ALTER COLUMN stg_reference_record_id DROP NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'ck_audit_record_processing_record_type'
          AND conrelid = 'audit.record_processing'::regclass
    ) THEN
        ALTER TABLE audit.record_processing
            ADD CONSTRAINT ck_audit_record_processing_record_type
            CHECK (record_type IN ('REFERENCE', 'TELEMETRY'));
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'ck_audit_record_processing_stg_type'
          AND conrelid = 'audit.record_processing'::regclass
    ) THEN
        ALTER TABLE audit.record_processing
            ADD CONSTRAINT ck_audit_record_processing_stg_type
            CHECK (
                (record_type = 'REFERENCE'
                    AND stg_reference_record_id IS NOT NULL
                    AND stg_telemetry_record_id IS NULL)
                OR
                (record_type = 'TELEMETRY'
                    AND stg_reference_record_id IS NULL
                    AND stg_telemetry_record_id IS NOT NULL)
            );
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_audit_record_processing_telemetry_stg'
          AND conrelid = 'audit.record_processing'::regclass
    ) THEN
        ALTER TABLE audit.record_processing
            ADD CONSTRAINT fk_audit_record_processing_telemetry_stg
            FOREIGN KEY (stg_telemetry_record_id)
            REFERENCES stg.telemetry_record(stg_telemetry_record_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'ck_rejected_record_record_type'
          AND conrelid = 'rejected.record'::regclass
    ) THEN
        ALTER TABLE rejected.record
            ADD CONSTRAINT ck_rejected_record_record_type
            CHECK (record_type IN ('REFERENCE', 'TELEMETRY'));
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'ck_rejected_record_stg_type'
          AND conrelid = 'rejected.record'::regclass
    ) THEN
        ALTER TABLE rejected.record
            ADD CONSTRAINT ck_rejected_record_stg_type
            CHECK (
                (record_type = 'REFERENCE'
                    AND stg_reference_record_id IS NOT NULL
                    AND stg_telemetry_record_id IS NULL)
                OR
                (record_type = 'TELEMETRY'
                    AND stg_reference_record_id IS NULL
                    AND stg_telemetry_record_id IS NOT NULL)
            );
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_rejected_record_telemetry_stg'
          AND conrelid = 'rejected.record'::regclass
    ) THEN
        ALTER TABLE rejected.record
            ADD CONSTRAINT fk_rejected_record_telemetry_stg
            FOREIGN KEY (stg_telemetry_record_id)
            REFERENCES stg.telemetry_record(stg_telemetry_record_id);
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION ods.load_telemetry_page(
    p_page jsonb,
    p_source_name text,
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
    v_expected integer;
    v_is_duplicate boolean;
    v_batch_started_at timestamptz;
    v_batch_ended_at timestamptz;
    v_batch_equipment_id text;
    v_material_id text;
    v_range_unit text;
    v_min_value numeric;
    v_max_value numeric;
    v_measured_value numeric;
    v_measured_at timestamptz;
    v_source_updated_at timestamptz;
    v_next_updated_at timestamptz;
    v_next_record_id text;
    v_page_max_updated_at timestamptz;
    v_page_max_record_id text;
BEGIN
    IF COALESCE(NULLIF(p_source_name, ''), '') = '' THEN
        RAISE EXCEPTION 'source_name is required';
    END IF;

    IF jsonb_typeof(p_page->'records') <> 'array' THEN
        RAISE EXCEPTION 'Telemetry page records must be an array';
    END IF;

    v_expected := COALESCE(
        (p_page->>'record_count')::integer,
        jsonb_array_length(p_page->'records')
    );

    IF v_expected <> jsonb_array_length(p_page->'records') THEN
        RAISE EXCEPTION 'record_count does not match telemetry records array length';
    END IF;

    IF v_expected > 0 AND p_page->'next_watermark' IS NULL THEN
        RAISE EXCEPTION 'A non-empty telemetry page requires next_watermark';
    END IF;

    IF v_expected > 0 THEN
        SELECT
            (item->>'updated_at')::timestamptz,
            item->>'source_record_id'
        INTO v_page_max_updated_at, v_page_max_record_id
        FROM jsonb_array_elements(p_page->'records') AS item
        ORDER BY
            (item->>'updated_at')::timestamptz DESC,
            item->>'source_record_id' DESC
        LIMIT 1;

        IF COALESCE(p_page->'next_watermark'->>'updated_at', '')
                !~ '(Z|[+-][0-9]{2}:[0-9]{2})$'
           OR COALESCE(p_page->'next_watermark'->>'source_record_id', '') = '' THEN
            RAISE EXCEPTION 'Invalid telemetry next_watermark';
        END IF;

        v_next_updated_at := (p_page->'next_watermark'->>'updated_at')::timestamptz;
        v_next_record_id := p_page->'next_watermark'->>'source_record_id';

        IF (v_next_updated_at, v_next_record_id)
                <> (v_page_max_updated_at, v_page_max_record_id) THEN
            RAISE EXCEPTION 'next_watermark does not match the greatest page tuple';
        END IF;
    END IF;

    INSERT INTO audit.load_run (
        run_id, source_name, source_object, entity_type, status
    ) VALUES (
        v_run_id, p_source_name, p_source_object, 'telemetry', 'RUNNING'
    );

    FOR v_record IN SELECT value FROM jsonb_array_elements(p_page->'records')
    LOOP
        v_received := v_received + 1;
        v_correlation_id := gen_random_uuid();
        v_checksum := encode(digest(v_record::text, 'sha256'), 'hex');
        v_record_id := v_record->>'source_record_id';

        INSERT INTO stg.telemetry_record (
            run_id, source_name, source_object, source_record_id,
            payload, correlation_id, checksum, processing_status
        ) VALUES (
            v_run_id, p_source_name, p_source_object, v_record_id,
            v_record, v_correlation_id, v_checksum, 'RECEIVED'
        ) RETURNING stg_telemetry_record_id INTO v_stg_record_id;

        BEGIN
            IF COALESCE(v_record_id, '') = '' THEN
                RAISE EXCEPTION USING
                    ERRCODE = '23502',
                    MESSAGE = 'Missing telemetry source_record_id';
            END IF;

            v_is_duplicate := EXISTS (
                SELECT 1
                FROM ods.telemetry_measurement
                WHERE source_record_id = v_record_id
                  AND source_checksum = v_checksum
            );

            IF v_is_duplicate THEN
                UPDATE stg.telemetry_record
                SET processing_status = 'DUPLICATE'
                WHERE stg_telemetry_record_id = v_stg_record_id;

                INSERT INTO audit.record_processing (
                    run_id, record_type, stg_telemetry_record_id,
                    correlation_id, outcome, detail
                ) VALUES (
                    v_run_id, 'TELEMETRY', v_stg_record_id,
                    v_correlation_id, 'DUPLICATE',
                    'source_record_id and checksum already loaded'
                );
                v_duplicate := v_duplicate + 1;
                CONTINUE;
            END IF;

            IF COALESCE(v_record->>'measured_at', '')
                    !~ '(Z|[+-][0-9]{2}:[0-9]{2})$'
               OR COALESCE(v_record->>'updated_at', '')
                    !~ '(Z|[+-][0-9]{2}:[0-9]{2})$' THEN
                RAISE EXCEPTION USING
                    ERRCODE = '22007',
                    MESSAGE = format('Telemetry %s timestamps require a UTC offset', v_record_id);
            END IF;

            v_measured_value := (v_record->>'value')::numeric;
            v_measured_at := (v_record->>'measured_at')::timestamptz;
            v_source_updated_at := (v_record->>'updated_at')::timestamptz;

            SELECT
                b.started_at,
                b.ended_at,
                b.equipment_id,
                b.material_id
            INTO
                v_batch_started_at,
                v_batch_ended_at,
                v_batch_equipment_id,
                v_material_id
            FROM ods.production_batch b
            WHERE b.batch_id = v_record->>'batch_id';

            IF NOT FOUND THEN
                RAISE EXCEPTION 'Unknown batch_id: %', v_record->>'batch_id';
            END IF;

            IF COALESCE(v_record->>'equipment_id', '') <> v_batch_equipment_id THEN
                RAISE EXCEPTION 'Equipment % does not match batch % equipment %',
                    v_record->>'equipment_id', v_record->>'batch_id', v_batch_equipment_id;
            END IF;

            IF v_measured_at < v_batch_started_at OR v_measured_at > v_batch_ended_at THEN
                RAISE EXCEPTION 'Telemetry % timestamp is outside batch period', v_record_id;
            END IF;

            SELECT r.unit, r.min_value, r.max_value
            INTO v_range_unit, v_min_value, v_max_value
            FROM ods.material_parameter_range r
            WHERE r.material_id = v_material_id
              AND r.parameter_code = v_record->>'parameter_code';

            IF NOT FOUND THEN
                RAISE EXCEPTION 'Unknown parameter % for material %',
                    v_record->>'parameter_code', v_material_id;
            END IF;

            IF COALESCE(v_record->>'unit', '') <> v_range_unit THEN
                RAISE EXCEPTION 'Unit % does not match expected unit % for parameter %',
                    v_record->>'unit', v_range_unit, v_record->>'parameter_code';
            END IF;

            INSERT INTO ods.telemetry_measurement (
                source_record_id, batch_id, equipment_id, parameter_code,
                measured_value, unit, measured_at, source_updated_at,
                min_value, max_value, is_deviation, source_checksum
            ) VALUES (
                v_record_id,
                v_record->>'batch_id',
                v_record->>'equipment_id',
                v_record->>'parameter_code',
                v_measured_value,
                v_record->>'unit',
                v_measured_at,
                v_source_updated_at,
                v_min_value,
                v_max_value,
                v_measured_value < v_min_value OR v_measured_value > v_max_value,
                v_checksum
            )
            ON CONFLICT (source_record_id) DO UPDATE SET
                batch_id = EXCLUDED.batch_id,
                equipment_id = EXCLUDED.equipment_id,
                parameter_code = EXCLUDED.parameter_code,
                measured_value = EXCLUDED.measured_value,
                unit = EXCLUDED.unit,
                measured_at = EXCLUDED.measured_at,
                source_updated_at = EXCLUDED.source_updated_at,
                min_value = EXCLUDED.min_value,
                max_value = EXCLUDED.max_value,
                is_deviation = EXCLUDED.is_deviation,
                source_checksum = EXCLUDED.source_checksum,
                updated_at = clock_timestamp();

            UPDATE stg.telemetry_record
            SET processing_status = 'ACCEPTED'
            WHERE stg_telemetry_record_id = v_stg_record_id;

            INSERT INTO audit.record_processing (
                run_id, record_type, stg_telemetry_record_id,
                correlation_id, outcome, detail
            ) VALUES (
                v_run_id, 'TELEMETRY', v_stg_record_id,
                v_correlation_id, 'ACCEPTED', 'Validated and upserted into ODS'
            );
            v_accepted := v_accepted + 1;

        EXCEPTION WHEN OTHERS THEN
            UPDATE stg.telemetry_record
            SET processing_status = 'REJECTED',
                error_code = SQLSTATE,
                error_text = SQLERRM
            WHERE stg_telemetry_record_id = v_stg_record_id;

            INSERT INTO rejected.record (
                run_id, record_type, stg_telemetry_record_id,
                source_name, source_object, entity_type, source_record_id,
                payload, correlation_id, error_code, error_text
            ) VALUES (
                v_run_id, 'TELEMETRY', v_stg_record_id,
                p_source_name, p_source_object, 'telemetry', v_record_id,
                v_record, v_correlation_id, SQLSTATE, SQLERRM
            );

            INSERT INTO audit.record_processing (
                run_id, record_type, stg_telemetry_record_id,
                correlation_id, outcome, detail
            ) VALUES (
                v_run_id, 'TELEMETRY', v_stg_record_id,
                v_correlation_id, 'REJECTED', SQLSTATE || ': ' || SQLERRM
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

    INSERT INTO control.reconciliation_result (
        run_id, check_name, expected_count, actual_count, status, detail
    ) VALUES (
        v_run_id,
        'telemetry_page_accounting',
        v_expected,
        v_accepted + v_rejected + v_duplicate,
        CASE WHEN v_expected = v_accepted + v_rejected + v_duplicate
            THEN 'MATCHED'
            ELSE 'MISMATCHED'
        END,
        'received = accepted + rejected + duplicate'
    );

    IF v_expected <> v_accepted + v_rejected + v_duplicate THEN
        RAISE EXCEPTION 'Telemetry page reconciliation mismatch';
    END IF;

    IF v_next_updated_at IS NOT NULL THEN
        INSERT INTO control.watermark (
            source_name, watermark_value, watermark_record_id
        ) VALUES (
            p_source_name, p_page->'next_watermark'->>'updated_at', v_next_record_id
        )
        ON CONFLICT (source_name) DO UPDATE SET
            watermark_value = EXCLUDED.watermark_value,
            watermark_record_id = EXCLUDED.watermark_record_id,
            updated_at = clock_timestamp()
        WHERE (
            EXCLUDED.watermark_value::timestamptz,
            EXCLUDED.watermark_record_id
        ) > (
            control.watermark.watermark_value::timestamptz,
            COALESCE(control.watermark.watermark_record_id, '')
        );
    END IF;

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

DROP VIEW IF EXISTS dm.dm_batch_process_deviations;

CREATE VIEW dm.dm_batch_process_deviations AS
SELECT
    t.batch_id,
    t.source_record_id,
    t.equipment_id,
    t.parameter_code,
    t.measured_at,
    t.measured_value,
    t.unit,
    t.min_value,
    t.max_value,
    CASE
        WHEN t.measured_value < t.min_value THEN 'BELOW_MIN'
        WHEN t.measured_value > t.max_value THEN 'ABOVE_MAX'
    END AS deviation_type
FROM ods.telemetry_measurement t
WHERE t.is_deviation;

CREATE OR REPLACE VIEW dm.dm_batch_investigation AS
SELECT
    b.batch_id,
    b.started_at,
    b.ended_at,
    b.status AS batch_status,
    p.plant_id,
    p.plant_name,
    l.line_id,
    l.line_name,
    e.equipment_id,
    e.equipment_name,
    m.material_id,
    m.material_name,
    m.grade,
    COALESCE((
        SELECT jsonb_agg(
            jsonb_build_object(
                'parameter_code', r.parameter_code,
                'unit', r.unit,
                'min_value', r.min_value,
                'max_value', r.max_value
            ) ORDER BY r.parameter_code
        )
        FROM ods.material_parameter_range r
        WHERE r.material_id = m.material_id
    ), '[]'::jsonb) AS operating_ranges,
    NULL::text AS laboratory_overall_status,
    (
        SELECT count(*)
        FROM ods.telemetry_measurement t
        WHERE t.batch_id = b.batch_id
          AND t.is_deviation
    ) AS process_deviation_count,
    0::numeric AS downtime_minutes
FROM ods.production_batch b
JOIN ods.material m ON m.material_id = b.material_id
JOIN ods.production_line l ON l.line_id = b.line_id
JOIN ods.plant p ON p.plant_id = l.plant_id
JOIN ods.equipment e ON e.equipment_id = b.equipment_id;
