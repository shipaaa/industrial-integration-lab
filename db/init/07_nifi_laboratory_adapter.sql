CREATE OR REPLACE FUNCTION ods.load_laboratory_csv(
    p_rows jsonb,
    p_source_name text,
    p_source_object text,
    p_file_checksum text,
    p_replay_of_rejected_record_id bigint DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    v_numbered_rows jsonb;
BEGIN
    IF jsonb_typeof(p_rows) <> 'array' THEN
        RAISE EXCEPTION 'Laboratory CSV rows must be a JSON array';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM jsonb_array_elements(p_rows) AS source_row(value)
        WHERE jsonb_typeof(source_row.value) <> 'object'
    ) THEN
        RAISE EXCEPTION 'Every laboratory CSV row must be a JSON object';
    END IF;

    SELECT COALESCE(
        jsonb_agg(
            source_row.value
            || jsonb_build_object('row_number', source_row.ordinality + 1)
            ORDER BY source_row.ordinality
        ),
        '[]'::jsonb
    )
    INTO v_numbered_rows
    FROM jsonb_array_elements(p_rows) WITH ORDINALITY
        AS source_row(value, ordinality);

    RETURN ods.load_laboratory_file(
        v_numbered_rows,
        p_source_name,
        p_source_object,
        p_file_checksum,
        p_replay_of_rejected_record_id
    );
END;
$$;
