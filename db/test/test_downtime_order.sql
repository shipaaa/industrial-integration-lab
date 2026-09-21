\set ON_ERROR_STOP on

BEGIN;

SELECT ods.load_downtime_event(
    $event${"schema_version":"1.0","source_system":"MAINTENANCE_CMS","event_id":"EVT-DT-ORDER-START","downtime_id":"DT-ORDER","event_type":"DOWNTIME_STARTED","batch_id":"BATCH-001","equipment_id":"EXT-01","reason_code":"MATERIAL_JAM","occurred_at":"2026-07-15T05:50:00Z"}$event$::jsonb,
    'plantbridge.downtime.events', 0, 100, 'EVT-DT-ORDER-START'
);

SELECT ods.load_downtime_event(
    $event${"schema_version":"1.0","source_system":"MAINTENANCE_CMS","event_id":"EVT-DT-ORDER-END","downtime_id":"DT-ORDER","event_type":"DOWNTIME_ENDED","batch_id":"BATCH-001","equipment_id":"EXT-01","reason_code":"MATERIAL_JAM","occurred_at":"2026-07-15T05:49:00Z"}$event$::jsonb,
    'plantbridge.downtime.events', 0, 101, 'EVT-DT-ORDER-END'
);

DO $$
DECLARE
    v_status text;
    v_rejected bigint;
BEGIN
    SELECT status INTO v_status
    FROM ods.downtime_incident WHERE downtime_id = 'DT-ORDER';
    IF v_status <> 'OPEN' THEN
        RAISE EXCEPTION 'Out-of-order end changed incident status to %', v_status;
    END IF;

    SELECT count(*) INTO v_rejected
    FROM rejected.record
    WHERE record_type = 'DOWNTIME'
      AND source_record_id = 'EVT-DT-ORDER-END'
      AND error_text LIKE 'Downtime end % is earlier than start %';
    IF v_rejected <> 1 THEN
        RAISE EXCEPTION 'Expected out-of-order end rejection, got %', v_rejected;
    END IF;
END;
$$;

ROLLBACK;
