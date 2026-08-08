DO $$
DECLARE
    v_count integer;
BEGIN
    SELECT count(*) INTO v_count FROM ods.plant;
    IF v_count <> 1 THEN RAISE EXCEPTION 'Expected 1 plant, got %', v_count; END IF;

    SELECT count(*) INTO v_count FROM ods.production_line;
    IF v_count <> 1 THEN RAISE EXCEPTION 'Expected 1 line, got %', v_count; END IF;

    SELECT count(*) INTO v_count FROM ods.equipment;
    IF v_count <> 1 THEN RAISE EXCEPTION 'Expected 1 equipment, got %', v_count; END IF;

    SELECT count(*) INTO v_count FROM ods.material;
    IF v_count <> 2 THEN RAISE EXCEPTION 'Expected 2 materials, got %', v_count; END IF;

    SELECT count(*) INTO v_count FROM ods.production_batch;
    IF v_count <> 3 THEN RAISE EXCEPTION 'Expected 3 batches, got %', v_count; END IF;

    SELECT count(*) INTO v_count
    FROM dm.dm_batch_investigation
    WHERE batch_id = 'BATCH-003';
    IF v_count <> 1 THEN RAISE EXCEPTION 'BATCH-003 dossier is missing'; END IF;

    SELECT count(*) INTO v_count
    FROM dm.dm_data_reconciliation
    WHERE reconciliation_status <> 'MATCHED';
    IF v_count <> 0 THEN RAISE EXCEPTION 'Found % mismatched load runs', v_count; END IF;
END $$;

SELECT batch_id, material_id, line_id, equipment_id, started_at, ended_at
FROM dm.dm_batch_investigation
WHERE batch_id = 'BATCH-003';

SELECT source_object, received_count, accepted_count, rejected_count, duplicate_count
FROM audit.load_run
ORDER BY started_at;
