#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["httpx"]
# ///
"""Push 24h of synthetic traces to Grafana Cloud Tempo via OTLP/HTTP.

Usage:
    cd pov-starter-pack
    TEMPO_URL=tempo-prod-xxx.grafana.net:443 \
    TEMPO_USERNAME=123456 \
    TEMPO_API_KEY=glc_xxx \
    uv run scripts/seed-traces.py
"""

import os
import sys
import time
from datetime import datetime, timezone
from typing import Any

import httpx

TEMPO_URL = os.environ.get("TEMPO_URL", "")
TEMPO_USERNAME = os.environ.get("TEMPO_USERNAME", "")
TEMPO_API_KEY = os.environ.get("TEMPO_API_KEY", "")

if not all([TEMPO_URL, TEMPO_USERNAME, TEMPO_API_KEY]):
    print("Required env vars: TEMPO_URL, TEMPO_USERNAME, TEMPO_API_KEY", file=sys.stderr)
    sys.exit(1)

# TEMPO_URL is the gRPC endpoint (e.g. tempo-prod-xxx.grafana.net:443).
# OTLP/HTTP is at https://<host>/otlp/v1/traces
host = TEMPO_URL.removesuffix(":443")
OTLP_URL = f"https://{host}/otlp/v1/traces"

HOURS = 24
TRACE_INTERVAL_MS = 10_000
BATCH_SIZE = 100

DOWNSTREAM_SERVICES = [
    {"name": "payments-rules-engine", "op": "fraud_check", "min_ms": 30, "max_ms": 60},
    {"name": "payments-orchestrator", "op": "payment_orchestration", "min_ms": 80, "max_ms": 150},
    {"name": "idempotency-token-service", "op": "idempotency_check", "min_ms": 10, "max_ms": 20},
    {"name": "wallet-api", "op": "wallet_lookup", "min_ms": 40, "max_ms": 80},
    {"name": "balance-manager", "op": "balance_validation", "min_ms": 15, "max_ms": 30},
    {"name": "notification-service", "op": "notification_dispatch", "min_ms": 20, "max_ms": 40},
]


class SeededRandom:
    def __init__(self, seed: int) -> None:
        self._state = seed

    def next(self) -> float:
        self._state = (self._state * 1664525 + 1013904223) & 0x7FFFFFFF
        return self._state / 0x7FFFFFFF

    def hex(self, n_bytes: int) -> str:
        return "".join(f"{int(self.next() * 256):02x}" for _ in range(n_bytes))


def to_nanos(ms: int) -> str:
    return str(ms * 1_000_000)


def str_attr(key: str, val: str) -> dict[str, Any]:
    return {"key": key, "value": {"stringValue": val}}


def make_span(
    *,
    trace_id: str,
    span_id: str,
    parent_span_id: str | None,
    name: str,
    kind: int,
    start_ms: int,
    end_ms: int,
    attrs: list[dict[str, Any]],
    status_code: int = 1,
) -> dict[str, Any]:
    span: dict[str, Any] = {
        "traceId": trace_id,
        "spanId": span_id,
        "name": name,
        "kind": kind,
        "startTimeUnixNano": to_nanos(start_ms),
        "endTimeUnixNano": to_nanos(end_ms),
        "status": {"code": status_code},
        "attributes": attrs,
    }
    if parent_span_id:
        span["parentSpanId"] = parent_span_id
    return span


def generate_trace(rand: SeededRandom, timestamp_ms: int) -> list[dict[str, Any]]:
    trace_id = rand.hex(16)
    frontend_span_id = rand.hex(8)
    payments_span_id = rand.hex(8)

    frontend_duration = int(rand.next() * 400 + 100)
    frontend_span = make_span(
        trace_id=trace_id,
        span_id=frontend_span_id,
        parent_span_id=None,
        name="POST /transfer",
        kind=2,  # SERVER
        start_ms=timestamp_ms,
        end_ms=timestamp_ms + frontend_duration,
        attrs=[
            str_attr("http.method", "POST"),
            str_attr("http.route", "/transfer"),
            str_attr("http.status_code", "200"),
        ],
    )

    payments_start = timestamp_ms + int(rand.next() * 20 + 10)
    payments_duration = int(rand.next() * 300 + 60)
    payments_span = make_span(
        trace_id=trace_id,
        span_id=payments_span_id,
        parent_span_id=frontend_span_id,
        name="POST /api/process-transfer",
        kind=2,  # SERVER
        start_ms=payments_start,
        end_ms=payments_start + payments_duration,
        attrs=[
            str_attr("http.method", "POST"),
            str_attr("http.route", "/api/process-transfer"),
            str_attr("http.status_code", "200"),
        ],
    )

    downstream_spans: list[dict[str, Any]] = []
    cursor = payments_start + 5
    for svc in DOWNSTREAM_SERVICES:
        span_id = rand.hex(8)
        duration = int(rand.next() * (svc["max_ms"] - svc["min_ms"]) + svc["min_ms"])
        downstream_spans.append(make_span(
            trace_id=trace_id,
            span_id=span_id,
            parent_span_id=payments_span_id,
            name=svc["op"],
            kind=3,  # CLIENT
            start_ms=cursor,
            end_ms=cursor + duration,
            attrs=[str_attr("peer.service", svc["name"])],
        ))
        cursor += duration + int(rand.next() * 5)

    return [
        {
            "resource": {"attributes": [str_attr("service.name", "orbitpay-frontend")]},
            "scopeSpans": [{"scope": {"name": "orbitpay-frontend"}, "spans": [frontend_span]}],
        },
        {
            "resource": {"attributes": [str_attr("service.name", "payments-api-gateway")]},
            "scopeSpans": [{
                "scope": {"name": "payments-api-gateway"},
                "spans": [payments_span, *downstream_spans],
            }],
        },
    ]


def push_batch(client: httpx.Client, resource_spans: list[dict[str, Any]]) -> None:
    resp = client.post(OTLP_URL, json={"resourceSpans": resource_spans})
    resp.raise_for_status()


def main() -> None:
    rand = SeededRandom(999)
    now_ms = int(time.time() * 1000)
    start_ms = now_ms - HOURS * 3600 * 1000

    timestamps: list[int] = []
    cursor = start_ms
    while cursor < now_ms:
        jitter = int(rand.next() * 4000 - 2000)
        timestamps.append(cursor + jitter)
        cursor += TRACE_INTERVAL_MS

    start_dt = datetime.fromtimestamp(start_ms / 1000, tz=timezone.utc).isoformat()
    end_dt = datetime.fromtimestamp(now_ms / 1000, tz=timezone.utc).isoformat()
    print(f"Generating {len(timestamps)} traces over {HOURS}h")
    print(f"Target: {OTLP_URL}")
    print(f"Time range: {start_dt} -> {end_dt}\n")

    total_batches = (len(timestamps) + BATCH_SIZE - 1) // BATCH_SIZE
    client = httpx.Client(
        auth=(TEMPO_USERNAME, TEMPO_API_KEY),
        headers={"Content-Type": "application/json"},
        timeout=30,
    )

    try:
        for b in range(total_batches):
            batch = timestamps[b * BATCH_SIZE : (b + 1) * BATCH_SIZE]
            all_resource_spans: list[dict[str, Any]] = []
            for ts in batch:
                all_resource_spans.extend(generate_trace(rand, ts))

            print(f"  Batch {b + 1}/{total_batches} ({len(batch)} traces)... ", end="", flush=True)
            push_batch(client, all_resource_spans)
            print("OK")

            if b < total_batches - 1:
                time.sleep(0.3)
    finally:
        client.close()

    print("\nDone. Traces seeded successfully.")


if __name__ == "__main__":
    main()
