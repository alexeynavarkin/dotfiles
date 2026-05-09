# Grafana Dashboard JSON Model

## Core Dashboard Structure

```json
{
  "uid": "service-health-api",
  "title": "Service Health — API Gateway",
  "tags": ["team:platform", "service:api-gateway", "method:red"],
  "timezone": "browser",
  "schemaVersion": 39,
  "version": 1,
  "refresh": "30s",
  "time": { "from": "now-6h", "to": "now" },
  "fiscalYearStartMonth": 0,
  "editable": true,
  "graphTooltip": 1,
  "templating": { "list": [] },
  "annotations": { "list": [] },
  "panels": [],
  "links": []
}
```

**Key fields:**
- `uid`: Unique string identifier (8-40 chars, URL-safe). Set explicitly for stable URLs and provisioning idempotency.
- `graphTooltip`: `0` = per-panel, `1` = shared crosshair, `2` = shared tooltip. Use `1` for correlated panels.
- `tags`: Use for filtering in dashboard search. Include team, service, and method tags.
- `refresh`: Match to scrape interval. Common: `"30s"` for Prometheus with 15s scrape.

---

## Panel Structure

```json
{
  "id": 1,
  "type": "timeseries",
  "title": "Request Rate",
  "description": "Total HTTP requests per second by status code",
  "gridPos": { "x": 0, "y": 0, "w": 12, "h": 8 },
  "datasource": { "type": "prometheus", "uid": "${datasource}" },
  "targets": [
    {
      "refId": "A",
      "expr": "sum by (status) (rate(http_requests_total{job=\"$job\"}[$__rate_interval]))",
      "legendFormat": "{{status}}",
      "interval": "",
      "instant": false,
      "range": true
    }
  ],
  "fieldConfig": {
    "defaults": {
      "unit": "reqps",
      "color": { "mode": "palette-classic" },
      "custom": {
        "drawStyle": "line",
        "lineInterpolation": "smooth",
        "fillOpacity": 10,
        "showPoints": "never",
        "spanNulls": true
      },
      "thresholds": {
        "mode": "absolute",
        "steps": [
          { "color": "green", "value": null },
          { "color": "yellow", "value": 1000 },
          { "color": "red", "value": 5000 }
        ]
      }
    },
    "overrides": []
  },
  "options": {
    "legend": { "displayMode": "table", "placement": "bottom", "calcs": ["mean", "max", "last"] },
    "tooltip": { "mode": "multi", "sort": "desc" }
  }
}
```

---

## Grid Position System (gridPos)

The dashboard uses a **24-column grid**. Panels cannot overlap.

- `x`: Column position (0-23)
- `y`: Row position (0-based, grows downward)
- `w`: Width in columns (1-24)
- `h`: Height in grid units (each unit ~30 pixels)

**Standard layouts:**

```
# Two equal columns
Panel A: { x: 0, y: 0, w: 12, h: 8 }   Panel B: { x: 12, y: 0, w: 12, h: 8 }

# Three equal columns
Panel A: { x: 0, y: 0, w: 8, h: 8 }   Panel B: { x: 8, y: 0, w: 8, h: 8 }   Panel C: { x: 16, y: 0, w: 8, h: 8 }

# Four stat panels + two time series
Stat1: { x: 0, y: 0, w: 6, h: 4 }    Stat2: { x: 6, y: 0, w: 6, h: 4 }
Stat3: { x: 12, y: 0, w: 6, h: 4 }   Stat4: { x: 18, y: 0, w: 6, h: 4 }
TS1:   { x: 0, y: 4, w: 12, h: 8 }   TS2:   { x: 12, y: 4, w: 12, h: 8 }

# Full-width panel
Panel: { x: 0, y: 0, w: 24, h: 10 }
```

---

## Collapsible Row Panels

Group related panels with row panels:

```json
{
  "id": 100,
  "type": "row",
  "title": "HTTP Metrics",
  "collapsed": false,
  "gridPos": { "x": 0, "y": 12, "w": 24, "h": 1 },
  "panels": []
}
```

When `collapsed: true`, child panels (those with `y` values between this row and the next) are hidden until expanded.

---

## fieldConfig Common Units

| Category | Unit value | Display |
|---|---|---|
| Throughput | `reqps` | req/s |
| Throughput | `ops` | ops/s |
| Duration | `s` | seconds |
| Duration | `ms` | milliseconds |
| Duration | `us` | microseconds |
| Data rate | `Bps` | bytes/sec |
| Data size | `bytes` | bytes (auto-scaled to KB/MB/GB) |
| Data size | `decbytes` | bytes (decimal, SI) |
| Percentage | `percent` | 0-100% |
| Percentage | `percentunit` | 0.0-1.0 → displayed as % |
| Count | `short` | auto-scaled (K, M, B) |
| Boolean | `bool` | true/false |

---

## Thresholds

```json
"thresholds": {
  "mode": "absolute",
  "steps": [
    { "color": "green", "value": null },
    { "color": "#EAB839", "value": 0.01 },
    { "color": "red", "value": 0.05 }
  ]
}
```

- `mode`: `"absolute"` (fixed values) or `"percentage"` (relative to min/max)
- First step must have `"value": null` (base color)
- Steps are evaluated in order; last matching step wins

---

## Field Overrides

Target specific series for custom styling:

```json
"overrides": [
  {
    "matcher": { "id": "byName", "options": "5xx" },
    "properties": [
      { "id": "color", "value": { "fixedColor": "red", "mode": "fixed" } },
      { "id": "custom.fillOpacity", "value": 30 }
    ]
  }
]
```

**Matcher types:** `byName`, `byRegexp`, `byType`, `byFrameRefID`

---

## Template Variable Definition

```json
"templating": {
  "list": [
    {
      "name": "datasource",
      "type": "datasource",
      "query": "prometheus",
      "current": {},
      "hide": 0
    },
    {
      "name": "job",
      "type": "query",
      "datasource": { "type": "prometheus", "uid": "${datasource}" },
      "query": "label_values(up, job)",
      "refresh": 2,
      "sort": 1,
      "multi": false,
      "includeAll": false
    },
    {
      "name": "instance",
      "type": "query",
      "datasource": { "type": "prometheus", "uid": "${datasource}" },
      "query": "label_values(up{job=\"$job\"}, instance)",
      "refresh": 2,
      "sort": 1,
      "multi": true,
      "includeAll": true
    }
  ]
}
```

**`refresh` values:** `0` = never, `1` = on dashboard load, `2` = on time range change.
**`sort` values:** `0` = disabled, `1` = alphabetical (asc), `2` = alphabetical (desc), `3` = numerical (asc), `4` = numerical (desc).

---

## Annotations

```json
"annotations": {
  "list": [
    {
      "name": "Deployments",
      "datasource": { "type": "prometheus", "uid": "${datasource}" },
      "expr": "changes(process_start_time_seconds{job=\"$job\"}[2m]) > 0",
      "step": "60s",
      "tagKeys": "job",
      "titleFormat": "Deploy: {{job}}",
      "iconColor": "blue",
      "enable": true
    }
  ]
}
```

---

## Dashboard Links

```json
"links": [
  {
    "title": "Service Logs",
    "url": "/explore?orgId=1&left=%7B%22datasource%22:%22Loki%22,%22queries%22:%5B%7B%22expr%22:%22%7Bjob%3D%5C%22${job}%5C%22%7D%22%7D%5D%7D",
    "type": "link",
    "icon": "doc",
    "targetBlank": true
  },
  {
    "title": "Related Dashboards",
    "type": "dashboards",
    "tags": ["service:$job"]
  }
]
```

---

## Provisioning via YAML

File: `provisioning/dashboards/default.yaml`
```yaml
apiVersion: 1
providers:
  - name: 'default'
    orgId: 1
    folder: 'Services'
    folderUid: 'services'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: true
```

Place dashboard JSON files in `/var/lib/grafana/dashboards/`. Grafana auto-loads and updates them. If the JSON has a `uid`, existing dashboards with that UID are updated in place.

---

## Stat Panel Example

```json
{
  "type": "stat",
  "title": "Error Rate",
  "gridPos": { "x": 6, "y": 0, "w": 6, "h": 4 },
  "datasource": { "type": "prometheus", "uid": "${datasource}" },
  "targets": [{
    "refId": "A",
    "expr": "sum(rate(http_requests_total{job=\"$job\",status=~\"5..\"}[$__rate_interval])) / sum(rate(http_requests_total{job=\"$job\"}[$__rate_interval])) * 100",
    "instant": true
  }],
  "fieldConfig": {
    "defaults": {
      "unit": "percent",
      "thresholds": {
        "mode": "absolute",
        "steps": [
          { "color": "green", "value": null },
          { "color": "yellow", "value": 1 },
          { "color": "red", "value": 5 }
        ]
      },
      "mappings": []
    }
  },
  "options": {
    "reduceOptions": { "calcs": ["lastNotNull"] },
    "colorMode": "background",
    "graphMode": "area",
    "textMode": "auto",
    "orientation": "auto"
  }
}
```
