#!/usr/bin/env bash
set -euo pipefail

# OrbitPay POV Provisioner
# - Interactive wizard to spin up or tear down a POV environment

MODE="provision"
if [[ "${1:-}" == "--destroy" || "${1:-}" == "-d" || "${1:-}" == "destroy" ]]; then
  MODE="destroy"
fi

echo "========================================"
if [[ "$MODE" == "destroy" ]]; then
  echo "   OrbitPay POV CLEANUP (Destroy)"
else
  echo "   OrbitPay POV Provisioner (Sandbox)"
fi
echo "========================================"

# --- 1. Credentials ---
if [[ -z "${PAGERDUTY_TOKEN:-}" ]]; then
  echo "Please enter your PagerDuty API Token."
  read -rsp "Token: " token
  echo
  if [[ -z "$token" ]]; then
    echo "Error: Token required." >&2
    exit 1
  fi
  export PAGERDUTY_TOKEN="$token"
fi
export TF_VAR_pagerduty_token="$PAGERDUTY_TOKEN"

# --- Slack Integration (Optional) ---
if [[ -z "${SLACK_ENABLED:-}" ]]; then
  echo
  read -r -p "Enable Slack integration? (y/N): " slack_choice
  case "$slack_choice" in
    y|Y|yes|YES)
      SLACK_ENABLED="true"
      ;;
    *)
      SLACK_ENABLED="false"
      ;;
  esac
fi

if [[ "$SLACK_ENABLED" == "true" ]]; then
  if [[ -z "${SLACK_TOKEN:-}" ]]; then
    echo "Please enter your Slack Bot Token (xoxb-...)."
    read -rsp "Slack Token: " slack_token
    echo
    if [[ -z "$slack_token" ]]; then
      echo "Error: Slack token required when Slack is enabled." >&2
      exit 1
    fi
    export SLACK_TOKEN="$slack_token"
  fi
  export TF_VAR_slack_token="$SLACK_TOKEN"

  if [[ -z "${SLACK_WORKSPACE_ID:-}" ]]; then
    echo "Enter your Slack Workspace ID (T... format)."
    echo "  Found in: PagerDuty -> Integrations -> Slack"
    read -r -p "Slack Workspace ID: " slack_workspace_id
    if [[ -z "$slack_workspace_id" ]]; then
      echo "Error: Slack workspace ID required when Slack is enabled." >&2
      exit 1
    fi
    export SLACK_WORKSPACE_ID="$slack_workspace_id"
  fi
  export TF_VAR_slack_workspace_id="$SLACK_WORKSPACE_ID"

  if [[ -z "${PAGERDUTY_USER_TOKEN:-}" ]]; then
    echo "Please enter your PagerDuty User Token (Profile -> API Access -> User Token)."
    read -rsp "PagerDuty User Token: " PAGERDUTY_USER_TOKEN
    echo
    if [[ -z "$PAGERDUTY_USER_TOKEN" ]]; then
      echo "Error: PagerDuty User Token required for Slack connections." >&2
      exit 1
    fi
    export PAGERDUTY_USER_TOKEN="$PAGERDUTY_USER_TOKEN"
  fi
  export TF_VAR_pagerduty_user_token="$PAGERDUTY_USER_TOKEN"
  export TF_VAR_enable_slack="true"
else
  export TF_VAR_enable_slack="false"
fi

# --- 2. Region Selection ---
if [[ -z "${PD_REGION:-}" ]]; then
  echo
  echo "Select PagerDuty Region:"
  echo "  1) US (default)"
  echo "  2) EU"
  echo "  3) Staging"
  read -r -p "Enter 1, 2, or 3: " region_choice
  case "$region_choice" in
    2|EU|eu)
      PD_REGION="EU"
      ;;
    3|STAGING|staging)
      PD_REGION="STAGING"
      ;;
    *)
      PD_REGION="US"
      ;;
  esac
fi

if [[ "$PD_REGION" == "EU" ]]; then
  API_BASE_URL="https://api.eu.pagerduty.com"
elif [[ "$PD_REGION" == "STAGING" ]]; then
  API_BASE_URL="https://api.pd-staging.com"
else
  API_BASE_URL="https://api.pagerduty.com"
fi
export PD_REGION
export TF_VAR_pagerduty_api_url_override="$API_BASE_URL"

# --- 3. Domain Check ---
# (Verify connectivity to ensure valid token)
echo
if [[ -z "${PD_DOMAIN:-}" ]]; then
  echo "Enter PagerDuty Domain Name (subdomain only):"
  echo "  Example: for 'https://acme-corp.pagerduty.com', enter 'acme-corp'"
  read -r domain
  if [[ -z "$domain" ]]; then
    echo "Error: Domain required." >&2
    exit 1
  fi
  export PD_DOMAIN="$domain"
fi

echo "-> Verifying connectivity to $PD_DOMAIN ($PD_REGION)..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Token token=$PAGERDUTY_TOKEN" -H "Accept: application/vnd.pagerduty+json;version=2" "$API_BASE_URL/priorities")

if [[ "$HTTP_STATUS" != "200" ]]; then
  if [[ "$HTTP_STATUS" == "401" || "$HTTP_STATUS" == "403" ]]; then
    echo "   [ERROR] Authentication failed (Status: $HTTP_STATUS). Check your Token."
    exit 1
  fi
  echo "   [WARN] API Check returned status $HTTP_STATUS. Proceeding..."
fi

# --- 4. Terraform Init ---
echo "-> Initializing Terraform..."
terraform init -upgrade -input=false >/dev/null

# --- 5. Workspace Selection (Destroy Mode) ---

if [[ "$MODE" == "destroy" ]]; then
  echo
  echo "Fetching available POV workspaces..."

  # Get list of workspaces, filter for 'pov-', strip '*', remove empty lines
  raw_list=$(terraform workspace list | grep "pov-" | sed 's/[*[:space:]]//g')

  # Convert to array
  workspaces=()
  while IFS= read -r line; do
    if [[ -n "$line" ]]; then
      workspaces+=("$line")
    fi
  done <<< "$raw_list"

  if [[ ${#workspaces[@]} -eq 0 ]]; then
    echo "No 'pov-*' workspaces found to destroy."
    exit 0
  fi

  echo "Select a workspace to destroy:"
  i=1
  for ws in "${workspaces[@]}"; do
    # Display stripped name (e.g., 'pov-acme' -> 'acme')
    display_name=${ws#pov-}
    echo "  $i) $display_name"
    ((i++))
  done

  echo
  read -r -p "Enter number (1-${#workspaces[@]}): " selection

  # Validate input
  if ! [[ "$selection" =~ ^[0-9]+$ ]] || (( selection < 1 || selection > ${#workspaces[@]} )); then
    echo "Error: Invalid selection." >&2
    exit 1
  fi

  # Map selection to actual workspace name
  WORKSPACE="${workspaces[$((selection-1))]}"

  # Confirm
  echo
  echo "WARNING: You are about to DESTROY the OrbitPay POV for: $WORKSPACE"
  echo "This action cannot be undone."
  read -r -p "Type 'yes' to confirm destruction: " confirm

  if [[ "$confirm" != "yes" ]]; then
    echo "Aborted."
    exit 0
  fi

  echo "-> Selecting Workspace: $WORKSPACE..."
  if ! terraform workspace select "$WORKSPACE"; then
    echo "Error: Failed to select workspace."
    exit 1
  fi

  # Remove Slack connections before destroy (not managed by Terraform)
  if [[ "${TF_VAR_enable_slack:-false}" == "true" ]]; then
    echo "-> Removing Slack connections..."
    bash "$(dirname "$0")/create-slack-connections.sh" --destroy
  fi

  # Execute Destroy
  echo "-> Destroying Resources..."
  terraform destroy -auto-approve

  echo "-> Removing Workspace..."
  terraform workspace select default
  terraform workspace delete "$WORKSPACE"

  echo
  echo "========================================"
  echo "   Cleanup Complete."
  echo "========================================"
  exit 0
fi

# --- 6. Provision Mode Flow ---

# User Email (Required for Provisioning)
if [[ -z "${POV_USER_EMAIL:-}" ]]; then
  echo
  echo "Who is the primary user for this POV? (Used for Schedules)"
  echo "  Enter the email address of a valid user in this account."
  read -r user_email
  if [[ -z "$user_email" ]]; then
    echo "Error: Email required." >&2
    exit 1
  fi
  export POV_USER_EMAIL="$user_email"
fi
export TF_VAR_pov_user_email="$POV_USER_EMAIL"

# Customer Name
if [[ -z "${POV_CUSTOMER_NAME:-}" ]]; then
  echo
  echo "Enter Customer Name for this POV (e.g. 'Acme Corp'):"
  read -r customer_name
  if [[ -z "$customer_name" ]]; then
    echo "Error: Customer name required." >&2
    exit 1
  fi
else
  customer_name="$POV_CUSTOMER_NAME"
fi
# Sanitize
safe_name=$(echo "$customer_name" | tr '[:upper:]' '[:lower:]' | tr -s ' ' '-' | sed 's/[^a-z0-9-]//g')
# Prevent double prefixing
safe_name=${safe_name#pov-}

if [[ -z "$safe_name" ]]; then
  echo "Error: Invalid customer name." >&2
  exit 1
fi

WORKSPACE="pov-$safe_name"
echo "-> Target Workspace: $WORKSPACE"

echo "-> Selecting/Creating Workspace..."
terraform workspace new "$WORKSPACE" >/dev/null 2>&1 || true
terraform workspace select "$WORKSPACE"

echo
echo "Ready to provision OrbitPay POV for '$customer_name'."
echo "This will create teams, services, and schedules for $POV_USER_EMAIL."
read -p "Press Enter to continue..."

terraform apply -auto-approve

# Create Slack connections via API (supports all regions including Staging)
if [[ "${TF_VAR_enable_slack:-false}" == "true" ]]; then
  echo
  echo "-> Creating Slack connections..."
  bash "$(dirname "$0")/create-slack-connections.sh"
fi

echo
echo "========================================"
echo "   POV Provisioned Successfully!"
echo "   Workspace: $WORKSPACE"
echo "========================================"