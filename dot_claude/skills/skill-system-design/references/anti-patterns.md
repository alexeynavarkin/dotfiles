# Architecture Anti-Patterns

## 1. Distributed Monolith

**What it is:** Services deployed independently but coupled so tightly they must change and deploy together.

**Detection checklist:**
- [ ] Deploying service A requires deploying service B at the same time
- [ ] Services share data models or generated code that must be version-locked
- [ ] A change in one service's internal logic breaks another service
- [ ] Cross-service integration tests must pass before any service deploys
- [ ] Services communicate synchronously in long chains (A → B → C → D)
- [ ] Shared libraries contain business logic, not just utilities

**Why it's worse than a monolith:** You get all the operational complexity of distributed systems (network failures, partial outages, distributed debugging) with none of the benefits (independent deployment, isolated scaling, fault isolation).

**Remediation:**
1. Map service dependencies. Draw arrows for every synchronous call.
2. Identify the tightest couplings. These are candidates for merging back into one service.
3. Replace synchronous chains with async events where the caller doesn't need an immediate response.
4. Move shared business logic into the service that owns the domain concept.
5. Shared libraries should contain only cross-cutting infrastructure concerns (logging, metrics, auth middleware).

---

## 2. Shared Database Between Services

**What it is:** Multiple independently deployed services read from and write to the same database tables.

**Why it's harmful:**
- Schema changes require coordinating all consuming services simultaneously
- No clear ownership of data — who decides the column type? Who handles migrations?
- Services can bypass each other's business rules by writing directly
- Cannot scale services independently (all share the same DB bottleneck)
- Locks and contention from unrelated workloads interfere with each other

**Remediation:**
- Each service owns its tables exclusively. Other services access data through APIs or events.
- Use CDC (change data capture) to propagate data changes to services that need read access.
- During migration: create API endpoints in the owning service, redirect consumers one by one, then restrict direct DB access.

---

## 3. Chatty Services

**What it is:** Fine-grained service decomposition leading to excessive inter-service communication.

**Symptoms:**
- A single user request triggers 10+ internal service calls
- N+1 query patterns across service boundaries (fetch list, then fetch detail for each item)
- Latency dominated by network overhead, not computation
- High inter-service bandwidth consumption

**Impact:** Netflix found reducing internal service calls by 78% using API aggregation.

**Remediation:**
- **BFF pattern (Backend for Frontend):** Aggregation layer that combines multiple service calls into one response.
- **Batch/bulk APIs:** Replace N individual calls with one batch call.
- **Denormalize across boundaries:** Store copies of frequently-needed data (accept eventual consistency).
- **Merge services:** If two services always call each other, they might be one service.

---

## 4. Premature Optimization

**What it is:** Solving scale problems you don't have yet, adding complexity that doesn't pay for itself.

**Examples:**
- Sharding a database that's at 5% capacity
- Kafka for 100 messages/day (a simple queue or even a database table suffices)
- Microservices architecture for a 3-person team
- Custom serialization format when JSON throughput is 100x what you need
- Read replicas when the database has <1000 QPS

**The monolith-first principle:** Start with a well-structured monolith. Extract services only when you have evidence that a component needs independent scaling, independent deployment, or isolation from failures in other components.

**Decision framework:**
1. Can a single node handle 10x current load? → Don't distribute.
2. Does the team have operational maturity for distributed systems? → If no, stay simple.
3. Is there a specific scaling bottleneck? → Extract only that component.

---

## 5. Cache-as-Architecture

**What it is:** Using a cache layer to mask underlying performance problems instead of fixing them.

**Symptoms:**
- Removing the cache would make the system unusable
- No defined cache invalidation strategy — "we just set TTL to 5 minutes"
- Cache and database are permanently divergent for some records
- Cache warming takes so long that deploys cause outages
- Business logic depends on cache state (not just performance)

**Remediation:**
- Fix the underlying performance issue (missing index, expensive query, unnecessary computation).
- Define explicit invalidation strategy: TTL + event-driven invalidation on writes.
- Cache should be a performance optimization, not a correctness requirement. The system must function (possibly slower) without it.

---

## 6. Dual Writes

**What it is:** Writing to two different systems (e.g., database + message queue) without transactional guarantee.

**The problem:**
```
1. Write to database  ← succeeds
2. Publish to Kafka   ← fails (network error)
Result: Database updated, event never published, consumers out of sync
```

Or worse:
```
1. Publish to Kafka   ← succeeds
2. Write to database  ← fails
Result: Event published for data that doesn't exist
```

**Fix: Outbox Pattern**
1. Write business data + event record to OUTBOX table in one database transaction.
2. Separate process (or CDC connector like Debezium) reads OUTBOX and publishes to message broker.
3. Single write = atomic. Publishing is retried until success.

---

## 7. Distributed Transactions Spanning Services

**What it is:** Using 2PC (two-phase commit) or XA transactions across microservice boundaries.

**Why it fails at scale:**
- Coordinator is a single point of failure
- Participants hold locks during voting phase — blocking
- Network partitions leave participants in uncertain state
- Latency: two round-trips across network minimum
- Doesn't scale beyond a handful of participants

**Use instead: Saga pattern**
- Sequence of local transactions, each with a compensating action
- Orchestration (central coordinator) or choreography (event-driven)
- Eventually consistent, but no distributed locking

---

## 8. Synchronous Call Chains

**What it is:** Service A synchronously calls B, which synchronously calls C, which synchronously calls D.

**Why it's harmful:**
- **Latency multiplication:** Total latency = sum of all service latencies + network overhead for each hop
- **Availability multiplication:** If each service is 99.9% available, chain of 4 services: 99.9%^4 = 99.6% (3.5 hours downtime/month instead of 43 minutes)
- **Tail latency amplification:** P99 of chain is worse than worst P99 of any individual service
- **Cascade failures:** Slowest service in chain causes timeouts in all upstream services

**Remediation:**
- Make calls async where the caller doesn't need immediate response
- Use events for eventually-consistent data propagation
- Collapse chain by merging services or using direct DB access where appropriate
- Add circuit breakers at each boundary
- Set cascading timeout budgets: outer timeout > sum of inner timeouts

---

## 9. Generic Platform Built Too Early

**What it is:** Building an internal platform, framework, or abstraction layer before understanding the patterns it should support.

**Symptoms:**
- Platform team has no internal customers yet
- Platform API is designed by speculation rather than from concrete use cases
- Platform requires consuming teams to change their workflow significantly
- Platform abstractions leak — consumers regularly need escape hatches

**Rule:** Build the thing three times first. Then extract the platform from the commonality. Never build the platform first and force applications into it.

---

## 10. Ignoring Back-of-Envelope Math

**What it is:** Choosing infrastructure based on buzzwords or hype rather than sizing the problem.

**Examples of unnecessary complexity from skipping math:**
- "We need Kafka" → 50 events/second → PostgreSQL with a polling consumer handles this trivially
- "We need sharding" → 500GB database → single PostgreSQL instance handles this
- "We need a distributed cache" → 100MB working set → in-process LRU cache handles this
- "We need microservices" → 10K req/s → single Go/Java service handles this easily

**Always do the math first:**
1. How much data? (GB/TB)
2. How many operations per second? (read QPS, write QPS)
3. What latency is acceptable? (P50, P99)
4. Can a single node handle it? (check reference numbers in capacity-planning.md)

If a single node handles it, start there. Distribute when you must, not when you might.
