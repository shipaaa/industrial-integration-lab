SELECT ods.load_reference_document(
    'plants', pg_read_file('/reference/plants.json')::jsonb, 'plants.json'
);
SELECT ods.load_reference_document(
    'lines', pg_read_file('/reference/lines.json')::jsonb, 'lines.json'
);
SELECT ods.load_reference_document(
    'equipment', pg_read_file('/reference/equipment.json')::jsonb, 'equipment.json'
);
SELECT ods.load_reference_document(
    'materials', pg_read_file('/reference/materials.json')::jsonb, 'materials.json'
);
SELECT ods.load_reference_document(
    'batches', pg_read_file('/reference/batches.json')::jsonb, 'batches.json'
);
