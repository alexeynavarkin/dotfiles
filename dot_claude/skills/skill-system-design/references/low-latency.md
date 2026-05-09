# Low Latency

## Latency Numbers Every Architect Should Know

| Operation | Latency | Relative |
|---|---|---|
| L1 cache reference | 1 ns | 1x |
| L2 cache reference | 4 ns | 4x |
| Main memory reference | 100 ns | 100x |
| SSD random read | 100 μs | 100,000x |
| Network roundtrip (same DC) | 500 μs | 500,000x |
| SSD sequential read (1MB) | 1 ms | 1,000,000x |
| HDD seek | 10 ms | 10,000,000x |
| Network roundtrip (cross-region) | 50 ms | 50,000,000x |
| Network roundtrip (cross-ocean) | 150 ms | 150,000,000x |

**Key insight:** The gap between memory and network is 5,000x. The gap between same-DC and cross-ocean is 300x. These numbers drive architectural decisions: colocate data with compute, cache aggressively, minimize network hops.

---

## Percentile Thinking

### Why P99 Matters More Than Average

- Average hides outliers. A service with 10ms average may have 500ms P99.
- In a system with 100 parallel backend calls, probability that at least one hits P99: `1 - (0.99)^100 = 63%`
- Users experience the worst call, not the average call.

### Measuring Percentiles

| Tool/Algorithm | Use case |
|---|---|
| HDR Histogram | High-resolution, low-overhead, fixed memory |
| t-digest | Streaming percentile estimation, mergeable across nodes |
| Reservoir sampling | Simple, but less accurate at tails |

### Coordinated Omission

**Problem:** Load testing tools that wait for responses before sending next request undercount latency during slowdowns.

```
If service is slow (1s instead of 10ms):
  Naive tool: sends 1 req/s during slowdown → misses the 99 requests that WOULD have arrived
  Corrected: accounts for all requests that would have been in-flight
```

**Fix:** Use tools that account for coordinated omission (wrk2, Gatling with proper configuration) or correct for it in analysis.

---

## Cache Hierarchy

### Three-Level Cache Architecture

```
Request → L1 (in-process) → L2 (Redis/Memcached) → L3 (CDN/edge) → Database
             ~1μs              ~1ms                   ~10-50ms        ~5-50ms
```

| Level | Technology | Size | Latency | Consistency |
|---|---|---|---|---|
| L1 | In-process map, Caffeine, Guava | MB | <1μs | Process-local (stale on other instances) |
| L2 | Redis, Memcached | GB | 0.1-1ms | Shared (eventual with TTL) |
| L3 | CDN (CloudFront, Fastly) | TB | Varies by edge | Eventual (TTL + purge) |

### Cache Invalidation Strategies

| Strategy | How | Pros | Cons |
|---|---|---|---|
| TTL-based | Entry expires after N seconds | Simple, self-healing | Stale during TTL window |
| Event-driven | Invalidate on write (publish event) | Low staleness | More complex, must not miss events |
| Write-through | Write to cache + DB synchronously | Always consistent | Write latency = cache + DB |
| Write-behind | Write to cache, async flush to DB | Fast writes | Data loss risk if cache crashes |

### Cache Stampede Prevention

**Problem:** Cache entry expires → 1000 concurrent requests all miss cache → all hit database simultaneously.

| Solution | How it works |
|---|---|
| Singleflight / request coalescing | First request fetches, others wait for result |
| Probabilistic early expiration | Each request has small chance of refreshing before TTL expires |
| Lock-based refresh | Acquire lock to refresh; others serve stale while refresh in progress |
| Background refresh | Separate process refreshes before TTL expires |

**Singleflight pattern (Go):**
```
// Only one concurrent fetch per key
result, err = singleflight.Do(key, func() (interface{}, error) {
    return db.Query(key)
})
```

---

## Hedged Requests

### How It Works

```
1. Send request to primary replica
2. If no response within hedge_delay (e.g., P50 latency):
   Send same request to secondary replica
3. Accept first response, cancel the other
```

### When to Use

- **Read operations only** (must be idempotent)
- Acceptable cost: ~5% additional traffic (most requests complete before hedge triggers)
- Tail latency is significantly worse than median (P99 >> P50)

### Configuring Hedge Delay

| Setting | Overhead | Latency reduction |
|---|---|---|
| P50 (median) | ~50% extra traffic | Maximum reduction |
| P90 | ~10% extra traffic | Good reduction |
| P95 | ~5% extra traffic | Moderate reduction (recommended) |
| P99 | ~1% extra traffic | Minimal reduction |

### Real-World Results

- Google: Hedged requests reduce P99 from 1800ms to 74ms for BigTable reads
- Grafana Tempo: 45% tail latency reduction
- Global Payments: 30% P99 reduction with DynamoDB

---

## Hot Path Optimization

### Methodology

1. **Profile first.** Identify the actual hot path with CPU/trace profiling. Don't guess.
2. **Measure the hot path.** How many times per second? What's the per-invocation cost?
3. **Optimize the hot path.** Focus effort on the code that runs most frequently.
4. **Move cold work off-path.** Async, batch, or pre-compute anything not needed in the hot path.

### Common Hot Path Optimizations

| Bottleneck | Fix | Typical improvement |
|---|---|---|
| JSON serialization | Use protobuf or flatbuffers | 5-10x faster |
| Memory allocation in loops | Object pooling, pre-allocated buffers | 2-20x fewer allocations |
| Lock contention | Lock-free structures, reduce critical section | 2-10x throughput |
| System calls in tight loops | Batch operations, async I/O | 5-50x fewer syscalls |
| Random memory access | Sequential access, struct-of-arrays | 2-5x cache hit improvement |
| Repeated computation | Memoization, pre-computation | Varies (often 10-100x) |

### Pre-Serialized Responses

For endpoints serving the same response to many clients:
```
// Serialize once, serve many
cached_bytes = protobuf.Marshal(response)
// Serve cached_bytes directly, skip per-request serialization
```

---

## Protocol Selection

### gRPC vs REST vs GraphQL

| Aspect | gRPC | REST | GraphQL |
|---|---|---|---|
| Encoding | Protobuf (binary) | JSON (text) | JSON (text) |
| Transport | HTTP/2 | HTTP/1.1 or HTTP/2 | HTTP (typically POST) |
| Payload size | 3-10x smaller | Baseline | Varies (no over-fetching) |
| Latency | Lower (binary, multiplexing) | Higher | Higher (query parsing) |
| Streaming | Native (bidirectional) | SSE or WebSocket | Subscriptions (complex) |
| Code generation | Built-in from .proto | Manual or OpenAPI | Schema-based |
| Browser support | Limited (grpc-web) | Native | Native |
| Caching | Not HTTP-cacheable | HTTP caching works | POST = not cacheable |
| Tooling | Specialized (grpcurl, grpc-web) | Universal (curl, browser) | Specialized (GraphiQL) |

### Decision Guide

| Use case | Recommendation |
|---|---|
| Service-to-service, high throughput | gRPC |
| Public API, browser clients | REST |
| Mobile clients needing flexible queries | GraphQL |
| Real-time bidirectional streaming | gRPC |
| Simple CRUD, broad compatibility | REST |
| Multiple client types with different data needs | GraphQL |

---

## Connection Optimization

### HTTP/2 Multiplexing

- Single TCP connection carries multiple request/response streams
- No head-of-line blocking at HTTP level (but TCP-level HOL blocking remains)
- Reduces connection overhead: 1 connection vs 6+ connections per host (HTTP/1.1)
- Server push: proactively send resources before client requests them

### QUIC / HTTP/3

- UDP-based, no TCP head-of-line blocking
- 0-RTT connection resumption (send data on first packet for repeat connections)
- Connection ID survives IP changes (mobile network switching)
- Independent stream loss recovery (one stream's packet loss doesn't block others)

**When QUIC helps most:**
- High packet loss environments (mobile, satellite)
- Frequent connection migration (mobile users switching WiFi/cellular)
- Many concurrent streams per connection

### Connection Keep-Alive

```
Keep-alive timeout: 60-120 seconds (match client and server)
Max requests per connection: 1000-10000
Idle timeout: 30-60 seconds
```

**Pitfall:** Load balancer and server keep-alive timeouts must be aligned. If server closes before LB expects, clients get connection reset errors.

---

## Serialization Performance

| Format | Encode speed | Decode speed | Size | Schema | Human-readable |
|---|---|---|---|---|---|
| JSON | Baseline | Baseline | Baseline | No | Yes |
| Protobuf | 2-5x faster | 2-5x faster | 3-10x smaller | Yes (.proto) | No |
| FlatBuffers | Fastest (zero-copy) | Fastest (zero-copy) | Small | Yes (.fbs) | No |
| MessagePack | 1.5-3x faster | 1.5-3x faster | 1.5-2x smaller | No | No |
| Avro | 2-4x faster | 2-4x faster | 2-5x smaller | Yes (.avsc) | No |

**Decision:** Use JSON for external APIs and debugging. Use protobuf for service-to-service communication. Use FlatBuffers only for ultra-low-latency paths where zero-copy matters.

---

## Zero-Copy and Kernel Bypass

### io_uring (Linux 5.1+)

- Asynchronous I/O with submission and completion queues in shared memory
- Minimal syscall overhead (batched submissions)
- Supports zero-copy send/receive
- Compatible with existing kernel TCP stack

**When to use:** High-throughput network servers (>100K connections), disk I/O intensive applications.

### DPDK (Data Plane Development Kit)

- Completely bypasses kernel network stack
- User-space application polls NIC directly
- 1-10μs per-packet latency (vs kernel: 10-100μs)

**When to use:** Ultra-low-latency requirements (financial trading, telecom), >1M packets/second.

**When NOT to use:** Most applications. The complexity and CPU cost (busy polling) is rarely justified.

### DNS and Anycast

**GeoDNS:** Returns different IP addresses based on client's geographic location. Routes users to nearest data center.

**Anycast:** Multiple servers advertise the same IP address. Network routes to nearest server by topology.

| Aspect | GeoDNS | Anycast |
|---|---|---|
| Routing decision | DNS resolver location | BGP topology |
| Granularity | Per-DNS-query | Per-packet |
| Failover speed | TTL-dependent (seconds to minutes) | BGP convergence (seconds) |
| Protocol support | Any (client gets IP, connects normally) | Best for UDP/short TCP; long TCP sessions can break on route change |
| Use case | CDN, multi-region web apps | DNS servers, DDoS mitigation, CDN edge |
