ALTER TABLE stg.downtime_event_record
    ADD COLUMN IF NOT EXISTS kafka_timestamp timestamptz;

ALTER TABLE ods.downtime_event
    ADD COLUMN IF NOT EXISTS source_timestamp timestamptz;

CREATE OR REPLACE FUNCTION ods.load_downtime_kafka_record(
    p_message_text text,
    p_topic_name text,
    p_partition_id integer,
    p_offset_id bigint,
    p_message_key text,
    p_kafka_timestamp_ms bigint,
    p_is_replay boolean DEFAULT false
) RETURNS TABLE (
    run_id text,
    correlation_id text,
    outcome text,
    rejected_record_id bigint,
    error_code text,
    error_text text
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_message jsonb;
    v_result jsonb;
    v_replay_of_rejected_record_id bigint;
    v_run_id uuid;
    v_kafka_timestamp timestamptz;
BEGIN
    v_message := p_message_text::jsonb;
    v_kafka_timestamp := to_timestamp(p_kafka_timestamp_ms / 1000.0);

    IF p_is_replay THEN
        SELECT record.rejected_record_id
        INTO v_replay_of_rejected_record_id
        FROM rejected.record record
        WHERE record.record_type = 'DOWNTIME'
          AND record.source_record_id = v_message->>'event_id'
          AND record.replay_status = 'PENDING'
        ORDER BY record.rejected_at DESC
        LIMIT 1;

    END IF;

    v_result := ods.load_downtime_event(
        v_message,
        p_topic_name,
        p_partition_id,
        p_offset_id,
        p_message_key,
        v_replay_of_rejected_record_id
    );
    v_run_id := (v_result->>'run_id')::uuid;

    UPDATE stg.downtime_event_record
    SET kafka_timestamp = v_kafka_timestamp
    WHERE stg.downtime_event_record.run_id = v_run_id;

    IF v_result->>'outcome' = 'ACCEPTED' THEN
        UPDATE ods.downtime_event
        SET source_timestamp = v_kafka_timestamp
        WHERE event_id = v_message->>'event_id'
          AND source_topic = p_topic_name
          AND source_partition = p_partition_id
          AND source_offset = p_offset_id;
    END IF;

    RETURN QUERY SELECT
        v_result->>'run_id',
        v_result->>'correlation_id',
        v_result->>'outcome',
        NULLIF(v_result->>'rejected_record_id', '')::bigint,
        v_result->>'error_code',
        v_result->>'error_text';
END;
$$;
