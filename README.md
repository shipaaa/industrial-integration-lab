# Industrial Integration Lab

**Polymer Production Quality & Downtime**

Portfolio-grade industrial data integration project demonstrating how equipment telemetry, laboratory quality results, reference data, and downtime events can be ingested, validated, reconciled, and prepared for analysis.

The lab is designed to demonstrate the practical responsibilities of a Middle Technical Implementation Engineer: discovery, source analysis, solution design, data mapping, integration development, testing, deployment planning, troubleshooting, and operational handover.

> **Project status:** Stage 1 — Platform Foundation. ADR-001 is accepted and the
> reference-data vertical slice is implemented as an executable database
> contract. NiFi deployment is the next architecture gate.

## Business Scenario

A polymer compounding plant produces batches of granular materials on extrusion lines. Product quality depends on stable process conditions, correct raw materials, and controlled equipment operation.

Operational data is distributed across four source channels:

| Source | Format | Example data |
|---|---|---|
| Equipment telemetry API | REST / JSON | temperature, pressure, screw speed, power consumption, equipment status |
| Laboratory results | CSV | moisture, density, melt flow index, test result and specification limits |
| Equipment and material reference data | JSON files | production lines, equipment, materials and valid operating ranges |
| Downtime events | Kafka messages | downtime start, end, reason, equipment and event status |

The integration platform will connect these datasets so that production and quality teams can investigate questions such as:

- Did process deviations occur during a production batch?
- Which equipment and materials were associated with a failed laboratory result?
- How much downtime occurred by line, equipment, and reason?
- Were all expected source records loaded exactly once?
- Can rejected or missed data be safely corrected and replayed?

## Planned Solution

```mermaid
flowchart LR
    API["FastAPI telemetry source"] --> NIFI["Apache NiFi"]
    CSV["Laboratory CSV files"] --> NIFI
    JSON["Reference JSON files"] --> NIFI
    KAFKA["Kafka downtime events"] --> NIFI

    NIFI --> STG["PostgreSQL STG"]
    STG --> ODS["PostgreSQL ODS"]
    ODS --> DDS["PostgreSQL DDS"]
    DDS --> DM["PostgreSQL DM"]

    NIFI --> REJECTED["Rejected records"]
    KAFKA --> DLQ["Kafka DLQ"]
```

The complete environment is intended to run locally through Docker Compose and contain:

- a FastAPI application that simulates the telemetry source system;
- Apache NiFi for ingestion, validation, routing, retry, and failure handling;
- a single-broker Kafka setup for downtime-event delivery and replay exercises;
- PostgreSQL organized into STG, ODS, DDS, and DM layers;
- separate audit, control, reconciliation, and rejected-record structures;
- structured logs and correlation IDs for end-to-end traceability.

## Target Capabilities

The implementation will demonstrate:

- incremental data loading;
- idempotent processing and duplicate handling;
- safe reruns without double-counting;
- schema and business-rule validation;
- data-quality checks and source-to-target reconciliation;
- NiFi provenance, back pressure, retry, and failure routes;
- Kafka consumer recovery, DLQ handling, and controlled replay;
- source-to-target mapping and data lineage;
- operational troubleshooting using logs, audit data, and correlation IDs;
- UAT, rollout, rollback, and support documentation.

## Data Platform Layers

| Layer | Responsibility |
|---|---|
| **STG** | Preserve received source data and ingestion metadata with minimal transformation |
| **ODS** | Store validated, standardized, and deduplicated operational records |
| **DDS** | Represent conformed dimensions and facts at explicitly defined grains |
| **DM** | Provide focused analytical datasets for quality and downtime analysis |

Invalid records will not be silently discarded. They will be stored separately with the original payload, validation reason, source metadata, correlation ID, and processing timestamp.

## Implementation Lifecycle

The project is organized into five stages:

1. **Discovery and Design** — business scope, requirements, source contracts, mappings, architecture, data model, and acceptance criteria.
2. **Platform Foundation** — Docker Compose, PostgreSQL, Kafka, NiFi, and source simulation.
3. **Integration Implementation** — ingestion flows, DWH layers, validation, idempotency, and error handling.
4. **Verification and Operations** — automated checks, reconciliation, UAT, replay, incident cases, and runbook.
5. **Portfolio Packaging** — architecture diagrams, screenshots, reproducible demo, and final documentation.

## Scope Boundaries

This is an integration and data-engineering laboratory, not a full manufacturing execution system.

The project intentionally excludes:

- frontend development;
- production planning and order management;
- operator and shift management;
- recipe lifecycle management;
- predictive maintenance and machine learning;
- Kubernetes and cloud infrastructure;
- a BI platform;
- complex Kafka platform administration;
- microservice architecture.

Kafka is used only at the application level to demonstrate event consumption, duplicate handling, failure isolation, and replay.

## Planned Evidence

The completed portfolio project will include:

- documented discovery decisions and assumptions;
- functional and non-functional requirements;
- four versioned source contracts;
- source-to-target mappings and lineage diagrams;
- reproducible Docker-based deployment;
- NiFi flow documentation and provenance screenshots;
- SQL data-quality and reconciliation results;
- UAT scenarios and acceptance evidence;
- rollout and rollback checklists;
- an operational runbook;
- two documented incident investigations;
- a guided end-to-end demo.

## Current Work

Stage 0 must be reviewed and agreed before code or infrastructure implementation starts. The immediate deliverables are:

- project charter and business scenario;
- discovery questions;
- functional and non-functional requirements;
- assumptions, constraints, and out-of-scope items;
- measurable acceptance criteria;
- source contracts for REST, CSV, JSON, and Kafka;
- initial dimensional model with declared grains;
- documentation structure for the implementation lifecycle.

## Technology Stack

- **API:** Python, FastAPI
- **Integration:** Apache NiFi
- **Event transport:** Apache Kafka, single broker
- **Database:** PostgreSQL
- **Runtime:** Docker Compose, Linux containers
- **Documentation:** Markdown, Mermaid diagrams

## First Vertical Slice

The current slice loads one plant, one line, one extruder, two materials, and
three production batches from JSON into PostgreSQL. It preserves the raw record,
audits every attempt, rejects invalid records, treats an unchanged replay as a
duplicate, and exposes the initial `BATCH-003` dossier.

Prerequisites: Docker with Compose v2 and Python 3.9 or newer.

```bash
make test
make start
make verify-reference
make replay-reference
```

`make start` initializes and loads the reference files on a new PostgreSQL
volume. `make replay-reference` loads the same documents again and proves that
the ODS counts remain unchanged while duplicate attempts appear in audit.

The shell loader is a temporary contract-test adapter. The accepted target
architecture calls the same `ods.load_reference_document` function from NiFi.

Architecture decisions are recorded in [`docs/adr`](docs/adr), and the current
solution design is in [`docs/04-solution-design.md`](docs/04-solution-design.md).
