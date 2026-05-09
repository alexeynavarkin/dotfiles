# Observability Methods: RED, USE, and Golden Signals

## Method Selection Matrix

| Question | Use this method | Best for |
|---|---|---|
| "Is my service healthy for users?" | RED | APIs, microservices, HTTP/gRPC services |
| "Are my resources overloaded?" | USE | Servers, databases, load balancers, network devices |
| "What's the overall system health?" | Golden Signals | Executive dashboards, high-level overviews |
| "Are we meeting our reliability targets?" | SLI/SLO | Reliability engineering, error budgets |

---

## RED Method (Rate, Errors, Duration)

Created by Tom Wilkie. Measures the **user experience** of a service.

| Signal | What to measure | Example metric | Panel type |
|---|---|---|---|
| **Rate** | Requests per second | `sum(rate(http_requests_total[$__rate_interval]))` | Stat + Time series |
| **Errors** | Failed requests per second or error % | `sum(rate(http_requests_total{status=~"5.."}[$__rate_interval]))` | Stat (%) + Time series |
| **Duration** | Latency distribution (P50, P95, P99) | `histogram_quantile(0.99, sum by (le)(rate(http_request_duration_seconds_bucket[$__rate_interval])))` | Stat (P99) + Time series (overlay P50/P95/P99) |

**When to use RED:**
- Any service that receives requests (HTTP, gRPC, GraphQL, message consumers)
- Microservice architectures — apply RED to each service independently
- Building SLI metrics (error rate → availability SLI, duration → latency SLI)

**When NOT to use RED:**
- Batch processing jobs (no "request rate" concept)
- Infrastructure resources (use USE instead)
- Storage systems where throughput/IOPS matter more than latency

---

## USE Method (Utilization, Saturation, Errors)

Created by Brendan Gregg. Measures **resource health**.

| Signal | Definition | How to measure |
|---|---|---|
| **Utilization** | Average time the resource was busy (0-100%) | Gauge or rate over time |
| **Saturation** | Work the resource could not serve (queued/waiting) | Queue depth, wait time |
| **Errors** | Count of error events on the resource | Counter rate |

### USE for Common Resources

| Resource | Utilization | Saturation | Errors |
|---|---|---|---|
| **CPU** | `rate(node_cpu_seconds_total{mode!="idle"}[5m])` | `node_load1 / count(cpu cores)` | Machine check exceptions |
| **Memory** | `1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes` | `rate(node_vmstat_pgmajfault[5m])` (page faults) | `node_edac_correctable_errors_total` |
| **Disk I/O** | `rate(node_disk_io_time_seconds_total[5m])` | `rate(node_disk_io_time_weighted_seconds_total[5m])` (I/O wait) | `rate(node_disk_io_errors_total[5m])` |
| **Disk Space** | `1 - node_filesystem_avail_bytes / node_filesystem_size_bytes` | N/A (full = saturated) | Filesystem errors (dmesg) |
| **Network** | `rate(node_network_receive_bytes_total[5m]) / max_bandwidth` | `node_network_transmit_queue_length` | `rate(node_network_receive_errs_total[5m])` |
| **Database Connections** | `active_connections / max_connections` | Connection queue/wait time | Connection errors |

**When to use USE:**
- Physical/virtual servers, containers, databases
- Infrastructure capacity planning
- Identifying bottleneck resources during incidents

---

## Four Golden Signals (Google SRE)

From Google's SRE book. Measures **overall system health**.

| Signal | What it measures | RED equivalent | USE equivalent |
|---|---|---|---|
| **Latency** | Time to serve a request (successful vs failed) | Duration | — |
| **Traffic** | Demand on the system (req/s, I/O, sessions) | Rate | Utilization |
| **Errors** | Rate of failed requests (explicit + implicit) | Errors | Errors |
| **Saturation** | How "full" the system is (utilization + queuing) | — | Saturation |

**Key insight:** Golden Signals bridge RED and USE. For service-centric monitoring, they overlap with RED. For resource monitoring, they overlap with USE. Use Golden Signals when you want a single dashboard covering both perspectives.

---

## Combined Dashboard Strategy

For a complete observability setup, layer the methods:

```
Level 1: Golden Signals Overview Dashboard
  ├── Service health (RED per service)
  ├── Infrastructure health (USE per resource)
  └── Key business metrics

Level 2: Service Detail Dashboards (RED)
  ├── Per-service RED metrics
  ├── Dependency health
  └── Endpoint-level breakdown

Level 3: Infrastructure Detail Dashboards (USE)
  ├── Per-host resource metrics
  ├── Capacity trends
  └── Saturation alerts
```

---

## Prometheus Metric Naming Conventions

### Format

`<namespace>_<name>_<unit>_<suffix>`

| Part | Rule | Example |
|---|---|---|
| Namespace | Application or library name | `http`, `process`, `node` |
| Name | Descriptive, snake_case | `request_duration`, `cpu_seconds`, `memory_available` |
| Unit | Always base units, plural | `_seconds`, `_bytes`, `_meters` (NOT ms, KB, GB) |
| Suffix | Metric type indicator | `_total` (counter), `_bucket` (histogram), `_info` (info) |

### Examples

```
# Good
http_request_duration_seconds_bucket    # histogram, seconds
http_requests_total                     # counter, total requests
process_resident_memory_bytes           # gauge, bytes
node_cpu_seconds_total                  # counter, seconds

# Bad
http_request_duration_ms                # use seconds, not ms
httpRequestCount                        # use snake_case
requests                               # too vague, no namespace
http_request_duration_seconds_by_method # labels go in labels, not names
```

### Type Suffixes

| Metric type | Suffix | Example |
|---|---|---|
| Counter | `_total` | `http_requests_total` |
| Histogram | `_bucket`, `_sum`, `_count` | `http_request_duration_seconds_bucket` |
| Summary | `_sum`, `_count` + quantile label | `rpc_duration_seconds{quantile="0.99"}` |
| Gauge | (none required) | `node_memory_MemAvailable_bytes` |
| Info | `_info` | `build_info{version="1.2.3"}` |

---

## Label Best Practices

### Do

- Use labels for dimensions you filter/aggregate by: `method`, `status`, `handler`, `instance`, `job`
- Keep label values bounded (10-100 distinct values per label)
- Use consistent label names across services: `job`, `instance`, `namespace`, `cluster`
- Instrument at the client library level for consistent labeling

### Don't

- Never use high-cardinality values: user IDs, email addresses, UUIDs, trace IDs, timestamps
- Never use `__` prefix (reserved for internal Prometheus use)
- Never encode label values in metric names: `api_create_requests_total` → use `api_requests_total{operation="create"}`
- Never add a label you won't query by — it multiplies series count for no benefit

### Cardinality Rule of Thumb

```
Total series = unique_metric_names × product(distinct_values_per_label)
```

Example: `http_requests_total` with labels `method` (4 values) × `status` (5 values) × `handler` (20 endpoints) × `instance` (10 pods) = 4,000 series per metric. Adding `user_id` (100k users) → 400 million series. This crashes Prometheus.

---

## Choosing Metrics for Each Dashboard Type

### Service Health (RED)

Must-have metrics:
1. `http_requests_total` (counter) — labels: `method`, `status`, `handler`
2. `http_request_duration_seconds` (histogram) — labels: `method`, `handler`
3. `http_requests_in_flight` (gauge) — current concurrent requests

Nice-to-have:
4. `http_request_size_bytes` (histogram) — request payload sizes
5. `http_response_size_bytes` (histogram) — response payload sizes

### Infrastructure (USE)

Must-have (per node):
1. `node_cpu_seconds_total` — CPU utilization
2. `node_memory_MemAvailable_bytes`, `node_memory_MemTotal_bytes` — memory
3. `node_filesystem_avail_bytes`, `node_filesystem_size_bytes` — disk
4. `node_network_receive_bytes_total`, `node_network_transmit_bytes_total` — network

### Kubernetes

Must-have:
1. `container_cpu_usage_seconds_total` — container CPU
2. `container_memory_usage_bytes` — container memory
3. `kube_pod_status_phase` — pod lifecycle
4. `kube_pod_container_status_restarts_total` — restart counts
5. `kube_deployment_status_replicas` — deployment health
