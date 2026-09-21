CREATE TABLE IF NOT EXISTS stg.downtime_event_record (
    stg_downtime_event_record_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_id uuid NOT NULL REFERENCES audit.load_run(run_id),
    topic_name text NOT NULL,
    partition_id integer NOT NULL CHECK (partition_id >= 0),
    offset_id bigint NOT NULL CHECK (offset_id >= 0),
    message_key text,
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

CREATE INDEX IF NOT EXISTS ix_stg_downtime_event_correlation
    ON stg.downtime_event_record(correlation_id);

CREATE INDEX IF NOT EXISTS ix_stg_downtime_event_source_record
    ON stg.downtime_event_record(source_record_id);

CREATE TABLE IF NOT EXISTS ods.downtime_reason (
    reason_code text PRIMARY KEY,
    reason_name text NOT NULL,
    downtime_type text NOT NULL CHECK (downtime_type IN ('PLANNED', 'UNPLANNED'))
);

INSERT INTO ods.downtime_reason (reason_code, reason_name, downtime_type)
VALUES
    ('MATERIAL_JAM', 'Material jam', 'UNPLANNED'),
    ('PLANNED_CLEANING', 'Planned cleaning', 'PLANNED')
ON CONFLICT (reason_code) DO UPDATE SET
    reason_name = EXCLUDED.reason_name,
    downtime_type = EXCLUDED.downtime_type;

CREATE TABLE IF NOT EXISTS ods.downtime_event (
    event_id text PRIMARY KEY,
    downtime_id text NOT NULL,
    event_type text NOT NULL
        CHECK (event_type IN ('DOWNTIME_STARTED', 'DOWNTIME_ENDED')),
    batch_id text NOT NULL REFERENCES ods.production_batch(batch_id),
    equipment_id text NOT NULL REFERENCES ods.equipment(equipment_id),
    reason_code text NOT NULL REFERENCES ods.downtime_reason(reason_code),
    occurred_at timestamptz NOT NULL,
    source_system text NOT NULL,
    source_topic text NOT NULL,
    source_partition integer NOT NULL,
    source_offset bigint NOT NULL,
    source_checksum char(64) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (source_topic, source_partition, source_offset)
);

CREATE INDEX IF NOT EXISTS ix_downtime_event_incident
    ON ods.downtime_event(downtime_id, occurred_at);

CREATE TABLE IF NOT EXISTS ods.downtime_incident (
    downtime_id text PRIMARY KEY,
    batch_id text NOT NULL REFERENCES ods.production_batch(batch_id),
    equipment_id text NOT NULL REFERENCES ods.equipment(equipment_id),
    reason_code text NOT NULL REFERENCES ods.downtime_reason(reason_code),
    started_at timestamptz NOT NULL,
    ended_at timestamptz,
    status text NOT NULL CHECK (status IN ('OPEN', 'COMPLETED')),
    start_event_id text NOT NULL UNIQUE REFERENCES ods.downtime_event(event_id),
    end_event_id text UNIQUE REFERENCES ods.downtime_event(event_id),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CHECK (
        (status = 'OPEN' AND ended_at IS NULL AND end_event_id IS NULL)
        OR
        (status = 'COMPLETED' AND ended_at IS NOT NULL AND end_event_id IS NOT NULL)
    ),
    CHECK (ended_at IS NULL OR ended_at >= started_at)
);

CREATE INDEX IF NOT EXISTS ix_downtime_incident_batch
    ON ods.downtime_incident(batch_id, status);

ALTER TABLE audit.record_processing
    ADD COLUMN IF NOT EXISTS stg_downtime_event_record_id bigint;

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
        WHERE conname = 'fk_audit_record_processing_downtime_stg'
          AND conrelid = 'audit.record_processing'::regclass
    ) THEN
        ALTER TABLE audit.record_processing
            ADD CONSTRAINT fk_audit_record_processing_downtime_stg
            FOREIGN KEY (stg_downtime_event_record_id)
            REFERENCES stg.downtime_event_record(stg_downtime_event_record_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_rejected_record_downtime_stg'
          AND conrelid = 'rejected.record'::regclass
    ) THEN
        ALTER TABLE rejected.record
            ADD CONSTRAINT fk_rejected_record_downtime_stg
            FOREIGN KEY (stg_downtime_event_record_id)
            REFERENCES stg.downtime_event_record(stg_downtime_event_record_id);
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION ods.load_downtime_event(
    p_message jsonb,
    p_topic_name text,
    p_partition_id integer,
    p_offset_id bigint,
    p_message_key text,
    p_replay_of_rejected_record_id bigint DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_run_id uuid := gen_random_uuid();
    v_correlation_id uuid := gen_random_uuid();
    v_stg_record_id bigint;
    v_event_id text := p_message->>'event_id';
    v_checksum char(64) := encode(digest(p_message::text, 'sha256'), 'hex');
    v_event_type text;
    v_occurred_at timestamptz;
    v_existing_checksum char(64);
    v_incident ods.downtime_incident%ROWTYPE;
    v_batch_equipment_id text;
    v_error_code text;
    v_error_text text;
    v_rejected_record_id bigint;
    v_replay_source_record_id text;
BEGIN
    IF p_replay_of_rejected_record_id IS NOT NULL THEN
        SELECT source_record_id
        INTO v_replay_source_record_id
        FROM rejected.record
        WHERE rejected_record_id = p_replay_of_rejected_record_id
          AND record_type = 'DOWNTIME'
          AND replay_status = 'PENDING';

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Pending downtime rejection % was not found',
                p_replay_of_rejected_record_id;
        END IF;

        IF v_replay_source_record_id IS DISTINCT FROM v_event_id THEN
            RAISE EXCEPTION 'Replay event_id % does not match rejected event_id %',
                v_event_id, v_replay_source_record_id;
        END IF;
    END IF;

    INSERT INTO audit.load_run (
        run_id, source_name, source_object, entity_type, status
    ) VALUES (
        v_run_id,
        'MAINTENANCE_CMS_KAFKA',
        format('%s/%s/%s', p_topic_name, p_partition_id, p_offset_id),
        'downtime_event',
        'RUNNING'
    );

    INSERT INTO stg.downtime_event_record (
        run_id, topic_name, partition_id, offset_id, message_key,
        source_record_id, payload, correlation_id, checksum, processing_status
    ) VALUES (
        v_run_id, p_topic_name, p_partition_id, p_offset_id, p_message_key,
        v_event_id, p_message, v_correlation_id, v_checksum, 'RECEIVED'
    ) RETURNING stg_downtime_event_record_id INTO v_stg_record_id;

    BEGIN
        IF COALESCE(btrim(p_topic_name), '') = ''
           OR p_partition_id < 0
           OR p_offset_id < 0 THEN
            RAISE EXCEPTION USING
                ERRCODE = '22023',
                MESSAGE = 'Valid Kafka topic, partition, and offset are required';
        END IF;

        IF COALESCE(btrim(v_event_id), '') = ''
           OR COALESCE(btrim(p_message->>'downtime_id'), '') = ''
           OR COALESCE(btrim(p_message->>'batch_id'), '') = ''
           OR COALESCE(btrim(p_message->>'equipment_id'), '') = ''
           OR COALESCE(btrim(p_message->>'reason_code'), '') = ''
           OR COALESCE(btrim(p_message->>'occurred_at'), '') = '' THEN
            RAISE EXCEPTION USING
                ERRCODE = '23502',
                MESSAGE = 'Required downtime event field is missing';
        END IF;

        IF p_message->>'schema_version' IS DISTINCT FROM '1.0' THEN
            RAISE EXCEPTION 'Unsupported downtime schema_version: %',
                p_message->>'schema_version';
        END IF;

        IF p_message->>'source_system' IS DISTINCT FROM 'MAINTENANCE_CMS' THEN
            RAISE EXCEPTION 'Unsupported downtime source_system: %',
                p_message->>'source_system';
        END IF;

        IF p_message_key IS DISTINCT FROM v_event_id THEN
            RAISE EXCEPTION 'Kafka message key % does not match event_id %',
                p_message_key, v_event_id;
        END IF;

        v_event_type := p_message->>'event_type';
        IF v_event_type NOT IN ('DOWNTIME_STARTED', 'DOWNTIME_ENDED') THEN
            RAISE EXCEPTION 'Unsupported downtime event_type: %', v_event_type;
        END IF;

        IF p_message->>'occurred_at' !~ '(Z|[+-][0-9]{2}:[0-9]{2})$' THEN
            RAISE EXCEPTION USING
                ERRCODE = '22007',
                MESSAGE = 'Downtime occurred_at requires a UTC offset';
        END IF;
        v_occurred_at := (p_message->>'occurred_at')::timestamptz;

        SELECT source_checksum
        INTO v_existing_checksum
        FROM ods.downtime_event
        WHERE event_id = v_event_id;

        IF FOUND THEN
            IF v_existing_checksum = v_checksum THEN
                UPDATE stg.downtime_event_record
                SET processing_status = 'DUPLICATE'
                WHERE stg_downtime_event_record_id = v_stg_record_id;

                INSERT INTO audit.record_processing (
                    run_id, record_type, stg_downtime_event_record_id,
                    correlation_id, outcome, detail
                ) VALUES (
                    v_run_id, 'DOWNTIME', v_stg_record_id,
                    v_correlation_id, 'DUPLICATE',
                    'event_id and payload checksum already exist in ODS'
                );

                UPDATE audit.load_run
                SET finished_at = clock_timestamp(), status = 'COMPLETED',
                    received_count = 1, duplicate_count = 1
                WHERE run_id = v_run_id;

                INSERT INTO control.reconciliation_result (
                    run_id, check_name, expected_count, actual_count, status, detail
                ) VALUES (
                    v_run_id, 'downtime_event_accounting', 1, 1, 'MATCHED',
                    'received = accepted + rejected + duplicate'
                );

                RETURN jsonb_build_object(
                    'run_id', v_run_id,
                    'correlation_id', v_correlation_id,
                    'outcome', 'DUPLICATE'
                );
            END IF;

            RAISE EXCEPTION 'event_id % conflicts with a different accepted payload',
                v_event_id;
        END IF;

        SELECT equipment_id
        INTO v_batch_equipment_id
        FROM ods.production_batch
        WHERE batch_id = p_message->>'batch_id';

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Unknown batch_id: %', p_message->>'batch_id';
        END IF;

        IF v_batch_equipment_id IS DISTINCT FROM p_message->>'equipment_id' THEN
            RAISE EXCEPTION 'Equipment % does not match batch % equipment %',
                p_message->>'equipment_id', p_message->>'batch_id',
                v_batch_equipment_id;
        END IF;

        PERFORM 1
        FROM ods.downtime_reason
        WHERE reason_code = p_message->>'reason_code';

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Unknown downtime reason_code: %',
                p_message->>'reason_code';
        END IF;

        IF v_event_type = 'DOWNTIME_STARTED' THEN
            PERFORM 1
            FROM ods.downtime_incident
            WHERE downtime_id = p_message->>'downtime_id';

            IF FOUND THEN
                RAISE EXCEPTION 'Downtime incident % already exists',
                    p_message->>'downtime_id';
            END IF;
        ELSE
            SELECT *
            INTO v_incident
            FROM ods.downtime_incident
            WHERE downtime_id = p_message->>'downtime_id'
            FOR UPDATE;

            IF NOT FOUND OR v_incident.status <> 'OPEN' THEN
                RAISE EXCEPTION 'Open downtime incident % was not found',
                    p_message->>'downtime_id';
            END IF;

            IF v_incident.batch_id IS DISTINCT FROM p_message->>'batch_id'
               OR v_incident.equipment_id IS DISTINCT FROM p_message->>'equipment_id'
               OR v_incident.reason_code IS DISTINCT FROM p_message->>'reason_code' THEN
                RAISE EXCEPTION 'Downtime end attributes do not match incident %',
                    p_message->>'downtime_id';
            END IF;

            IF v_occurred_at < v_incident.started_at THEN
                RAISE EXCEPTION 'Downtime end % is earlier than start %',
                    v_occurred_at, v_incident.started_at;
            END IF;
        END IF;

        INSERT INTO ods.downtime_event (
            event_id, downtime_id, event_type, batch_id, equipment_id,
            reason_code, occurred_at, source_system, source_topic,
            source_partition, source_offset, source_checksum
        ) VALUES (
            v_event_id, p_message->>'downtime_id', v_event_type,
            p_message->>'batch_id', p_message->>'equipment_id',
            p_message->>'reason_code', v_occurred_at,
            p_message->>'source_system', p_topic_name, p_partition_id,
            p_offset_id, v_checksum
        );

        IF v_event_type = 'DOWNTIME_STARTED' THEN
            INSERT INTO ods.downtime_incident (
                downtime_id, batch_id, equipment_id, reason_code,
                started_at, status, start_event_id
            ) VALUES (
                p_message->>'downtime_id', p_message->>'batch_id',
                p_message->>'equipment_id', p_message->>'reason_code',
                v_occurred_at, 'OPEN', v_event_id
            );
        ELSE
            UPDATE ods.downtime_incident
            SET ended_at = v_occurred_at,
                status = 'COMPLETED',
                end_event_id = v_event_id,
                updated_at = clock_timestamp()
            WHERE downtime_id = p_message->>'downtime_id';
        END IF;

        UPDATE stg.downtime_event_record
        SET processing_status = 'ACCEPTED'
        WHERE stg_downtime_event_record_id = v_stg_record_id;

        INSERT INTO audit.record_processing (
            run_id, record_type, stg_downtime_event_record_id,
            correlation_id, outcome, detail
        ) VALUES (
            v_run_id, 'DOWNTIME', v_stg_record_id,
            v_correlation_id, 'ACCEPTED',
            format('Validated and applied %s for %s',
                v_event_type, p_message->>'downtime_id')
        );

        UPDATE audit.load_run
        SET finished_at = clock_timestamp(), status = 'COMPLETED',
            received_count = 1, accepted_count = 1
        WHERE run_id = v_run_id;

        INSERT INTO control.reconciliation_result (
            run_id, check_name, expected_count, actual_count, status, detail
        ) VALUES (
            v_run_id, 'downtime_event_accounting', 1, 1, 'MATCHED',
            'received = accepted + rejected + duplicate'
        );

        IF p_replay_of_rejected_record_id IS NOT NULL THEN
            INSERT INTO rejected.replay_history (
                rejected_record_id, replay_run_id, outcome, detail
            ) VALUES (
                p_replay_of_rejected_record_id, v_run_id, 'ACCEPTED',
                format('Accepted corrected downtime event %s', v_event_id)
            );

            UPDATE rejected.record
            SET replay_status = 'REPLAYED'
            WHERE rejected_record_id = p_replay_of_rejected_record_id;
        END IF;

        RETURN jsonb_build_object(
            'run_id', v_run_id,
            'correlation_id', v_correlation_id,
            'outcome', 'ACCEPTED'
        );

    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS
            v_error_code = RETURNED_SQLSTATE,
            v_error_text = MESSAGE_TEXT;

        UPDATE stg.downtime_event_record
        SET processing_status = 'REJECTED',
            error_code = v_error_code,
            error_text = v_error_text
        WHERE stg_downtime_event_record_id = v_stg_record_id;

        INSERT INTO rejected.record (
            run_id, record_type, stg_downtime_event_record_id,
            source_name, source_object, entity_type, source_record_id,
            payload, correlation_id, error_code, error_text
        ) VALUES (
            v_run_id, 'DOWNTIME', v_stg_record_id,
            'MAINTENANCE_CMS_KAFKA',
            format('%s/%s/%s', p_topic_name, p_partition_id, p_offset_id),
            'downtime_event', v_event_id, p_message, v_correlation_id,
            v_error_code, v_error_text
        ) RETURNING rejected_record_id INTO v_rejected_record_id;

        INSERT INTO audit.record_processing (
            run_id, record_type, stg_downtime_event_record_id,
            correlation_id, outcome, detail
        ) VALUES (
            v_run_id, 'DOWNTIME', v_stg_record_id,
            v_correlation_id, 'REJECTED', v_error_code || ': ' || v_error_text
        );

        UPDATE audit.load_run
        SET finished_at = clock_timestamp(),
            status = 'COMPLETED_WITH_REJECTIONS',
            received_count = 1, rejected_count = 1
        WHERE run_id = v_run_id;

        INSERT INTO control.reconciliation_result (
            run_id, check_name, expected_count, actual_count, status, detail
        ) VALUES (
            v_run_id, 'downtime_event_accounting', 1, 1, 'MATCHED',
            'received = accepted + rejected + duplicate'
        );

        IF p_replay_of_rejected_record_id IS NOT NULL THEN
            INSERT INTO rejected.replay_history (
                rejected_record_id, replay_run_id, outcome, detail
            ) VALUES (
                p_replay_of_rejected_record_id, v_run_id, 'NOT_ACCEPTED',
                v_error_code || ': ' || v_error_text
            );
        END IF;

        RETURN jsonb_build_object(
            'run_id', v_run_id,
            'correlation_id', v_correlation_id,
            'outcome', 'REJECTED',
            'rejected_record_id', v_rejected_record_id,
            'error_code', v_error_code,
            'error_text', v_error_text
        );
    END;
END;
$$;

CREATE OR REPLACE VIEW dm.dm_downtime_incidents AS
SELECT
    incident.downtime_id,
    incident.batch_id,
    incident.equipment_id,
    incident.reason_code,
    reason.reason_name,
    reason.downtime_type,
    incident.started_at,
    incident.ended_at,
    incident.status,
    CASE
        WHEN incident.status = 'COMPLETED'
        THEN extract(epoch FROM incident.ended_at - incident.started_at) / 60
        ELSE NULL
    END AS downtime_minutes,
    incident.start_event_id,
    incident.end_event_id
FROM ods.downtime_incident incident
JOIN ods.downtime_reason reason USING (reason_code);

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
            SELECT 1 FROM ods.laboratory_result lab
            WHERE lab.batch_id = b.batch_id AND lab.result_status = 'FAIL'
        ) THEN 'FAIL'
        WHEN EXISTS (
            SELECT 1 FROM ods.laboratory_result lab
            WHERE lab.batch_id = b.batch_id
        ) THEN 'PASS'
        ELSE NULL
    END AS laboratory_overall_status,
    (
        SELECT count(*)
        FROM ods.telemetry_measurement t
        WHERE t.batch_id = b.batch_id AND t.is_deviation
    ) AS process_deviation_count,
    COALESCE((
        SELECT sum(
            extract(epoch FROM incident.ended_at - incident.started_at) / 60
        )
        FROM ods.downtime_incident incident
        WHERE incident.batch_id = b.batch_id
          AND incident.status = 'COMPLETED'
    ), 0)::numeric AS downtime_minutes
FROM ods.production_batch b
JOIN ods.material m ON m.material_id = b.material_id
JOIN ods.production_line l ON l.line_id = b.line_id
JOIN ods.plant p ON p.plant_id = l.plant_id
JOIN ods.equipment e ON e.equipment_id = b.equipment_id;
