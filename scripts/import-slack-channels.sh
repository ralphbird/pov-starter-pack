#!/usr/bin/env bash
# Import existing Slack channels into Terraform state.
# Prevents "name_taken" errors when channels already exist in Slack but not in TF
# state (e.g., after running destroy with action_on_destroy = "none").
#
# Required env vars:
#   SLACK_TOKEN - Slack Bot Token (xoxb-...)

set -euo pipefail

if [[ -z "${SLACK_TOKEN:-}" ]]; then
  echo "Error: SLACK_TOKEN is required." >&2
  exit 1
fi
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required (brew install jq)." >&2
  exit 1
fi

# These mirror local.team_slack_channel_name in main.tf.
# Keep in sync if team_catalog changes.
TEAM_KEYS=("PP" "WL" "CX" "CI")
CHANNEL_NAMES=(
  "incidents-payments-platform"
  "incidents-wallet-and-ledgers"
  "incidents-customer-experience"
  "incidents-core-infrastructure"
)

echo "-> Fetching Slack channel list..."
channels_json=$(curl -s -H "Authorization: Bearer $SLACK_TOKEN" \
  "https://slack.com/api/conversations.list?types=public_channel&exclude_archived=false&limit=1000")

if [[ "$(echo "$channels_json" | jq -r '.ok')" != "true" ]]; then
  echo "Error: Slack API call failed: $(echo "$channels_json" | jq -r '.error')" >&2
  exit 1
fi

IMPORTED=0
for i in "${!TEAM_KEYS[@]}"; do
  key="${TEAM_KEYS[$i]}"
  channel_name="${CHANNEL_NAMES[$i]}"

  channel_id=$(echo "$channels_json" | jq -r \
    ".channels[] | select(.name == \"$channel_name\") | .id")

  if [[ -z "$channel_id" ]]; then
    continue
  fi

  # Skip if already tracked in state
  if terraform state show "slack_conversation.team[\"$key\"]" >/dev/null 2>&1; then
    echo "  [STATE]  $key ($channel_name) already in Terraform state"
    continue
  fi

  echo "  [IMPORT] $key ($channel_name) -> $channel_id"
  terraform import "slack_conversation.team[\"$key\"]" "$channel_id"
  IMPORTED=$((IMPORTED + 1))
done

if [[ "$IMPORTED" -gt 0 ]]; then
  echo "-> Imported $IMPORTED existing Slack channel(s) into Terraform state."
else
  echo "-> No existing Slack channels to import."
fi
