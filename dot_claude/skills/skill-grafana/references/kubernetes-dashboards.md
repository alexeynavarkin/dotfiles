# Kubernetes Dashboard Patterns

## Dashboard Hierarchy

Design Kubernetes dashboards as a drilldown hierarchy:

```
Cluster Overview
  → Namespace Detail
    → Workload Detail (Deployment/StatefulSet/DaemonSet)
      → Pod Detail
        → Container Detail
```

Each level links to the next via template variables and dashboard links.

---

## Essential Variables

```json
[
  { "name": "datasource", "type": "datasource", "query": "prometheus" },
  { "name": "cluster", "type": "query", "query": "label_values(up, cluster)" },
  { "name": "namespace", "type": "query", "query": "label_values(kube_pod_info{cluster=\"$cluster\"}, namespace)", "multi": true, "includeAll": true },
  { "name": "workload", "type": "query", "query": "label_values(kube_deployment_labels{cluster=\"$cluster\", namespace=~\"$namespace\"}, deployment)", "multi": true, "includeAll": true },
  { "name": "pod", "type": "query", "query": "label_values(kube_pod_info{cluster=\"$cluster\", namespace=~\"$namespace\"}, pod)", "multi": true, "includeAll": true }
]
```

---

## Cluster Overview Dashboard

### Row 1 — Cluster Health (Stat panels)

```promql
# Total nodes
count(kube_node_info{cluster="$cluster"})

# Ready nodes
count(kube_node_status_condition{cluster="$cluster", condition="Ready", status="true"})

# Total pods
count(kube_pod_info{cluster="$cluster"})

# Running pods
count(kube_pod_status_phase{cluster="$cluster", phase="Running"})

# Failed pods
count(kube_pod_status_phase{cluster="$cluster", phase="Failed"})

# Cluster CPU utilization
sum(rate(container_cpu_usage_seconds_total{cluster="$cluster", container!=""}[$__rate_interval]))
/ sum(kube_node_status_allocatable{cluster="$cluster", resource="cpu"})
```

### Row 2 — Resource Utilization (Time series)

```promql
# CPU usage vs allocatable by node
sum by (node) (rate(container_cpu_usage_seconds_total{cluster="$cluster", container!=""}[$__rate_interval]))
# Overlay: sum by (node) (kube_node_status_allocatable{cluster="$cluster", resource="cpu"})

# Memory usage vs allocatable by node
sum by (node) (container_memory_usage_bytes{cluster="$cluster", container!=""})
# Overlay: sum by (node) (kube_node_status_allocatable{cluster="$cluster", resource="memory"})
```

### Row 3 — Pod Status (Table or Bar chart)

```promql
# Pod count by phase
count by (phase) (kube_pod_status_phase{cluster="$cluster"})

# Pods with restarts (last 24h)
topk(20, sum by (namespace, pod) (increase(kube_pod_container_status_restarts_total{cluster="$cluster"}[24h])) > 0)
```

---

## Namespace Detail Dashboard

### Row 1 — Namespace KPIs

```promql
# Pod count in namespace
count(kube_pod_info{cluster="$cluster", namespace=~"$namespace"})

# CPU usage (namespace total)
sum(rate(container_cpu_usage_seconds_total{cluster="$cluster", namespace=~"$namespace", container!=""}[$__rate_interval]))

# Memory usage (namespace total)
sum(container_memory_usage_bytes{cluster="$cluster", namespace=~"$namespace", container!=""})

# CPU request utilization (actual / requested)
sum(rate(container_cpu_usage_seconds_total{cluster="$cluster", namespace=~"$namespace", container!=""}[$__rate_interval]))
/ sum(kube_pod_container_resource_requests{cluster="$cluster", namespace=~"$namespace", resource="cpu"})
```

### Row 2 — Resource Usage by Workload

```promql
# CPU by deployment
sum by (deployment) (
  label_replace(
    rate(container_cpu_usage_seconds_total{cluster="$cluster", namespace=~"$namespace", container!=""}[$__rate_interval]),
    "deployment", "$1", "pod", "(.*)-[a-z0-9]+-[a-z0-9]+"
  )
)

# Memory by deployment
sum by (deployment) (
  label_replace(
    container_memory_usage_bytes{cluster="$cluster", namespace=~"$namespace", container!=""},
    "deployment", "$1", "pod", "(.*)-[a-z0-9]+-[a-z0-9]+"
  )
)
```

### Row 3 — Network

```promql
# Network receive by pod
sum by (pod) (rate(container_network_receive_bytes_total{cluster="$cluster", namespace=~"$namespace"}[$__rate_interval]))

# Network transmit by pod
sum by (pod) (rate(container_network_transmit_bytes_total{cluster="$cluster", namespace=~"$namespace"}[$__rate_interval]))
```

---

## Pod Detail Dashboard

### Row 1 — Pod Status

```promql
# Pod phase (use value mapping: 1=Pending/yellow, 2=Running/green, 3=Succeeded/blue, 4=Failed/red, 5=Unknown/grey)
max(kube_pod_status_phase{cluster="$cluster", namespace="$namespace", pod="$pod"}) by (phase)

# Container restarts
sum(kube_pod_container_status_restarts_total{cluster="$cluster", namespace="$namespace", pod="$pod"})

# Pod age
time() - max(kube_pod_start_time{cluster="$cluster", namespace="$namespace", pod="$pod"})
```

### Row 2 — Resource Usage vs Requests/Limits

```promql
# CPU: usage, requests, limits on one panel
# Usage:
sum(rate(container_cpu_usage_seconds_total{cluster="$cluster", namespace="$namespace", pod="$pod", container!=""}[$__rate_interval]))
# Requests (threshold line):
sum(kube_pod_container_resource_requests{cluster="$cluster", namespace="$namespace", pod="$pod", resource="cpu"})
# Limits (threshold line):
sum(kube_pod_container_resource_limits{cluster="$cluster", namespace="$namespace", pod="$pod", resource="cpu"})

# Memory: usage, requests, limits on one panel
# Usage:
sum(container_memory_usage_bytes{cluster="$cluster", namespace="$namespace", pod="$pod", container!=""})
# Requests:
sum(kube_pod_container_resource_requests{cluster="$cluster", namespace="$namespace", pod="$pod", resource="memory"})
# Limits:
sum(kube_pod_container_resource_limits{cluster="$cluster", namespace="$namespace", pod="$pod", resource="memory"})
```

### Row 3 — Container Logs

```logql
{cluster="$cluster", namespace="$namespace", pod="$pod"}
```

---

## Key Metrics Reference

### From kube-state-metrics

| Metric | Type | Description |
|---|---|---|
| `kube_pod_info` | Gauge | Pod metadata (node, IP, labels) |
| `kube_pod_status_phase` | Gauge | Pod lifecycle phase |
| `kube_pod_container_status_restarts_total` | Counter | Container restart count |
| `kube_pod_container_resource_requests` | Gauge | CPU/memory requests |
| `kube_pod_container_resource_limits` | Gauge | CPU/memory limits |
| `kube_deployment_status_replicas` | Gauge | Current replica count |
| `kube_deployment_spec_replicas` | Gauge | Desired replica count |
| `kube_node_info` | Gauge | Node metadata |
| `kube_node_status_condition` | Gauge | Node conditions (Ready, Pressure) |
| `kube_node_status_allocatable` | Gauge | Allocatable resources per node |
| `kube_hpa_status_current_replicas` | Gauge | HPA current replicas |
| `kube_hpa_spec_max_replicas` | Gauge | HPA max replicas |

### From cAdvisor (kubelet)

| Metric | Type | Description |
|---|---|---|
| `container_cpu_usage_seconds_total` | Counter | CPU time consumed |
| `container_memory_usage_bytes` | Gauge | Current memory usage |
| `container_memory_working_set_bytes` | Gauge | Memory working set (closer to OOM threshold) |
| `container_network_receive_bytes_total` | Counter | Network bytes received |
| `container_network_transmit_bytes_total` | Counter | Network bytes transmitted |
| `container_fs_reads_bytes_total` | Counter | Filesystem bytes read |
| `container_fs_writes_bytes_total` | Counter | Filesystem bytes written |

**Important:** Always filter with `container!=""` to exclude the pod-level cgroup aggregation (the "pause" container).

---

## Alert Rules for Kubernetes

```promql
# Pod crash looping (more than 3 restarts in 1 hour)
increase(kube_pod_container_status_restarts_total{namespace=~"$namespace"}[1h]) > 3

# Pod stuck in pending
kube_pod_status_phase{phase="Pending"} == 1
# with: for: 15m

# Deployment replicas mismatch
kube_deployment_spec_replicas != kube_deployment_status_available_replicas
# with: for: 10m

# Node not ready
kube_node_status_condition{condition="Ready", status="true"} == 0
# with: for: 5m

# CPU throttling (container hitting CPU limits)
sum by (namespace, pod, container) (
  rate(container_cpu_cfs_throttled_periods_total[$__rate_interval])
  / rate(container_cpu_cfs_periods_total[$__rate_interval])
) > 0.25
# with: for: 10m

# Memory near limit (>90% of limit)
sum by (namespace, pod, container) (container_memory_working_set_bytes)
/ sum by (namespace, pod, container) (kube_pod_container_resource_limits{resource="memory"})
> 0.9
# with: for: 5m

# PersistentVolume almost full
kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes > 0.85
# with: for: 15m
```

---

## Resource Right-Sizing Queries

Identify over-provisioned or under-provisioned workloads:

```promql
# CPU over-provisioned (usage < 20% of request for 7 days)
avg_over_time(
  (sum by (namespace, pod) (rate(container_cpu_usage_seconds_total{container!=""}[5m]))
   / sum by (namespace, pod) (kube_pod_container_resource_requests{resource="cpu"})
  )[7d:1h]
) < 0.2

# Memory over-provisioned
avg_over_time(
  (sum by (namespace, pod) (container_memory_working_set_bytes{container!=""})
   / sum by (namespace, pod) (kube_pod_container_resource_requests{resource="memory"})
  )[7d:1h]
) < 0.3

# CPU under-provisioned (P99 usage > 80% of request)
quantile_over_time(0.99,
  (sum by (namespace, pod) (rate(container_cpu_usage_seconds_total{container!=""}[5m]))
   / sum by (namespace, pod) (kube_pod_container_resource_requests{resource="cpu"})
  )[7d:1h]
) > 0.8
```

Display results in a table panel sorted by waste (request - usage) for prioritizing right-sizing efforts.

---

## Dashboard Links for Drilldown

Add links that pass current variable selections to the next dashboard level:

```json
"links": [
  {
    "title": "Namespace Detail",
    "url": "/d/namespace-detail?var-cluster=$cluster&var-namespace=${__data.fields.namespace}",
    "type": "link",
    "targetBlank": false
  }
]
```

Use data link on table panels to enable click-through from a row to the detail dashboard.
