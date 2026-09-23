# NiFi telemetry flow runbook

## Start

Docker Desktop must be running. The first build downloads NiFi and the pinned
PostgreSQL JDBC driver and can take several minutes.

```bash
make start-nifi
```

This starts PostgreSQL, the FastAPI source simulator, and NiFi; waits for their
health checks; creates the Parameter Context and process group; enables the
controller services; and starts the processors.

Open `https://localhost:8443/nifi` and accept the local self-signed certificate.
Development login values are read from the local `.env` file. Create it once:

```bash
cp .env.example .env
```

The example credentials are only for the isolated local lab. Replace them in
`.env` if the host is shared; `.env` is ignored by Git.

## Verify

```bash
make verify-nifi
```

The check waits for the flow and proves that:

- 24 telemetry measurements are present;
- the composite watermark ends at `TEL-0024`;
- at least one load run came from the NiFi source object;
- every NiFi page reconciliation is matched.

To prove controlled replay and pagination against an already loaded ODS:

```bash
make replay-nifi
```

This removes only the `EXTRUDER_SCADA` checkpoint, requests one immediate poll,
accounts for the three pages `10 + 10 + 4`, proves that ODS remains at 24 rows,
and restores periodic polling.

## Re-provision

Running the bootstrap again is safe when the deployed process group was created
from the same specification:

```bash
make bootstrap-nifi
```

If the specification digest changed, bootstrap stops instead of overwriting a
possibly edited flow. For this local MVP, reset the NiFi volumes only after any
required provenance evidence has been saved:

```bash
docker compose down
docker volume ls --filter name=plantbridge_nifi
```

Removing volumes deletes the local flow configuration, queues, state, and
provenance and is therefore intentionally not automated.

## Failure triage

1. Inspect the `Log Technical Failure` processor and its incoming queue.
2. Check NiFi bulletins and provenance for `Invoke Telemetry API` or
   `Load Telemetry Page`.
3. Check `audit.load_run`, `stg.telemetry_record`, and `rejected.record` in
   PostgreSQL.
4. Correct the technical cause and replay from the unchanged database watermark.
