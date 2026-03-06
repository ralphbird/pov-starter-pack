#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["httpx"]
# ///
"""Push 24h of synthetic logs to Grafana Cloud Loki.

Usage:
    cd pov-starter-pack
    LOKI_URL=https://logs-prod-xxx.grafana.net/loki/api/v1/push \
    LOKI_USERNAME=123456 \
    LOKI_API_KEY=glc_xxx \
    uv run scripts/seed-logs.py
"""

import json
import os
import sys
import time
from dataclasses import dataclass

import httpx

LOKI_URL = os.environ.get("LOKI_URL", "")
LOKI_USERNAME = os.environ.get("LOKI_USERNAME", "")
LOKI_API_KEY = os.environ.get("LOKI_API_KEY", "")

if not all([LOKI_URL, LOKI_USERNAME, LOKI_API_KEY]):
    print("Required env vars: LOKI_URL, LOKI_USERNAME, LOKI_API_KEY", file=sys.stderr)
    sys.exit(1)

HOURS = 24
SERVICE = "orbitpay-frontend"
BATCH_SIZE = 5000

NAMES = [
    "Alice Chen", "Bob Martinez", "Carol Singh", "Dave Okonkwo", "Eve Johansson",
    "Frank Petrov", "Grace Tanaka", "Hiro Yamamoto", "Ingrid Larsen", "James Osei",
]


class SeededRandom:
    def __init__(self, seed: int) -> None:
        self._state = seed

    def next(self) -> float:
        self._state = (self._state * 1664525 + 1013904223) & 0x7FFFFFFF
        return self._state / 0x7FFFFFFF


@dataclass
class LogEntry:
    timestamp_ns: str
    line: str


def generate_logs(rand: SeededRandom) -> list[LogEntry]:
    entries: list[LogEntry] = []
    now_ms = int(time.time() * 1000)
    start_ms = now_ms - HOURS * 3600 * 1000
    cursor = start_ms

    while cursor < now_ms:
        gap_ms = 800 + int(rand.next() * 400)
        cursor += gap_ms
        if cursor >= now_ms:
            break

        ts_ns = str(cursor * 1_000_000)
        account_id = f"ACC-{int(rand.next() * 9000 + 1000)}"
        name = NAMES[int(rand.next() * len(NAMES))]
        amount = f"{(int(rand.next() * 50000) / 100 + 10):.2f}"
        tx_id = f"TXN-{cursor:X}-{int(rand.next() * 0xFFFF):04X}"
        duration_ms = int(rand.next() * 400 + 50)

        entries.append(LogEntry(
            timestamp_ns=ts_ns,
            line=json.dumps({
                "severity": "info",
                "body": "transfer initiated",
                "attributes": {"route": "/transfer", "accountId": account_id, "amount": amount},
            }),
        ))

        completion_ns = str((cursor + duration_ms) * 1_000_000)
        r = rand.next()

        if r < 0.001:
            entries.append(LogEntry(
                timestamp_ns=completion_ns,
                line=json.dumps({
                    "severity": "error",
                    "body": "payments-api call failed",
                    "attributes": {
                        "route": "/transfer",
                        "error": "ETIMEDOUT: connect timeout",
                    },
                }),
            ))
        elif r < 0.006:
            entries.append(LogEntry(
                timestamp_ns=completion_ns,
                line=json.dumps({
                    "severity": "warn",
                    "body": "transfer slow",
                    "attributes": {
                        "route": "/transfer",
                        "txId": tx_id,
                        "durationMs": duration_ms + 1500,
                    },
                }),
            ))
        else:
            entries.append(LogEntry(
                timestamp_ns=completion_ns,
                line=json.dumps({
                    "severity": "info",
                    "body": "transfer completed",
                    "attributes": {
                        "route": "/transfer",
                        "txId": tx_id,
                        "durationMs": duration_ms,
                    },
                }),
            ))

        if rand.next() < 0.1:
            entries.append(LogEntry(
                timestamp_ns=ts_ns,
                line=json.dumps({
                    "severity": "info",
                    "body": "request completed",
                    "attributes": {
                        "route": "/health",
                        "method": "GET",
                        "statusCode": 200,
                        "durationMs": int(rand.next() * 5 + 1),
                    },
                }),
            ))

        if rand.next() < 0.03:
            entries.append(LogEntry(
                timestamp_ns=ts_ns,
                line=json.dumps({
                    "severity": "info",
                    "body": "request completed",
                    "attributes": {
                        "route": "/",
                        "method": "GET",
                        "statusCode": 200,
                        "durationMs": int(rand.next() * 20 + 5),
                    },
                }),
            ))

    entries.sort(key=lambda e: e.timestamp_ns)
    return entries


def push_batch(client: httpx.Client, entries: list[LogEntry]) -> None:
    payload = {
        "streams": [{
            "stream": {"service_name": SERVICE},
            "values": [[e.timestamp_ns, e.line] for e in entries],
        }],
    }
    resp = client.post(LOKI_URL, json=payload)
    resp.raise_for_status()


def main() -> None:
    rand = SeededRandom(777)
    print("Generating 24h of synthetic logs...")
    all_entries = generate_logs(rand)
    print(f"Generated {len(all_entries)} log entries")

    total_batches = (len(all_entries) + BATCH_SIZE - 1) // BATCH_SIZE
    print(f"Pushing to {LOKI_URL} in {total_batches} batches\n")

    client = httpx.Client(
        auth=(LOKI_USERNAME, LOKI_API_KEY),
        headers={"Content-Type": "application/json"},
        timeout=30,
    )

    try:
        for i in range(total_batches):
            batch = all_entries[i * BATCH_SIZE : (i + 1) * BATCH_SIZE]
            print(f"  Batch {i + 1}/{total_batches} ({len(batch)} entries)... ", end="", flush=True)
            push_batch(client, batch)
            print("OK")
            if i < total_batches - 1:
                time.sleep(0.3)
    finally:
        client.close()

    print("\nDone. Logs seeded successfully.")


if __name__ == "__main__":
    main()
