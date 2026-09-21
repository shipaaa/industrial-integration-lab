#!/usr/bin/env python3

from __future__ import annotations

import json

from downtime_kafka_adapter import consume


RECEIPT_TOPIC = "plantbridge.downtime.receipts"


def main() -> None:
    records = consume(RECEIPT_TOPIC, 7)
    receipts = [record["payload"] for record in records]
    outcomes = [receipt.get("outcome") for receipt in receipts]
    errors: list[str] = []

    if outcomes.count("ACCEPTED") != 6:
        errors.append(f"expected 6 ACCEPTED receipts, got {outcomes.count('ACCEPTED')}")
    if outcomes.count("DUPLICATE") != 1:
        errors.append(
            f"expected 1 DUPLICATE receipt, got {outcomes.count('DUPLICATE')}"
        )
    coordinates = {
        (
            receipt.get("source_topic"),
            receipt.get("source_partition"),
            receipt.get("source_offset"),
        )
        for receipt in receipts
    }
    if len(coordinates) != 7:
        errors.append("receipt Kafka coordinates are not unique")
    if any(not isinstance(receipt.get("source_timestamp"), int) for receipt in receipts):
        errors.append("a receipt is missing the Kafka timestamp")
    if any(not receipt.get("run_id") or not receipt.get("correlation_id") for receipt in receipts):
        errors.append("a receipt is missing database lineage")
    if errors:
        raise SystemExit("; ".join(errors))

    print(
        json.dumps(
            {
                "topic": RECEIPT_TOPIC,
                "verified": len(receipts),
                "accepted": outcomes.count("ACCEPTED"),
                "duplicate": outcomes.count("DUPLICATE"),
            }
        )
    )


if __name__ == "__main__":
    main()
