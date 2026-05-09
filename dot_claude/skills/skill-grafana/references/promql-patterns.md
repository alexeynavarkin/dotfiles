# PromQL Patterns for Grafana Dashboards

## Rate and Increase

**Always use `$__rate_interval` in Grafana** — it automatically adjusts to at least 4x the scrape interval, preventing gaps in rate calculations across different time ranges.

```promql
# Request rate per second
sum(rate(http_requests_total{job="$job"}[$__rate_interval]))

# Request rate by status code
sum by (status) (rate(http_requests_total{job="$job"}[$__rate_interval]))

# Total count increase over selected range
sum(increase(http_requests_total{job="$job"}[$__range]))

# Per-instance rate
rate(http_requests_total{job="$job", instance=~"$instance"}[$__rate_interval])
```

**Why not fixed intervals:** `rate(metric[5m])` breaks when the dashboard time range is short (e.g., last 15 minutes — too few samples) or very long (e.g., 30 days — unnecessarily granular).

---

## Histogram Percentiles

```promql
# P99 latency
histogram_quantile(0.99,
  sum by (le) (rate(http_request_duration_seconds_bucket{job="$job"}[$__rate_interval]))
)

# P95 latency
histogram_quantile(0.95,
  sum by (le) (rate(http_request_duration_seconds_bucket{job="$job"}[$__rate_interval]))
)

# P50 latency (median)
histogram_quantile(0.50,
  sum by (le) (rate(http_request_duration_seconds_bucket{job="$job"}[$__rate_interval]))
)

# Latency by endpoint
histogram_quantile(0.99,
  sum by (le, handler) (rate(http_request_duration_seconds_bucket{job="$job"}[$__rate_interval]))
)

# Average latency (alternative to percentiles)
sum(rate(http_request_duration_seconds_sum{job="$job"}[$__rate_interval]))
/
sum(rate(http_request_duration_seconds_count{job="$job"}[$__rate_interval]))
```

**Important:** `histogram_quantile` works on `_bucket` metrics. The result is in the unit of the histogram (usually seconds). Always `rate()` the buckets before applying `histogram_quantile`.

---

## Heatmap Queries

For heatmap panels showing latency distribution over time:

```promql
# Use with heatmap panel, format: "Time series buckets"
sum(increase(http_request_duration_seconds_bucket{job="$job"}[$__interval])) by (le)
```

Set panel data source format to **"Time series buckets"** and max data points to **25** for optimal rendering.

---

## Error Rate Patterns

```promql
# Error percentage (0-100)
sum(rate(http_requests_total{job="$job", status=~"5.."}[$__rate_interval]))
/ sum(rate(http_requests_total{job="$job"}[$__rate_interval])) * 100

# Error ratio (0-1, for SLI use)
1 - (
  sum(rate(http_requests_total{job="$job", status=~"2.."}[$__rate_interval]))
  / sum(rate(http_requests_total{job="$job"}[$__rate_interval]))
)

# gRPC error rate
sum(rate(grpc_server_handled_total{job="$job", grpc_code!="OK"}[$__rate_interval]))
/ sum(rate(grpc_server_handled_total{job="$job"}[$__rate_interval])) * 100

# Error rate by endpoint (find the noisiest)
topk(5,
  sum by (handler) (rate(http_requests_total{job="$job", status=~"5.."}[$__rate_interval]))
  / sum by (handler) (rate(http_requests_total{job="$job"}[$__rate_interval])) * 100
)
```

---

## Resource Metrics (USE Method)

```promql
# CPU utilization (0-1)
1 - avg(rate(node_cpu_seconds_total{mode="idle", instance=~"$instance"}[$__rate_interval]))

# Memory utilization (0-1)
1 - (node_memory_MemAvailable_bytes{instance=~"$instance"} / node_memory_MemTotal_bytes{instance=~"$instance"})

# Disk utilization
1 - (node_filesystem_avail_bytes{instance=~"$instance", mountpoint="/"} / node_filesystem_size_bytes{instance=~"$instance", mountpoint="/"})

# Network receive rate
rate(node_network_receive_bytes_total{instance=~"$instance", device!~"lo|veth.*|docker.*|br.*"}[$__rate_interval])

# CPU saturation (load per CPU)
node_load1{instance=~"$instance"} / count without (cpu) (node_cpu_seconds_total{mode="idle", instance=~"$instance"})
```

---

## Aggregation Patterns

```promql
# Sum across all instances
sum(metric{job="$job"})

# Average across instances
avg(metric{job="$job"})

# Top N consumers
topk(10, sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="$namespace"}[$__rate_interval])))

# Bottom N (least active)
bottomk(5, sum by (instance) (rate(http_requests_total{job="$job"}[$__rate_interval])))

# Count of instances matching condition
count(up{job="$job"} == 1)

# Group by multiple labels
sum by (method, status) (rate(http_requests_total{job="$job"}[$__rate_interval]))
```

---

## Recording Rules

Precompute expensive queries to improve dashboard load time. Place in Prometheus rules file:

```yaml
groups:
  - name: service_red_metrics
    interval: 30s
    rules:
      # Request rate by job
      - record: job:http_requests:rate5m
        expr: sum by (job) (rate(http_requests_total[5m]))

      # Error rate by job
      - record: job:http_requests_errors:ratio5m
        expr: |
          sum by (job) (rate(http_requests_total{status=~"5.."}[5m]))
          / sum by (job) (rate(http_requests_total[5m]))

      # P99 latency by job
      - record: job:http_request_duration_seconds:p99_5m
        expr: |
          histogram_quantile(0.99,
            sum by (job, le) (rate(http_request_duration_seconds_bucket[5m]))
          )

      # Availability (success ratio)
      - record: job:http_requests:availability5m
        expr: |
          sum by (job) (rate(http_requests_total{status=~"2.."}[5m]))
          / sum by (job) (rate(http_requests_total[5m]))
```

**Naming convention:** `level:metric:operations` (e.g., `job:http_requests:rate5m`)

Use recording rules in dashboard queries for instant loading:
```promql
# Instead of computing rate in the dashboard:
job:http_requests:rate5m{job="$job"}
```

---

## Multi-Cluster Queries

```promql
# Rate across clusters
sum by (cluster) (rate(http_requests_total{job="$job"}[$__rate_interval]))

# Total across all clusters
sum(rate(http_requests_total{job="$job"}[$__rate_interval]))

# Compare specific clusters
sum by (cluster) (rate(http_requests_total{job="$job", cluster=~"$cluster"}[$__rate_interval]))

# Cross-cluster P99
histogram_quantile(0.99,
  sum by (le, cluster) (rate(http_request_duration_seconds_bucket{job="$job"}[$__rate_interval]))
)
```

---

## LogQL for Loki Panels

```logql
# Basic log query
{job="$job"} |= "error"

# Structured metadata filtering
{job="$job"} | json | level="error"

# Log rate (metric query for time series panel)
sum(rate({job="$job"} |= "error" [$__auto]))

# Extract and aggregate from logs
sum by (status) (rate({job="$job"} | json | __error__="" | unwrap status [$__auto]))

# Log volume by level
sum by (level) (count_over_time({job="$job"} | json [$__auto]))
```

---

## Grafana Special Variables

| Variable | Expands to | Use in |
|---|---|---|
| `$__rate_interval` | Max(4 * scrape_interval, $__interval) | `rate()`, `increase()` |
| `$__interval` | Auto-calculated step based on time range and panel width | `increase()`, heatmaps |
| `$__range` | Selected time range as duration | `increase()` over full range |
| `$__range_s` | Selected time range in seconds | Recording rule parameters |
| `$__auto` | Auto-calculated interval for LogQL | Loki metric queries |
| `${__from:date}` | Start time of selected range | Annotations, links |
| `${__to:date}` | End time of selected range | Annotations, links |

---

## Query Performance Tips

1. **Filter early** — Put label matchers inside `{}` not after `and`. `rate(metric{job="x"}[5m])` is faster than `rate(metric[5m]) and on(job) {job="x"}`.
2. **Avoid `.*` in regex** — `{handler=~".*"}` matches everything and adds overhead. Omit the label matcher entirely.
3. **Use recording rules** for queries aggregating over many series (>1000 source series).
4. **Set `Min interval`** on panels querying slow-changing metrics (e.g., `1m` for node metrics scraped at 60s).
5. **Limit `topk`/`bottomk`** — Keep N reasonable (5-20). High N defeats the purpose.
6. **Avoid `count(rate(...))` patterns** — Pre-aggregate with recording rules if you need series counts.
