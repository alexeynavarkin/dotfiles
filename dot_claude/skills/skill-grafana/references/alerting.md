# Grafana Alerting Best Practices

## Core Principles

1. **Alert on symptoms, not causes.** Alert when users are affected (high error rate, high latency), not when infrastructure metrics change (CPU spike). A CPU spike that doesn't affect users is not worth waking someone up for.
2. **Every alert must be actionable.** If the oncall engineer can't do anything about it, it shouldn't page. Convert to a ticket or remove it.
3. **Every alert needs an owner.** Unowned alerts rot. Assign a team responsible for tuning and maintaining each alert.

---

## Alert Rule Design

### Symptom-Based Alerts (Preferred)

```yaml
# Good: alerts when users experience errors
- alert: HighErrorRate
  expr: |
    sum(rate(http_requests_total{job="api", status=~"5.."}[5m]))
    / sum(rate(http_requests_total{job="api"}[5m])) > 0.01
  for: 5m
  labels:
    severity: critical
  annotations:
    summary: "Error rate above 1% for 5 minutes"
    dashboard: "https://grafana.example.com/d/service-api"
    runbook: "https://wiki.example.com/runbooks/high-error-rate"

# Bad: alerts on a cause that may not affect users
- alert: HighCPU
  expr: node_cpu_utilization > 0.9
  # CPU at 90% might be fine if latency is normal
```

### Threshold Guidelines

| Metric type | Warning | Critical | Reasoning |
|---|---|---|---|
| Error rate | > 0.1% for 10m | > 1% for 5m | Small error rates are normal; sustained high rates need attention |
| P99 latency | > 2× baseline for 10m | > 5× baseline for 5m | Compare to historical baseline, not arbitrary values |
| Availability | < 99.95% (30m window) | < 99.9% (15m window) | Tied to SLO targets |
| Disk usage | > 80% | > 90% | Leave room for growth and burst writes |
| Error budget burn rate | 6× for 6h | 14.4× for 1h | Multi-window SLO alerting (see slo-dashboards.md) |

---

## Pending Periods (`for` clause)

The `for` clause requires the condition to persist before the alert fires. This prevents transient spikes from causing false alarms.

| Alert type | Recommended `for` | Why |
|---|---|---|
| Critical (page) | 2-5 minutes | Fast response needed, but avoid single-sample spikes |
| Warning (ticket) | 10-15 minutes | Non-urgent; filter out transient noise |
| Capacity (planning) | 30-60 minutes | Long-term trend, not transient |

**Anti-pattern:** `for: 0s` on anything except heartbeat/dead-man-switch alerts. Single-sample alerts are almost always false positives.

---

## Notification Routing

### Notification Policy Tree

Structure notification policies as a routing tree:

```
Root Policy (default: email)
├── severity=critical → PagerDuty
│   ├── team=platform → PagerDuty (platform rotation)
│   └── team=product → PagerDuty (product rotation)
├── severity=warning → Slack #alerts-warning
│   ├── team=platform → Slack #platform-alerts
│   └── team=product → Slack #product-alerts
└── severity=info → Slack #alerts-info (batched, 30m interval)
```

### Alert Grouping

Group related alerts to prevent notification spam:

```yaml
# Group by service — all alerts for the same service arrive as one notification
group_by: [job, alertname]

# Timing
group_wait: 30s        # Wait before sending first notification (to batch)
group_interval: 5m     # Wait before sending updates for existing group
repeat_interval: 4h    # Wait before re-sending unchanged alert
```

**Key insight:** A database failure triggers multiple downstream service alerts. Grouping by `job` ensures the oncall sees "database is down" once, not 15 individual service failure alerts.

---

## Alert Annotations

Every alert should include annotations that help the oncall engineer act quickly:

```yaml
annotations:
  summary: "{{ $labels.job }}: error rate {{ printf \"%.2f\" $value }}% (threshold: 1%)"
  description: |
    Error rate for {{ $labels.job }} has been above 1% for more than 5 minutes.
    Current value: {{ printf "%.2f" $value }}%.
    Instance: {{ $labels.instance }}
  dashboard: "https://grafana.example.com/d/service-{{ $labels.job }}"
  runbook: "https://wiki.example.com/runbooks/{{ $labels.alertname | toLower }}"
  logs: "https://grafana.example.com/explore?left=[\"now-1h\",\"now\",\"Loki\",{\"expr\":\"{job=\\\"{{ $labels.job }}\\\"} |= \\\"error\\\"\"}]"
```

**Required annotations:**
1. `summary` — One-line description with current value and threshold
2. `dashboard` — Direct link to the relevant dashboard (with variables pre-filled if possible)
3. `runbook` — Link to remediation steps

**Recommended annotations:**
4. `description` — Detailed context about the alert condition
5. `logs` — Direct link to Grafana Explore with pre-filled log query

---

## Preventing False Positives

### Use Percentiles, Not Averages

```promql
# Bad: average hides outliers
avg(http_request_duration_seconds) > 1

# Good: P99 catches tail latency
histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket[5m]))) > 1
```

### Use `$__rate_interval` for Stable Rates

```promql
# Bad: fixed interval may miss samples or over-aggregate
rate(metric[5m])

# Good: Grafana auto-adjusts interval
rate(metric[$__rate_interval])
```

### Aggregate Before Comparing

```promql
# Bad: per-instance alert fires when one pod restarts
http_requests_total{status="500"} > 0

# Good: aggregate across instances
sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) > 0.01
```

### Exclude Maintenance Windows

```promql
# Skip alerting during known maintenance
... unless on() maintenance_mode == 1
```

---

## Alert Testing and Maintenance

### Before Deploying

1. **Test with real data** — Use Grafana's "Test Rule" button to simulate the alert against live data
2. **Verify notification delivery** — Send a test notification to each channel
3. **Check for label collisions** — Ensure alert labels don't conflict with routing policies

### Ongoing Maintenance

| Frequency | Action |
|---|---|
| Weekly | Review alerts that fired — were they actionable? |
| Monthly | Audit alert fatigue — remove/tune alerts firing > 10x/month without action |
| Quarterly | Review all alert thresholds against current baselines |
| On each deploy | Verify alerts still match new metric names/labels |

### Alert Health Metrics

Monitor your alerting system itself:

```promql
# Alerts firing too frequently (potential noise)
count_over_time(ALERTS{alertstate="firing"}[7d]) > 50

# Alerts that never fire (dead alerts, remove them)
# Review: alerts with no firing instances in 90 days
```

---

## Grafana Alert Rule JSON

```json
{
  "alert": {
    "name": "High Error Rate",
    "conditions": [
      {
        "evaluator": { "type": "gt", "params": [0.01] },
        "operator": { "type": "and" },
        "query": { "params": ["A", "5m", "now"] },
        "reducer": { "type": "last" }
      }
    ],
    "executionErrorState": "alerting",
    "for": "5m",
    "frequency": "1m",
    "noDataState": "no_data",
    "notifications": [
      { "uid": "pagerduty-critical" }
    ]
  }
}
```

---

## Common Alert Anti-Patterns

- **Alerting on causes** — CPU, memory, disk alerts without correlation to user impact. Convert to capacity planning tickets.
- **No `for` clause** — Single-sample alerts generate constant noise from transient spikes.
- **Alerting on every instance** — One unhealthy pod in a 50-pod deployment is not critical. Aggregate first.
- **Duplicate alerts** — Same condition in Prometheus alertmanager AND Grafana alerting. Pick one.
- **No runbook** — Alert fires at 3 AM and the oncall has no idea what to do. Every page needs a runbook.
- **Alert fatigue** — More than 5-10 actionable alerts per oncall shift indicates over-alerting. Tune thresholds or consolidate.
