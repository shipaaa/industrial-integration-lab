\set ON_ERROR_STOP on

SELECT ods.load_downtime_event(
    $event${"schema_version":"1.0","source_system":"MAINTENANCE_CMS","event_id":"EVT-DT-003-START","downtime_id":"DT-003","event_type":"DOWNTIME_STARTED","batch_id":"BATCH-003","equipment_id":"EXT-01","reason_code":"MATERIAL_JAM","occurred_at":"2026-07-15T10:40:00Z"}$event$::jsonb,
    'plantbridge.downtime.events', 0, 0, 'EVT-DT-003-START'
);

SELECT ods.load_downtime_event(
    $event${"schema_version":"1.0","source_system":"MAINTENANCE_CMS","event_id":"EVT-DT-003-END","downtime_id":"DT-003","event_type":"DOWNTIME_ENDED","batch_id":"BATCH-003","equipment_id":"EXT-01","reason_code":"MATERIAL_JAM","occurred_at":"2026-07-15T10:47:00Z"}$event$::jsonb,
    'plantbridge.downtime.events', 0, 1, 'EVT-DT-003-END'
);

SELECT ods.load_downtime_event(
    $event${"schema_version":"1.0","source_system":"MAINTENANCE_CMS","event_id":"EVT-DT-003-END","downtime_id":"DT-003","event_type":"DOWNTIME_ENDED","batch_id":"BATCH-003","equipment_id":"EXT-01","reason_code":"MATERIAL_JAM","occurred_at":"2026-07-15T10:47:00Z"}$event$::jsonb,
    'plantbridge.downtime.events', 0, 2, 'EVT-DT-003-END'
);

SELECT ods.load_downtime_event(
    $event${"schema_version":"1.0","source_system":"MAINTENANCE_CMS","event_id":"EVT-DT-002-START","downtime_id":"DT-002","event_type":"DOWNTIME_STARTED","batch_id":"BATCH-002","equipment_id":"EXT-01","reason_code":"PLANNED_CLEANING","occurred_at":"2026-07-15T08:10:00Z"}$event$::jsonb,
    'plantbridge.downtime.events', 0, 3, 'EVT-DT-002-START'
);

SELECT ods.load_downtime_event(
    $event${"schema_version":"1.0","source_system":"MAINTENANCE_CMS","event_id":"EVT-DT-002-END","downtime_id":"DT-002","event_type":"DOWNTIME_ENDED","batch_id":"BATCH-002","equipment_id":"EXT-01","reason_code":"PLANNED_CLEANING","occurred_at":"2026-07-15T08:20:00Z"}$event$::jsonb,
    'plantbridge.downtime.events', 0, 4, 'EVT-DT-002-END'
);

SELECT ods.load_downtime_event(
    $event${"schema_version":"1.0","source_system":"MAINTENANCE_CMS","event_id":"EVT-DT-INVALID-START","downtime_id":"DT-REPLAY","event_type":"DOWNTIME_STARTED","batch_id":"BATCH-001","equipment_id":"EXT-01","reason_code":"UNMAPPED_REASON","occurred_at":"2026-07-15T05:45:00Z"}$event$::jsonb,
    'plantbridge.downtime.events', 0, 5, 'EVT-DT-INVALID-START'
);
