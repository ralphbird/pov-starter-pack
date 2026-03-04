variable "default_escalation_delay" {
  description = "Minutes before escalating to next rule"
  type        = number
  default     = 15
}

# Provider auth: prefer env PAGERDUTY_TOKEN; allow override via tfvars
variable "pagerduty_token" {
  description = "PagerDuty API token. If empty, provider uses env PAGERDUTY_TOKEN."
  type        = string
  default     = ""
  sensitive   = true
}

variable "pagerduty_api_url_override" {
  description = "Optional override for the PagerDuty API base URL (e.g., https://api.pd-staging.com)."
  type        = string
  default     = ""
}

variable "pov_user_email" {
  description = "The email address of the PagerDuty user who will be on-call for the POV schedules."
  type        = string
  default     = null
}

# Map of team code -> schedule ID (Optional - if empty, schedules will be created)
variable "team_schedule_ids" {
  description = "PagerDuty schedule IDs per team code (PP, WL, CX, CI). If empty, new schedules are created for 'pov_user_email'."
  type        = map(string)
  default     = {}
}

# Incident type ID where custom fields will be attached (Optional)
variable "base_incident_type_id" {
  description = "Existing incident type ID to attach custom fields to (optional)."
  type        = string
  default     = ""
}

# If incident custom fields already exist, provide their IDs here to skip creation
# Keys: cuj_impacted, propose_major_incident
variable "incident_custom_field_ids" {
  description = "Optional existing incident custom field IDs by key (cuj_impacted, propose_major_incident)"
  type        = map(string)
  default     = {}
}

variable "manage_service_custom_fields" {
  description = "If true, create Service Custom Fields (Criticality, Service Tier, Environment)"
  type        = bool
  default     = true
}

# If SCF field definitions already exist, provide their IDs here to skip creation
# Keys: criticality, service_tier, environment
variable "service_custom_field_ids" {
  description = "Optional: existing Service Custom Field IDs by key (criticality, service_tier, environment)"
  type        = map(string)
  default     = {}
}

variable "enable_scf_assignments" {
  description = "Enable Service Custom Field value assignments"
  type        = bool
  default     = true
}

variable "enable_slack" {
  description = "If true, create Slack channels and PagerDuty Slack connections for each team."
  type        = bool
  default     = false
}

variable "slack_token" {
  description = "Slack bot token (xoxb-...) with channels:write and channels:read scopes."
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_grafana" {
  description = "If true, provision Grafana alert rules for orbitpay-frontend."
  type        = bool
  default     = false
}

variable "grafana_url" {
  description = "Grafana Cloud stack URL (e.g. https://acme.grafana.net)."
  type        = string
  default     = ""
}

variable "grafana_token" {
  description = "Grafana instance service account token (Admin role). Not a Grafana Cloud access policy token."
  type        = string
  default     = ""
  sensitive   = true
}

variable "grafana_loki_ds_name" {
  description = "Loki datasource name in Grafana Cloud. Defaults to grafanacloud-<stack>-logs."
  type        = string
  default     = ""
}

variable "grafana_prometheus_ds_name" {
  description = "Prometheus datasource name in Grafana Cloud. Defaults to grafanacloud-<stack>-prom."
  type        = string
  default     = ""
}

variable "grafana_tempo_ds_name" {
  description = "Tempo datasource name in Grafana Cloud. Defaults to grafanacloud-<stack>-traces."
  type        = string
  default     = ""
}

variable "enable_rollback_workflow" {
  description = "If true, create an Incident Workflow to roll back web-frontend to v1.2.0."
  type        = bool
  default     = false
}

variable "rollback_webhook_url" {
  description = "Base URL of the FastDeploy API (e.g. http://1.2.3.4:8080). Required when enable_rollback_workflow = true."
  type        = string
  default     = ""
}

variable "rollback_basic_auth" {
  description = "Basic auth credentials for FastDeploy in user:password format. Required when enable_rollback_workflow = true."
  type        = string
  default     = ""
  sensitive   = true
}
