#!/usr/bin/env python3

from __future__ import annotations

import json

from downtime_kafka_adapter import DLQ_TOPIC, consume


def main() -> None:
    record = consume(DLQ_TOPIC, 1)[0]
    envelope = record["payload"]
    original = envelope.get("original_payload", {})
    errors = []
    if record["key"] != "EVT-DT-INVALID-START":
        errors.append(f"unexpected DLQ key {record['key']!r}")
    if original.get("reason_code") != "UNMAPPED_REASON":
        errors.append("DLQ does not preserve the unknown reason payload")
    if not isinstance(envelope.get("rejected_record_id"), int):
        errors.append("DLQ does not contain a numeric rejected_record_id")
    if "Unknown downtime reason_code" not in envelope.get("error_text", ""):
        errors.append("DLQ does not contain the database validation error")
    if errors:
        raise SystemExit("; ".join(errors))
    print(json.dumps({"topic": DLQ_TOPIC, "verified": 1, "event_id": record["key"]}))


if __name__ == "__main__":
    main()
