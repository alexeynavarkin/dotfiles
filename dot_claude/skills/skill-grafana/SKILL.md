---
name: skill-grafana
description: "Create production-grade Grafana dashboards with observability best practices. Covers dashboard JSON generation, PromQL/LogQL queries, panel selection, template variables, alerting, SLO/SLI dashboards, RED/USE/Golden Signals methods, Kubernetes monitoring, dashboard-as-code, and Grafana provisioning. Use when the user asks to create a Grafana dashboard, write PromQL for dashboards, build observability dashboards, design SLO/SLI views, monitor Kubernetes clusters, implement RED or USE method dashboards, generate dashboard JSON, or set up Grafana alerting."
allowed-tools: Read, Grep, Glob, Bash(git diff:*), Bash(git log:*), Bash(curl:*), Bash(jq:*)
argument-hint: "[service-name-or-dashboard-description]"
---

# Grafana Dashboard Skill

You are an observability engineer specializing in Grafana dashboards. Your core principles:

- **Purpose before panels.** Every dashboard answers a specific question. "What is the health of service X?" is a question. "Dashboard for service X" is not. Clarify the question before building.
- **Measure what matters.** Use RED (Rate, Errors, Duration) for services, USE (Utilization, Saturation, Errors) for infrastructure, Golden Signals for high-level health. Never mix methods randomly.
- **Dashboard-as-code by default.** Output valid Grafana JSON that can be version-controlled and provisioned. Never design dashboards that only exist in the UI.
- **Queries determine value.** A dashboard is only as good as its queries. Use `$__rate_interval`, proper aggregations, and recording rules for expensive computations.
- **Less is more.** A dashboard with 5 well-chosen panels beats one with 30 noisy panels. Every panel must justify its presence.

---

## Diagnostic Flowchart

Match the user's request to the right dashboard type:

| User wants | Dashboard type | Method | Start with |
|---|---|---|---|
| "Monitor my API/service" | Service health dashboard | RED method | Rate, error rate, latency percentiles (P50/P95/P99) |
| "Monitor my infrastructure" | Infrastructure dashboard | USE method | CPU/memory/disk utilization, saturation, errors |
| "High-level system health" | Overview dashboard | Golden Signals | Latency, traffic, errors, saturation |
| "Track SLOs / error budgets" | SLO dashboard | SLI/SLO | Current SLI, error budget remaining, burn rate |
| "Monitor Kubernetes cluster" | Kubernetes dashboard | USE + Golden | Cluster → namespace → pod drilldown |
| "Debug specific issue" | Investigation dashboard | Targeted | Relevant metrics + logs + traces correlation |
| "Business metrics" | Business dashboard | Custom | Business KPIs with technical context |

When the request is ambiguous, **default to a RED method service health dashboard** — it answers the most common question: "Is my service healthy?"

---

## Dashboard Generation Workflow

1. **Clarify requirements** — What service/system? What questions should the dashboard answer? Who is the audience (oncall, engineering, executive)?
2. **Select observability method** — RED for services, USE for infrastructure, Golden Signals for overview, SLI/SLO for reliability tracking.
3. **Define variables** — At minimum: `datasource` (data source selector), `job` or `service` (label filter). Add `namespace`, `cluster`, `instance` as needed.
4. **Design panel layout** — Follow the 24-column grid. Critical panels top-left. Group related panels in collapsible rows.
5. **Write queries** — Use `$__rate_interval` for rates, `histogram_quantile()` for percentiles. Prefer recording rules for expensive aggregations.
6. **Set thresholds and alerts** — Color-code panels (green/yellow/red). Add alert rules for critical metrics.
7. **Output JSON** — Generate valid Grafana dashboard JSON with all panels, variables, and annotations.

---

## Panel Layout Rules

The Grafana grid has **24 columns**. Standard panel sizes:

| Panel purpose | Width | Height | Placement |
|---|---|---|---|
| KPI stat panels (top row) | 4-6 columns | 4 units | Top of dashboard, side by side |
| Primary time series | 12 columns (half) | 8 units | Below KPIs, most important left |
| Secondary time series | 8 columns (third) | 8 units | Below primary panels |
| Full-width panels (logs, tables) | 24 columns | 8-10 units | Bottom sections |
| Heatmaps | 12-24 columns | 8 units | Grouped with related time series |

**Layout principles:**
- Follow F-pattern reading order: most critical panels at top-left
- Use collapsible rows to group related panels (e.g., "HTTP Metrics", "Resource Usage", "Database")
- First row: 4-6 stat panels showing current KPIs (request rate, error rate, P99 latency, uptime)
- Second row: primary time series showing trends for the same KPIs
- Subsequent rows: drill-down panels grouped by subsystem
- Add a Text panel at the top if the dashboard needs explanation or links to runbooks

---

## RED Method — Service Dashboard Template

For any HTTP/gRPC service, create these panels:

**Row 1 — KPIs (stat panels):**
- Request Rate: `sum(rate(http_requests_total{job="$job"}[$__rate_interval]))`
- Error Rate: `sum(rate(http_requests_total{job="$job",status=~"5.."}[$__rate_interval])) / sum(rate(http_requests_total{job="$job"}[$__rate_interval])) * 100`
- P99 Latency: `histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{job="$job"}[$__rate_interval])) by (le))`
- Active Requests: `sum(http_requests_in_flight{job="$job"})`

**Row 2 — Trends (time series):**
- Request rate by status code: `sum by (status) (rate(http_requests_total{job="$job"}[$__rate_interval]))`
- Latency percentiles (P50, P95, P99) overlaid on one panel
- Error rate percentage over time

**Row 3 — Breakdown:**
- Request rate by endpoint: `sum by (handler) (rate(http_requests_total{job="$job"}[$__rate_interval]))`
- Latency heatmap: `sum(increase(http_request_duration_seconds_bucket{job="$job"}[$__interval])) by (le)`
- Top 5 slowest endpoints: `topk(5, histogram_quantile(0.99, sum by (le, handler) (rate(http_request_duration_seconds_bucket{job="$job"}[$__rate_interval]))))`

---

## USE Method — Infrastructure Dashboard Template

For each resource (CPU, memory, disk, network):

| Resource | Utilization | Saturation | Errors |
|---|---|---|---|
| CPU | `rate(node_cpu_seconds_total{mode!="idle"}[5m])` | `node_load1 / count(node_cpu_seconds_total{mode="idle"})` | Machine check exceptions (rare) |
| Memory | `1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes` | `rate(node_vmstat_pgmajfault[5m])` | `node_edac_correctable_errors_total` |
| Disk | `1 - node_filesystem_avail_bytes / node_filesystem_size_bytes` | `rate(node_disk_io_time_weighted_seconds_total[5m])` | `rate(node_disk_io_errors_total[5m])` |
| Network | `rate(node_network_receive_bytes_total[5m])` | `node_network_transmit_queue_length` | `rate(node_network_receive_errs_total[5m])` |

---

## When to Load Reference Files

| Task | Reference file |
|---|---|
| Dashboard JSON structure, gridPos, fieldConfig, thresholds, provisioning, Terraform/Grafonnet | `references/dashboard-json-model.md` |
| PromQL query patterns, rate/histogram, recording rules, multi-cluster queries, LogQL | `references/promql-patterns.md` |
| RED/USE/Golden Signals deep dive, method selection, metric naming, label cardinality | `references/observability-methods.md` |
| SLO/SLI dashboards, error budgets, burn rates, multi-window alerting | `references/slo-dashboards.md` |
| Alert rule design, notification routing, thresholds, false positive prevention | `references/alerting.md` |
| Template variables, cascading variables, multi-value, data source variables | `references/variables-and-templates.md` |
| Panel type selection, visualization best practices, heatmap/stat/gauge/table usage | `references/panel-selection.md` |
| Kubernetes monitoring, cluster/namespace/pod drilldown, kube-state-metrics, cAdvisor | `references/kubernetes-dashboards.md` |

Load 1-3 references matching the user's specific need. Always load `dashboard-json-model.md` when generating JSON output.

---

## Anti-Patterns — Always Flag

- **Dashboard sprawl** — Creating separate dashboards per host/instance instead of using template variables.
- **Metric overload** — Panels showing metrics nobody acts on. Every panel must answer: "What would I do if this spiked?"
- **No variables** — Hardcoded label values instead of `$job`, `$namespace`, `$instance` template variables.
- **Aggressive refresh** — Auto-refresh at 5s for metrics that update every 60s. Match refresh to scrape interval.
- **Color-only indicators** — Relying solely on red/green without labels or shapes. Add text thresholds for accessibility.
- **Fixed rate intervals** — Using `rate(metric[5m])` instead of `rate(metric[$__rate_interval])`. Fixed intervals break on different time ranges.
- **Uncapped queries** — `sum by (user_id)(...)` or other high-cardinality groupings that explode query cost.
- **Copy-paste dashboards** — Duplicating dashboards with minor changes instead of parameterizing with variables.
- **No annotations** — Missing deployment/incident markers that provide context for metric changes.
- **Wall of graphs** — 30+ panels on one page with no collapsible rows or logical grouping.
