# Resilience Patterns

## Circuit Breaker

### States and Transitions

```
CLOSED ──(failures exceed threshold)──→ OPEN
                                         │
                                    (timeout expires)
                                         │
                                         ▼
CLOSED ←──(success threshold met)──── HALF-OPEN
   ▲                                     │
   └─────────────────────────────────────┘
                (failures in half-open → back to OPEN)
```

### Configuration Guidelines

| Parameter | Recommended value | Rationale |
|---|---|---|
| Failure rate threshold | 50% over sliding window of 10-20 calls | Avoids tripping on single transient error |
| Slow call duration threshold | 2-5× normal P99 latency | Slow calls consume resources like failures |
| Slow call rate threshold | 50-80% | Trip when majority of calls are slow |
| Wait duration in OPEN | 30-60 seconds | Give downstream time to recover |
| Permitted calls in HALF-OPEN | 3-5 calls | Enough to validate recovery without flooding |
| Minimum number of calls | 10-20 | Don't trip on tiny sample sizes |

### Design Principles

- **Per-endpoint, not per-service.** Service A's `/search` may be degraded while `/health` is fine.
- **Monitor circuit state.** Expose open/closed/half-open as a metric. Alert on circuits staying open.
- **Define fallback behavior.** What happens when the circuit is open? Cached response? Degraded response? Error with retry guidance?
- **Combine with timeout.** Circuit breaker wraps a call that already has a timeout configured.

---

## Bulkhead

### Thread Pool vs Semaphore Isolation

| Aspect | Thread pool | Semaphore |
|---|---|---|
| Execution context | Separate thread pool per dependency | Current thread, bounded by semaphore count |
| Overhead | Higher (context switching, thread management) | Lower (counter increment/decrement) |
| Timeout support | Can enforce timeout by interrupting thread | Relies on call's own timeout |
| Async support | Native (runs in background thread) | Good for synchronous calls |
| Monitoring | Queue depth, active threads, rejections | Active permits, waiting count |
| Best for | I/O-bound calls to external services | Synchronous, in-process rate limiting |

### Sizing

```
Thread pool size = peak_concurrent_requests × dependency_percentage + headroom

Example: 1000 peak concurrent, dependency handles 20% of requests
  Pool size = 1000 × 0.20 × 1.5 (headroom) = 300 threads
```

**Key principle:** If one dependency's thread pool is exhausted, other dependencies continue functioning normally. The failure is contained.

### Common Configuration

```
Service A bulkheads:
  - Payment Service:  maxConcurrency=50,  maxWait=100ms
  - User Service:     maxConcurrency=100, maxWait=200ms
  - Search Service:   maxConcurrency=200, maxWait=500ms
  - Non-critical API: maxConcurrency=20,  maxWait=50ms
```

---

## Timeout Strategies

### Three Timeout Types

| Type | Typical value | What it protects against |
|---|---|---|
| Connection timeout | 1-3 seconds | DNS failure, unreachable host, firewall drop |
| Read/request timeout | Based on P99 + margin | Slow response, upstream overload |
| Write timeout | Rarely configured separately | Large payload transmission delays |

### Setting Request Timeouts

**Formula:** `timeout = dependency_P99 × safety_margin`

| Dependency P99 | Safety margin | Timeout |
|---|---|---|
| 50ms | 4x | 200ms |
| 200ms | 3x | 600ms |
| 1s | 2x | 2s |
| 5s | 1.5x | 7.5s |

### Cascading Timeout Budget

In a call chain A → B → C:

```
A's total timeout: 3000ms
  ├── B call timeout: 2000ms
  │     └── C call timeout: 1000ms
  └── Remaining processing: 1000ms
```

**Rule:** Outer timeout > sum of inner timeouts + own processing time. If the inner call times out at the boundary, the outer service still has time to handle the failure gracefully.

---

## Retry with Exponential Backoff and Jitter

### Base Formula

```
delay = min(cap, base × 2^attempt)
```

### Jitter Strategies

| Strategy | Formula | Use when |
|---|---|---|
| Full jitter | `random(0, delay)` | Default choice. Best spread. |
| Equal jitter | `delay/2 + random(0, delay/2)` | Need minimum wait guarantee |
| Decorrelated | `random(base, prev_delay × 3)` | Successive retries should spread independently |

**AWS recommendation:** Full jitter. It provides the widest spread and prevents thundering herd most effectively.

### Example Configuration

```
base = 100ms
cap = 30s
max_retries = 4

Attempt 1: random(0, 200ms)
Attempt 2: random(0, 400ms)
Attempt 3: random(0, 800ms)
Attempt 4: random(0, 1600ms)
```

### Retry Budget

**Critical for scale:** Limit total retry traffic to 10-20% of normal traffic.

```
retry_budget = max_retry_rate × window
Example: Allow at most 20 extra retries per second per client
```

**When budget exhausted:** Fail fast instead of retrying. This prevents retry storms from overwhelming a recovering service.

### When NOT to Retry

- **Non-idempotent operations** without an idempotency key
- **4xx client errors** (400, 403, 404) — retrying won't fix the request
- **Circuit breaker is OPEN** — retrying will be rejected anyway
- **Retry budget exhausted** — too many retries already in flight

---

## Load Shedding

### Strategies

| Strategy | How it works | Best for |
|---|---|---|
| Queue-depth based | Reject when queue exceeds threshold | Simple, predictable |
| Latency-based | Reject when estimated wait exceeds SLA | SLO-aware |
| Priority-based | Shed lowest-priority requests first | Multi-tier service |
| Adaptive (CoDel) | Track sojourn time in queue; shed old requests | Sophisticated, self-tuning |

### CoDel (Controlled Delay) Algorithm

1. Track how long each request waits in queue (sojourn time).
2. If sojourn time exceeds target (e.g., 5ms) for sustained period (e.g., 100ms window):
   - Start dropping requests (oldest first).
3. Drop rate increases as congestion persists.
4. When sojourn time drops below target, stop dropping.

**Advantage over static thresholds:** Self-adjusting. Handles both sudden spikes and sustained overload.

### Implementation Pattern

```
On request arrival:
  1. Check queue depth. If > max_queue → reject with 503 + Retry-After header
  2. Check request priority. If low priority AND system under pressure → reject
  3. Check latency budget. If estimated wait > client timeout → reject (no point processing)
  4. Accept and process
```

**HTTP response for shed requests:** 503 Service Unavailable with `Retry-After: N` header.

---

## Graceful Degradation

### Degradation Levels

| Level | Service state | Strategy |
|---|---|---|
| L0 | Full service | All features operational |
| L1 | Degraded | Non-essential features disabled (recommendations, analytics) |
| L2 | Minimal | Core functionality only (search works, personalization off) |
| L3 | Static | Serve cached/static content. No dynamic processing. |

### Implementation Patterns

- **Feature toggling under load:** Monitor system health metrics → automatically disable non-critical features when thresholds breached
- **Stale cache serving:** When backend is down, serve last-known-good cached response with `X-Cache-Stale: true` header
- **Read-only mode:** Disable writes when write path is degraded; read path continues from replicas
- **Static fallback:** Pre-generate static HTML for critical pages. Serve from CDN when origin is down.

### Priority-Based Processing

Classify all request types:

| Priority | Examples | Shed at |
|---|---|---|
| Critical | Login, checkout, payment | Never (last to shed) |
| High | Search, product pages | L2 degradation |
| Medium | Recommendations, reviews | L1 degradation |
| Low | Analytics, telemetry, A/B tracking | First to shed |

---

## Chaos Engineering

### Process

1. **Define steady state** — What does "normal" look like? (Success rate, P99 latency, error rate)
2. **Hypothesize** — "If we kill one instance of service X, the system continues serving with <5% increase in P99"
3. **Introduce failure** — Kill the instance (in production, with blast radius controls)
4. **Observe** — Did steady state hold? What deviated?
5. **Learn** — Fix gaps. Repeat.

### Failure Injection Types

| Type | What to test | Tools |
|---|---|---|
| Instance termination | Auto-recovery, load balancing | Chaos Monkey, LitmusChaos |
| Network latency | Timeout handling, circuit breakers | tc (traffic control), Toxiproxy |
| Network partition | Split-brain handling, consensus | iptables, Chaos Mesh |
| Disk full | Logging resilience, WAL handling | dd, fallocate |
| DNS failure | Fallback resolution, caching | Block DNS responses |
| Dependency failure | Fallback behavior, graceful degradation | Fault injection proxy |

### Blast Radius Control

- Start in staging/pre-production
- In production: start with single instance in single AZ
- Gradually expand: single AZ → single region → multi-region
- Always have a kill switch to stop the experiment
- Run during business hours with the team watching

---

## Dependency Management

### Classification

| Type | Definition | Requirement |
|---|---|---|
| Critical | System cannot function without it | Must have redundancy, failover, monitoring |
| Degradable | System can function with reduced quality | Must have fallback behavior defined |
| Non-critical | System functions normally without it | Timeout fast, log error, continue |

### Rules

1. **Timeout all external calls.** No exception. Default: 1-3 seconds.
2. **Non-critical dependencies must have fallbacks.** If recommendation service is down, show popular items.
3. **Critical dependencies need redundancy.** If the primary database is down, fail over to replica.
4. **Monitor dependency health.** Track latency, error rate, and availability per dependency.
5. **Test failure modes.** Chaos engineering for each critical dependency.
6. **Document degradation behavior.** "When X is down, the system does Y instead."
