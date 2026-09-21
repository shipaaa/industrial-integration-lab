\set ON_ERROR_STOP on

SELECT ods.load_downtime_event(
    $event${"schema_version":"1.0","source_system":"MAINTENANCE_CMS","event_id":"EVT-DT-INVALID-START","downtime_id":"DT-REPLAY","event_type":"DOWNTIME_STARTED","batch_id":"BATCH-001","equipment_id":"EXT-01","reason_code":"PLANNED_CLEANING","occurred_at":"2026-07-15T05:45:00Z"}$event$::jsonb,
    'plantbridge.downtime.replay', 0, 0, 'EVT-DT-INVALID-START',
    (
        SELECT rejected_record_id
        FROM rejected.record
        WHERE record_type = 'DOWNTIME'
          AND source_record_id = 'EVT-DT-INVALID-START'
          AND replay_status = 'PENDING'
        ORDER BY rejected_record_id DESC
        LIMIT 1
    )
);

SELECT ods.load_downtime_event(
    $event${"schema_version":"1.0","source_system":"MAINTENANCE_CMS","event_id":"EVT-DT-REPLAY-END","downtime_id":"DT-REPLAY","event_type":"DOWNTIME_ENDED","batch_id":"BATCH-001","equipment_id":"EXT-01","reason_code":"PLANNED_CLEANING","occurred_at":"2026-07-15T05:48:00Z"}$event$::jsonb,
    'plantbridge.downtime.replay', 0, 1, 'EVT-DT-REPLAY-END'
);
