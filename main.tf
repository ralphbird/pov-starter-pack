terraform {
  required_providers {
    pagerduty = {
      source  = "PagerDuty/pagerduty"
      version = ">= 3.29.0, < 4.0.0"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.0.0"
    }
    slack = {
      source  = "pablovarela/slack"
      version = "~> 1.2"
    }
    grafana = {
      source  = "grafana/grafana"
      version = ">= 3.0.0, < 4.0.0"
    }
  }
}

provider "pagerduty" {
  # If empty, provider will use env var PAGERDUTY_TOKEN
  token            = var.pagerduty_token != "" ? var.pagerduty_token : null
  api_url_override = var.pagerduty_api_url_override != "" ? var.pagerduty_api_url_override : null
}

provider "slack" {
  # Token is set to "unused" when Slack is disabled to avoid provider validation errors.
  token = var.enable_slack ? var.slack_token : "unused"
}

provider "grafana" {
  url  = var.grafana_url != "" ? var.grafana_url : "https://localhost"
  auth = var.grafana_token != "" ? var.grafana_token : "unused"
}

########################################
# Locals: POV Teams, Business & Technical
########################################

# POV-only team catalog (code => display name)
locals {
  team_catalog = {
    PP = "Payments Platform"
    WL = "Wallet & Ledgers"
    CX = "Customer Experience"
    CI = "Core Infrastructure"
  }

  # Sanitized team names for Escalation Policy names (PagerDuty EP name rules)
  team_ep_safe_name = {
    for code, name in local.team_catalog :
    code => replace(
      replace(
        replace(
          replace(
            replace(trimspace(name), "&", "and"),
          "/", "-"),
        "\\", "-"),
      "<", "-"),
    ">", "-")
  }

  team_slack_channel_name = {
    for code, name in local.team_catalog :
    code => "incidents-${lower(replace(replace(name, " & ", "-and-"), " ", "-"))}"
  }

  business_services = [
    "Payments API",
    "Digital Wallet",
    "Customer Experience Portal",
    "Account Management",
  ]

  technical_services = {
    # Payments API
    "Payments API Gateway"         = { team = "PP" }
    "Payments Orchestrator (sync)" = { team = "PP" }
    "Payments Rules Engine"        = { team = "PP" }
    "Idempotency Token Service"    = { team = "PP" }
    "Payments Ledger DB Cluster"   = { team = "WL" }
    "Service Mesh / mTLS"          = { team = "CI" }
    "Edge WAF/CDN"                 = { team = "CI" }

    # Digital Wallet
    "Wallet API"                 = { team = "WL" }
    "Balance Manager"            = { team = "WL" }
    "Funding Source Linker"      = { team = "WL" }
    "Ledger DB Cluster (wallet)" = { team = "WL" }
    "Profile Service"            = { team = "CX" }
    "Secrets Manager"            = { team = "CI" }

    # Customer Experience Portal
    "Web Frontend (SSR)"      = { team = "CX" }
    "Mobile API BFF"          = { team = "CX" }
    "Notification Service"    = { team = "CX" }
    "Accessibility & A/B Testing" = { team = "CX" }
    "Content & CMS Service"   = { team = "CX" }
    "CDN/Edge Caching"        = { team = "CI" }
    "Push Gateway"            = { team = "CI" }

    # Account Management
    "Profile API"       = { team = "CX" }
    "Preferences Service" = { team = "CX" }
  }

  # Business -> technical dependencies (POV only)
  dependencies = [
    # Payments API
    { b = "Payments API", t = "Idempotency Token Service", layer = "L1" },
    { b = "Payments API", t = "Payments API Gateway", layer = "L1" },
    { b = "Payments API", t = "Payments Orchestrator (sync)", layer = "L1" },
    { b = "Payments API", t = "Payments Rules Engine", layer = "L1" },
    { b = "Payments API", t = "Payments Ledger DB Cluster", layer = "L2" },
    { b = "Payments API", t = "Edge WAF/CDN", layer = "L3" },
    { b = "Payments API", t = "Service Mesh / mTLS", layer = "L3" },

    # Digital Wallet
    { b = "Digital Wallet", t = "Balance Manager", layer = "L1" },
    { b = "Digital Wallet", t = "Funding Source Linker", layer = "L1" },
    { b = "Digital Wallet", t = "Wallet API", layer = "L1" },
    { b = "Digital Wallet", t = "Ledger DB Cluster (wallet)", layer = "L2" },
    { b = "Digital Wallet", t = "Profile Service", layer = "L2" },
    { b = "Digital Wallet", t = "Secrets Manager", layer = "L3" },

    # Customer Experience Portal
    { b = "Customer Experience Portal", t = "Mobile API BFF", layer = "L1" },
    { b = "Customer Experience Portal", t = "Notification Service", layer = "L1" },
    { b = "Customer Experience Portal", t = "Web Frontend (SSR)", layer = "L1" },
    { b = "Customer Experience Portal", t = "Accessibility & A/B Testing", layer = "L2" },
    { b = "Customer Experience Portal", t = "Content & CMS Service", layer = "L2" },
    { b = "Customer Experience Portal", t = "CDN/Edge Caching", layer = "L3" },
    { b = "Customer Experience Portal", t = "Push Gateway", layer = "L3" },

    # Account Management
    { b = "Account Management", t = "Profile API", layer = "L1" },
    { b = "Account Management", t = "Preferences Service", layer = "L2" },
  ]

  # Technical -> technical dependencies (POV only)
  tech_edges = [
    # Payments API
    { from = "Payments API Gateway", to = "Payments Orchestrator (sync)" },
    { from = "Payments Orchestrator (sync)", to = "Payments Rules Engine" },
    { from = "Payments Orchestrator (sync)", to = "Payments Ledger DB Cluster" },
    { from = "Payments API Gateway", to = "Service Mesh / mTLS" },
    { from = "Payments API Gateway", to = "Edge WAF/CDN" },

    # Digital Wallet
    { from = "Wallet API", to = "Balance Manager" },
    { from = "Wallet API", to = "Ledger DB Cluster (wallet)" },
    { from = "Wallet API", to = "Secrets Manager" },

    # Customer Experience Portal
    { from = "Web Frontend (SSR)", to = "Mobile API BFF" },
    { from = "Mobile API BFF", to = "Notification Service" },
    { from = "Mobile API BFF", to = "Content & CMS Service" },
    { from = "Web Frontend (SSR)", to = "CDN/Edge Caching" },
  ]
}

############################
# Teams & Escalation Policies
############################

data "pagerduty_user" "pov_user" {
  count = var.pov_user_email != null ? 1 : 0
  email = var.pov_user_email
}

locals {
  create_schedules = length(var.team_schedule_ids) == 0
}

resource "pagerduty_schedule" "pov_schedule" {
  for_each  = local.create_schedules ? local.team_catalog : {}
  name      = "${local.team_ep_safe_name[each.key]} Schedule (POV)"
  time_zone = "Etc/UTC"
  description = "Created by POV Starter Pack"
  teams = [pagerduty_team.team[each.key].id]
  layer {
    name                         = "Always on call"
    start                        = "2023-01-01T00:00:00-00:00"
    rotation_virtual_start       = "2023-01-01T00:00:00-00:00"
    rotation_turn_length_seconds = 86400
    # During destroy (email is null), provide a dummy ID to satisfy provider schema validation.
    # The resource is being deleted, so this ID is never used against the API.
    users = var.pov_user_email != null ? [data.pagerduty_user.pov_user[0].id] : ["P000000"]
  }
}

locals {
  final_schedule_ids = local.create_schedules ? {
    for k, v in pagerduty_schedule.pov_schedule : k => v.id
  } : var.team_schedule_ids
}

resource "pagerduty_team" "team" {
  for_each    = local.team_catalog
  name        = local.team_ep_safe_name[each.key]
  description = "OrbitPay synthetic team: ${each.value} (Created by POV Starter Pack)"
}

resource "pagerduty_escalation_policy" "team_ep" {
  for_each    = local.team_catalog
  name        = "${local.team_ep_safe_name[each.key]} EP"
  description = "Escalation policy for ${each.value} (Created by POV Starter Pack)"
  num_loops   = 2
  teams       = [pagerduty_team.team[each.key].id]

  rule {
    escalation_delay_in_minutes = var.default_escalation_delay

    target {
      type = "schedule_reference"
      id   = local.final_schedule_ids[each.key]
    }
  }
}

############################
# Business Services
############################

resource "pagerduty_business_service" "orbitpay_bs" {
  for_each    = toset(local.business_services)
  name        = each.key
  description = "OrbitPay synthetic business service: ${each.key} (Created by POV Starter Pack)"
}

############################
# Technical Services
############################

resource "pagerduty_service" "orbitpay_ts" {
  for_each                = local.technical_services
  name                    = each.key
  description             = "OrbitPay synthetic technical service: ${each.key} (Created by POV Starter Pack)"
  escalation_policy       = pagerduty_escalation_policy.team_ep[each.value.team].id
  alert_creation          = "create_alerts_and_incidents"
  auto_resolve_timeout    = 0
  acknowledgement_timeout = 0

  # Notification preference: severity-based urgency (Dynamic notifications)
  incident_urgency_rule {
    type    = "constant"
    urgency = "severity_based"
  }

  # Enable Auto Pause Notifications for 5 minutes (300 seconds)
  auto_pause_notifications_parameters {
    enabled = true
    timeout = 300
  }
}

############################
# FastDeploy Change Events Integration
############################

resource "pagerduty_service_integration" "fastdeploy_change_events" {
  name    = "FastDeploy Change Events"
  service = pagerduty_service.orbitpay_ts["Web Frontend (SSR)"].id
  type    = "pagerduty_change_inbound_integration"
}

############################
# Dependencies: Business -> Technical + Technical -> Technical
############################

locals {
  bs_id_by_name = { for name, r in pagerduty_business_service.orbitpay_bs : name => r.id }
  ts_id_by_name = { for name, r in pagerduty_service.orbitpay_ts : name => r.id }
}

resource "pagerduty_service_dependency" "orbitpay_deps" {
  for_each = { for d in local.dependencies : "${d.b} -> ${d.t}" => d }

  dependency {
    dependent_service {
      type = "business_service"
      id   = local.bs_id_by_name[each.value.b]
    }
    supporting_service {
      type = "service"
      id   = local.ts_id_by_name[each.value.t]
    }
  }
}

resource "pagerduty_service_dependency" "orbitpay_ts_edges" {
  for_each = { for e in local.tech_edges : "${e.from} -> ${e.to}" => e }

  dependency {
    dependent_service {
      type = "service"
      id   = local.ts_id_by_name[each.value.from]
    }
    supporting_service {
      type = "service"
      id   = local.ts_id_by_name[each.value.to]
    }
  }
}

############################
# Global Event Orchestration
############################

# Priorities (names must exist)
# Priorities (Fetch via HTTP to be name-agnostic and support dynamic environments)
locals {
  # Default to US API if override is empty
  pd_api_url = var.pagerduty_api_url_override != "" ? var.pagerduty_api_url_override : "https://api.pagerduty.com"
}

data "http" "priorities" {
  url = "${local.pd_api_url}/priorities"

  request_headers = {
    Authorization = "Token token=${var.pagerduty_token}"
    Accept        = "application/vnd.pagerduty+json;version=2"
    Content-Type  = "application/json"
  }
}

locals {
  # Parse the JSON response
  # PagerDuty returns priorities sorted by severity (P1=Index 0, P2=Index 1...)
  priorities_list = jsondecode(data.http.priorities.response_body).priorities
}

resource "pagerduty_event_orchestration" "global" {
  name        = "OrbitPay Operations Global"
  description = "Created by POV Starter Pack"
}

resource "pagerduty_event_orchestration_router" "global" {
  event_orchestration = pagerduty_event_orchestration.global.id

  set {
    id = "start"

    rule {
      actions {
        dynamic_route_to {
          lookup_by = "service_name"
          source    = "event.custom_details.service_name"
          regex     = ".*"
        }
      }
    }
  }

  catch_all {
    actions {
      route_to = "unrouted"
    }
  }
}

resource "pagerduty_event_orchestration_global" "global" {
  event_orchestration = pagerduty_event_orchestration.global.id

  set {
    id = "start"

    rule {
      disabled = false
      label    = "Warning Alert - P5"
      condition { expression = "event.severity matches part 'warning'" }
      actions {
        priority = local.priorities_list[4].id
      }
    }

    rule {
      disabled = false
      label    = "Critical Alert - P4"
      condition { expression = "event.severity matches part 'critical'" }
      actions {
        priority = local.priorities_list[3].id
      }
    }

    rule {
      disabled = false
      label    = "Suppress Informational Events"
      condition { expression = "event.severity matches part 'info'" }
      actions {
        suppress = true
      }
    }

    rule {
      disabled = false
      label    = "Suppress Maintenance Events"
      condition { expression = "event.custom_details.maintenance matches part 'True'" }
      actions {
        suppress = true
      }
    }

    rule {
      disabled = false
      label    = "Application Outage Expected - Escalate to P2"
      condition { expression = "event.custom_details.application_impact matches part 'Outage'" }
      actions {
        event_action = "trigger"
        priority     = local.priorities_list[1].id
        severity     = "critical"

        dynamic "incident_custom_field_update" {
          for_each = local.incident_custom_field_short_ids.cuj_impacted != "" ? [local.incident_custom_field_short_ids.cuj_impacted] : []
          content {
            id    = incident_custom_field_update.value
            value = "True"
          }
        }
      }
    }
  }

  catch_all {
    actions {}
  }
}

resource "pagerduty_event_orchestration_integration" "global" {
  event_orchestration = pagerduty_event_orchestration.global.id
  label               = "OrbitPay Operations Global Integration"
}

############################
# Incident Type Custom Fields
############################

resource "pagerduty_incident_type_custom_field" "customer_journey_impacted" {
  count         = var.base_incident_type_id != "" ? 1 : 0
  data_type     = "boolean"
  default_value = jsonencode(false)
  description   = "Created by POV Starter Pack"
  display_name  = "Customer Journey Impacted"
  enabled       = true
  field_options = null
  field_type    = "single_value"
  incident_type = var.base_incident_type_id
  name          = "cuj_impacted"
}

resource "pagerduty_incident_type_custom_field" "propose_major_incident" {
  count         = var.base_incident_type_id != "" ? 1 : 0
  data_type     = "string"
  default_value = jsonencode("NO")
  description   = "Set to yes to kick off Major Incident workflow (Created by POV Starter Pack)"
  display_name  = "Propose Major Incident"
  enabled       = true
  field_options = ["NO", "YES"]
  field_type    = "single_value_fixed"
  incident_type = var.base_incident_type_id
  name          = "propose_major_incident"
}

locals {
  incident_custom_field_raw_ids = merge(
    {
      cuj_impacted           = try(pagerduty_incident_type_custom_field.customer_journey_impacted[0].id, ""),
      propose_major_incident = try(pagerduty_incident_type_custom_field.propose_major_incident[0].id, "")
    },
    var.incident_custom_field_ids
  )

  incident_custom_field_short_ids = {
    for key, raw_id in local.incident_custom_field_raw_ids :
    key => (
      raw_id == ""
      ? ""
      : (
        length(split(":", raw_id)) > 1
        ? element(split(":", raw_id), length(split(":", raw_id)) - 1)
        : raw_id
      )
    )
  }
}

############################
# Team Event Orchestrations
############################

resource "pagerduty_event_orchestration" "team" {
  for_each    = local.team_catalog
  name        = "OrbitPay Team - ${local.team_ep_safe_name[each.key]}"
  description = "Created by POV Starter Pack"
}

resource "pagerduty_event_orchestration_router" "team" {
  for_each            = local.team_catalog
  event_orchestration = pagerduty_event_orchestration.team[each.key].id

  set {
    id = "start"

    rule {
      actions {
        dynamic_route_to {
          lookup_by = "service_name"
          source    = "event.custom_details.service_name"
          regex     = ".*"
        }
      }
    }
  }

  catch_all {
    actions {
      route_to = "unrouted"
    }
  }
}

resource "pagerduty_event_orchestration_global" "team" {
  for_each            = local.team_catalog
  event_orchestration = pagerduty_event_orchestration.team[each.key].id

  set {
    id = "start"

    rule {
      condition { expression = "event.severity == 'critical'" }
      actions { priority = local.priorities_list[1].id }
    }
    rule {
      condition { expression = "event.severity == 'error'" }
      actions { priority = local.priorities_list[2].id }
    }
    rule {
      condition { expression = "event.severity == 'warning'" }
      actions { priority = local.priorities_list[3].id }
    }
    rule {
      condition { expression = "event.severity == 'info'" }
      actions { priority = local.priorities_list[4].id }
    }
  }

  catch_all {
    actions {}
  }
}

resource "pagerduty_event_orchestration_integration" "team" {
  for_each            = local.team_catalog
  event_orchestration = pagerduty_event_orchestration.team[each.key].id
  label               = "OrbitPay Team Integration - ${local.team_ep_safe_name[each.key]}"
}

############################
# Service Custom Fields
############################

resource "pagerduty_service_custom_field" "criticality" {
  count = var.manage_service_custom_fields ? 1 : 0

  name         = "criticality"
  display_name = "Criticality"
  description  = "Service criticality. (Created by POV Starter Pack)"
  field_type   = "single_value_fixed"
  data_type    = "string"

  field_option {
    data_type = "string"
    value     = "Critical"
  }
  field_option {
    data_type = "string"
    value     = "High"
  }
  field_option {
    data_type = "string"
    value     = "Medium"
  }
}

resource "pagerduty_service_custom_field" "service_tier" {
  count = var.manage_service_custom_fields ? 1 : 0

  name         = "service_tier"
  display_name = "Service Tier"
  description  = "Service tiering. (Created by POV Starter Pack)"
  field_type   = "single_value_fixed"
  data_type    = "string"

  field_option {
    data_type = "string"
    value     = "Tier-1"
  }
  field_option {
    data_type = "string"
    value     = "Tier-2"
  }
  field_option {
    data_type = "string"
    value     = "Tier-3"
  }
}

resource "pagerduty_service_custom_field" "environment" {
  count = var.manage_service_custom_fields ? 1 : 0

  name         = "environment"
  display_name = "Environment"
  description  = "Service environment. (Created by POV Starter Pack)"
  field_type   = "single_value_fixed"
  data_type    = "string"

  field_option {
    data_type = "string"
    value     = "prod"
  }
  field_option {
    data_type = "string"
    value     = "sandbox"
  }
  field_option {
    data_type = "string"
    value     = "staging"
  }
}

data "pagerduty_service_custom_field" "criticality" {
  count        = var.manage_service_custom_fields || length(var.service_custom_field_ids) > 0 ? 0 : 1
  display_name = "Criticality"
}

data "pagerduty_service_custom_field" "tier" {
  count        = var.manage_service_custom_fields || length(var.service_custom_field_ids) > 0 ? 0 : 1
  display_name = "Service Tier"
}

data "pagerduty_service_custom_field" "environment" {
  count        = var.manage_service_custom_fields || length(var.service_custom_field_ids) > 0 ? 0 : 1
  display_name = "Environment"
}

locals {
  scf_id_criticality = lookup(
    var.service_custom_field_ids,
    "criticality",
    try(
      pagerduty_service_custom_field.criticality[0].id,
      data.pagerduty_service_custom_field.criticality[0].id,
    ),
  )
  scf_id_tier = lookup(
    var.service_custom_field_ids,
    "service_tier",
    try(
      pagerduty_service_custom_field.service_tier[0].id,
      data.pagerduty_service_custom_field.tier[0].id,
    ),
  )
  scf_id_environment = lookup(
    var.service_custom_field_ids,
    "environment",
    try(
      pagerduty_service_custom_field.environment[0].id,
      data.pagerduty_service_custom_field.environment[0].id,
    ),
  )

  scf_service_targets = toset(keys(local.technical_services))

  tier1_services = toset([
    "Payments API Gateway",
    "Payments Orchestrator (sync)",
    "Payments Rules Engine",
    "Payments Ledger DB Cluster",
    "Wallet API",
    "Mobile API BFF",
    "Web Frontend (SSR)",
  ])

  tier2_services = toset([
    "Balance Manager",
    "Funding Source Linker",
    "Ledger DB Cluster (wallet)",
    "Profile Service",
    "Notification Service",
    "Content & CMS Service",
    "Profile API",
    "Preferences Service",
    "Edge WAF/CDN",
    "Service Mesh / mTLS",
    "Secrets Manager",
    "CDN/Edge Caching",
    "Push Gateway",
  ])

  criticality_by_service_ts = {
    for name in keys(local.technical_services) :
    name => (
      contains(local.tier1_services, name) ? "Critical" :
      contains(local.tier2_services, name) ? "High" :
      "Medium"
    )
  }

  tier_by_service_ts = {
    for name in keys(local.technical_services) :
    name => (
      contains(local.tier1_services, name) ? "Tier-1" :
      contains(local.tier2_services, name) ? "Tier-2" :
      "Tier-3"
    )
  }

  default_environment = strcontains(var.pagerduty_api_url_override, "staging") ? "staging" : "prod"
  environment_by_service_ts = {
    for name in keys(local.technical_services) :
    name => local.default_environment
  }
}

resource "pagerduty_service_custom_field_value" "assignments" {
  for_each = var.enable_scf_assignments ? local.scf_service_targets : toset([])

  service_id = pagerduty_service.orbitpay_ts[each.key].id
  custom_fields = [
    {
      id    = local.scf_id_criticality
      name  = "criticality"
      value = jsonencode(local.criticality_by_service_ts[each.key])
    },
    {
      id    = local.scf_id_tier
      name  = "service_tier"
      value = jsonencode(local.tier_by_service_ts[each.key])
    },
    {
      id    = local.scf_id_environment
      name  = "environment"
      value = jsonencode(local.environment_by_service_ts[each.key])
    },
  ]
}

############################
# Slack Integration (Optional)
############################

resource "slack_conversation" "team" {
  for_each          = var.enable_slack ? local.team_catalog : {}
  name              = local.team_slack_channel_name[each.key]
  is_private        = false
  action_on_destroy = "none"
}
