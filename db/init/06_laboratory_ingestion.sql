CREATE TABLE IF NOT EXISTS stg.laboratory_record (
    stg_laboratory_record_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_id uuid NOT NULL REFERENCES audit.load_run(run_id),
    source_name text NOT NULL,
    source_object text NOT NULL,
    file_checksum char(64) NOT NULL,
    row_number integer NOT NULL CHECK (row_number >= 2),
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

CREATE INDEX IF NOT EXISTS ix_stg_laboratory_delivery
    ON stg.laboratory_record(file_checksum, row_number);

CREATE INDEX IF NOT EXISTS ix_stg_laboratory_correlation
    ON stg.laboratory_record(correlation_id);

CREATE TABLE IF NOT EXISTS ods.laboratory_result (
    lab_result_id text PRIMARY KEY,
    result_version integer NOT NULL CHECK (result_version > 0),
    batch_id text NOT NULL REFERENCES ods.production_batch(batch_id),
    test_code text NOT NULL,
    test_name text NOT NULL,
    result_value numeric NOT NULL,
    unit text NOT NULL,
    min_limit numeric NOT NULL,
    max_limit numeric NOT NULL,
    result_status text NOT NULL CHECK (result_status IN ('PASS', 'FAIL')),
    tested_at timestamptz NOT NULL,
    source_file_checksum char(64) NOT NULL,
    source_row_number integer NOT NULL,
    source_checksum char(64) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CHECK (min_limit <= max_limit),
    CHECK (
        (result_value BETWEEN min_limit AND max_limit AND result_status = 'PASS')
        OR
        ((result_value < min_limit OR result_value > max_limit) AND result_status = 'FAIL')
    )
);

CREATE INDEX IF NOT EXISTS ix_laboratory_result_batch
    ON ods.laboratory_result(batch_id);

ALTER TABLE audit.record_processing
    ADD COLUMN IF NOT EXISTS stg_laboratory_record_id bigint;

ALTER TABLE audit.record_processing
    ADD COLUMN IF NOT EXISTS stg_downtime_event_record_id bigint;

ALTER TABLE rejected.record
    ADD COLUMN IF NOT EXISTS stg_laboratory_record_id bigint;

ALTER TABLE rejected.record
    ADD COLUMN IF NOT EXISTS stg_downtime_event_record_id bigint;

ALTER TABLE audit.record_processing
    DROP CONSTRAINT IF EXISTS record_processing_record_type_check,
    DROP CONSTRAINT IF EXISTS ck_audit_record_processing_record_type,
    DROP CONSTRAINT IF EXISTS ck_audit_record_processing_stg_type;

ALTER TABLE audit.record_processing
    ADD CONSTRAINT ck_audit_record_processing_record_type
        CHECK (record_type IN ('REFERENCE', 'TELEMETRY', 'LABORATORY', 'DOWNTIME')),
    ADD CONSTRAINT ck_audit_record_processing_stg_type CHECK (
        (record_type = 'REFERENCE'
            AND stg_reference_record_id IS NOT NULL
            AND stg_telemetry_record_id IS NULL
            AND stg_laboratory_record_id IS NULL
            AND stg_downtime_event_record_id IS NULL)
        OR
        (record_type = 'TELEMETRY'
            AND stg_reference_record_id IS NULL
            AND stg_telemetry_record_id IS NOT NULL
            AND stg_laboratory_record_id IS NULL
            AND stg_downtime_event_record_id IS NULL)
        OR
        (record_type = 'LABORATORY'
            AND stg_reference_record_id IS NULL
            AND stg_telemetry_record_id IS NULL
            AND stg_laboratory_record_id IS NOT NULL
            AND stg_downtime_event_record_id IS NULL)
        OR
        (record_type = 'DOWNTIME'
            AND stg_reference_record_id IS NULL
            AND stg_telemetry_record_id IS NULL
            AND stg_laboratory_record_id IS NULL
            AND stg_downtime_event_record_id IS NOT NULL)
    );

ALTER TABLE rejected.record
    DROP CONSTRAINT IF EXISTS record_record_type_check,
    DROP CONSTRAINT IF EXISTS ck_rejected_record_record_type,
    DROP CONSTRAINT IF EXISTS ck_rejected_record_stg_type;

ALTER TABLE rejected.record
    ADD CONSTRAINT ck_rejected_record_record_type
        CHECK (record_type IN ('REFERENCE', 'TELEMETRY', 'LABORATORY', 'DOWNTIME')),
    ADD CONSTRAINT ck_rejected_record_stg_type CHECK (
        (record_type = 'REFERENCE'
            AND stg_reference_record_id IS NOT NULL
            AND stg_telemetry_record_id IS NULL
            AND stg_laboratory_record_id IS NULL
            AND stg_downtime_event_record_id IS NULL)
        OR
        (record_type = 'TELEMETRY'
            AND stg_reference_record_id IS NULL
            AND stg_telemetry_record_id IS NOT NULL
            AND stg_laboratory_record_id IS NULL
            AND stg_downtime_event_record_id IS NULL)
        OR
        (record_type = 'LABORATORY'
            AND stg_reference_record_id IS NULL
            AND stg_telemetry_record_id IS NULL
            AND stg_laboratory_record_id IS NOT NULL
            AND stg_downtime_event_record_id IS NULL)
        OR
        (record_type = 'DOWNTIME'
            AND stg_reference_record_id IS NULL
            AND stg_telemetry_record_id IS NULL
            AND stg_laboratory_record_id IS NULL
            AND stg_downtime_event_record_id IS NOT NULL)
    );

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_audit_record_processing_laboratory_stg'
          AND conrelid = 'audit.record_processing'::regclass
    ) THEN
        ALTER TABLE audit.record_processing
            ADD CONSTRAINT fk_audit_record_processing_laboratory_stg
            FOREIGN KEY (stg_laboratory_record_id)
            REFERENCES stg.laboratory_record(stg_laboratory_record_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_rejected_record_laboratory_stg'
          AND conrelid = 'rejected.record'::regclass
    ) THEN
        ALTER TABLE rejected.record
            ADD CONSTRAINT fk_rejected_record_laboratory_stg
            FOREIGN KEY (stg_laboratory_record_id)
            REFERENCES stg.laboratory_record(stg_laboratory_record_id);
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION ods.load_laboratory_file(
    p_rows jsonb,
    p_source_name text,
    p_source_object text,
    p_file_checksum text,
    p_replay_of_rejected_record_id bigint DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    v_run_id uuid := gen_random_uuid();
    v_row jsonb;
    v_payload jsonb;
    v_row_number integer;
    v_record_id text;
    v_correlation_id uuid;
    v_checksum char(64);
    v_stg_record_id bigint;
    v_received integer := 0;
    v_accepted integer := 0;
    v_rejected integer := 0;
    v_duplicate integer := 0;
    v_expected integer;
    v_result_version integer;
    v_result_value numeric;
    v_min_limit numeric;
    v_max_limit numeric;
    v_result_status text;
    v_tested_at timestamptz;
    v_current_version integer;
    v_current_checksum char(64);
    v_replay_record_id text;
    v_replay_original_version integer;
    v_replay_accepted boolean := false;
BEGIN
    IF COALESCE(btrim(p_source_name), '') = '' THEN
        RAISE EXCEPTION 'source_name is required';
    END IF;

    IF COALESCE(btrim(p_source_object), '') = '' THEN
        RAISE EXCEPTION 'source_object is required';
    END IF;

    IF COALESCE(p_file_checksum, '') !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'file_checksum must be a lowercase SHA-256 value';
    END IF;

    IF jsonb_typeof(p_rows) <> 'array' THEN
        RAISE EXCEPTION 'Laboratory rows must be a JSON array';
    END IF;

    v_expected := jsonb_array_length(p_rows);

    IF p_replay_of_rejected_record_id IS NOT NULL THEN
        SELECT source_record_id, (payload->>'result_version')::integer
        INTO v_replay_record_id, v_replay_original_version
        FROM rejected.record
        WHERE rejected_record_id = p_replay_of_rejected_record_id
          AND record_type = 'LABORATORY'
          AND replay_status = 'PENDING';

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Pending laboratory rejection % was not found',
                p_replay_of_rejected_record_id;
        END IF;
    END IF;

    INSERT INTO audit.load_run (
        run_id, source_name, source_object, entity_type, status
    ) VALUES (
        v_run_id, p_source_name, p_source_object, 'laboratory', 'RUNNING'
    );

    FOR v_row IN SELECT value FROM jsonb_array_elements(p_rows)
    LOOP
        v_received := v_received + 1;
        v_row_number := (v_row->>'row_number')::integer;
        v_payload := v_row - 'row_number';
        v_record_id := v_payload->>'lab_result_id';
        v_correlation_id := gen_random_uuid();
        v_checksum := encode(digest(v_payload::text, 'sha256'), 'hex');

        INSERT INTO stg.laboratory_record (
            run_id, source_name, source_object, file_checksum, row_number,
            source_record_id, payload, correlation_id, checksum, processing_status
        ) VALUES (
            v_run_id, p_source_name, p_source_object, p_file_checksum, v_row_number,
            v_record_id, v_payload, v_correlation_id, v_checksum, 'RECEIVED'
        ) RETURNING stg_laboratory_record_id INTO v_stg_record_id;

        BEGIN
            IF EXISTS (
                SELECT 1
                FROM stg.laboratory_record previous
                WHERE previous.file_checksum = p_file_checksum
                  AND previous.row_number = v_row_number
                  AND previous.stg_laboratory_record_id <> v_stg_record_id
                  AND previous.processing_status IN ('ACCEPTED', 'REJECTED', 'DUPLICATE')
            ) THEN
                UPDATE stg.laboratory_record
                SET processing_status = 'DUPLICATE'
                WHERE stg_laboratory_record_id = v_stg_record_id;

                INSERT INTO audit.record_processing (
                    run_id, record_type, stg_laboratory_record_id,
                    correlation_id, outcome, detail
                ) VALUES (
                    v_run_id, 'LABORATORY', v_stg_record_id,
                    v_correlation_id, 'DUPLICATE',
                    'file_checksum and row_number were already processed'
                );
                v_duplicate := v_duplicate + 1;
                CONTINUE;
            END IF;

            IF COALESCE(btrim(v_record_id), '') = ''
               OR COALESCE(btrim(v_payload->>'batch_id'), '') = ''
               OR COALESCE(btrim(v_payload->>'test_code'), '') = ''
               OR COALESCE(btrim(v_payload->>'test_name'), '') = ''
               OR COALESCE(btrim(v_payload->>'unit'), '') = '' THEN
                RAISE EXCEPTION USING
                    ERRCODE = '23502',
                    MESSAGE = 'Required laboratory identifier or description is missing';
            END IF;

            v_result_version := (v_payload->>'result_version')::integer;
            v_result_value := (v_payload->>'result_value')::numeric;
            v_min_limit := (v_payload->>'min_limit')::numeric;
            v_max_limit := (v_payload->>'max_limit')::numeric;
            v_result_status := v_payload->>'result_status';

            IF v_result_version <= 0 THEN
                RAISE EXCEPTION 'Laboratory result_version must be positive';
            END IF;

            IF v_min_limit > v_max_limit THEN
                RAISE EXCEPTION 'Laboratory min_limit must not exceed max_limit';
            END IF;

            IF v_result_status NOT IN ('PASS', 'FAIL') THEN
                RAISE EXCEPTION 'Laboratory result_status must be PASS or FAIL';
            END IF;

            IF (v_result_value BETWEEN v_min_limit AND v_max_limit)
                    <> (v_result_status = 'PASS') THEN
                RAISE EXCEPTION 'Laboratory status % does not agree with value % and limits [%..%]',
                    v_result_status, v_result_value, v_min_limit, v_max_limit;
            END IF;

            IF COALESCE(v_payload->>'tested_at', '')
                    !~ '(Z|[+-][0-9]{2}:[0-9]{2})$' THEN
                RAISE EXCEPTION USING
                    ERRCODE = '22007',
                    MESSAGE = format(
                        'Laboratory result % tested_at requires a UTC offset',
                        v_record_id
                    );
            END IF;

            v_tested_at := (v_payload->>'tested_at')::timestamptz;

            PERFORM 1
            FROM ods.production_batch
            WHERE batch_id = v_payload->>'batch_id';

            IF NOT FOUND THEN
                RAISE EXCEPTION 'Unknown batch_id: %', v_payload->>'batch_id';
            END IF;

            v_current_version := NULL;
            v_current_checksum := NULL;

            SELECT result_version, source_checksum
            INTO v_current_version, v_current_checksum
            FROM ods.laboratory_result
            WHERE lab_result_id = v_record_id;

            IF FOUND AND v_current_version > v_result_version THEN
                UPDATE stg.laboratory_record
                SET processing_status = 'DUPLICATE'
                WHERE stg_laboratory_record_id = v_stg_record_id;

                INSERT INTO audit.record_processing (
                    run_id, record_type, stg_laboratory_record_id,
                    correlation_id, outcome, detail
                ) VALUES (
                    v_run_id, 'LABORATORY', v_stg_record_id,
                    v_correlation_id, 'DUPLICATE',
                    format('stale version %s; ODS contains version %s',
                        v_result_version, v_current_version)
                );
                v_duplicate := v_duplicate + 1;
                CONTINUE;
            END IF;

            IF FOUND AND v_current_version = v_result_version THEN
                IF v_current_checksum = v_checksum THEN
                    UPDATE stg.laboratory_record
                    SET processing_status = 'DUPLICATE'
                    WHERE stg_laboratory_record_id = v_stg_record_id;

                    INSERT INTO audit.record_processing (
                        run_id, record_type, stg_laboratory_record_id,
                        correlation_id, outcome, detail
                    ) VALUES (
                        v_run_id, 'LABORATORY', v_stg_record_id,
                        v_correlation_id, 'DUPLICATE',
                        'lab_result_id, version, and checksum already loaded'
                    );
                    v_duplicate := v_duplicate + 1;
                    CONTINUE;
                END IF;

                RAISE EXCEPTION 'Laboratory result % version % conflicts with ODS; increment result_version',
                    v_record_id, v_result_version;
            END IF;

            INSERT INTO ods.laboratory_result (
                lab_result_id, result_version, batch_id, test_code, test_name,
                result_value, unit, min_limit, max_limit, result_status,
                tested_at, source_file_checksum, source_row_number, source_checksum
            ) VALUES (
                v_record_id,
                v_result_version,
                v_payload->>'batch_id',
                v_payload->>'test_code',
                v_payload->>'test_name',
                v_result_value,
                v_payload->>'unit',
                v_min_limit,
                v_max_limit,
                v_result_status,
                v_tested_at,
                p_file_checksum,
                v_row_number,
                v_checksum
            )
            ON CONFLICT (lab_result_id) DO UPDATE SET
                result_version = EXCLUDED.result_version,
                batch_id = EXCLUDED.batch_id,
                test_code = EXCLUDED.test_code,
                test_name = EXCLUDED.test_name,
                result_value = EXCLUDED.result_value,
                unit = EXCLUDED.unit,
                min_limit = EXCLUDED.min_limit,
                max_limit = EXCLUDED.max_limit,
                result_status = EXCLUDED.result_status,
                tested_at = EXCLUDED.tested_at,
                source_file_checksum = EXCLUDED.source_file_checksum,
                source_row_number = EXCLUDED.source_row_number,
                source_checksum = EXCLUDED.source_checksum,
                updated_at = clock_timestamp()
            WHERE ods.laboratory_result.result_version < EXCLUDED.result_version;

            UPDATE stg.laboratory_record
            SET processing_status = 'ACCEPTED'
            WHERE stg_laboratory_record_id = v_stg_record_id;

            INSERT INTO audit.record_processing (
                run_id, record_type, stg_laboratory_record_id,
                correlation_id, outcome, detail
            ) VALUES (
                v_run_id, 'LABORATORY', v_stg_record_id,
                v_correlation_id, 'ACCEPTED',
                format('Validated and stored as ODS version %s', v_result_version)
            );
            v_accepted := v_accepted + 1;

            IF p_replay_of_rejected_record_id IS NOT NULL
               AND v_record_id = v_replay_record_id
               AND v_result_version > v_replay_original_version THEN
                v_replay_accepted := true;
            END IF;

        EXCEPTION WHEN OTHERS THEN
            UPDATE stg.laboratory_record
            SET processing_status = 'REJECTED',
                error_code = SQLSTATE,
                error_text = SQLERRM
            WHERE stg_laboratory_record_id = v_stg_record_id;

            INSERT INTO rejected.record (
                run_id, record_type, stg_laboratory_record_id,
                source_name, source_object, entity_type, source_record_id,
                payload, correlation_id, error_code, error_text
            ) VALUES (
                v_run_id, 'LABORATORY', v_stg_record_id,
                p_source_name, p_source_object, 'laboratory', v_record_id,
                v_payload, v_correlation_id, SQLSTATE, SQLERRM
            );

            INSERT INTO audit.record_processing (
                run_id, record_type, stg_laboratory_record_id,
                correlation_id, outcome, detail
            ) VALUES (
                v_run_id, 'LABORATORY', v_stg_record_id,
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
        'laboratory_file_accounting',
        v_expected,
        v_accepted + v_rejected + v_duplicate,
        CASE WHEN v_expected = v_accepted + v_rejected + v_duplicate
            THEN 'MATCHED'
            ELSE 'MISMATCHED'
        END,
        'received = accepted + rejected + duplicate'
    );

    IF v_expected <> v_accepted + v_rejected + v_duplicate THEN
        RAISE EXCEPTION 'Laboratory file reconciliation mismatch';
    END IF;

    IF p_replay_of_rejected_record_id IS NOT NULL THEN
        INSERT INTO rejected.replay_history (
            rejected_record_id, replay_run_id, outcome, detail
        ) VALUES (
            p_replay_of_rejected_record_id,
            v_run_id,
            CASE WHEN v_replay_accepted THEN 'ACCEPTED' ELSE 'NOT_ACCEPTED' END,
            CASE WHEN v_replay_accepted
                THEN format('Accepted corrected version for %s', v_replay_record_id)
                ELSE format('No higher valid version accepted for %s', v_replay_record_id)
            END
        );

        IF v_replay_accepted THEN
            UPDATE rejected.record
            SET replay_status = 'REPLAYED'
            WHERE rejected_record_id = p_replay_of_rejected_record_id;
        END IF;
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

CREATE OR REPLACE FUNCTION dm.batch_downtime_minutes(p_batch_id text)
RETURNS numeric
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_minutes numeric;
BEGIN
    IF to_regclass('ods.downtime_incident') IS NULL THEN
        RETURN 0;
    END IF;

    EXECUTE $query$
        SELECT COALESCE(sum(
            extract(epoch FROM ended_at - started_at) / 60
        ), 0)::numeric
        FROM ods.downtime_incident
        WHERE batch_id = $1
          AND status = 'COMPLETED'
    $query$
    INTO v_minutes
    USING p_batch_id;

    RETURN v_minutes;
END;
$$;

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
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM ods.laboratory_result lab
            WHERE lab.batch_id = b.batch_id
              AND lab.result_status = 'FAIL'
        ) THEN 'FAIL'
        WHEN EXISTS (
            SELECT 1
            FROM ods.laboratory_result lab
            WHERE lab.batch_id = b.batch_id
        ) THEN 'PASS'
        ELSE NULL
    END AS laboratory_overall_status,
    (
        SELECT count(*)
        FROM ods.telemetry_measurement t
        WHERE t.batch_id = b.batch_id
          AND t.is_deviation
    ) AS process_deviation_count,
    dm.batch_downtime_minutes(b.batch_id) AS downtime_minutes
FROM ods.production_batch b
JOIN ods.material m ON m.material_id = b.material_id
JOIN ods.production_line l ON l.line_id = b.line_id
JOIN ods.plant p ON p.plant_id = l.plant_id
JOIN ods.equipment e ON e.equipment_id = b.equipment_id;
