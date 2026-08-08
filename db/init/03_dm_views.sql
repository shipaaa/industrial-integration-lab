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
    0::bigint AS process_deviation_count,
    0::numeric AS downtime_minutes
FROM ods.production_batch b
JOIN ods.material m ON m.material_id = b.material_id
JOIN ods.production_line l ON l.line_id = b.line_id
JOIN ods.plant p ON p.plant_id = l.plant_id
JOIN ods.equipment e ON e.equipment_id = b.equipment_id;

CREATE OR REPLACE VIEW dm.dm_data_reconciliation AS
SELECT
    run_id,
    source_name,
    source_object,
    entity_type,
    received_count AS expected_count,
    accepted_count + rejected_count + duplicate_count AS accounted_count,
    received_count - (accepted_count + rejected_count + duplicate_count) AS difference,
    CASE
        WHEN received_count = accepted_count + rejected_count + duplicate_count
            THEN 'MATCHED'
        ELSE 'MISMATCHED'
    END AS reconciliation_status,
    started_at,
    finished_at
FROM audit.load_run;

CREATE OR REPLACE VIEW dm.dm_batch_process_deviations AS
SELECT
    b.batch_id,
    NULL::text AS parameter_code,
    NULL::timestamptz AS measured_at,
    NULL::numeric AS measured_value,
    NULL::numeric AS min_value,
    NULL::numeric AS max_value
FROM ods.production_batch b
WHERE false;
