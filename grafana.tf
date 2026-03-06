# Grafana Cloud alert rules for orbitpay-frontend.
# All resources are conditional on var.enable_grafana.

locals {
  grafana_stack_slug = (
    var.enable_grafana && var.grafana_url != ""
    ? replace(replace(var.grafana_url, "https://", ""), ".grafana.net", "")
    : ""
  )
  loki_ds_name = (
    var.grafana_loki_ds_name != ""
    ? var.grafana_loki_ds_name
    : "grafanacloud-${local.grafana_stack_slug}-logs"
  )
  prometheus_ds_name = (
    var.grafana_prometheus_ds_name != ""
    ? var.grafana_prometheus_ds_name
    : "grafanacloud-${local.grafana_stack_slug}-prom"
  )
  tempo_ds_name = (
    var.grafana_tempo_ds_name != ""
    ? var.grafana_tempo_ds_name
    : "grafanacloud-${local.grafana_stack_slug}-traces"
  )
}

# ── Datasource lookups ───────────────────────────────────────────────────────

data "grafana_data_source" "loki" {
  count = var.enable_grafana ? 1 : 0
  name  = local.loki_ds_name
}

data "grafana_data_source" "prometheus" {
  count = var.enable_grafana ? 1 : 0
  name  = local.prometheus_ds_name
}

data "grafana_data_source" "tempo" {
  count = var.enable_grafana ? 1 : 0
  name  = local.tempo_ds_name
}

# ── PagerDuty Events API v2 integration for Web Frontend (SSR) ──────────────

resource "pagerduty_service_integration" "web_frontend_events_v2" {
  count   = var.enable_grafana ? 1 : 0
  name    = "Grafana Alerts"
  service = pagerduty_service.orbitpay_ts["Web Frontend (SSR)"].id
  type    = "events_api_v2_inbound_integration"
}

# ── Grafana folder ───────────────────────────────────────────────────────────

resource "grafana_folder" "orbitpay" {
  count = var.enable_grafana ? 1 : 0
  uid   = "orbitpay"
  title = "orbitpay"
}

# ── Contact point ────────────────────────────────────────────────────────────

resource "grafana_contact_point" "orbitpay_pagerduty" {
  count = var.enable_grafana ? 1 : 0
  name  = "orbitpay-pagerduty"

  pagerduty {
    integration_key         = pagerduty_service_integration.web_frontend_events_v2[0].integration_key
    severity                = "critical"
    class                   = "orbitpay-alert"
    component               = "orbitpay-frontend"
    group                   = "orbitpay"
    disable_resolve_message = false
  }
}

# ── Alert rule group ─────────────────────────────────────────────────────────

resource "grafana_rule_group" "orbitpay_frontend" {
  count            = var.enable_grafana ? 1 : 0
  name             = "orbitpay-frontend"
  folder_uid       = grafana_folder.orbitpay[0].uid
  interval_seconds = 30

  # Rule 1: 5xx error rate (Prometheus, critical)
  rule {
    name      = "orbitpay-5xx-error-rate"
    condition = "B"
    for       = "30s"

    no_data_state  = "OK"
    exec_err_state = "Error"
    is_paused      = false

    labels = {
      severity = "critical"
      service  = "orbitpay-frontend"
      team     = "cx"
    }
    annotations = {
      summary = "orbitpay-frontend: HTTP 5xx error rate exceeds 0.05 rps"
    }

    data {
      ref_id         = "A"
      datasource_uid = data.grafana_data_source.prometheus[0].uid
      query_type     = ""
      relative_time_range {
        from = 300
        to   = 0
      }
      model = jsonencode({
        datasource = { type = "prometheus", uid = data.grafana_data_source.prometheus[0].uid }
        editorMode = "code"
        expr       = "sum(rate(http_server_duration_milliseconds_count{service_name=\"orbitpay-frontend\",http_status_code=~\"5..\"}[2m]))"
        instant    = true
        refId      = "A"
      })
    }
    data {
      ref_id         = "B"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 300
        to   = 0
      }
      model = jsonencode({
        datasource = { type = "__expr__", uid = "__expr__" }
        type       = "classic_conditions"
        conditions = [{
          evaluator = { params = [0.05], type = "gt" }
          operator  = { type = "and" }
          query     = { params = ["A"] }
          reducer   = { type = "last" }
          type      = "query"
        }]
        refId = "B"
      })
    }
  }

  # Rule 2: transfer POST error rate (Prometheus, critical)
  rule {
    name      = "orbitpay-transfer-error-rate"
    condition = "B"
    for       = "30s"

    no_data_state  = "OK"
    exec_err_state = "Error"
    is_paused      = false

    labels = {
      severity = "critical"
      service  = "orbitpay-frontend"
      team     = "cx"
    }
    annotations = {
      summary = "orbitpay-frontend: POST /transfer errors detected — payment path degraded"
    }

    data {
      ref_id         = "A"
      datasource_uid = data.grafana_data_source.prometheus[0].uid
      query_type     = ""
      relative_time_range {
        from = 300
        to   = 0
      }
      model = jsonencode({
        datasource = { type = "prometheus", uid = data.grafana_data_source.prometheus[0].uid }
        editorMode = "code"
        expr       = "sum(rate(http_server_duration_milliseconds_count{service_name=\"orbitpay-frontend\",http_route=\"/transfer\",http_status_code=~\"[45]..\"}[2m]))"
        instant    = true
        refId      = "A"
      })
    }
    data {
      ref_id         = "B"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 300
        to   = 0
      }
      model = jsonencode({
        datasource = { type = "__expr__", uid = "__expr__" }
        type       = "classic_conditions"
        conditions = [{
          evaluator = { params = [0.01], type = "gt" }
          operator  = { type = "and" }
          query     = { params = ["A"] }
          reducer   = { type = "last" }
          type      = "query"
        }]
        refId = "B"
      })
    }
  }

  # Rule 3: p99 latency (Prometheus, warning)
  rule {
    name      = "orbitpay-p99-latency"
    condition = "B"
    for       = "2m"

    no_data_state  = "OK"
    exec_err_state = "Error"
    is_paused      = false

    labels = {
      severity = "warning"
      service  = "orbitpay-frontend"
      team     = "cx"
    }
    annotations = {
      summary = "orbitpay-frontend: p99 request latency exceeds 2000ms"
    }

    data {
      ref_id         = "A"
      datasource_uid = data.grafana_data_source.prometheus[0].uid
      query_type     = ""
      relative_time_range {
        from = 300
        to   = 0
      }
      model = jsonencode({
        datasource = { type = "prometheus", uid = data.grafana_data_source.prometheus[0].uid }
        editorMode = "code"
        expr       = "histogram_quantile(0.99, rate(http_server_duration_milliseconds_bucket{service_name=\"orbitpay-frontend\"}[2m]))"
        instant    = true
        refId      = "A"
      })
    }
    data {
      ref_id         = "B"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 300
        to   = 0
      }
      model = jsonencode({
        datasource = { type = "__expr__", uid = "__expr__" }
        type       = "classic_conditions"
        conditions = [{
          evaluator = { params = [2000], type = "gt" }
          operator  = { type = "and" }
          query     = { params = ["A"] }
          reducer   = { type = "last" }
          type      = "query"
        }]
        refId = "B"
      })
    }
  }

  # Rule 4: service absent — no metrics for 5m (Prometheus, critical)
  rule {
    name      = "orbitpay-service-absent"
    condition = "B"
    for       = "5m"

    no_data_state  = "OK"
    exec_err_state = "Error"
    is_paused      = false

    labels = {
      severity = "critical"
      service  = "orbitpay-frontend"
      team     = "cx"
    }
    annotations = {
      summary = "orbitpay-frontend: no metrics received for 5 minutes — service may be down"
    }

    data {
      ref_id         = "A"
      datasource_uid = data.grafana_data_source.prometheus[0].uid
      query_type     = ""
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        datasource = { type = "prometheus", uid = data.grafana_data_source.prometheus[0].uid }
        editorMode = "code"
        expr       = "absent_over_time(http_server_duration_milliseconds_count{service_name=\"orbitpay-frontend\"}[5m])"
        instant    = true
        refId      = "A"
      })
    }
    data {
      ref_id         = "B"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        datasource = { type = "__expr__", uid = "__expr__" }
        type       = "classic_conditions"
        conditions = [{
          evaluator = { params = [0], type = "gt" }
          operator  = { type = "and" }
          query     = { params = ["A"] }
          reducer   = { type = "last" }
          type      = "query"
        }]
        refId = "B"
      })
    }
  }

  # Rule 5: Node.js event loop lag (Prometheus, warning)
  rule {
    name      = "orbitpay-event-loop-lag"
    condition = "B"
    for       = "2m"

    no_data_state  = "OK"
    exec_err_state = "Error"
    is_paused      = false

    labels = {
      severity = "warning"
      service  = "orbitpay-frontend"
      team     = "cx"
    }
    annotations = {
      summary = "orbitpay-frontend: Node.js event loop lag exceeds 100ms"
    }

    data {
      ref_id         = "A"
      datasource_uid = data.grafana_data_source.prometheus[0].uid
      query_type     = ""
      relative_time_range {
        from = 300
        to   = 0
      }
      model = jsonencode({
        datasource = { type = "prometheus", uid = data.grafana_data_source.prometheus[0].uid }
        editorMode = "code"
        expr       = "nodejs_eventloop_lag_seconds{service_name=\"orbitpay-frontend\"}"
        instant    = true
        refId      = "A"
      })
    }
    data {
      ref_id         = "B"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 300
        to   = 0
      }
      model = jsonencode({
        datasource = { type = "__expr__", uid = "__expr__" }
        type       = "classic_conditions"
        conditions = [{
          evaluator = { params = [0.1], type = "gt" }
          operator  = { type = "and" }
          query     = { params = ["A"] }
          reducer   = { type = "last" }
          type      = "query"
        }]
        refId = "B"
      })
    }
  }

  # Rule 6: error/warn log rate (Loki, warning)
  rule {
    name      = "orbitpay-error-log-rate"
    condition = "B"
    for       = "2m"

    no_data_state  = "OK"
    exec_err_state = "Error"
    is_paused      = false

    labels = {
      severity = "warning"
      service  = "orbitpay-frontend"
      team     = "cx"
    }
    annotations = {
      summary = "orbitpay-frontend: application error/warn log rate elevated"
    }

    data {
      ref_id         = "A"
      datasource_uid = data.grafana_data_source.loki[0].uid
      query_type     = "range"
      relative_time_range {
        from = 300
        to   = 0
      }
      model = jsonencode({
        datasource = { type = "loki", uid = data.grafana_data_source.loki[0].uid }
        editorMode = "code"
        expr       = "sum(rate({service_name=\"orbitpay-frontend\"} | json | severity =~ \"error|warn\" [2m]))"
        queryType  = "range"
        refId      = "A"
      })
    }
    data {
      ref_id         = "B"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 300
        to   = 0
      }
      model = jsonencode({
        datasource = { type = "__expr__", uid = "__expr__" }
        type       = "classic_conditions"
        conditions = [{
          evaluator = { params = [0.1], type = "gt" }
          operator  = { type = "and" }
          query     = { params = ["A"] }
          reducer   = { type = "last" }
          type      = "query"
        }]
        refId = "B"
      })
    }
  }

  # Rule 7: heap memory > 85% (Prometheus, warning)
  rule {
    name      = "orbitpay-heap-memory"
    condition = "B"
    for       = "2m"

    no_data_state  = "OK"
    exec_err_state = "Error"
    is_paused      = false

    labels = {
      severity = "warning"
      service  = "orbitpay-frontend"
      team     = "cx"
    }
    annotations = {
      summary = "orbitpay-frontend: heap memory usage exceeds 99%"
    }

    data {
      ref_id         = "A"
      datasource_uid = data.grafana_data_source.prometheus[0].uid
      query_type     = ""
      relative_time_range {
        from = 300
        to   = 0
      }
      model = jsonencode({
        datasource = { type = "prometheus", uid = data.grafana_data_source.prometheus[0].uid }
        editorMode = "code"
        expr       = "nodejs_heap_size_used_bytes{service_name=\"orbitpay-frontend\"} / nodejs_heap_size_total_bytes{service_name=\"orbitpay-frontend\"}"
        instant    = true
        refId      = "A"
      })
    }
    data {
      ref_id         = "B"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 300
        to   = 0
      }
      model = jsonencode({
        datasource = { type = "__expr__", uid = "__expr__" }
        type       = "classic_conditions"
        conditions = [{
          evaluator = { params = [0.99], type = "gt" }
          operator  = { type = "and" }
          query     = { params = ["A"] }
          reducer   = { type = "last" }
          type      = "query"
        }]
        refId = "B"
      })
    }
  }
}

# ── Notification policy ──────────────────────────────────────────────────────
# Manages the entire Grafana notification policy tree.
# Uses orbitpay-pagerduty as both the default and the orbitpay-specific receiver.

resource "grafana_notification_policy" "main" {
  count         = var.enable_grafana ? 1 : 0
  contact_point = grafana_contact_point.orbitpay_pagerduty[0].name
  group_by      = ["grafana_folder", "alertname"]

  policy {
    contact_point   = grafana_contact_point.orbitpay_pagerduty[0].name
    group_by        = ["alertname"]
    group_wait      = "10s"
    group_interval  = "5m"
    repeat_interval = "4h"

    matcher {
      label = "service"
      match = "="
      value = "orbitpay-frontend"
    }
  }
}
