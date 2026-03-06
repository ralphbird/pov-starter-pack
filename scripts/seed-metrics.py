#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["httpx"]
# ///
"""Push 24h of synthetic Prometheus metrics to Grafana Cloud so the dashboard
looks lived-in when the demo starts.

Usage:
    cd pov-starter-pack
    ALLOY_URL=https://prometheus-prod-xxx.grafana.net/api/prom/push \
    ALLOY_USERNAME=123456 \
    ALLOY_API_KEY=glc_xxx \
    uv run scripts/seed-metrics.py
"""

import math
import os
import re
import sys
import time

import httpx

ALLOY_URL = os.environ.get("ALLOY_URL", "")
ALLOY_USERNAME = os.environ.get("ALLOY_USERNAME", "")
ALLOY_API_KEY = os.environ.get("ALLOY_API_KEY", "")

if not all([ALLOY_URL, ALLOY_USERNAME, ALLOY_API_KEY]):
    print("Required env vars: ALLOY_URL, ALLOY_USERNAME, ALLOY_API_KEY", file=sys.stderr)
    sys.exit(1)

IMPORT_URL = re.sub(r"/api/prom/push$", "/api/v1/import/prometheus", ALLOY_URL)

STEP_SECONDS = 30
HOURS = 24
TOTAL_SAMPLES = (HOURS * 3600) // STEP_SECONDS  # 2880

LE_BOUNDARIES = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]

SERVICES = [
    {
        "name": "orbitpay-frontend",
        "routes": [
            {"method": "GET", "route": "/", "rps": 0.4, "p50_ms": 10, "p99_ms": 100},
            {"method": "POST", "route": "/transfer", "rps": 0.3, "p50_ms": 50, "p99_ms": 500},
            {"method": "GET", "route": "/health", "rps": 0.3, "p50_ms": 5, "p99_ms": 50},
        ],
    },
    {
        "name": "payments-api-gateway",
        "routes": [
            {
                "method": "POST",
                "route": "/api/process-transfer",
                "rps": 0.3,
                "p50_ms": 80,
                "p99_ms": 300,
            },
            {"method": "GET", "route": "/health", "rps": 0.3, "p50_ms": 3, "p99_ms": 20},
        ],
    },
]


class SeededRandom:
    def __init__(self, seed: int) -> None:
        self._state = seed

    def next(self) -> float:
        self._state = (self._state * 1664525 + 1013904223) & 0x7FFFFFFF
        return self._state / 0x7FFFFFFF


def normal_cdf(x: float) -> float:
    t = 1.0 / (1.0 + 0.2316419 * abs(x))
    d = 0.3989422804014327
    p = d * math.exp(-x * x / 2) * (
        t * (0.319381530 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))))
    )
    return 1 - p if x >= 0 else p


def lognormal_params(p50_ms: float, p99_ms: float) -> tuple[float, float]:
    mu = math.log(p50_ms / 1000)
    sigma = (math.log(p99_ms / 1000) - mu) / 2.326
    return mu, sigma


def lognormal_sample(rand: SeededRandom, mu: float, sigma: float) -> float:
    u1 = max(rand.next(), 1e-10)
    u2 = rand.next()
    z = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
    return math.exp(mu + sigma * z)


def cdf_at_boundary(boundary: float, mu: float, sigma: float) -> float:
    z = (math.log(boundary) - mu) / sigma
    return normal_cdf(z)


def hash_code(s: str) -> int:
    h = 0
    for ch in s:
        h = ((h * 31) + ord(ch)) & 0xFFFFFFFF
    return h


def generate_request_series(
    route: dict,
    status_code: int,
    error_rate: float,
    rand: SeededRandom,
) -> dict:
    is_error = status_code >= 400
    effective_rps = route["rps"] * (error_rate if is_error else (1 - error_rate))
    requests_per_step = effective_rps * STEP_SECONDS
    mu, sigma = lognormal_params(route["p50_ms"], route["p99_ms"])

    count_arr: list[int] = []
    sum_arr: list[float] = []
    bucket_map: dict[str, list[int]] = {str(le): [] for le in LE_BOUNDARIES}
    bucket_map["+Inf"] = []

    cumulative_count = 0
    cumulative_sum = 0.0

    for _ in range(TOTAL_SAMPLES):
        jitter = 0.8 + rand.next() * 0.4
        step_requests = max(0, round(requests_per_step * jitter))
        cumulative_count += step_requests

        step_sum = sum(lognormal_sample(rand, mu, sigma) for _ in range(step_requests))
        cumulative_sum += step_sum

        count_arr.append(cumulative_count)
        sum_arr.append(cumulative_sum)

        for le in LE_BOUNDARIES:
            fraction = cdf_at_boundary(le, mu, sigma)
            bucket_map[str(le)].append(round(cumulative_count * fraction))
        bucket_map["+Inf"].append(cumulative_count)

    return {"count": count_arr, "sum": sum_arr, "buckets": bucket_map, "status_code": status_code}


def generate_gauge_series(
    rand: SeededRandom,
    base_min: float,
    base_max: float,
    sawtooth_period: int | None,
    spike_prob: float,
    spike_mult: float,
) -> list[float]:
    values: list[float] = []
    current = base_min + rand.next() * (base_max - base_min)
    spread = base_max - base_min

    for i in range(TOTAL_SAMPLES):
        drift = (rand.next() - 0.5) * spread * 0.05
        current = max(base_min, min(base_max, current + drift))

        if sawtooth_period and i % sawtooth_period == 0:
            current = base_min + rand.next() * spread * 0.3

        value = current * spike_mult if rand.next() < spike_prob else current
        values.append(value)

    return values


def format_labels(labels: dict[str, str]) -> str:
    return ",".join(f'{k}="{v}"' for k, v in labels.items())


def precompute() -> dict:
    error_rate = 0.001
    all_service_data = []

    for svc in SERVICES:
        service_name = svc["name"]
        request_series = []

        for route in svc["routes"]:
            for status_code in [200, 500]:
                seed = hash_code(f"{service_name}-{route['route']}-{route['method']}-{status_code}")
                series = generate_request_series(route, status_code, error_rate, SeededRandom(seed))
                request_series.append({
                    "series": series,
                    "base_labels": {
                        "service_name": service_name,
                        "http_method": route["method"],
                        "http_route": route["route"],
                        "http_status_code": str(status_code),
                    },
                })

        gauge_seed_base = hash_code(service_name)
        all_service_data.append({
            "service_name": service_name,
            "request_series": request_series,
            "heap_used": generate_gauge_series(
                SeededRandom(gauge_seed_base + 1), 55_000_000, 85_000_000, 120, 0, 1,
            ),
            "heap_total": generate_gauge_series(
                SeededRandom(gauge_seed_base + 2), 140_000_000, 160_000_000, None, 0, 1,
            ),
            "event_loop_lag": generate_gauge_series(
                SeededRandom(gauge_seed_base + 3), 0.001, 0.005, None, 0.02, 5,
            ),
        })

    return {"services": all_service_data}


def build_batch(
    pre: dict,
    start_idx: int,
    end_idx: int,
    start_ts_ms: int,
) -> str:
    lines: list[str] = []

    for svc_data in pre["services"]:
        service_name = svc_data["service_name"]

        for entry in svc_data["request_series"]:
            series = entry["series"]
            bl = entry["base_labels"]

            for i in range(start_idx, end_idx):
                ts_ms = start_ts_ms + i * STEP_SECONDS * 1000

                for le, bucket_values in series["buckets"].items():
                    bucket_labels = {**bl, "le": le}
                    lines.append(
                        f"http_server_request_duration_seconds_bucket"
                        f"{{{format_labels(bucket_labels)}}} {bucket_values[i]} {ts_ms}"
                    )

                lbl = format_labels(bl)
                lines.append(
                    f"http_server_request_duration_seconds_count{{{lbl}}} "
                    f"{series['count'][i]} {ts_ms}"
                )
                lines.append(
                    f"http_server_request_duration_seconds_sum{{{lbl}}} "
                    f"{series['sum'][i]:.6f} {ts_ms}"
                )

        sl = format_labels({"service_name": service_name})
        for i in range(start_idx, end_idx):
            ts_ms = start_ts_ms + i * STEP_SECONDS * 1000
            lines.append(
                f"nodejs_heap_size_used_bytes{{{sl}}} {round(svc_data['heap_used'][i])} {ts_ms}"
            )
            lines.append(
                f"nodejs_heap_size_total_bytes{{{sl}}} {round(svc_data['heap_total'][i])} {ts_ms}"
            )
            lines.append(
                f"nodejs_eventloop_lag_seconds{{{sl}}} "
                f"{svc_data['event_loop_lag'][i]:.6f} {ts_ms}"
            )

    return "\n".join(lines) + "\n"


def push_batch(client: httpx.Client, payload: str) -> None:
    resp = client.post(
        IMPORT_URL,
        content=payload.encode(),
        headers={"Content-Type": "text/plain"},
    )
    resp.raise_for_status()


def main() -> None:
    now_ms = int(time.time() * 1000)
    start_ts_ms = now_ms - HOURS * 3600 * 1000

    batch_hours = 1
    samples_per_batch = (batch_hours * 3600) // STEP_SECONDS
    total_batches = math.ceil(TOTAL_SAMPLES / samples_per_batch)

    service_names = ", ".join(s["name"] for s in SERVICES)
    print(f"Pushing {HOURS}h of metrics ({TOTAL_SAMPLES} samples) in {total_batches} batches")
    print(f"Services: {service_names}")
    print(f"Target: {IMPORT_URL}")
    start_iso = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(start_ts_ms / 1000))
    end_iso = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now_ms / 1000))
    print(f"Time range: {start_iso} -> {end_iso}\n")

    print("Precomputing series...")
    pre = precompute()
    print("Done.\n")

    client = httpx.Client(auth=(ALLOY_USERNAME, ALLOY_API_KEY), timeout=30)

    try:
        for batch in range(total_batches):
            start_idx = batch * samples_per_batch
            end_idx = min(start_idx + samples_per_batch, TOTAL_SAMPLES)

            payload = build_batch(pre, start_idx, end_idx, start_ts_ms)
            n_lines = sum(1 for line in payload.split("\n") if line)

            print(f"  Batch {batch + 1}/{total_batches} ({n_lines} lines)... ", end="", flush=True)
            push_batch(client, payload)
            print("OK")

            if batch < total_batches - 1:
                time.sleep(0.5)
    finally:
        client.close()

    print("\nDone. Metrics seeded successfully.")


if __name__ == "__main__":
    main()
