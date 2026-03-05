output "team_ids" {
  description = "Created PagerDuty team IDs by code"
  value       = { for k, v in pagerduty_team.team : k => v.id }
}

output "team_ep_ids" {
  description = "Escalation policy IDs by team code"
  value       = { for k, v in pagerduty_escalation_policy.team_ep : k => v.id }
}

output "business_service_ids" {
  description = "Business service IDs by name"
  value       = { for name, r in pagerduty_business_service.orbitpay_bs : name => r.id }
}

output "technical_service_ids" {
  description = "Technical service IDs by name"
  value       = { for name, r in pagerduty_service.orbitpay_ts : name => r.id }
}

output "service_custom_field_ids" {
  description = "Service Custom Field IDs by key"
  value = {
    criticality  = local.scf_id_criticality
    service_tier = local.scf_id_tier
    environment  = local.scf_id_environment
  }
}

output "global_orchestration_id" {
  description = "Global orchestration ID"
  value       = pagerduty_event_orchestration.global.id
}

output "global_orchestration_routing_key" {
  description = "Global orchestration integration routing key"
  value       = pagerduty_event_orchestration_integration.global.parameters[0].routing_key
  sensitive   = true
}

output "slack_channel_ids" {
  description = "Slack channel IDs by team code (only populated when enable_slack = true)"
  value       = { for k, v in slack_conversation.team : k => v.id }
}

output "fastdeploy_change_events_routing_key" {
  description = "Events API v2 routing key for FastDeploy change events"
  value       = pagerduty_service_integration.fastdeploy_change_events.integration_key
  sensitive   = true
}

output "web_frontend_incident_routing_key" {
  description = "Events API v2 routing key for Web Frontend (SSR) incidents"
  value       = pagerduty_service_integration.web_frontend_incident_events.integration_key
  sensitive   = true
}

output "rollback_incident_workflow_id" {
  description = "ID of the rollback Incident Workflow (only set when enable_rollback_workflow = true)"
  value       = length(pagerduty_incident_workflow.rollback) > 0 ? pagerduty_incident_workflow.rollback[0].id : null
}
