# Template Variables and Dynamic Dashboards

## Variable Types

| Type | Purpose | Example |
|---|---|---|
| **Query** | Dynamically populated from data source | `label_values(up, job)` → dropdown of all jobs |
| **Data source** | Switch data source dashboard-wide | Dropdown of all Prometheus instances |
| **Constant** | Fixed value used across queries | `slo_target = 0.999` |
| **Custom** | Static list of values | `env: prod, staging, dev` |
| **Text box** | Free-text input | Custom filter strings |
| **Interval** | Time interval selection | `1m, 5m, 15m, 1h` |

---

## Essential Variables for Every Dashboard

At minimum, include these three variables:

```json
[
  {
    "name": "datasource",
    "type": "datasource",
    "query": "prometheus",
    "label": "Data Source"
  },
  {
    "name": "job",
    "type": "query",
    "query": "label_values(up, job)",
    "datasource": { "uid": "${datasource}" },
    "label": "Service"
  },
  {
    "name": "instance",
    "type": "query",
    "query": "label_values(up{job=\"$job\"}, instance)",
    "datasource": { "uid": "${datasource}" },
    "multi": true,
    "includeAll": true,
    "label": "Instance"
  }
]
```

---

## Query Variable Patterns (Prometheus)

### Basic Label Values

```promql
# All values for a label
label_values(up, job)

# Filtered by another label
label_values(up{namespace="$namespace"}, job)

# From a specific metric
label_values(http_requests_total, handler)
```

### Advanced Queries

```promql
# Top 10 busiest services
topk(10, sum by (job) (rate(http_requests_total[$__range])))

# Only services with errors
label_values(http_requests_total{status=~"5.."}, job)

# Services above traffic threshold
query_result(sum by (job) (rate(http_requests_total[5m])) > 10)
```

### Regex Filtering

Filter returned values with regex in the variable definition:

| Pattern | Effect |
|---|---|
| `/^prod-.*/` | Only values starting with "prod-" |
| `/.*-api$/` | Only values ending with "-api" |
| `/^(?!test).*/` | Exclude values starting with "test" |
| `/gateway\|proxy/` | Only "gateway" or "proxy" |

---

## Cascading Variables

Create parent-child relationships where the child depends on the parent:

```
Variable 1: cluster
  Query: label_values(up, cluster)

Variable 2: namespace (depends on cluster)
  Query: label_values(up{cluster="$cluster"}, namespace)

Variable 3: pod (depends on namespace)
  Query: label_values(kube_pod_info{cluster="$cluster", namespace="$namespace"}, pod)
```

**Order matters:** Variables are evaluated top-to-bottom. Parent variables must be defined before children in the `templating.list` array.

---

## Multi-Value Variables

Enable `multi: true` and `includeAll: true` for variables that should support selecting multiple values:

```json
{
  "name": "namespace",
  "multi": true,
  "includeAll": true,
  "allValue": ".*",
  "query": "label_values(kube_pod_info{cluster=\"$cluster\"}, namespace)"
}
```

**Using in queries:**

```promql
# With multi-value variable (Grafana auto-joins with |)
rate(http_requests_total{namespace=~"$namespace"}[$__rate_interval])
```

When `includeAll` is selected, the `allValue` field determines what gets substituted. Use `".*"` for regex matchers (`=~`), or leave empty for Grafana's default pipe-separated list.

---

## Data Source Variables

Allow switching between environments without separate dashboards:

```json
{
  "name": "datasource",
  "type": "datasource",
  "query": "prometheus",
  "regex": "/^(?!.*internal).*/",
  "label": "Environment"
}
```

Reference in all panels: `"datasource": { "type": "prometheus", "uid": "${datasource}" }`

For multi-backend setups (Prometheus + Loki + Tempo):

```json
[
  { "name": "metrics_ds", "type": "datasource", "query": "prometheus" },
  { "name": "logs_ds", "type": "datasource", "query": "loki" },
  { "name": "traces_ds", "type": "datasource", "query": "tempo" }
]
```

---

## Interval Variables

Let users control query granularity:

```json
{
  "name": "resolution",
  "type": "interval",
  "query": "1m,5m,15m,30m,1h",
  "current": { "text": "5m", "value": "5m" },
  "label": "Resolution"
}
```

Use in queries: `rate(metric[$resolution])` — but prefer `$__rate_interval` for automatic resolution in most cases. Custom interval variables are useful when users need explicit control.

---

## Constant Variables

Store values used across multiple panels:

```json
{
  "name": "slo_target",
  "type": "constant",
  "query": "0.999",
  "hide": 2,
  "label": "SLO Target"
}
```

`hide: 2` hides the variable from the dashboard UI. Use for:
- SLO targets referenced in multiple panels
- Threshold values shared across panels
- Environment-specific constants

---

## Variable Syntax in Queries

| Syntax | Usage | Example |
|---|---|---|
| `$varname` | Standard — readable, can't be mid-word | `{job="$job"}` |
| `${varname}` | When variable is adjacent to other text | `${job}_suffix` |
| `${varname:regex}` | Escape for regex matchers | `{job=~"${job:regex}"}` |
| `${varname:pipe}` | Pipe-separated for multi-value | `value1\|value2` |
| `${varname:csv}` | Comma-separated | `value1,value2` |

---

## Performance Considerations

1. **Limit returned values** — Use regex to filter out irrelevant options
2. **Set `refresh: 2`** (on time range change) not `refresh: 1` (on dashboard load) for variables that depend on the time range
3. **Avoid expensive queries** in variable definitions — `label_values()` is fast; `query_result()` with complex aggregations is slow
4. **Cap multi-value selections** — Document recommended maximum selections to avoid query explosion
5. **Use `skipUrlSync: true`** for constant variables that shouldn't clutter the URL

---

## Common Patterns

### Environment Selector

```json
{
  "name": "env",
  "type": "custom",
  "query": "prod, staging, dev",
  "current": { "text": "prod", "value": "prod" }
}
```

### Kubernetes Hierarchy

```
cluster → namespace → deployment → pod
```

Each level filters the next using cascading queries.

### Service Discovery

```promql
# Auto-discover services by scrape target
label_values(up{job=~".*"}, job)

# Auto-discover endpoints
label_values(http_requests_total{job="$job"}, handler)
```

### Time Comparison

```json
{
  "name": "compare_offset",
  "type": "custom",
  "query": "1h, 1d, 7d, 30d",
  "label": "Compare To"
}
```

Use: `rate(metric[$__rate_interval]) offset $compare_offset`
