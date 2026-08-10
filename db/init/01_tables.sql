CREATE TABLE audit.load_run (
    run_id uuid PRIMARY KEY,
    source_name text NOT NULL,
    source_object text NOT NULL,
    entity_type text NOT NULL,
    started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    finished_at timestamptz,
    status text NOT NULL CHECK (status IN ('RUNNING', 'COMPLETED', 'COMPLETED_WITH_REJECTIONS', 'FAILED')),
    received_count integer NOT NULL DEFAULT 0,
    accepted_count integer NOT NULL DEFAULT 0,
    rejected_count integer NOT NULL DEFAULT 0,
    duplicate_count integer NOT NULL DEFAULT 0,
    error_text text
);

CREATE TABLE stg.reference_record (
    stg_record_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_id uuid NOT NULL REFERENCES audit.load_run(run_id),
    source_name text NOT NULL,
    source_object text NOT NULL,
    entity_type text NOT NULL,
    source_record_id text,
    payload jsonb NOT NULL,
    correlation_id uuid NOT NULL,
    checksum char(64) NOT NULL,
    ingestion_ts timestamptz NOT NULL DEFAULT clock_timestamp(),
    processing_status text NOT NULL CHECK (processing_status IN ('RECEIVED', 'ACCEPTED', 'REJECTED', 'DUPLICATE')),
    error_code text,
    error_text text
);

CREATE INDEX ix_stg_reference_record_correlation
    ON stg.reference_record(correlation_id);

CREATE TABLE audit.record_processing (
    processing_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_id uuid NOT NULL REFERENCES audit.load_run(run_id),
    record_type text NOT NULL CHECK (record_type IN ('REFERENCE', 'TELEMETRY')),
    stg_reference_record_id bigint REFERENCES stg.reference_record(stg_record_id),
    stg_telemetry_record_id bigint,
    correlation_id uuid NOT NULL,
    outcome text NOT NULL CHECK (outcome IN ('ACCEPTED', 'REJECTED', 'DUPLICATE')),
    processed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    detail text,
    CONSTRAINT ck_audit_record_processing_stg_type CHECK (
        (record_type = 'REFERENCE' AND stg_reference_record_id IS NOT NULL AND stg_telemetry_record_id IS NULL)
        OR
        (record_type = 'TELEMETRY' AND stg_reference_record_id IS NULL AND stg_telemetry_record_id IS NOT NULL)
    )
);

CREATE TABLE rejected.record (
    rejected_record_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_id uuid NOT NULL REFERENCES audit.load_run(run_id),
    record_type text NOT NULL CHECK (record_type IN ('REFERENCE', 'TELEMETRY')),
    stg_reference_record_id bigint REFERENCES stg.reference_record(stg_record_id),
    stg_telemetry_record_id bigint,
    source_name text NOT NULL,
    source_object text NOT NULL,
    entity_type text NOT NULL,
    source_record_id text,
    payload jsonb NOT NULL,
    correlation_id uuid NOT NULL,
    error_code text NOT NULL,
    error_text text NOT NULL,
    rejected_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    replay_status text NOT NULL DEFAULT 'PENDING'
        CHECK (replay_status IN ('PENDING', 'REPLAYED', 'DISCARDED')),
    CONSTRAINT ck_rejected_record_stg_type CHECK (
        (record_type = 'REFERENCE' AND stg_reference_record_id IS NOT NULL AND stg_telemetry_record_id IS NULL)
        OR
        (record_type = 'TELEMETRY' AND stg_reference_record_id IS NULL AND stg_telemetry_record_id IS NOT NULL)
    )
);

CREATE TABLE rejected.replay_history (
    replay_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    rejected_record_id bigint NOT NULL REFERENCES rejected.record(rejected_record_id),
    replay_run_id uuid REFERENCES audit.load_run(run_id),
    replayed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    outcome text NOT NULL,
    detail text
);

CREATE TABLE ods.plant (
    plant_id text PRIMARY KEY,
    plant_name text NOT NULL,
    timezone text NOT NULL,
    source_checksum char(64) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE ods.production_line (
    line_id text PRIMARY KEY,
    plant_id text NOT NULL REFERENCES ods.plant(plant_id),
    line_name text NOT NULL,
    source_checksum char(64) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE ods.equipment (
    equipment_id text PRIMARY KEY,
    line_id text NOT NULL REFERENCES ods.production_line(line_id),
    equipment_name text NOT NULL,
    equipment_type text NOT NULL,
    source_checksum char(64) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE ods.material (
    material_id text PRIMARY KEY,
    material_name text NOT NULL,
    grade text NOT NULL,
    source_checksum char(64) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE ods.material_parameter_range (
    material_id text NOT NULL REFERENCES ods.material(material_id) ON DELETE CASCADE,
    parameter_code text NOT NULL,
    unit text NOT NULL,
    min_value numeric NOT NULL,
    max_value numeric NOT NULL,
    PRIMARY KEY (material_id, parameter_code),
    CHECK (min_value <= max_value)
);

CREATE TABLE ods.production_batch (
    batch_id text PRIMARY KEY,
    material_id text NOT NULL REFERENCES ods.material(material_id),
    line_id text NOT NULL REFERENCES ods.production_line(line_id),
    equipment_id text NOT NULL REFERENCES ods.equipment(equipment_id),
    started_at timestamptz NOT NULL,
    ended_at timestamptz NOT NULL,
    status text NOT NULL,
    source_checksum char(64) NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CHECK (ended_at > started_at)
);

CREATE TABLE control.watermark (
    source_name text PRIMARY KEY,
    watermark_value text NOT NULL,
    watermark_record_id text,
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE control.reconciliation_result (
    reconciliation_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_id uuid REFERENCES audit.load_run(run_id),
    check_name text NOT NULL,
    expected_count integer NOT NULL,
    actual_count integer NOT NULL,
    status text NOT NULL CHECK (status IN ('MATCHED', 'MISMATCHED')),
    checked_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    detail text
);
