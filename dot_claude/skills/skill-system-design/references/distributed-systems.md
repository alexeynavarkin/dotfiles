# Distributed Systems

## CAP Theorem

**Statement:** During a network partition, a distributed system must choose between Consistency and Availability.

| Property | Definition |
|---|---|
| Consistency | All clients see the same data at the same time (linearizability) |
| Availability | Every request receives a response (no timeout/error) |
| Partition Tolerance | System continues operating despite network partitions |

**Practical interpretation:** Network partitions are not optional — they happen. The real decision is what the system does during a partition:

- **CP (choose consistency):** Reject writes during partition to maintain data integrity. Example: distributed locks, financial ledgers.
- **AP (choose availability):** Accept writes during partition, reconcile later. Example: shopping cart, social media feed.

**Most systems are not purely CP or AP.** They make per-operation decisions: strong consistency for payments, eventual consistency for recommendations.

---

## PACELC Theorem

**Extension:** Even without partitions (normal operation), there's a trade-off between Latency and Consistency.

```
If Partition:  choose Consistency vs Availability
Else:          choose Latency vs Consistency
```

| System | During Partition | Normal Operation |
|---|---|---|
| Spanner | Consistent (CP) | Consistent (higher latency, sync replication) |
| DynamoDB | Available (AP) | Low latency (eventual consistency by default) |
| Cassandra | Available (AP) | Tunable (per-query consistency level) |
| PostgreSQL (single-leader) | Unavailable | Consistent (all reads from leader) |

**Key insight:** The normal-operation trade-off (latency vs consistency) affects every request, not just during rare partitions. This is often the more important design decision.

---

## Consistency Models

### Strong Consistency (Linearizability)

- Every read reflects the most recent write
- Operations appear to execute instantaneously at a single point in time
- **Cost:** Synchronous replication, consensus protocol, higher latency
- **Use when:** Financial transactions, inventory counts, user authentication state
- **Examples:** Spanner, PostgreSQL (single leader), etcd

### Causal Consistency

- Operations with cause-effect relationships ordered correctly
- Concurrent operations may be seen in different orders by different clients
- **Cost:** Vector clocks or hybrid logical clocks for ordering
- **Use when:** Collaborative editing, social media (reply always after original post)
- **Examples:** MongoDB (causal sessions), some CRDT-based systems

### Eventual Consistency

- Replicas will eventually converge to the same state
- No guarantee on when — could be milliseconds or seconds
- **Cost:** Lowest. Asynchronous replication.
- **Use when:** Caching, analytics, user preferences, content distribution
- **Examples:** DynamoDB (default), Cassandra, DNS, most caches
- **Risk:** Stale reads, lost updates on concurrent writes

### Read-Your-Own-Writes

- Client always sees its own writes immediately
- Other clients may see stale data
- **Implementation:** Read from leader after writing, or use session-sticky routing
- **Use when:** User profiles, settings — user expects to see what they just changed

### Session Consistency

- Guarantees within a single client session
- Different clients may see different versions
- **Implementation:** Session-affinity to a specific replica

---

## Distributed Transactions

### Two-Phase Commit (2PC)

```
Phase 1 (Prepare):  Coordinator → all participants: "Can you commit?"
                     All participants: "Yes" (vote commit) or "No" (vote abort)

Phase 2 (Commit):   If all voted "Yes": Coordinator → "Commit"
                     If any voted "No":  Coordinator → "Abort"
```

**Problems at scale:**
- **Blocking:** Participants hold locks during voting. If coordinator crashes after collecting votes but before sending decision, participants are stuck.
- **Single point of failure:** Coordinator crash = all participants blocked indefinitely.
- **Latency:** Two network round-trips minimum.
- **Not partition-tolerant:** Network partition during vote = uncertain state.

**When to use:** Within a single database (internal 2PC). Acceptable for 2-3 tightly-coupled databases in a single data center.

**When NOT to use:** Across microservice boundaries. Across data centers. More than 3 participants.

### Saga Pattern

A sequence of local transactions, each with a compensating action for rollback.

**Example: Order Processing**
```
1. Create Order        → Compensate: Cancel Order
2. Reserve Inventory   → Compensate: Release Inventory
3. Charge Payment      → Compensate: Refund Payment
4. Ship Order          → Compensate: Cancel Shipment

If step 3 fails: execute compensations 2, 1 (reverse order)
```

#### Orchestration vs Choreography

| Aspect | Orchestration | Choreography |
|---|---|---|
| Coordination | Central orchestrator directs each step | Each service reacts to events |
| Visibility | Single workflow view, easy to monitor | Logic distributed, harder to trace |
| Coupling | Orchestrator knows all services | Services only know events |
| Failure point | Orchestrator is SPoF | No central SPoF |
| Complexity | Complex coordinator, simple services | Simple services, complex event flows |
| Debugging | Follow orchestrator logs | Requires distributed tracing |
| Best for | Complex, multi-step business workflows | Simple, loosely-coupled flows |

**2024+ trend:** Hybrid. Use choreography for simple flows (2-3 steps). Use orchestration (Temporal, Cadence, Step Functions) for complex flows.

#### Compensating Transaction Design

- Compensations must be **idempotent** — may execute multiple times on retry
- Compensations must be **retryable** — if compensation fails, it must be retried until success
- Some actions are not reversible (email sent, SMS sent) — use semantic compensation (send correction email)
- Order of compensation: reverse order of forward steps

---

## Outbox Pattern

**Problem:** Need to atomically update database AND publish an event. Can't use distributed transaction.

**Solution:**
```
BEGIN TRANSACTION
  1. UPDATE orders SET status = 'confirmed' WHERE id = 123
  2. INSERT INTO outbox (event_type, payload) VALUES ('OrderConfirmed', '{...}')
COMMIT

-- Separate process (poller or CDC):
  3. Read unpublished events from outbox table
  4. Publish to message broker (Kafka, SQS)
  5. Mark events as published (or delete)
```

**CDC-based outbox (preferred):**
- Use Debezium to capture INSERT events on the outbox table from the WAL
- No polling needed — real-time, low-latency event propagation
- Debezium handles retries and offset management

**Consumer-side idempotency:** The consumer must be idempotent because the outbox guarantees at-least-once delivery (same event may be published twice during failure recovery).

---

## Idempotency

### Pattern

```
Client generates idempotency_key (UUID v4)
Client sends: POST /payments {amount: 100, idempotency_key: "abc-123"}

Server:
  1. Check if idempotency_key exists in store
  2. If exists: return cached response (don't re-execute)
  3. If not: execute operation, store response with key, return response
```

### Implementation Details

| Aspect | Recommendation |
|---|---|
| Key storage | Database table or Redis with TTL |
| Deduplication window | 24-72 hours (balance between safety and storage) |
| Key generation | Client-side UUID v4 or deterministic hash of request |
| Response storage | Store full response to return on duplicate |
| Concurrent duplicates | Use database UNIQUE constraint or Redis SETNX for atomic check-and-set |

### Naturally Idempotent Operations

- `PUT /users/123 {name: "Alice"}` — setting to a value is idempotent
- `DELETE /users/123` — deleting already-deleted resource is a no-op
- Read operations (GET) — inherently idempotent

### Non-Idempotent Operations That Need Keys

- `POST /payments` — creating a payment (must not duplicate)
- `POST /orders` — placing an order
- Any operation that increments/decrements (balance adjustments)

---

## CRDTs (Conflict-free Replicated Data Types)

Data structures that automatically merge to a consistent state without coordination.

### Common CRDTs

| CRDT | What it models | Merge strategy |
|---|---|---|
| G-Counter | Grow-only counter | Each node has own counter; total = sum of all nodes |
| PN-Counter | Counter with increment and decrement | Two G-Counters: one for increments, one for decrements |
| LWW-Register | Single value | Keep value with highest timestamp |
| G-Set | Grow-only set | Union of all sets |
| OR-Set | Set with add and remove | Each element tagged with unique ID; remove by specific tag |

### When to Use CRDTs

- **Multi-leader replication** where conflicts are expected
- **Offline-first** applications (mobile, edge computing)
- **Collaborative editing** (character-level CRDTs)
- **Distributed counters** (likes, views, metrics)

### When NOT to Use CRDTs

- **Strong consistency required** — CRDTs provide eventual consistency only
- **Complex business logic** — CRDTs work for specific data types, not arbitrary state machines
- **Storage overhead concerns** — CRDTs carry metadata (tombstones, version vectors)

### Production Systems Using CRDTs

- Redis Enterprise (active-active geo-replication)
- Riak (distributed key-value store)
- Automerge (collaborative editing library)
- SoundCloud (distributed counters)

---

## Vector Clocks

**Purpose:** Determine causal ordering of events in a distributed system without synchronized physical clocks.

### How They Work

Each node maintains a vector of logical clocks (one entry per node):

```
Node A: [A:0, B:0, C:0]

Event at A:     [A:1, B:0, C:0]
A sends to B:   B receives [A:1, B:0, C:0], merges:
                B: [A:1, B:1, C:0]  (increment own, take max of each)
```

### Comparison Rules

- `VC1 < VC2` (VC1 happened before VC2) if all elements VC1[i] ≤ VC2[i] AND at least one is strictly less
- `VC1 || VC2` (concurrent) if neither VC1 < VC2 nor VC2 < VC1

### Practical Use

- **Conflict detection:** If two versions have concurrent vector clocks, they conflict and need resolution
- **Causal ordering:** If VC1 < VC2, then the event at VC1 causally precedes VC2
- **Systems:** DynamoDB (simplified version vectors), Riak (full vector clocks)

---

## Distributed Locking

### Approaches

| Approach | Guarantee | Availability | Complexity |
|---|---|---|---|
| Single Redis lock (SETNX + TTL) | Weak (leader failover loses lock) | Low (single point of failure) | Simple |
| Redlock (Redis multi-node) | Debated (see Martin Kleppmann's analysis) | Medium | Moderate |
| ZooKeeper/etcd (consensus-based) | Strong (consensus protocol) | High (replicated) | Higher |
| Database advisory lock | Strong (within single DB) | Depends on DB HA | Simple |

### Fencing Tokens

**Problem:** Lock holder A's lock expires while A is still processing. B acquires lock. Now both A and B think they hold the lock.

**Solution:** Each lock acquisition returns a monotonically increasing fencing token. The resource (e.g., database) rejects requests with a token lower than the highest token it has seen.

```
A acquires lock, token=33
A is slow, lock expires
B acquires lock, token=34
A tries to write with token=33 → rejected (34 > 33)
B writes with token=34 → accepted
```

### When to Avoid Distributed Locks

- **Performance:** Locks serialize access. Consider if eventual consistency or optimistic concurrency control (version numbers) works instead.
- **Deadlock risk:** Multiple locks = deadlock potential. Use lock ordering or timeout-based acquisition.
- **Single-leader writes:** If only one node writes, it doesn't need a lock — it already has exclusive access.
