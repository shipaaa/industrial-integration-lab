#!/usr/bin/env python3
"""Temporary Kafka-to-PostgreSQL adapter for the downtime contract slice.

NiFi orchestration is intentionally deferred. This adapter keeps Kafka record
metadata intact, calls the same database contract NiFi will use, and publishes
database rejections to the DLQ.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess
from typing import Any


EVENTS_TOPIC = "plantbridge.downtime.events"
REPLAY_TOPIC = "plantbridge.downtime.replay"
DLQ_TOPIC = "plantbridge.downtime.dlq"
ALLOWED_TOPICS = (EVENTS_TOPIC, REPLAY_TOPIC)
PROJECT_DIR = Path(__file__).resolve().parents[1]


def run(command: list[str], *, stdin: str | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=PROJECT_DIR,
        input=stdin,
        text=True,
        capture_output=True,
        check=True,
    )


def compose_command(*args: str) -> list[str]:
    return ["docker", "compose", "--project-directory", str(PROJECT_DIR), *args]


def parse_consumer_line(line: str) -> dict[str, Any]:
    partition_part, offset_part, key, raw_payload = line.split("|", 3)
    if not partition_part.startswith("Partition:"):
        raise ValueError(f"Missing partition metadata: {line!r}")
    if not offset_part.startswith("Offset:"):
        raise ValueError(f"Missing offset metadata: {line!r}")

    payload = json.loads(raw_payload)
    if not isinstance(payload, dict):
        raise ValueError("Kafka value must be a JSON object")

    return {
        "partition": int(partition_part.removeprefix("Partition:")),
        "offset": int(offset_part.removeprefix("Offset:")),
        "key": key,
        "payload": payload,
    }


def consume(topic: str, max_messages: int) -> list[dict[str, Any]]:
    result = run(
        compose_command(
            "exec",
            "-T",
            "kafka",
            "/opt/kafka/bin/kafka-console-consumer.sh",
            "--bootstrap-server",
            "kafka:19092",
            "--topic",
            topic,
            "--from-beginning",
            "--max-messages",
            str(max_messages),
            "--timeout-ms",
            "15000",
            "--formatter",
            "org.apache.kafka.tools.consumer.DefaultMessageFormatter",
            "--formatter-property",
            "print.partition=true",
            "--formatter-property",
            "print.offset=true",
            "--formatter-property",
            "print.key=true",
            "--formatter-property",
            "print.value=true",
            "--formatter-property",
            "key.separator=|",
        )
    )
    lines = [
        line for line in result.stdout.splitlines() if line.startswith("Partition:")
    ]
    if len(lines) != max_messages:
        raise RuntimeError(
            f"Expected {max_messages} messages from {topic}, received {len(lines)}"
        )
    return [parse_consumer_line(line) for line in lines]


def dollar_quote(value: str, label: str) -> str:
    tag = f"$plantbridge_{label}$"
    if tag in value:
        raise ValueError(f"Value contains reserved SQL dollar-quote tag {tag}")
    return f"{tag}{value}{tag}"


def psql_scalar(sql: str) -> str:
    result = run(
        compose_command(
            "exec",
            "-T",
            "postgres",
            "psql",
            "--username",
            "plantbridge",
            "--dbname",
            "plantbridge",
            "--set",
            "ON_ERROR_STOP=1",
            "--tuples-only",
            "--no-align",
        ),
        stdin=sql,
    )
    values = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    return values[-1] if values else ""


def pending_rejection_id(event_id: str) -> int | None:
    quoted_event_id = dollar_quote(event_id, "event_id")
    value = psql_scalar(
        "SELECT rejected_record_id "
        "FROM rejected.record "
        "WHERE record_type = 'DOWNTIME' "
        f"AND source_record_id = {quoted_event_id} "
        "AND replay_status = 'PENDING' "
        "ORDER BY rejected_record_id DESC LIMIT 1;\n"
    )
    return int(value) if value else None


def load_record(topic: str, record: dict[str, Any], replay_id: int | None) -> dict[str, Any]:
    raw_payload = json.dumps(record["payload"], separators=(",", ":"), sort_keys=True)
    replay_sql = "NULL" if replay_id is None else str(replay_id)
    sql = (
        "SELECT ods.load_downtime_event("
        f"{dollar_quote(raw_payload, 'payload')}::jsonb, "
        f"{dollar_quote(topic, 'topic')}, "
        f"{record['partition']}, {record['offset']}, "
        f"{dollar_quote(record['key'], 'key')}, {replay_sql});\n"
    )
    raw_result = psql_scalar(sql)
    result = json.loads(raw_result)
    if not isinstance(result, dict) or "outcome" not in result:
        raise RuntimeError(f"Unexpected database result: {raw_result!r}")
    return result


def publish_dlq(topic: str, record: dict[str, Any], result: dict[str, Any]) -> None:
    envelope = {
        "schema_version": "1.0",
        "original_topic": topic,
        "original_partition": record["partition"],
        "original_offset": record["offset"],
        "original_key": record["key"],
        "original_payload": record["payload"],
        "rejected_record_id": result["rejected_record_id"],
        "correlation_id": result["correlation_id"],
        "error_code": result["error_code"],
        "error_text": result["error_text"],
    }
    line = record["key"] + "|" + json.dumps(envelope, separators=(",", ":")) + "\n"
    run(
        compose_command(
            "exec",
            "-T",
            "kafka",
            "/opt/kafka/bin/kafka-console-producer.sh",
            "--bootstrap-server",
            "kafka:19092",
            "--topic",
            DLQ_TOPIC,
            "--reader-property",
            "parse.key=true",
            "--reader-property",
            "key.separator=|",
        ),
        stdin=line,
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--topic", required=True, choices=ALLOWED_TOPICS)
    parser.add_argument("--max-messages", required=True, type=int)
    args = parser.parse_args()
    if args.max_messages <= 0:
        parser.error("--max-messages must be positive")

    totals = {"ACCEPTED": 0, "DUPLICATE": 0, "REJECTED": 0}
    for record in consume(args.topic, args.max_messages):
        event_id = str(record["payload"].get("event_id", ""))
        replay_id = pending_rejection_id(event_id) if args.topic == REPLAY_TOPIC else None
        result = load_record(args.topic, record, replay_id)
        outcome = result["outcome"]
        totals[outcome] = totals.get(outcome, 0) + 1
        if outcome == "REJECTED":
            publish_dlq(args.topic, record, result)

    print(json.dumps({"topic": args.topic, "processed": args.max_messages, **totals}))


if __name__ == "__main__":
    main()
