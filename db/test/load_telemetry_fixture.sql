WITH fixture AS (
    SELECT pg_read_file('/telemetry/telemetry.json')::jsonb AS document
), page AS (
    SELECT jsonb_build_object(
        'records', document->'records',
        'record_count', jsonb_array_length(document->'records'),
        'has_more', false,
        'next_watermark', jsonb_build_object(
            'updated_at', '2026-07-16T13:00:05Z',
            'source_record_id', 'TEL-0024'
        )
    ) AS payload
    FROM fixture
)
SELECT ods.load_telemetry_page(
    payload,
    'EXTRUDER_SCADA',
    'GET /telemetry bootstrap contract test'
)
FROM page;
