# Solution design

## MVP topology

```mermaid
flowchart LR
    JSON["Reference JSON"] --> NIFI["Apache NiFi"]
    REST["FastAPI telemetry"] --> NIFI
    CSV["Laboratory CSV"] --> NIFI
    KAFKA["Kafka downtime events"] --> NIFI
    NIFI --> CONTRACT["PostgreSQL ingestion contracts"]
    CONTRACT --> STG["STG raw records"]
    CONTRACT --> ODS["ODS validated facts"]
    CONTRACT --> REJECTED["Rejected records"]
    ODS --> DM["DM investigation and reconciliation"]
    CONTRACT --> AUDIT["Audit and control"]
```

## First vertical slice

The first executable slice loads reference documents in dependency order:

```text
plants -> lines -> equipment -> materials -> batches
```

Each record is preserved in `stg.reference_record`, then validated and upserted
into an entity-specific ODS table. A SHA-256 checksum identifies an unchanged
repeat delivery. Every attempt creates a new load run even when every record is
a duplicate.

The slice is complete when:

1. one plant, one line, one extruder, two materials, and three batches exist;
2. replay does not change ODS row counts;
3. replay is visible in audit as duplicate processing;
4. `dm.dm_batch_investigation` returns one dossier row for `BATCH-003`;
5. received equals accepted plus rejected plus duplicate for every load run.

## NiFi deployment

The local MVP runs Apache NiFi 2.10.0 as one secure node. The telemetry process
group is described by a declarative JSON specification in Git and provisioned
through the NiFi REST API. A Parameter Context separates endpoints, credentials,
page size, and retry policy from processor topology. A standalone NiFi Registry
is not deployed because it is deprecated; the deployment decision is recorded
in [`ADR-004`](adr/0004-nifi-telemetry-flow-deployment.md).

REST watermark semantics are defined in
[`ADR-002`](adr/0002-telemetry-watermark-and-pagination.md).

## Telemetry database slice

NiFi will pass one API page to `ods.load_telemetry_page`. PostgreSQL preserves
every delivery in STG, validates and deduplicates records into ODS, calculates
material-range deviations, records reconciliation, and advances the composite
watermark at the end of the transaction. The transaction boundary is defined
in [`ADR-003`](adr/0003-telemetry-page-transaction.md).

The process group reads the current composite watermark, calls the paginated API,
retries HTTP and database technical failures independently, and follows
`has_more` only after the database transaction succeeds. Business-invalid
records remain a successful page outcome because PostgreSQL isolates them in
`rejected.record` and reconciles the page.
