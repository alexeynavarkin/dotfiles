# SLO/SLI Dashboards

## Core Concepts

**SLI (Service Level Indicator):** A quantitative measure of service health. Always a ratio: `good_events / total_events`.

**SLO (Service Level Objective):** A target value for an SLI. Example: "99.9% of requests succeed."

**Error Budget:** The allowed failure margin: `1 - SLO`. For 99.9% SLO → 0.1% error budget.

**Burn Rate:** How fast the error budget is being consumed relative to the compliance window.

---

## SLI Types

### Event-Based SLI (Recommended)

Measures the ratio of successful events to total events:

```promql
# Availability SLI
sli_availability = sum(rate(http_requests_total{status=~"2..|3.."}[$__rate_interval]))
                   / sum(rate(http_requests_total[$__rate_interval]))

# Latency SLI (fraction of requests faster than threshold)
sli_latency = sum(rate(http_request_duration_seconds_bucket{le="0.5"}[$__rate_interval]))
              / sum(rate(http_request_duration_seconds_count[$__rate_interval]))
```

### Time-Based SLI

Measures the fraction of time the system meets criteria:

```promql
# Fraction of time with successful probe
avg_over_time((probe_success{job="$job"} == 1)[$__range:1m])
```

---

## Error Budget Calculation

```
Error Budget (total)    = (1 - SLO) × compliance_window
Error Budget (remaining) = Error Budget (total) - errors_consumed
Error Budget (%)         = Error Budget (remaining) / Error Budget (total) × 100
```

**Example:** 99.9% SLO over 30-day window:
- Total budget: 0.1% × 30 days × 24h × 60m = 43.2 minutes of errors allowed
- Or: 0.1% × total_requests = allowed failing requests

```promql
# Error budget consumed (as fraction of budget)
(
  1 - (
    sum(increase(http_requests_total{job="$job", status=~"2..|3.."}[30d]))
    / sum(increase(http_requests_total{job="$job"}[30d]))
  )
) / (1 - 0.999)
```

---

## Burn Rate

Burn rate measures how fast the error budget is consumed, normalized to the compliance window.

- **Burn rate 1.0** = budget consumed in exactly the compliance window (30d)
- **Burn rate 2.0** = budget consumed in half the time (15d)
- **Burn rate 14.4** = budget consumed in 50 hours (need to act immediately)

```promql
# Burn rate formula
burn_rate = error_rate / (1 - SLO)

# Concrete example for 99.9% SLO:
# 1-hour burn rate
(
  1 - (
    sum(rate(http_requests_total{job="$job", status=~"2..|3.."}[1h]))
    / sum(rate(http_requests_total{job="$job"}[1h]))
  )
) / (1 - 0.999)
```

---

## Multi-Window Alerting (Google SRE Approach)

Combine a **long window** (confirms sustained impact) and a **short window** (confirms problem is still active). The short window should be ~1/12 of the long window.

### Recommended Alert Configuration for 99.9% SLO

| Severity | Long Window | Short Window | Burn Rate | Budget Consumed | Action |
|---|---|---|---|---|---|
| **Page (critical)** | 1 hour | 5 minutes | 14.4x | 2% | Wake someone up |
| **Page (high)** | 6 hours | 30 minutes | 6x | 5% | Respond within minutes |
| **Ticket** | 3 days | 6 hours | 1x | 10% | Fix within days |

### Alert Rules (PromQL)

```promql
# Page alert: 14.4x burn rate over 1h AND 5m
(
  (1 - sum(rate(http_requests_total{job="$job", status=~"2..|3.."}[1h]))
       / sum(rate(http_requests_total{job="$job"}[1h])))
  / (1 - 0.999) > 14.4
)
and
(
  (1 - sum(rate(http_requests_total{job="$job", status=~"2..|3.."}[5m]))
       / sum(rate(http_requests_total{job="$job"}[5m])))
  / (1 - 0.999) > 14.4
)

# High alert: 6x burn rate over 6h AND 30m
(
  (1 - sum(rate(http_requests_total{job="$job", status=~"2..|3.."}[6h]))
       / sum(rate(http_requests_total{job="$job"}[6h])))
  / (1 - 0.999) > 6
)
and
(
  (1 - sum(rate(http_requests_total{job="$job", status=~"2..|3.."}[30m]))
       / sum(rate(http_requests_total{job="$job"}[30m])))
  / (1 - 0.999) > 6
)
```

---

## SLO Dashboard Panel Layout

### Executive View (Stat + Gauge panels)

**Row 1 — Current Status (stat panels):**
| Panel | Query | Type | Thresholds |
|---|---|---|---|
| Current SLI | `sli_availability` | Stat | green >= SLO, yellow >= SLO-0.1%, red < SLO-0.1% |
| SLO Target | Static `0.999` | Stat | Always blue |
| Error Budget Remaining | `1 - budget_consumed_ratio` | Gauge | green > 50%, yellow > 20%, red <= 20% |
| Time to Budget Exhaustion | `remaining_budget / current_burn_rate` | Stat | green > 7d, yellow > 1d, red <= 1d |

**Row 2 — Trends (time series):**
| Panel | Content |
|---|---|
| SLI over time | SLI value with SLO target as threshold line |
| Error budget burndown | Budget remaining over compliance window |
| Burn rate | 1h and 6h burn rates with threshold lines |

### Engineering View

Add these panels below the executive view:

**Row 3 — Error Analysis:**
| Panel | Content |
|---|---|
| Error rate by endpoint | `topk(5, error_rate by handler)` |
| Error rate by status code | Breakdown of 4xx vs 5xx |
| Latency P99 by endpoint | Which endpoints breach the latency SLI |

**Row 4 — Dependency Health:**
| Panel | Content |
|---|---|
| Upstream dependency latency | P99 to each dependency |
| Database query duration | Slow query impact on SLI |
| Cache hit rate | Cache misses correlating with latency spikes |

### Oncall View

Focus on actionability:

**Row 1 — Alerts:**
| Panel | Content |
|---|---|
| Active burn rate alerts | Current alert state |
| Recent incidents | Annotation-based incident markers |

**Row 2 — Context:**
| Panel | Content |
|---|---|
| Deployment markers | Annotation showing recent deploys |
| Error log stream | Loki panel filtered to errors |
| Runbook links | Text panel with links to runbooks |

---

## Recording Rules for SLO Dashboards

Precompute SLI and burn rate metrics to avoid expensive real-time calculations:

```yaml
groups:
  - name: slo_rules
    interval: 30s
    rules:
      # SLI: availability
      - record: job:sli_availability:ratio5m
        expr: |
          sum by (job) (rate(http_requests_total{status=~"2..|3.."}[5m]))
          / sum by (job) (rate(http_requests_total[5m]))

      # Burn rate: 1 hour
      - record: job:error_budget_burn_rate:1h
        expr: |
          (1 - sum by (job) (rate(http_requests_total{status=~"2..|3.."}[1h]))
               / sum by (job) (rate(http_requests_total[1h])))
          / (1 - 0.999)

      # Burn rate: 6 hours
      - record: job:error_budget_burn_rate:6h
        expr: |
          (1 - sum by (job) (rate(http_requests_total{status=~"2..|3.."}[6h]))
               / sum by (job) (rate(http_requests_total[6h])))
          / (1 - 0.999)

      # Burn rate: 3 days
      - record: job:error_budget_burn_rate:3d
        expr: |
          (1 - sum by (job) (rate(http_requests_total{status=~"2..|3.."}[3d]))
               / sum by (job) (rate(http_requests_total[3d])))
          / (1 - 0.999)

      # Budget consumed (30-day window)
      - record: job:error_budget_consumed:ratio30d
        expr: |
          (1 - sum by (job) (increase(http_requests_total{status=~"2..|3.."}[30d]))
               / sum by (job) (increase(http_requests_total[30d])))
          / (1 - 0.999)
```

---

## Compliance Windows

| Window | Error Budget (99.9% SLO) | Error Budget (99.95% SLO) | Error Budget (99.99% SLO) |
|---|---|---|---|
| 1 day | 1 min 26s | 43s | 8.6s |
| 7 days | 10 min 5s | 5 min 2s | 1 min |
| 30 days | 43 min 12s | 21 min 36s | 4 min 19s |
| 90 days | 2 hr 9 min | 1 hr 4 min | 12 min 58s |

---

## Multiple SLOs Per Service

A service often has multiple SLOs. Common combinations:

1. **Availability SLO:** 99.9% of requests return non-5xx status
2. **Latency SLO:** 99% of requests complete within 500ms
3. **Correctness SLO:** 99.99% of data transformations produce correct output

Each SLO gets its own error budget and burn rate tracking. The dashboard shows all SLOs for a service side by side, with the worst-performing SLO highlighted.
