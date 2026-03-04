# Rollback Incident Workflow — rolls web-frontend back to v1.2.0 via FastDeploy API.
# Gated on var.enable_rollback_workflow.

resource "pagerduty_incident_workflow" "rollback" {
  count       = var.enable_rollback_workflow ? 1 : 0
  name        = "OrbitPay — Rollback Web Frontend to v1.2.0"
  description = "Calls FastDeploy API to roll web-frontend back to the last known good version. Created by POV Starter Pack."

  step {
    name   = "Call FastDeploy rollback API"
    action = "pagerduty.com:incident-workflows:call-an-api:1"

    input {
      name  = "url"
      value = "${var.rollback_webhook_url}/api/services/web-frontend/deploy"
    }

    input {
      name  = "http_method"
      value = "POST"
    }

    input {
      name  = "headers"
      value = jsonencode([{ key = "Content-Type", value = "application/json" }])
    }

    input {
      name  = "body"
      value = jsonencode({ version = "v1.2.0" })
    }
  }
}

resource "pagerduty_incident_workflow_trigger" "rollback" {
  count                      = var.enable_rollback_workflow ? 1 : 0
  type                       = "manual"
  workflow                   = pagerduty_incident_workflow.rollback[0].id
  subscribed_to_all_services = false
  services                   = [local.ts_id_by_name["Web Frontend (SSR)"]]
}
