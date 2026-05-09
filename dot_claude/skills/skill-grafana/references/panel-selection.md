# Panel Type Selection Guide

## Decision Matrix

| You want to show... | Panel type | Configuration highlights |
|---|---|---|
| A single current value (KPI) | **Stat** | `reduceOptions.calcs: ["lastNotNull"]`, `colorMode: "background"` |
| Metric trend over time | **Time Series** | `drawStyle: "line"`, `fillOpacity: 10`, `legend.displayMode: "table"` |
| Value relative to a threshold | **Gauge** | `thresholds` with green/yellow/red steps |
| Distribution over time | **Heatmap** | Format: "Time series buckets", `maxDataPoints: 25` |
| Tabular data or top-N lists | **Table** | Use `Transform: Organize fields` to reorder/rename columns |
| Log stream | **Logs** | Loki datasource, `dedupStrategy: "exact"` |
| Categorical breakdown | **Bar Chart** | `orientation: "horizontal"` for readability |
| Proportional comparison | **Pie Chart** | Use sparingly — bar charts are usually clearer |
| Binary status (up/down) | **Stat** with value mappings | Map `1 → "UP" (green)`, `0 → "DOWN" (red)` |
| Geographic data | **Geomap** | Requires latitude/longitude fields |
| Annotations / context | **Text** | Markdown support for runbook links and descriptions |

---

## Time Series Panel

The workhorse of Grafana dashboards. Use for any metric that changes over time.

```json
{
  "type": "timeseries",
  "fieldConfig": {
    "defaults": {
      "custom": {
        "drawStyle": "line",
        "lineInterpolation": "smooth",
        "fillOpacity": 10,
        "showPoints": "never",
        "spanNulls": true,
        "lineWidth": 2,
        "stacking": { "mode": "none" }
      }
    }
  },
  "options": {
    "legend": {
      "displayMode": "table",
      "placement": "bottom",
      "calcs": ["mean", "max", "lastNotNull"]
    },
    "tooltip": { "mode": "multi", "sort": "desc" }
  }
}
```

**Best practices:**
- Use `legend.displayMode: "table"` with calcs for data-dense dashboards
- Use `stacking.mode: "normal"` for composition views (e.g., requests by status code)
- Set `spanNulls: true` to connect across gaps from missing scrapes
- Use `drawStyle: "bars"` for discrete event counts
- Keep 3-7 series per panel; more than 10 becomes unreadable
- Use `tooltip.mode: "multi"` to compare all series at a timestamp

### When to Use Area vs Line vs Bars

| Style | Use when |
|---|---|
| Line (`fillOpacity: 0`) | Comparing multiple series values |
| Area (`fillOpacity: 10-30`) | Showing volume/magnitude, stacked compositions |
| Bars (`drawStyle: "bars"`) | Discrete counts per interval (errors per minute) |
| Points (`drawStyle: "points"`) | Sparse data, individual events |

---

## Stat Panel

Display a single prominent value with optional sparkline.

```json
{
  "type": "stat",
  "options": {
    "reduceOptions": { "calcs": ["lastNotNull"] },
    "colorMode": "background",
    "graphMode": "area",
    "textMode": "auto",
    "orientation": "auto"
  },
  "fieldConfig": {
    "defaults": {
      "thresholds": {
        "steps": [
          { "color": "green", "value": null },
          { "color": "yellow", "value": 80 },
          { "color": "red", "value": 95 }
        ]
      }
    }
  }
}
```

**Best practices:**
- Use `colorMode: "background"` for at-a-glance status (the panel background changes color)
- Use `graphMode: "area"` to show trend sparkline below the value
- Use `instant: true` on the query for current value (avoids unnecessary range data)
- Common calcs: `lastNotNull`, `mean`, `max`, `sum`
- Place 4-6 stat panels in the first row as KPI summary

### Value Mappings

Map numeric values to meaningful text:

```json
"mappings": [
  { "type": "value", "options": { "0": { "text": "DOWN", "color": "red" }, "1": { "text": "UP", "color": "green" } } },
  { "type": "range", "options": { "from": 0, "to": 0.5, "result": { "text": "SLOW", "color": "yellow" } } }
]
```

---

## Gauge Panel

Show a value relative to min/max with threshold coloring.

```json
{
  "type": "gauge",
  "options": {
    "reduceOptions": { "calcs": ["lastNotNull"] },
    "showThresholdLabels": false,
    "showThresholdMarkers": true,
    "orientation": "auto"
  },
  "fieldConfig": {
    "defaults": {
      "min": 0,
      "max": 100,
      "unit": "percent",
      "thresholds": {
        "steps": [
          { "color": "green", "value": null },
          { "color": "yellow", "value": 70 },
          { "color": "red", "value": 90 }
        ]
      }
    }
  }
}
```

**Best practices:**
- Always set `min` and `max` — without them the gauge is misleading
- Use for bounded metrics: CPU %, memory %, disk %, error budget remaining
- Don't use for unbounded metrics (request rate, latency) — use stat instead
- Good for quick visual status, but stat panels are usually more space-efficient

---

## Heatmap Panel

Visualize distributions over time. Essential for histogram metrics.

```json
{
  "type": "heatmap",
  "options": {
    "calculate": false,
    "color": {
      "scheme": "Oranges",
      "mode": "scheme"
    },
    "yAxis": { "unit": "s" },
    "cellGap": 1,
    "showValue": "never"
  }
}
```

**Query setup:**
```promql
# For Prometheus histograms — use with format "Time series buckets"
sum(increase(http_request_duration_seconds_bucket{job="$job"}[$__interval])) by (le)
```

**Best practices:**
- Set `maxDataPoints: 25` — heatmaps are information-dense, more points add noise
- Use "Time series buckets" format when querying `_bucket` metrics
- Use `calculate: true` when your data isn't pre-bucketed
- Color scheme: use sequential (Oranges, Blues) for magnitude, diverging for deviation
- Heatmaps excel at showing latency distribution shifts (e.g., bimodal latency after a deploy)

---

## Table Panel

Display detailed, structured data.

**Best practices:**
- Use transforms to clean up columns: `Organize fields` to rename, reorder, hide
- Sort by the most important column by default
- Use cell color based on thresholds for visual scanning
- Common use cases: top-N lists, instance inventory, alert summaries
- Combine with `topk()` or `bottomk()` queries to show ranked data

**Useful transforms:**
- `Organize fields` — rename and reorder columns
- `Filter by value` — hide rows below threshold
- `Sort by` — default sort order
- `Group by` — aggregate rows

---

## Logs Panel

Display log streams from Loki or other log sources.

```json
{
  "type": "logs",
  "options": {
    "showTime": true,
    "showLabels": false,
    "showCommonLabels": false,
    "wrapLogMessage": true,
    "prettifyLogMessage": false,
    "enableLogDetails": true,
    "dedupStrategy": "none",
    "sortOrder": "Descending"
  }
}
```

**Best practices:**
- Filter aggressively — show only relevant logs (errors, specific services)
- Use `{job="$job"} |= "error"` as baseline, not `{job="$job"}` (too noisy)
- Enable `enableLogDetails: true` for expandable structured metadata
- Place logs panels at the bottom of dashboards (they're scroll-heavy)
- Set panel height to 10-12 units for comfortable reading

---

## Text Panel

Add context, documentation, and links.

```json
{
  "type": "text",
  "options": {
    "mode": "markdown",
    "content": "## Service Health Dashboard\n\nThis dashboard monitors the API Gateway using the RED method.\n\n**Runbook:** [link](https://wiki.example.com/runbooks/api-gateway)\n\n**Oncall:** [PagerDuty](https://pagerduty.com/schedules/api-team)"
  }
}
```

**Use text panels for:**
- Dashboard description and purpose
- Links to runbooks, wikis, and related dashboards
- Team ownership and contact information
- Explanation of unusual metrics or thresholds

---

## Bar Chart Panel

Compare values across categories.

**Best practices:**
- Use horizontal orientation for readability (especially with long label names)
- Sort by value descending for quick scanning
- Limit to 10-20 bars maximum
- Use for: top endpoints by latency, error count by service, resource usage by namespace

---

## Panel Layout Combinations

### Service Health (RED)

```
Row 0 (y=0):  [Stat: Rate w=6] [Stat: Errors w=6] [Stat: P99 w=6] [Stat: Active w=6]
Row 1 (y=4):  [TimeSeries: Rate by status w=12] [TimeSeries: Latency percentiles w=12]
Row 2 (y=12): [TimeSeries: Error rate w=12] [Heatmap: Latency distribution w=12]
Row 3 (y=20): [Table: Top endpoints by latency w=24]
Row 4 (y=30): [Logs: Error logs w=24]
```

### Infrastructure (USE)

```
Row 0 (y=0):  [Gauge: CPU% w=6] [Gauge: Mem% w=6] [Gauge: Disk% w=6] [Gauge: Net% w=6]
Row 1 (y=4):  [TimeSeries: CPU utilization w=12] [TimeSeries: Memory usage w=12]
Row 2 (y=12): [TimeSeries: Disk I/O w=12] [TimeSeries: Network I/O w=12]
Row 3 (y=20): [Table: Top processes by CPU w=12] [Table: Top processes by memory w=12]
```

### SLO Dashboard

```
Row 0 (y=0):  [Stat: SLI w=6] [Stat: SLO w=6] [Gauge: Budget w=6] [Stat: Time to exhaust w=6]
Row 1 (y=4):  [TimeSeries: SLI trend w=12] [TimeSeries: Burn rate w=12]
Row 2 (y=12): [TimeSeries: Error budget burndown w=24]
Row 3 (y=20): [Table: Top error sources w=12] [TimeSeries: Error rate by endpoint w=12]
```
