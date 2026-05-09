# High Availability

## Availability Math

### The Nines Table

| Availability | Downtime/year | Downtime/month | Downtime/week |
|---|---|---|---|
| 99% (two nines) | 3.65 days | 7.31 hours | 1.68 hours |
| 99.9% (three nines) | 8.77 hours | 43.8 minutes | 10.1 minutes |
| 99.95% | 4.38 hours | 21.9 minutes | 5.04 minutes |
| 99.99% (four nines) | 52.6 minutes | 4.38 minutes | 1.01 minutes |
| 99.999% (five nines) | 5.26 minutes | 26.3 seconds | 6.05 seconds |

### SLA Composition

**Serial (all must work):** `SLA_total = SLA_1 × SLA_2 × ... × SLA_n`

```
Example: API (99.99%) → Database (99.99%) → Cache (99.99%)
Total: 0.9999 × 0.9999 × 0.9999 = 99.97%
```

**Parallel (any can work):** `SLA_total = 1 - (1 - SLA_1) × (1 - SLA_2)`

```
Example: Primary DB (99.9%) || Standby DB (99.9%)
Total: 1 - (0.001 × 0.001) = 99.9999%
```

**Key insight:** Serial dependencies multiply failure probability. Each additional dependency in the critical path reduces overall availability.

### Error Budget

```
Error budget = 1 - SLO

SLO: 99.9% → Error budget: 0.1% → 43.8 minutes/month
```

When error budget is exhausted: freeze non-critical deployments, focus on reliability.

---

## Active-Active vs Active-Passive

### Active-Active

All nodes serve production traffic simultaneously.

| Aspect | Detail |
|---|---|
| Traffic distribution | Load balancer splits across all nodes |
| State synchronization | Requires data replication between all active nodes |
| Failover time | Near-zero (traffic already distributed) |
| Resource utilization | High (all nodes doing useful work) |
| Consistency challenge | Must handle concurrent writes to same data across nodes |
| Best for | Stateless services, read-heavy workloads, global user base |

**State synchronization options:**
- Shared database (all nodes read/write same DB)
- Replicated databases (multi-leader, conflict resolution needed)
- Shared cache (Redis Cluster, Memcached)
- No shared state (stateless, state in client or external store)

### Active-Passive

One primary handles all traffic; standby replicas wait.

| Aspect | Detail |
|---|---|
| Traffic distribution | All traffic to primary; standby is idle |
| State synchronization | Unidirectional replication: primary → standby |
| Failover time | Seconds to minutes (promote standby, DNS update) |
| Resource utilization | Lower (standby capacity wasted during normal operation) |
| Consistency | Simple (single writer) |
| Best for | Write-heavy workloads, simpler consistency requirements |

**Failover trigger:** Heartbeat monitor detects primary failure → promote standby → update DNS/load balancer.

**Replication lag risk:** If standby is behind, promotion may lose recent writes. Synchronous replication eliminates this at the cost of write latency.

---

## Consensus Protocols

### Raft Overview

**Purpose:** Achieve agreement on a sequence of operations across multiple nodes, even when some nodes fail.

**Roles:** Leader (1), Followers (N-1), Candidates (during election)

**Leader Election:**
1. Followers expect periodic heartbeat from leader
2. If heartbeat timeout expires, follower becomes candidate
3. Candidate requests votes from all nodes
4. Node that receives majority votes becomes leader
5. Leader sends heartbeats to maintain authority

**Log Replication:**
1. Client sends write to leader
2. Leader appends to its log, sends to all followers
3. When majority acknowledges → entry committed
4. Leader notifies client of success

**Quorum Math:**
```
Cluster size: 2f + 1 nodes (tolerates f failures)
3 nodes → tolerates 1 failure
5 nodes → tolerates 2 failures
7 nodes → tolerates 3 failures
```

**Production systems using Raft:** etcd, Consul, CockroachDB, TiKV, RabbitMQ (quorum queues)

### When to Use Consensus

- **Leader election** for single-leader architectures
- **Configuration management** (etcd, Consul)
- **Distributed locking** with strong guarantees
- **Metadata management** (who owns which partition, cluster topology)

**When NOT to use consensus:** For every write in a high-throughput data path. Consensus adds latency (majority acknowledgment). Use it for coordination, not for data storage at scale.

---

## Split-Brain Prevention

**Problem:** Network partition divides cluster. Both sides think the other is down. Both elect a leader. Two leaders accept conflicting writes.

### Prevention Strategies

**Quorum-based decisions:** Require majority (N/2 + 1) to elect leader or accept writes. Minority side cannot form quorum → becomes read-only or unavailable.

**Fencing tokens:** Each leader election produces a monotonically increasing token. Resources reject operations with stale tokens. See distributed-systems.md for details.

**STONITH (Shoot The Other Node In The Head):** When a node suspects the other is down, it physically powers off the other node (via IPMI/iLO) before assuming leadership. Prevents two nodes from being active simultaneously.

**Witness/tiebreaker:** Odd number of nodes, or a lightweight witness node in a third location that participates only in voting.

---

## Health Checking

### Deep vs Shallow Health Checks

| Type | What it checks | Response time | Use for |
|---|---|---|---|
| Shallow (liveness) | "Is the process running?" | <10ms | Container restart decisions |
| Deep (readiness) | "Can it serve traffic?" (DB connected, cache warm, dependencies up) | 10-500ms | Load balancer routing |

### Configuration

| Parameter | Liveness probe | Readiness probe |
|---|---|---|
| Initial delay | 10-30s (allow startup) | 5-15s |
| Period | 10-30s | 5-10s |
| Timeout | 1-3s | 3-5s |
| Failure threshold | 3 consecutive | 2-3 consecutive |
| Success threshold | 1 | 1-2 |

### Anti-Patterns

- **Health check that calls downstream services:** If dependency is slow, health check fails, node removed, cascading failure.
- **Health check without timeout:** Hanging health check blocks the probe, node eventually removed.
- **Too aggressive checks:** Checking every 1 second with failure threshold of 1 = flapping.

**Best practice:** Liveness checks should verify the process and basic state only. Readiness checks can verify local resources (DB connection pool, local cache). Neither should make synchronous calls to other services.

---

## Failover Patterns

### Cold, Warm, Hot Standby

| Pattern | Standby state | Failover time | Cost | Data loss risk |
|---|---|---|---|---|
| Cold | Off, periodic backup restore | Minutes to hours | Lowest | Highest (last backup) |
| Warm | Running, async replication | Seconds to minutes | Medium | Some (replication lag) |
| Hot | Running, sync replication | Seconds | Highest | Minimal |

### Automated vs Manual Failover

| Aspect | Automated | Manual |
|---|---|---|
| Speed | Seconds | Minutes to hours |
| Risk | False positive detection → unnecessary failover | Slow response to real outage |
| Suitable for | Well-tested failure modes with clear signals | Novel failures, complex state |
| Prerequisite | Comprehensive health checking, tested runbook | 24/7 on-call team |

**Recommendation:** Automate failover for well-understood, tested scenarios. Keep manual override for complex situations. Test automated failover regularly (chaos engineering).

---

## Multi-Region Architecture

### Deployment Patterns

| Pattern | Regions active | Consistency | Failover | Complexity |
|---|---|---|---|---|
| Active-passive | 1 active, 1+ standby | Strong (single writer) | Manual/automated switchover | Low |
| Active-active | All regions | Eventual or causal | Automatic (traffic shifts) | High |
| Deployment stamps | Independent per region | Independent | Region-level isolation | Medium |

### Cell-Based Architecture

**Concept:** Divide the system into independent cells, each containing all services needed to serve a subset of users.

```
Cell 1 (US-East): Users A-M
  └── API servers, databases, caches, queues

Cell 2 (US-West): Users N-Z
  └── API servers, databases, caches, queues

Router: Maps user → cell based on user ID or geography
```

**Benefits:**
- **Blast radius reduction:** Cell failure affects only its users, not the entire system
- **Independent scaling:** Scale cells independently based on load
- **Independent deployment:** Deploy and test changes per cell (canary at cell level)

**Trade-offs:**
- Cross-cell queries are expensive (avoid or use eventual consistency)
- Cell assignment must be sticky (user stays in same cell)
- Rebalancing cells requires data migration

### Data Sovereignty

- Some regulations require data to stay within geographic borders (GDPR, data residency laws)
- Cell-based architecture naturally supports this: cells aligned with regulatory regions
- Metadata/routing layer may need to be global but should not contain regulated data

---

## Zero-Downtime Deployments

### Blue-Green

```
Router → [Blue v1.0] (serving traffic)
         [Green v1.1] (deployed, tested, idle)

Switch: Router → [Green v1.1] (now serving)
                 [Blue v1.0] (idle, rollback target)
```

| Aspect | Detail |
|---|---|
| Rollback | Instant (switch router back) |
| Cost | 2x infrastructure during deployment |
| Database | Must be backward-compatible (both versions may run simultaneously) |
| Risk | 100% traffic switches at once |

### Canary

```
Router → [v1.0] 95% traffic
         [v1.1] 5% traffic (canary)

If healthy after N minutes: increase to 25%, 50%, 100%
If unhealthy: route 100% back to v1.0
```

| Aspect | Detail |
|---|---|
| Rollback | Fast (shift traffic back) |
| Cost | Minimal extra infrastructure |
| Risk | Only canary percentage affected by bugs |
| Monitoring | Must track metrics per-version (error rate, latency, business metrics) |

### Rolling Update

```
[v1.0] [v1.0] [v1.0] [v1.0]  ← start
[v1.1] [v1.0] [v1.0] [v1.0]  ← update 1/4
[v1.1] [v1.1] [v1.0] [v1.0]  ← update 2/4
[v1.1] [v1.1] [v1.1] [v1.0]  ← update 3/4
[v1.1] [v1.1] [v1.1] [v1.1]  ← complete
```

| Aspect | Detail |
|---|---|
| Rollback | Reverse roll (takes time) |
| Cost | No extra infrastructure |
| Database | Must handle mixed versions during rollout |
| Kubernetes | Default strategy. Configure maxSurge and maxUnavailable. |

### Database Migration Compatibility

Both old and new application versions will run simultaneously during deployment. Database changes must be **backward-compatible**:

1. **Add column:** Safe. Old version ignores new column.
2. **Remove column:** First deploy version that stops reading it. Then remove in next deploy.
3. **Rename column:** Add new column → deploy version that writes both → migrate data → deploy version that reads new → drop old column.
4. **Change type:** Similar multi-step process.

Never make a breaking schema change in a single deploy.
