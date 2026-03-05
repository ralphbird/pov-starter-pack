#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["httpx"]
# ///
"""Seed 7 days of realistic history for the Web Frontend (SSR) PagerDuty service."""

import argparse
import sys
from datetime import datetime, timedelta, timezone

import httpx

REGION_ENDPOINTS = {
    "US": "https://events.pagerduty.com",
    "EU": "https://events.eu.pagerduty.com",
    "STAGING": "https://events.staging.pagerduty.com",
}

CHANGE_EVENTS = [
    (-7, 10, "Deploy web-frontend v2.2.0", "Routine release"),
    (-6, 14, "Config update: CDN cache TTL 300s→600s", "Tuning cache TTL for improved hit rate"),
    (-5,  9, "Deploy web-frontend v2.2.1 (security patch)", "CVE-2024-9999 dependency patch"),
    (-4, 11, "Feature flag: checkout_v2=true", "Enabling new checkout flow for 100% of users"),
    (-3,  8, "Deploy web-frontend v2.3.0 (payment flow redesign)", "Major release: redesigned payment flow"),
    (-2,  3, "Deploy web-frontend v2.3.1 (hotfix: payment validation)", "Emergency fix for payment validation regression"),
    (-1, 15, "Config update: rate limit 1000→1500 req/min", "Increasing rate limit after load test validation"),
]

INCIDENTS = [
    (-6, 16, "info",     "Elevated p99 latency on checkout",           45),
    (-5, 11, "warning",  "5xx error spike on /api/cart",                20),
    (-3,  9, "error",    "Checkout flow failures after v2.3.0",        120),
    (-2,  1, "critical", "Payment processing degraded",                180),
    (-1, 13, "warning",  "Cache invalidation miss rate elevated",       15),
]


def days_ago(n: int, hour: int) -> str:
    """Return ISO 8601 timestamp for n days ago at the given UTC hour."""
    now = datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0)
    ts = now + timedelta(days=n, hours=hour - now.hour)
    return ts.strftime("%Y-%m-%dT%H:%M:%SZ")


def send_event(base_url: str, payload: dict) -> bool:
    try:
        r = httpx.post(f"{base_url}/v2/enqueue", json=payload, timeout=10)
        if r.status_code not in (200, 201, 202):
            print(f"  [WARN] Event send failed ({r.status_code}): {r.text}", file=sys.stderr)
            return False
        return True
    except Exception as e:
        print(f"  [WARN] Event send error: {e}", file=sys.stderr)
        return False


def send_change_event(base_url: str, payload: dict) -> bool:
    try:
        r = httpx.post(f"{base_url}/v2/change/enqueue", json=payload, timeout=10)
        if r.status_code not in (200, 201, 202):
            print(f"  [WARN] Change event send failed ({r.status_code}): {r.text}", file=sys.stderr)
            return False
        return True
    except Exception as e:
        print(f"  [WARN] Change event send error: {e}", file=sys.stderr)
        return False


def seed_change_events(base_url: str, routing_key: str) -> None:
    print("Seeding change events...")
    for day, hour, summary, details in CHANGE_EVENTS:
        payload = {
            "routing_key": routing_key,
            "payload": {
                "summary": summary,
                "timestamp": days_ago(day, hour),
                "custom_details": {"description": details},
            },
        }
        ok = send_change_event(base_url, payload)
        status = "ok" if ok else "WARN"
        print(f"  [{status}] day {day:+d}: {summary}")


def seed_incidents(base_url: str, routing_key: str) -> None:
    print("Seeding incidents...")
    for day, hour, severity, summary, resolve_after_min in INCIDENTS:
        dedup_key = f"seed-{day}-{summary[:20].replace(' ', '-')}"
        trigger_payload = {
            "routing_key": routing_key,
            "event_action": "trigger",
            "dedup_key": dedup_key,
            "payload": {
                "summary": summary,
                "severity": severity,
                "source": "web-frontend-ssr",
                "timestamp": days_ago(day, hour),
                "custom_details": {"seeded": True},
            },
        }
        ok = send_event(base_url, trigger_payload)
        status = "ok" if ok else "WARN"
        print(f"  [{status}] trigger day {day:+d} [{severity}]: {summary}")

        resolve_payload = {
            "routing_key": routing_key,
            "event_action": "resolve",
            "dedup_key": dedup_key,
            "payload": {
                "summary": summary,
                "severity": severity,
                "source": "web-frontend-ssr",
                "timestamp": days_ago(day, hour + (resolve_after_min // 60)),
                "custom_details": {"seeded": True},
            },
        }
        ok = send_event(base_url, resolve_payload)
        status = "ok" if ok else "WARN"
        print(f"  [{status}] resolve day {day:+d} [{severity}]: {summary} (+{resolve_after_min}m)")


def main() -> None:
    parser = argparse.ArgumentParser(description="Seed 7-day history for Web Frontend (SSR)")
    parser.add_argument("--incident-key", required=True, help="Events API v2 routing key for incidents")
    parser.add_argument("--change-key", required=True, help="Events API v2 routing key for change events")
    parser.add_argument(
        "--region",
        default="US",
        choices=list(REGION_ENDPOINTS),
        help="PagerDuty region (default: US)",
    )
    args = parser.parse_args()

    base_url = REGION_ENDPOINTS[args.region]
    print(f"Seeding history → {base_url}")

    try:
        seed_change_events(base_url, args.change_key)
        seed_incidents(base_url, args.incident_key)
        print("History seeding complete.")
    except Exception as e:
        print(f"[WARN] History seeding failed: {e}", file=sys.stderr)

    sys.exit(0)


if __name__ == "__main__":
    main()
