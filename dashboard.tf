# OrbitPay Frontend — SRE Overview dashboard.
# Shows the full story of a deployment regression: baseline → error spike → alert → rollback.
# All resources are conditional on var.enable_grafana.

locals {
  prom_uid  = try(data.grafana_data_source.prometheus[0].uid, "")
  loki_uid  = try(data.grafana_data_source.loki[0].uid, "")
  tempo_uid = try(data.grafana_data_source.tempo[0].uid, "")
}

resource "grafana_dashboard" "orbitpay_frontend" {
  count  = var.enable_grafana ? 1 : 0
  folder = grafana_folder.orbitpay[0].uid

  config_json = jsonencode({
    title   = "OrbitPay Frontend — SRE Overview"
    uid     = "orbitpay-frontend"
    tags    = ["orbitpay", "sre"]
    refresh = "30s"
    time    = { from = "now-1h", to = "now" }
    panels = [

      # ── Row 1: KPI Stats ─────────────────────────────────────────────────
      {
        id      = 1
        type    = "row"
        title   = "KPI"
        gridPos = { x = 0, y = 0, w = 24, h = 1 }
        collapsed = false
      },
      {
        id    = 2
        type  = "stat"
        title = "Request Rate"
        gridPos = { x = 0, y = 1, w = 6, h = 4 }
        datasource = { type = "prometheus", uid = local.prom_uid }
        targets = [{
          refId      = "A"
          datasource = { type = "prometheus", uid = local.prom_uid }
          expr       = "sum(rate(http_server_duration_milliseconds_count{service_name=\"orbitpay-frontend\"}[2m]))"
        }]
        options = {
          reduceOptions = { calcs = ["lastNotNull"] }
          orientation   = "auto"
          graphMode     = "area"
          colorMode     = "value"
          textMode      = "auto"
        }
        fieldConfig = {
          defaults = {
            unit = "reqps"
            thresholds = {
              mode = "absolute"
              steps = [
                { color = "green", value = null },
              ]
            }
          }
        }
      },
      {
        id    = 3
        type  = "stat"
        title = "5xx Error Rate"
        gridPos = { x = 6, y = 1, w = 6, h = 4 }
        datasource = { type = "prometheus", uid = local.prom_uid }
        targets = [{
          refId      = "A"
          datasource = { type = "prometheus", uid = local.prom_uid }
          expr       = "sum(rate(http_server_duration_milliseconds_count{service_name=\"orbitpay-frontend\",http_status_code=~\"5..\"}[2m])) / sum(rate(http_server_duration_milliseconds_count{service_name=\"orbitpay-frontend\"}[2m])) * 100 or vector(0)"
        }]
        options = {
          reduceOptions = { calcs = ["lastNotNull"] }
          orientation   = "auto"
          graphMode     = "area"
          colorMode     = "background"
          textMode      = "auto"
        }
        fieldConfig = {
          defaults = {
            unit = "percent"
            thresholds = {
              mode = "absolute"
              steps = [
                { color = "green", value = null },
                { color = "red", value = 5 },
              ]
            }
          }
        }
      },
      {
        id    = 4
        type  = "stat"
        title = "p99 Latency"
        gridPos = { x = 12, y = 1, w = 6, h = 4 }
        datasource = { type = "prometheus", uid = local.prom_uid }
        targets = [{
          refId      = "A"
          datasource = { type = "prometheus", uid = local.prom_uid }
          expr       = "histogram_quantile(0.99, rate(http_server_duration_milliseconds_bucket{service_name=\"orbitpay-frontend\"}[2m]))"
        }]
        options = {
          reduceOptions = { calcs = ["lastNotNull"] }
          orientation   = "auto"
          graphMode     = "area"
          colorMode     = "background"
          textMode      = "auto"
        }
        fieldConfig = {
          defaults = {
            unit = "ms"
            thresholds = {
              mode = "absolute"
              steps = [
                { color = "green", value = null },
                { color = "red", value = 2000 },
              ]
            }
          }
        }
      },
      {
        id    = 5
        type  = "stat"
        title = "Heap Memory %"
        gridPos = { x = 18, y = 1, w = 6, h = 4 }
        datasource = { type = "prometheus", uid = local.prom_uid }
        targets = [{
          refId      = "A"
          datasource = { type = "prometheus", uid = local.prom_uid }
          expr       = "nodejs_heap_size_used_bytes{service_name=\"orbitpay-frontend\"} / nodejs_heap_size_total_bytes{service_name=\"orbitpay-frontend\"} * 100"
        }]
        options = {
          reduceOptions = { calcs = ["lastNotNull"] }
          orientation   = "auto"
          graphMode     = "area"
          colorMode     = "background"
          textMode      = "auto"
        }
        fieldConfig = {
          defaults = {
            unit = "percent"
            thresholds = {
              mode = "absolute"
              steps = [
                { color = "green", value = null },
                { color = "red", value = 85 },
              ]
            }
          }
        }
      },

      # ── Row 2: HTTP Traffic ──────────────────────────────────────────────
      {
        id      = 10
        type    = "row"
        title   = "HTTP Traffic"
        gridPos = { x = 0, y = 5, w = 24, h = 1 }
        collapsed = false
      },
      {
        id    = 11
        type  = "timeseries"
        title = "Request Rate by Status"
        gridPos = { x = 0, y = 6, w = 12, h = 8 }
        datasource = { type = "prometheus", uid = local.prom_uid }
        targets = [
          {
            refId      = "A"
            datasource = { type = "prometheus", uid = local.prom_uid }
            expr       = "sum by (http_status_code) (rate(http_server_duration_milliseconds_count{service_name=\"orbitpay-frontend\",http_status_code=~\"2..\"}[2m]))"
            legendFormat = "2xx"
          },
          {
            refId      = "B"
            datasource = { type = "prometheus", uid = local.prom_uid }
            expr       = "sum by (http_status_code) (rate(http_server_duration_milliseconds_count{service_name=\"orbitpay-frontend\",http_status_code=~\"3..\"}[2m]))"
            legendFormat = "3xx"
          },
          {
            refId      = "C"
            datasource = { type = "prometheus", uid = local.prom_uid }
            expr       = "sum by (http_status_code) (rate(http_server_duration_milliseconds_count{service_name=\"orbitpay-frontend\",http_status_code=~\"4..\"}[2m]))"
            legendFormat = "4xx"
          },
          {
            refId      = "D"
            datasource = { type = "prometheus", uid = local.prom_uid }
            expr       = "sum by (http_status_code) (rate(http_server_duration_milliseconds_count{service_name=\"orbitpay-frontend\",http_status_code=~\"5..\"}[2m]))"
            legendFormat = "5xx"
          },
        ]
        fieldConfig = {
          defaults = {
            unit = "reqps"
          }
          overrides = [
            {
              matcher = { id = "byName", options = "5xx" }
              properties = [{ id = "color", value = { mode = "fixed", fixedColor = "red" } }]
            }
          ]
        }
        options = { tooltip = { mode = "multi" } }
      },
      {
        id    = 12
        type  = "timeseries"
        title = "5xx Error Rate"
        gridPos = { x = 12, y = 6, w = 12, h = 8 }
        datasource = { type = "prometheus", uid = local.prom_uid }
        targets = [{
          refId      = "A"
          datasource = { type = "prometheus", uid = local.prom_uid }
          expr       = "sum(rate(http_server_duration_milliseconds_count{service_name=\"orbitpay-frontend\",http_status_code=~\"5..\"}[2m])) or sum(rate(http_server_duration_milliseconds_count{service_name=\"orbitpay-frontend\"}[2m]) * 0)"
          legendFormat = "5xx rps"
        }]
        fieldConfig = {
          defaults = {
            unit = "reqps"
            thresholds = {
              mode = "absolute"
              steps = [
                { color = "green", value = null },
                { color = "red", value = 0.05 },
              ]
            }
            custom = {
              thresholdsStyle = { mode = "line+area" }
            }
          }
        }
        options = { tooltip = { mode = "single" } }
      },

      # ── Row 3: Transfer Endpoint ─────────────────────────────────────────
      {
        id      = 20
        type    = "row"
        title   = "Transfer Endpoint"
        gridPos = { x = 0, y = 14, w = 24, h = 1 }
        collapsed = false
      },
      {
        id    = 21
        type  = "timeseries"
        title = "Transfer Error Rate"
        gridPos = { x = 0, y = 15, w = 12, h = 8 }
        datasource = { type = "prometheus", uid = local.prom_uid }
        targets = [{
          refId      = "A"
          datasource = { type = "prometheus", uid = local.prom_uid }
          expr       = "sum(rate(http_server_duration_milliseconds_count{service_name=\"orbitpay-frontend\",http_route=\"/transfer\",http_status_code=~\"[45]..\"}[2m])) or vector(0)"
          legendFormat = "error rps"
        }]
        fieldConfig = {
          defaults = {
            unit = "reqps"
            thresholds = {
              mode = "absolute"
              steps = [
                { color = "green", value = null },
                { color = "red", value = 0.01 },
              ]
            }
            custom = {
              thresholdsStyle = { mode = "line+area" }
            }
          }
        }
        options = { tooltip = { mode = "single" } }
      },
      {
        id    = 22
        type  = "timeseries"
        title = "Transfer p99 Latency"
        gridPos = { x = 12, y = 15, w = 12, h = 8 }
        datasource = { type = "prometheus", uid = local.prom_uid }
        targets = [{
          refId      = "A"
          datasource = { type = "prometheus", uid = local.prom_uid }
          expr       = "histogram_quantile(0.99, rate(http_server_duration_milliseconds_bucket{service_name=\"orbitpay-frontend\",http_route=\"/transfer\"}[2m]))"
          legendFormat = "p99 latency"
        }]
        fieldConfig = {
          defaults = {
            unit = "ms"
            thresholds = {
              mode = "absolute"
              steps = [
                { color = "green", value = null },
                { color = "red", value = 2000 },
              ]
            }
            custom = {
              thresholdsStyle = { mode = "line+area" }
            }
          }
        }
        options = { tooltip = { mode = "single" } }
      },

      # ── Row 4: Node.js Runtime ───────────────────────────────────────────
      {
        id      = 30
        type    = "row"
        title   = "Node.js Runtime"
        gridPos = { x = 0, y = 23, w = 24, h = 1 }
        collapsed = false
      },
      {
        id    = 31
        type  = "timeseries"
        title = "Event Loop Lag"
        gridPos = { x = 0, y = 24, w = 12, h = 8 }
        datasource = { type = "prometheus", uid = local.prom_uid }
        targets = [{
          refId      = "A"
          datasource = { type = "prometheus", uid = local.prom_uid }
          expr       = "nodejs_eventloop_lag_seconds{service_name=\"orbitpay-frontend\"}"
          legendFormat = "event loop lag"
        }]
        fieldConfig = {
          defaults = {
            unit = "s"
            thresholds = {
              mode = "absolute"
              steps = [
                { color = "green", value = null },
                { color = "red", value = 0.1 },
              ]
            }
            custom = {
              thresholdsStyle = { mode = "line+area" }
            }
          }
        }
        options = { tooltip = { mode = "single" } }
      },
      {
        id    = 32
        type  = "timeseries"
        title = "Heap Memory"
        gridPos = { x = 12, y = 24, w = 12, h = 8 }
        datasource = { type = "prometheus", uid = local.prom_uid }
        targets = [
          {
            refId      = "A"
            datasource = { type = "prometheus", uid = local.prom_uid }
            expr       = "nodejs_heap_size_used_bytes{service_name=\"orbitpay-frontend\"}"
            legendFormat = "used"
          },
          {
            refId      = "B"
            datasource = { type = "prometheus", uid = local.prom_uid }
            expr       = "nodejs_heap_size_total_bytes{service_name=\"orbitpay-frontend\"}"
            legendFormat = "total"
          },
        ]
        fieldConfig = {
          defaults = {
            unit = "bytes"
          }
          overrides = [
            {
              matcher = { id = "byName", options = "total" }
              properties = [{ id = "custom.lineStyle", value = { fill = "dash" } }]
            }
          ]
        }
        options = { tooltip = { mode = "multi" } }
      },

      # ── Row 5: Logs ──────────────────────────────────────────────────────
      {
        id      = 40
        type    = "row"
        title   = "Logs"
        gridPos = { x = 0, y = 32, w = 24, h = 1 }
        collapsed = false
      },
      {
        id    = 41
        type  = "timeseries"
        title = "Error/Warn Log Rate"
        gridPos = { x = 0, y = 33, w = 12, h = 8 }
        datasource = { type = "loki", uid = local.loki_uid }
        targets = [{
          refId      = "A"
          datasource = { type = "loki", uid = local.loki_uid }
          expr       = "sum(rate({service_name=\"orbitpay-frontend\"} | json | severity =~ \"error|warn\" [2m]))"
          legendFormat = "error/warn rps"
        }]
        fieldConfig = {
          defaults = {
            unit = "reqps"
            thresholds = {
              mode = "absolute"
              steps = [
                { color = "green", value = null },
                { color = "red", value = 0.1 },
              ]
            }
            custom = {
              thresholdsStyle = { mode = "line+area" }
            }
          }
        }
        options = { tooltip = { mode = "single" } }
      },
      {
        id    = 42
        type  = "logs"
        title = "Recent Error/Warn Logs"
        gridPos = { x = 12, y = 33, w = 12, h = 8 }
        datasource = { type = "loki", uid = local.loki_uid }
        targets = [{
          refId      = "A"
          datasource = { type = "loki", uid = local.loki_uid }
          expr      = "{service_name=\"orbitpay-frontend\"} | json | severity =~ \"error|warn\""
          queryType = "range"
        }]
        options = {
          dedupStrategy   = "none"
          showLabels      = false
          showTime        = true
          sortOrder       = "Descending"
          wrapLogMessage  = true
        }
      },

      # ── Row 6: Traces ────────────────────────────────────────────────────
      {
        id      = 50
        type    = "row"
        title   = "Traces"
        gridPos = { x = 0, y = 41, w = 24, h = 1 }
        collapsed = false
      },
      {
        id    = 51
        type  = "nodeGraph"
        title = "Service Map"
        gridPos = { x = 0, y = 42, w = 12, h = 10 }
        datasource = { type = "tempo", uid = local.tempo_uid }
        targets = [{
          refId      = "A"
          datasource = { type = "tempo", uid = local.tempo_uid }
          queryType  = "serviceMap"
          serviceMapQuery = "{service=\"orbitpay-frontend\"}"
        }]
        options = {}
      },
      {
        id    = 52
        type  = "table"
        title = "Trace Search"
        gridPos = { x = 12, y = 42, w = 12, h = 10 }
        datasource = { type = "tempo", uid = local.tempo_uid }
        targets = [{
          refId      = "A"
          datasource = { type = "tempo", uid = local.tempo_uid }
          queryType  = "traceql"
          query      = "{resource.service.name=\"orbitpay-frontend\"}"
          limit      = 20
        }]
        options = {
          sortBy = [{ displayName = "Duration", desc = true }]
        }
        transformations = [
          { id = "sortBy", options = { fields = [{ displayName = "Duration", order = "desc" }] } }
        ]
      },
    ]
  })
}
