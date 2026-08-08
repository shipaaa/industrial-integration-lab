#!/usr/bin/env bash
set -euo pipefail

plantbridge_project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plantbridge_pg_bindir="$(pg_config --bindir)"

if [[ ! -x "${plantbridge_pg_bindir}/postgres" ]]; then
  echo "PostgreSQL server binaries are required for the local database test." >&2
  exit 2
fi

plantbridge_test_root="$(mktemp -d /tmp/plantbridge-pg.XXXXXX)"
plantbridge_data_dir="${plantbridge_test_root}/data"
plantbridge_socket_dir="${plantbridge_test_root}/socket"
plantbridge_port=55439

mkdir -p "${plantbridge_socket_dir}"
"${plantbridge_pg_bindir}/initdb" \
  --auth=trust \
  --no-locale \
  --pgdata "${plantbridge_data_dir}" >/dev/null

cleanup_plantbridge_postgres() {
  "${plantbridge_pg_bindir}/pg_ctl" \
    --pgdata "${plantbridge_data_dir}" \
    --mode fast \
    stop >/dev/null 2>&1 || true
}
trap cleanup_plantbridge_postgres EXIT

"${plantbridge_pg_bindir}/pg_ctl" \
  --pgdata "${plantbridge_data_dir}" \
  --log "${plantbridge_test_root}/postgres.log" \
  --options "-F -k ${plantbridge_socket_dir} -p ${plantbridge_port}" \
  start >/dev/null

"${plantbridge_pg_bindir}/createdb" \
  --host "${plantbridge_socket_dir}" \
  --port "${plantbridge_port}" \
  plantbridge

for plantbridge_sql_file in \
  db/init/00_schemas.sql \
  db/init/01_tables.sql \
  db/init/02_reference_ingestion.sql \
  db/init/03_dm_views.sql
do
  "${plantbridge_pg_bindir}/psql" \
    --host "${plantbridge_socket_dir}" \
    --port "${plantbridge_port}" \
    --dbname plantbridge \
    --set ON_ERROR_STOP=1 \
    --file "${plantbridge_project_dir}/${plantbridge_sql_file}" >/dev/null
done

load_reference_document() {
  local plantbridge_entity_type="$1"
  local plantbridge_filename="$2"
  local plantbridge_document_json

  plantbridge_document_json="$(python3 -c \
    'import json, sys; print(json.dumps(json.load(open(sys.argv[1], encoding="utf-8")), separators=(",", ":")))' \
    "${plantbridge_project_dir}/data/reference/${plantbridge_filename}")"

  "${plantbridge_pg_bindir}/psql" \
    --host "${plantbridge_socket_dir}" \
    --port "${plantbridge_port}" \
    --dbname plantbridge \
    --set ON_ERROR_STOP=1 \
    --set entity_type="${plantbridge_entity_type}" \
    --set source_object="${plantbridge_filename}" \
    --set document_json="${plantbridge_document_json}" <<'SQL' >/dev/null
SELECT ods.load_reference_document(
    :'entity_type', :'document_json'::jsonb, :'source_object'
);
SQL
}

load_all_reference_documents() {
  load_reference_document plants plants.json
  load_reference_document lines lines.json
  load_reference_document equipment equipment.json
  load_reference_document materials materials.json
  load_reference_document batches batches.json
}

load_all_reference_documents
load_all_reference_documents

"${plantbridge_pg_bindir}/psql" \
  --host "${plantbridge_socket_dir}" \
  --port "${plantbridge_port}" \
  --dbname plantbridge \
  --set ON_ERROR_STOP=1 \
  --file "${plantbridge_project_dir}/db/test/verify_reference.sql"
