#!/usr/bin/env bash
# Archive all Slack channels matching the web_frontend_* prefix.
# Run after a customer POV teardown to keep the workspace clean between demos.
#
# Usage:
#   bash scripts/archive-slack-channels.sh            # archive matching channels
#   bash scripts/archive-slack-channels.sh --dry-run  # list matches without archiving
#
# Required env vars:
#   SLACK_TOKEN - Slack Bot Token (xoxb-...)

set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

if [[ -z "${SLACK_TOKEN:-}" ]]; then
  echo "Error: SLACK_TOKEN is required." >&2
  exit 1
fi
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required (brew install jq)." >&2
  exit 1
fi

# Fetch all non-archived public channels, handling pagination.
fetch_all_channels() {
  local all_channels='[]'
  local cursor=""
  while true; do
    local url="https://slack.com/api/conversations.list?types=public_channel&exclude_archived=true&limit=1000"
    [[ -n "$cursor" ]] && url="${url}&cursor=${cursor}"
    local page
    page=$(curl -s -H "Authorization: Bearer $SLACK_TOKEN" "$url")
    if [[ "$(echo "$page" | jq -r '.ok')" != "true" ]]; then
      echo "Error: Slack API call failed: $(echo "$page" | jq -r '.error')" >&2
      exit 1
    fi
    all_channels=$(jq -n --argjson acc "$all_channels" --argjson page "$page" '$acc + $page.channels')
    cursor=$(echo "$page" | jq -r '.response_metadata.next_cursor // empty')
    [[ -z "$cursor" ]] && break
  done
  echo "$all_channels"
}

echo "-> Fetching Slack channel list..."
channels_json=$(fetch_all_channels)

mapfile -t matching_ids < <(echo "$channels_json" | jq -r '.[] | select(.name | startswith("web_frontend_")) | .id')
mapfile -t matching_names < <(echo "$channels_json" | jq -r '.[] | select(.name | startswith("web_frontend_")) | .name')

if [[ "${#matching_ids[@]}" -eq 0 ]]; then
  echo "-> No web_frontend_* channels found."
  exit 0
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo "-> [DRY RUN] Would archive ${#matching_ids[@]} channel(s):"
  for name in "${matching_names[@]}"; do
    echo "   $name"
  done
  exit 0
fi

ERRORS=0
for i in "${!matching_ids[@]}"; do
  id="${matching_ids[$i]}"
  name="${matching_names[$i]}"
  resp=$(curl -s -X POST "https://slack.com/api/conversations.archive" \
    -H "Authorization: Bearer $SLACK_TOKEN" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "channel=${id}")
  ok=$(echo "$resp" | jq -r '.ok')
  if [[ "$ok" == "true" ]]; then
    echo "  [ARCHIVE]          $name"
  else
    err=$(echo "$resp" | jq -r '.error')
    if [[ "$err" == "already_archived" ]]; then
      echo "  [ALREADY_ARCHIVED] $name"
    else
      echo "  [ERROR]            $name: $err" >&2
      ERRORS=$((ERRORS + 1))
    fi
  fi
done

if [[ "$ERRORS" -gt 0 ]]; then
  echo "-> $ERRORS error(s) encountered." >&2
  exit 1
fi

echo "-> Done. Archived ${#matching_ids[@]} channel(s)."
