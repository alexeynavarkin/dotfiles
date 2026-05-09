# Scalability Patterns

## Vertical vs Horizontal Scaling

### When Vertical Scaling Is Still the Right Answer

- Single PostgreSQL instance handles 10K-20K TPS easily
- Single Redis node handles 100K-200K ops/s
- Team is small (<5 engineers) and operational complexity is a concern
- Data fits on one machine (< ~1TB for most databases)
- Latency requirements are met by a single node

**Rule of thumb:** Don't distribute until a single node cannot meet requirements at 3-5x current load. Vertical scaling is simpler, cheaper, and has no distributed systems overhead.

### When to Go Horizontal

- Write throughput exceeds single-node capacity
- Data volume exceeds single-node storage/memory
- Availability requirements demand redundancy across failure domains
- Latency requirements demand geographic distribution
- Independent scaling of different components needed

---

## Sharding Strategies

### Hash-Based Sharding

```
shard_id = hash(key) % num_shards
```

| Pros | Cons |
|---|---|
| Even data distribution | Adding/removing shards requires rehashing |
| Simple to implement | Range queries span all shards |
| No hotspot if hash distributes well | Hash function determines distribution quality |

**Consistent Hashing:** Maps both nodes and keys to a ring. Key routes to nearest node clockwise.

```
Ring: 0 ──── Node_A(90) ──── Node_B(210) ──── Node_C(330) ──── 0
Key hash=150 → routes to Node_B (nearest clockwise)
```

- Adding a node only redistributes keys from adjacent nodes, not entire dataset
- Virtual nodes: each physical node maps to multiple ring positions for better distribution
- Used by: DynamoDB, Cassandra, consistent hash load balancers

### Range-Based Sharding

```
Shard 1: user_id 1 - 1,000,000
Shard 2: user_id 1,000,001 - 2,000,000
Shard 3: user_id 2,000,001 - 3,000,000
```

| Pros | Cons |
|---|---|
| Range queries efficient (within one shard) | Uneven distribution (hotspots) |
| Simple to understand | Popular ranges overload one shard |
| Good for time-series (partition by date) | Rebalancing requires data migration |

### Directory-Based Sharding

A lookup service maps each key to its shard location.

| Pros | Cons |
|---|---|
| Maximum flexibility (any mapping) | Lookup adds latency to every query |
| Easy rebalancing (update directory) | Directory is a SPoF (must be replicated) |
| No data movement for resharding | Directory must be highly available |

### Resharding

When you need to add or remove shards:

1. **Consistent hashing:** Minimal data movement. Add virtual nodes for new shard.
2. **Double-write period:** Write to both old and new shard assignments during migration.
3. **Background migration:** Copy data from old shard to new, then switch routing.
4. **Key range splitting:** Split the busiest shard into two at a midpoint.

---

## Load Balancing

### Layer 4 vs Layer 7

| Aspect | L4 (Transport) | L7 (Application) |
|---|---|---|
| Operates on | TCP/UDP connections | HTTP requests |
| Routing decisions | IP, port | URL, headers, cookies, body |
| Performance | Faster (less processing) | Slower (must parse application data) |
| Features | Basic (round-robin, least-conn) | Content-based routing, path routing, A/B |
| TLS termination | Pass-through or terminate | Typically terminates |
| gRPC | Cannot route per-RPC (sees one HTTP/2 connection) | Can route per-RPC |

**Recommendation:** L7 for most application load balancing. L4 for raw TCP/UDP or when L7 overhead is unacceptable.

### Algorithms

| Algorithm | How it works | Best for |
|---|---|---|
| Round-robin | Rotate through servers sequentially | Homogeneous servers, uniform requests |
| Weighted round-robin | Servers get traffic proportional to weight | Heterogeneous hardware |
| Least connections | Route to server with fewest active connections | Variable request duration |
| Least response time | Route to fastest server | Latency-sensitive workloads |
| Consistent hashing | Hash request attribute to server | Cache affinity, stateful services |
| Random with two choices | Pick 2 random servers, route to less loaded | Simple, surprisingly effective |

### Health Check Integration

- Load balancer probes backends at regular intervals
- Failed backend removed from rotation immediately
- Recovery: backend must pass N consecutive checks before re-adding
- Passive health checking: detect failures from real traffic (5xx responses, timeouts)

---

## Connection Pooling

### Sizing Formula

**General formula:**
```
pool_size = peak_QPS × avg_latency_seconds × safety_factor

Example: 5000 QPS, 10ms avg query latency, 1.5x safety
pool_size = 5000 × 0.010 × 1.5 = 75 connections
```

**HikariCP formula (database-specific):**
```
pool_size = (core_count × 2) + effective_spindle_count

Example: 4-core server, SSD (spindle=1)
pool_size = (4 × 2) + 1 = 9 connections
```

**Counterintuitive insight:** Smaller pools often perform better. Too many connections cause OS thread context-switching overhead. A 10,000-user application may need only 10-50 database connections.

### Pool Exhaustion Symptoms

| Symptom | Cause |
|---|---|
| Request latency spikes | Threads waiting for connection from pool |
| Connection wait timeout errors | Pool fully consumed, no connections available |
| Database "too many connections" error | Multiple pools across instances exceed DB limit |
| Increasing thread count | Threads blocked waiting for pool connections |

### Multi-Instance Pool Sizing

```
per_instance_pool = max_database_connections / num_instances

Example: PostgreSQL max_connections=100, 10 app instances
per_instance_pool = 100 / 10 = 10 connections each
```

Leave headroom for admin connections, monitoring, and migration tools.

---

## Rate Limiting

### Algorithms

| Algorithm | Burst handling | Memory | Accuracy | Best for |
|---|---|---|---|---|
| Token bucket | Allows controlled bursts | Low | Good | API rate limiting (default choice) |
| Leaky bucket | Smooths to constant rate | Low | Good | Traffic shaping, egress control |
| Fixed window | Allows 2x burst at window boundary | Low | Lower | Simple, low-overhead limiting |
| Sliding window log | No boundary issues | Higher | Highest | Precise limiting, lower volume |
| Sliding window counter | No boundary issues | Low | Good | Best balance for most APIs |

### Token Bucket

```
State: tokens (float), last_refill_time
Config: capacity (max tokens), refill_rate (tokens/second)

On request:
  elapsed = now - last_refill_time
  tokens = min(capacity, tokens + refill_rate × elapsed)
  last_refill_time = now

  if tokens >= 1:
    tokens -= 1
    ALLOW
  else:
    REJECT (429 Too Many Requests)
```

### Distributed Rate Limiting

For multi-instance services, rate limiting must be coordinated:

| Approach | Consistency | Latency | Complexity |
|---|---|---|---|
| Redis (INCR + EXPIRE) | Strong | +1ms per request | Low |
| Local counter + sync | Eventually consistent | None | Medium |
| Sliding window in Redis | Strong | +1-2ms | Medium |

### Response for Rate-Limited Requests

```
HTTP 429 Too Many Requests
Retry-After: 30
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1672531260
```

---

## Backpressure

### Mechanisms

| Mechanism | How it works | When to use |
|---|---|---|
| Bounded queue | Reject when queue full | Ingestion endpoints, job queues |
| HTTP 429 + Retry-After | Signal client to slow down | API rate limiting |
| TCP flow control | Receiver advertises window size | Network-level (automatic) |
| Reactive streams | Consumer signals demand (request-N) | Streaming data pipelines |
| Admission control | Accept based on current load/latency | Adaptive load management |

**Key principle:** Every ingestion point must have a backpressure mechanism. Unbounded queues lead to memory exhaustion and cascading failures.

---

## Autoscaling

### Metrics to Scale On

| Metric | Good for | Pitfall |
|---|---|---|
| CPU utilization | Compute-bound workloads | Misleading for I/O-bound (CPU low but service slow) |
| Request latency (P99) | Latency-sensitive services | Reactive (latency already degraded when triggered) |
| Queue depth | Async job processors | May not reflect end-user impact |
| Request rate | Predictable per-request resource usage | Doesn't account for request complexity |
| Custom business metric | Domain-specific scaling | More complex to implement |

**Recommendation:** Scale on queue depth or request rate for predictable workloads. Scale on latency for user-facing services. Avoid CPU-only scaling for I/O-bound services.

### Scaling Policy Design

```
Scale-up:   trigger at 70% utilization for 2 minutes → add 2 instances
Scale-down: trigger at 30% utilization for 10 minutes → remove 1 instance

Cooldown: 5 minutes between scaling actions
Min instances: 2 (HA minimum)
Max instances: 20 (cost guard)
```

**Asymmetric scaling:** Scale up aggressively (react fast to load spikes), scale down conservatively (avoid flapping).

### Predictive Autoscaling

- Analyzes 14 days of historical metrics for patterns
- ML model forecasts load 48 hours ahead
- Pre-provisions capacity before predicted spike
- Eliminates reactive scaling lag (30s-5min)
- **Limitation:** Cannot predict unprecedented traffic spikes

---

## Read and Write Scaling

### Read Scaling Strategies

| Strategy | Latency reduction | Consistency | Complexity |
|---|---|---|---|
| Read replicas | Moderate (same region) | Eventual (replication lag) | Low |
| Cache-aside (Redis) | High (<1ms vs 5-50ms DB) | Eventual (TTL-based) | Medium |
| CDN | Very high (edge-cached) | Eventual (TTL-based) | Low |
| Materialized views | High (pre-computed) | Depends on refresh strategy | Medium |

### Write Scaling Strategies

| Strategy | How | When |
|---|---|---|
| Write-behind/batching | Buffer writes, flush periodically | High write volume, tolerance for short delay |
| Sharding | Distribute writes across partitions | Single node write throughput exceeded |
| Command queuing | Queue writes for async processing | Writes don't need immediate confirmation |
| CQRS | Separate write model from read model | Different write and read patterns/scale |

---

## Service Mesh

### When It Helps

- **mTLS everywhere:** Automatic encryption between all services without application changes
- **Observability:** Distributed tracing, metrics, access logs injected at proxy level
- **Traffic management:** Canary routing, circuit breakers, retries at infrastructure level
- **Multi-team:** Consistent policies across services owned by different teams

### When It's Overhead

- **Small team (<10 engineers):** Operational complexity not justified
- **Few services (<10):** Library-based approach simpler
- **Latency-critical:** Proxy sidecar adds 1-5ms per hop
- **Simple networking:** No need for traffic shaping, mutual TLS, or per-service policies

### Popular Service Meshes

| Mesh | Proxy | Key strength |
|---|---|---|
| Istio | Envoy | Feature-rich, wide adoption |
| Linkerd | linkerd2-proxy (Rust) | Lightweight, simple, lower latency |
| Cilium | eBPF (kernel-level) | Highest performance, no sidecar |
