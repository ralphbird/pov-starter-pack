#!/usr/bin/env bash
set -euo pipefail

# Extracts incident workflow configs from PagerDuty API.
# Usage: PAGERDUTY_TOKEN=<token> ./scripts/extract-workflows.sh
# Optional: PAGERDUTY_API_URL=https://api.pd-staging.com ./scripts/extract-workflows.sh

PD_TOKEN="${PAGERDUTY_TOKEN:?PAGERDUTY_TOKEN is required}"
PD_URL="${PAGERDUTY_API_URL:-https://api.pagerduty.com}"

auth_header="Authorization: Token token=${PD_TOKEN}"
accept_header="Accept: application/vnd.pagerduty+json;version=2"

pd_get() {
  curl -sf -H "$auth_header" -H "$accept_header" -H "Content-Type: application/json" "${PD_URL}${1}"
}

workflows=$(pd_get "/incident_workflows")

echo "=== All incident workflows (names + IDs) ==="
echo "$workflows" | jq '.incident_workflows[] | {id, name}'

echo ""
echo "=== Finding rollback workflow ==="
rollback_id=$(echo "$workflows" | jq -r '.incident_workflows[] | select(.name | test("Rollback Web Frontend"; "i")) | .id' | head -1)
echo "Rollback ID: ${rollback_id:-NOT FOUND}"

echo ""
echo "=== Finding major incident workflow ==="
major_id=$(echo "$workflows" | jq -r '.incident_workflows[] | select(.name | test("Major Incident"; "i")) | .id' | head -1)
echo "Major Incident ID: ${major_id:-NOT FOUND}"

if [[ -n "${rollback_id:-}" ]]; then
  echo ""
  echo "=== Rollback workflow detail ==="
  pd_get "/incident_workflows/${rollback_id}" | jq .

  echo ""
  echo "=== Rollback trigger ==="
  pd_get "/incident_workflow_triggers?workflow_id=${rollback_id}" | jq .
fi

if [[ -n "${major_id:-}" ]]; then
  echo ""
  echo "=== Major Incident workflow detail ==="
  pd_get "/incident_workflows/${major_id}" | jq .

  echo ""
  echo "=== Major Incident trigger ==="
  pd_get "/incident_workflow_triggers?workflow_id=${major_id}" | jq .
fi
