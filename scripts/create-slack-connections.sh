#!/usr/bin/env bash
# Manage PagerDuty Slack connections for OrbitPay teams.
# Replaces the pagerduty_slack_connection Terraform resource so that staging
# environments are supported (the provider hardcodes app.pagerduty.com and
# ignores api_url_override).
#
# Usage:
#   bash scripts/create-slack-connections.sh           # create connections
#   bash scripts/create-slack-connections.sh --destroy # delete connections
#
# Required env vars:
#   PAGERDUTY_USER_TOKEN  - PagerDuty personal REST API key
#   SLACK_WORKSPACE_ID    - Slack workspace ID (T... format)
#   PD_REGION             - US | EU | STAGING (default: US)

set -euo pipefail

MODE="create"
if [[ "${1:-}" == "--destroy" ]]; then
  MODE="destroy"
fi

# ---- validate inputs --------------------------------------------------------

PAGERDUTY_USER_TOKEN="${PAGERDUTY_USER_TOKEN:-}"
SLACK_WORKSPACE_ID="${SLACK_WORKSPACE_ID:-}"
PD_REGION="${PD_REGION:-US}"

if [[ -z "$PAGERDUTY_USER_TOKEN" ]]; then
  echo "Error: PAGERDUTY_USER_TOKEN is required." >&2
  exit 1
fi
if [[ -z "$SLACK_WORKSPACE_ID" ]]; then
  echo "Error: SLACK_WORKSPACE_ID is required." >&2
  exit 1
fi
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required (brew install jq)." >&2
  exit 1
fi

# ---- determine app endpoint -------------------------------------------------

case "$PD_REGION" in
  EU)      APP_BASE_URL="https://app.eu.pagerduty.com" ;;
  STAGING) APP_BASE_URL="https://app.pd-staging.com" ;;
  *)       APP_BASE_URL="https://app.pagerduty.com" ;;
esac

CONNECTIONS_URL="$APP_BASE_URL/integration-slack/workspaces/$SLACK_WORKSPACE_ID/connections"
AUTH_HEADER="Authorization: Token token=$PAGERDUTY_USER_TOKEN"
ACCEPT_HEADER="Accept: application/vnd.pagerduty+json;version=2"

echo "-> Region:   $PD_REGION"
echo "-> Endpoint: $CONNECTIONS_URL"

# ---- helper: curl with status -----------------------------------------------
# Usage: pd_curl <method> <url> [extra curl args...]
# Sets globals: CURL_STATUS, CURL_BODY
pd_curl() {
  local method="$1"; shift
  local url="$1"; shift
  local raw
  raw=$(curl -s -w "\n%{http_code}" -X "$method" \
    -H "$AUTH_HEADER" \
    -H "$ACCEPT_HEADER" \
    "$@" "$url")
  CURL_BODY=$(echo "$raw" | sed '$d')
  CURL_STATUS=$(echo "$raw" | tail -n 1)
}

# ---- read terraform outputs -------------------------------------------------

echo "-> Reading Terraform outputs..."
team_ids=$(terraform output -json team_ids 2>/dev/null)
channel_ids=$(terraform output -json slack_channel_ids 2>/dev/null)

echo "   team_ids:    $team_ids"
echo "   channel_ids: $channel_ids"

if [[ "$team_ids" == "null" || -z "$team_ids" ]]; then
  echo "Error: Could not read team_ids from Terraform output. Run terraform apply first." >&2
  exit 1
fi
if [[ "$channel_ids" == "{}" || -z "$channel_ids" ]]; then
  echo "Error: slack_channel_ids output is empty. Was enable_slack=true when applying?" >&2
  exit 1
fi

# ---- fetch existing connections ---------------------------------------------

echo "-> Fetching existing Slack connections..."
pd_curl GET "$CONNECTIONS_URL"
echo "   GET $CONNECTIONS_URL -> HTTP $CURL_STATUS"

if [[ "$CURL_STATUS" != "200" ]]; then
  echo "Error: Could not fetch existing connections (HTTP $CURL_STATUS)" >&2
  echo "       Response: $CURL_BODY" >&2
  echo "       Check PAGERDUTY_USER_TOKEN and SLACK_WORKSPACE_ID." >&2
  exit 1
fi

existing="$CURL_BODY"

# ---- events list ------------------------------------------------------------

EVENTS_JSON='[
  "incident.triggered",
  "incident.acknowledged",
  "incident.escalated",
  "incident.resolved",
  "incident.reassigned",
  "incident.annotated",
  "incident.unacknowledged",
  "incident.delegated",
  "incident.priority_updated",
  "incident.responder.added",
  "incident.responder.replied",
  "incident.status_update_published",
  "incident.reopened"
]'

# ---- create or destroy ------------------------------------------------------

ERRORS=0
teams=$(echo "$team_ids" | jq -r 'keys[]')

for code in $teams; do
  team_id=$(echo "$team_ids" | jq -r ".\"$code\"")
  channel_id=$(echo "$channel_ids" | jq -r ".\"$code\" // empty")

  if [[ -z "$channel_id" ]]; then
    echo "  [SKIP] $code — no channel ID in Terraform output"
    continue
  fi

  # Find existing connection for this channel
  existing_id=$(echo "$existing" | jq -r \
    ".slack_connections[] | select(.channel_id == \"$channel_id\") | .id" 2>/dev/null || true)

  if [[ "$MODE" == "destroy" ]]; then
    if [[ -z "$existing_id" ]]; then
      echo "  [SKIP] $code ($channel_id) — no connection found"
    else
      echo "  [DELETE] $code ($channel_id) connection $existing_id"
      pd_curl DELETE "$CONNECTIONS_URL/$existing_id"
      echo "           HTTP $CURL_STATUS"
      if [[ "$CURL_STATUS" == "204" || "$CURL_STATUS" == "200" ]]; then
        echo "  [DONE]   $code"
      else
        echo "  [ERROR]  $code — HTTP $CURL_STATUS: $CURL_BODY"
        ERRORS=$((ERRORS + 1))
      fi
    fi
  else
    if [[ -n "$existing_id" ]]; then
      echo "  [EXISTS] $code ($channel_id) connection $existing_id — skipping"
    else
      echo "  [CREATE] $code — team $team_id -> channel $channel_id"
      payload=$(jq -n \
        --arg src "$team_id" \
        --arg ch "$channel_id" \
        --arg ws "$SLACK_WORKSPACE_ID" \
        --argjson events "$EVENTS_JSON" \
        '{slack_connection: {source_id: $src, source_type: "team_reference", workspace_id: $ws, channel_id: $ch, notification_type: "responder", config: {events: $events, priorities: null, urgency: null}}}')

      echo "           Payload: $payload"
      pd_curl POST "$CONNECTIONS_URL" -H "Content-Type: application/json" -d "$payload"
      echo "           HTTP $CURL_STATUS"

      if [[ "$CURL_STATUS" == "201" || "$CURL_STATUS" == "200" ]]; then
        connection_id=$(echo "$CURL_BODY" | jq -r '.slack_connection.id')
        echo "  [DONE]   $code — connection $connection_id"
      else
        echo "  [ERROR]  $code — HTTP $CURL_STATUS"
        echo "           Response: $CURL_BODY"
        ERRORS=$((ERRORS + 1))
      fi
    fi
  fi
done

echo
if [[ "$ERRORS" -gt 0 ]]; then
  echo "-> Finished with $ERRORS error(s)."
  exit 1
elif [[ "$MODE" == "destroy" ]]; then
  echo "-> Slack connections removed."
else
  echo "-> Slack connections created."
fi
