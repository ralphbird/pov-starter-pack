# Rollback Incident Workflow — rolls web-frontend back via FastDeploy API.
# Gated on var.enable_rollback_workflow.

resource "pagerduty_incident_workflow" "rollback" {
  count       = var.enable_rollback_workflow ? 1 : 0
  name        = "OrbitPay — Rollback Web Frontend"
  description = "Rolls back the web frontend to the previous version"

  step {
    name   = "Send a Webhook POST"
    action = "pagerduty.com:http-api:send-webhook-post:1"

    input {
      name  = "URL"
      value = "${var.rollback_webhook_url}/api/services/web-frontend/rollback"
    }

    input {
      name  = "Headers"
      value = "Content-Type: application/json"
    }
  }
}

resource "pagerduty_incident_workflow_trigger" "rollback" {
  count                      = var.enable_rollback_workflow ? 1 : 0
  type                       = "manual"
  workflow                   = pagerduty_incident_workflow.rollback[0].id
  subscribed_to_all_services = true
}

resource "pagerduty_incident_workflow" "rollback_payments_api" {
  count       = var.enable_rollback_workflow ? 1 : 0
  name        = "OrbitPay — Rollback Payments API Gateway"
  description = "Rolls back the payments API gateway to the previous version"

  step {
    name   = "Send a Webhook POST"
    action = "pagerduty.com:http-api:send-webhook-post:1"

    input {
      name  = "URL"
      value = "${var.rollback_webhook_url}/api/services/web-frontend/rollback"
    }

    input {
      name  = "Headers"
      value = "Content-Type: application/json"
    }
  }
}

resource "pagerduty_incident_workflow_trigger" "rollback_payments_api" {
  count                      = var.enable_rollback_workflow ? 1 : 0
  type                       = "manual"
  workflow                   = pagerduty_incident_workflow.rollback_payments_api[0].id
  subscribed_to_all_services = true
}

# Major Incident Workflow — Slack channel notification and Zoom conference bridge.
# Gated on var.enable_major_incident_workflow.

resource "pagerduty_incident_workflow" "major_incident" {
  count       = var.enable_major_incident_workflow ? 1 : 0
  name        = "Major Incident Workflow with Slack and Zoom"
  description = "Create a dedicated incident Slack channel and Zoom conference bridge to drive collaboration and incident management. Automate your response process and ensure responders have what they need to start collaborating."

  step {
    name   = "Set Priority to P1"
    action = "pagerduty.com:incident-workflows:update-incident-priority:1"

    input {
      name  = "Priority"
      value = "P1"
    }
  }

  step {
    name   = "Create a Zoom Meeting"
    action = "pagerduty.com:zoom:create-zoom-meeting:1"
  }

  step {
    name   = "Add PagerDuty Advance Scribe Agent"
    action = "pagerduty.com:pagerduty-advance:add-scribe-agent:1"
  }

  step {
    name   = "Add Responders"
    action = "pagerduty.com:incident-workflows:add-responders:2"

    input {
      name  = "Responders"
      value = jsonencode([{ id = pagerduty_escalation_policy.major_incidents_ep.id, type = "escalation_policy" }])
    }

    input {
      name  = "Message"
      value = "Please help me with {{incident.title}} - {{incident.url}}"
    }
  }

  step {
    name   = "Send a Message to a Channel"
    action = "pagerduty.com:slack:send-markdown-message:3"

    input {
      name  = "Workspace"
      value = var.major_incident_slack_workspace_id
    }

    input {
      name  = "Channel"
      value = "A specific channel"
    }

    input {
      name  = "Select the Channel"
      value = "major-incident-updates"
    }

    input {
      name  = "Message"
      value = ":fire: -- major incident declared!\nTo start response:\n- Assign the incident commander role (IC has been paged)\n- Page responders from impacted teams"
    }

    input {
      name  = "Pinned message"
      value = "No"
    }
  }

  step {
    name   = "Loop Until Incident is resolved"
    action = "pagerduty.com:logic:incident-workflows-loop-until:3"

    input {
      name  = "Condition"
      value = "incident.status matches 'resolved'"
    }

    input {
      name  = "Delay between loops"
      value = "10"
    }

    input {
      name  = "Maximum loops"
      value = "20"
    }

    inline_steps_input {
      name = "Actions"

      step {
        name   = "Prompt to Send a Status Update for the Incident"
        action = "pagerduty.com:slack:prompt-status-update:2"

        input {
          name  = "Workspace"
          value = var.major_incident_slack_workspace_id
        }

        input {
          name  = "Channel"
          value = "A specific channel"
        }

        input {
          name  = "Select the Channel"
          value = "major-incident-updates"
        }

        input {
          name  = "Message"
          value = "Reminder -- It's time to send a status update!"
        }
      }
    }
  }
}

resource "pagerduty_incident_workflow_trigger" "major_incident" {
  count                      = var.enable_major_incident_workflow ? 1 : 0
  type                       = "manual"
  workflow                   = pagerduty_incident_workflow.major_incident[0].id
  subscribed_to_all_services = true
}

# Per-incident Slack Channel Workflow — creates a dedicated Slack channel for every
# incident triggered on Web Frontend (SSR). Gated on var.enable_web_frontend_channel_workflow.
# Requires var.major_incident_slack_workspace_id to be set.

resource "pagerduty_incident_workflow" "web_frontend_channel" {
  count       = var.enable_web_frontend_channel_workflow ? 1 : 0
  name        = "Slack Channel Workflow"
  description = "Instantly set up communication channels for responders. Automatically name, create, and link Slack channels and conference bridges to the incident."

  step {
    name   = "Create a Slack Channel for an Incident"
    action = "pagerduty.com:slack:create-a-channel:4"

    input {
      name  = "Workspace"
      value = var.major_incident_slack_workspace_id
    }

    input {
      name  = "Channel Name"
      value = "web_frontend_{{incident.incident_number}}"
    }

    input {
      name  = "Channel visibility"
      value = "Public"
    }

    input {
      name  = "Pin incident"
      value = "Yes"
    }
  }
}

resource "pagerduty_incident_workflow_trigger" "web_frontend_channel" {
  count                      = var.enable_web_frontend_channel_workflow ? 1 : 0
  type                       = "conditional"
  workflow                   = pagerduty_incident_workflow.web_frontend_channel[0].id
  services                   = [pagerduty_service.orbitpay_ts["Web Frontend (SSR)"].id]
  condition                  = "incident.status matches 'triggered'"
  subscribed_to_all_services = false
}
