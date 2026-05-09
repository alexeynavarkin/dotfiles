# Capacity Planning

## Back-of-Envelope Estimation Framework

Work through these in order: **Traffic → Storage → Bandwidth → Compute**.

### Step 1: Traffic Estimation

```
Daily Active Users (DAU) → QPS

QPS = DAU × actions_per_user_per_day / 86400
Peak QPS = QPS × peak_multiplier (typically 2-5x average)

Example: 100M DAU, 10 actions/day
  Average QPS = 100M × 10 / 86400 ≈ 11,574 QPS
  Peak QPS = 11,574 × 3 ≈ 34,722 QPS
```

Split into read vs write QPS. Most systems are read-heavy (10:1 to 100:1 ratio).

### Step 2: Storage Estimation

```
Storage = rows × avg_row_size × replication_factor × retention_period

Example: 100M new records/day, 1KB each, 3x replication, 5 years
  Daily: 100M × 1KB = 100GB/day
  5 years: 100GB × 365 × 5 = 182.5TB
  With replication: 182.5TB × 3 = 547.5TB
```

### Step 3: Bandwidth Estimation

```
Ingress = write_QPS × avg_request_size
Egress = read_QPS × avg_response_size

Example: 12K write QPS × 1KB = 12MB/s ingress
         100K read QPS × 5KB = 500MB/s egress
```

### Step 4: Compute Estimation

```
CPU cores = QPS × cpu_seconds_per_request
Memory = concurrent_connections × memory_per_connection + cache_size

Example: 35K QPS × 0.01 CPU-sec/req = 350 cores
         50K concurrent × 256KB/conn = 12.8GB base memory
```

---

## Little's Law

**Formula:** `L = λ × W`

| Symbol | Meaning | Example |
|---|---|---|
| L | Mean number of items in system (concurrency) | 50 concurrent requests |
| λ | Mean arrival rate | 100 requests/second |
| W | Mean time each item spends in system | 500ms |

**Applications:**

| Sizing problem | Formula |
|---|---|
| Connection pool size | pool = QPS × avg_query_latency_seconds |
| Thread pool size | threads = QPS × avg_processing_time_seconds |
| Queue depth | depth = arrival_rate × avg_wait_time |

**Example:** API at 200 QPS, average DB query takes 50ms:
```
connections = 200 × 0.050 = 10 connections needed
```

Add 20-30% headroom for variance. If variance is high (P99 >> P50), size for P99 not average.

---

## Amdahl's Law

**Formula:** `Speedup = 1 / (s + (1-s)/p)`

| Symbol | Meaning |
|---|---|
| s | Serial fraction (non-parallelizable) |
| p | Number of parallel processors/instances |

**Key insight:** Maximum speedup is bounded by `1/s` regardless of how many instances you add.

| Serial fraction | Max speedup (infinite instances) |
|---|---|
| 1% | 100x |
| 5% | 20x |
| 10% | 10x |
| 25% | 4x |
| 50% | 2x |

**Practical meaning:** If 10% of your request handling is serialized (single-threaded lock, single-leader write, global counter), you cannot scale beyond 10x no matter how many servers you add.

**Common serial bottlenecks:**
- Single-leader database writes
- Global sequence generators (auto-increment IDs)
- Distributed locks
- Consensus protocols (leader bottleneck)

---

## Universal Scalability Law (USL)

**Formula:** `X(N) = γN / (1 + α(N-1) + βN(N-1))`

| Parameter | Meaning | Typical range |
|---|---|---|
| γ | Single-node throughput | Measured baseline |
| α | Contention coefficient (queuing for shared resources) | 0.001 - 0.1 |
| β | Coherency coefficient (data consistency overhead) | Much smaller than α |
| N | Number of nodes/instances | Variable |

**What it tells you:**
- When **α dominates**: bottleneck is contention (locks, single resource). Fix: reduce shared state.
- When **β dominates**: bottleneck is coherency (cache invalidation, distributed consensus). Fix: relax consistency or partition data.
- **Maximum useful nodes:** `Nmax = √((1-α)/β)` — adding beyond this actually decreases throughput (retrograde).

**Practical use:** Run load tests at N=1, 2, 4, 8 instances. Fit α and β. Predict where throughput peaks.

---

## Queue Theory Essentials

### M/M/1 Queue (single server)

**Utilization:** `ρ = λ/μ` (arrival rate / service rate)

**Mean queue length:** `Lq = ρ² / (1-ρ)`

**Mean wait time:** `Wq = ρ / (μ(1-ρ))`

### The Utilization-Latency Curve

| Utilization (ρ) | Relative latency | Practical meaning |
|---|---|---|
| 30% | 1.4x baseline | Comfortable |
| 50% | 2x baseline | Healthy |
| 70% | 3.3x baseline | Starting to feel pressure |
| 80% | 5x baseline | Noticeable latency increase |
| 90% | 10x baseline | Serious degradation |
| 95% | 20x baseline | Near collapse |
| 99% | 100x baseline | System effectively down |

**Rule of thumb:** Keep sustained utilization below 70-80%. Latency explodes non-linearly beyond this.

**Why this matters for capacity planning:** If your service runs at 80% CPU under normal load, a 25% traffic spike pushes you to near-100% and latency explodes. Design for headroom.

### Variability Amplifies Everything

Service time variability (coefficient of variation, CV) dramatically amplifies queue effects:

```
Wq ≈ (ρ / (1-ρ)) × ((CV² + 1) / 2)
```

High CV (inconsistent response times) makes utilization-latency curve much steeper. This is why P99 optimization matters — high variance in response time makes the whole system worse.

---

## Common Reference Numbers

Use these as starting points for estimation. Actual numbers depend heavily on workload, hardware, and configuration.

### Throughput Benchmarks

| Component | Approximate throughput | Notes |
|---|---|---|
| Single CPU core, simple HTTP handler | 1,000 - 10,000 req/s | Depends on language, payload |
| PostgreSQL, single node | 5,000 - 20,000 simple TPS | OLTP, indexed queries |
| MySQL, single node | 5,000 - 20,000 simple TPS | Similar to PostgreSQL |
| Redis, single node | 100,000 - 200,000 ops/s | In-memory, simple commands |
| Kafka, single partition | 10,000 - 100,000 msg/s | Depends on message size |
| Kafka, single broker | 200,000 - 2,000,000 msg/s | Multiple partitions |
| Memcached, single node | 200,000 - 500,000 ops/s | In-memory, simple get/set |
| Elasticsearch, single node | 5,000 - 20,000 index ops/s | Depends on mapping |
| Cassandra, single node | 10,000 - 50,000 ops/s | Depends on consistency level |

### Latency Benchmarks

| Operation | Approximate latency |
|---|---|
| L1 cache reference | 1 ns |
| L2 cache reference | 4 ns |
| Main memory reference | 100 ns |
| SSD random read | 100 μs |
| HDD random read | 10 ms |
| Network roundtrip (same DC) | 0.5 ms |
| Network roundtrip (cross-region, same continent) | 10-50 ms |
| Network roundtrip (cross-ocean) | 100-200 ms |
| Redis GET | 0.1-0.5 ms |
| PostgreSQL simple query | 0.5-5 ms |
| Kafka produce + ack | 2-10 ms |

### Storage Benchmarks

| Medium | Capacity | Sequential read | Random read IOPS |
|---|---|---|---|
| HDD | 1-20 TB | 100-200 MB/s | 100-200 IOPS |
| SSD (SATA) | 0.5-4 TB | 500-600 MB/s | 10,000-100,000 IOPS |
| NVMe SSD | 1-8 TB | 3-7 GB/s | 100,000-1,000,000 IOPS |

---

## Growth Planning

**Design for 10x current load.** Have a documented plan for 100x.

### The 10x Plan

For each component, answer: "What changes when load increases 10x?"

| Component | Likely 10x response |
|---|---|
| Stateless API servers | Add more instances (horizontal scaling) |
| Single-leader database | Read replicas for reads; evaluate sharding for writes |
| Cache (Redis) | Redis Cluster or add replicas |
| Message queue | Add partitions, add consumers |
| Object storage | Usually scales automatically (S3, GCS) |
| Search index | Add shards and replicas |

### The 100x Plan

At 100x, architectural changes are usually required:
- **Database sharding** becomes unavoidable for write-heavy workloads
- **Multi-region deployment** for latency and availability
- **Dedicated services** for hot paths (break monolith along load boundaries)
- **Caching layers** become critical (multi-tier caching)
- **Async processing** replaces synchronous where possible

### Warning Signs You Need to Scale

| Signal | What it means |
|---|---|
| P99 latency creeping up over weeks | Approaching capacity limits |
| Database CPU consistently >60% | Need read replicas or query optimization |
| Queue depth growing faster than draining | Consumer capacity insufficient |
| Connection pool wait time >10ms | Pool too small or queries too slow |
| Memory utilization >80% sustained | Risk of OOM under spike |
| Error rate increasing under load | Resource exhaustion or timeout cascades |
