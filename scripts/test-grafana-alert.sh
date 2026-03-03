#!/usr/bin/env bash
set -euo pipefail

# Fires a test alert directly into the Grafana Alertmanager and optionally resolves it.
# Requires GRAFANA_URL and GRAFANA_TOKEN to be set (exported by quickstart.sh).
#
# Usage:
#   bash scripts/test-grafana-alert.sh           # fire + auto-resolve after 5 min
#   bash scripts/test-grafana-alert.sh --resolve # resolve immediately (re-run after firing)

: "${GRAFANA_URL:?GRAFANA_URL is required}"
: "${GRAFANA_TOKEN:?GRAFANA_TOKEN is required}"

GRAFANA_URL="${GRAFANA_URL%/}"
MODE="${1:-fire}"

STARTS_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
# endsAt controls when Alertmanager auto-resolves. 5 minutes from now.
ENDS_AT=$(date -u -v+5M +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
  || date -u -d "+5 minutes" +"%Y-%m-%dT%H:%M:%SZ")

if [[ "$MODE" == "--resolve" ]]; then
  # Set endsAt in the past to resolve immediately
  ENDS_AT=$(date -u -v-1M +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
    || date -u -d "-1 minute" +"%Y-%m-%dT%H:%M:%SZ")
  echo "-> Resolving test alert..."
else
  echo "-> Firing test alert (auto-resolves in 5 minutes)..."
fi

PAYLOAD=$(jq -n \
  --arg starts "$STARTS_AT" \
  --arg ends   "$ENDS_AT" \
  '[{
    "labels": {
      "alertname": "orbipay-test-alert",
      "service":   "orbipay-frontend",
      "severity":  "critical",
      "team":      "cx"
    },
    "annotations": {
      "summary": "Test alert — verifying Grafana → PagerDuty pipeline"
    },
    "startsAt": $starts,
    "endsAt":   $ends
  }]')

HTTP_CODE=$(curl -s -o /tmp/test-alert-response.json -w "%{http_code}" \
  -X POST \
  -H "Authorization: Bearer $GRAFANA_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "${GRAFANA_URL}/api/alertmanager/grafana/api/v2/alerts")

if [[ "$HTTP_CODE" == "200" ]]; then
  if [[ "$MODE" == "--resolve" ]]; then
    echo "   Alert resolved."
  else
    echo "   Alert fired (HTTP 200)."
    echo "   Check PagerDuty — an incident should appear on 'Web Frontend (SSR)' within 30 seconds."
    echo "   To resolve: bash scripts/test-grafana-alert.sh --resolve"
  fi
else
  echo "ERROR: Alertmanager returned HTTP $HTTP_CODE"
  cat /tmp/test-alert-response.json
  exit 1
fi
