# Data Layer

## Database Selection Decision Matrix

| Use case | DB type | Examples | Key strengths |
|---|---|---|---|
| Transactional data (orders, users, payments) | Relational (OLTP) | PostgreSQL, MySQL, CockroachDB | ACID, joins, mature ecosystem |
| Analytics, reporting, BI | Columnar (OLAP) | BigQuery, Redshift, ClickHouse, Snowflake | Fast aggregations, compression |
| Metrics, logs, IoT sensor data | Time-series | TimescaleDB, InfluxDB, Prometheus, QuestDB | Time-range queries, high write throughput, auto-downsampling |
| Semi-structured, flexible schema | Document | MongoDB, DynamoDB, Firestore | Schema flexibility, horizontal scaling |
| Social networks, recommendations | Graph | Neo4j, ArangoDB, Neptune | Relationship traversal, path queries |
| Full-text search, faceted queries | Search engine | Elasticsearch, OpenSearch, Meilisearch | Text analysis, relevance scoring |
| Session, cache, leaderboard | Key-value | Redis, Memcached, DragonflyDB | Sub-millisecond latency, simple ops |
| Wide-column, high write throughput | Wide-column | Cassandra, ScyllaDB, HBase | Write-optimized, linear scaling |

### Selection Decision Tree

```
1. Is data time-ordered events/metrics?        → Time-series DB
2. Is data highly connected (relationships)?    → Graph DB
3. Need full-text search?                       → Search engine (+ primary DB)
4. Need sub-millisecond reads, simple access?   → Key-value store
5. Need flexible schema, document access?       → Document DB
6. Need heavy analytics/aggregations?           → Columnar OLAP
7. Need ACID, complex queries, joins?           → Relational OLTP
8. Need extreme write throughput, wide rows?    → Wide-column
```

---

## Replication Topologies

### Single-Leader (Primary-Secondary)

```
Writes → [Leader] → replication → [Follower 1]
                                → [Follower 2]
                                → [Follower 3]
Reads ← any node (leader or followers)
```

| Aspect | Detail |
|---|---|
| Write scalability | Limited by single leader |
| Read scalability | Linear with follower count |
| Consistency | Strong from leader; eventual from followers |
| Failover | Promote follower to leader (may lose unreplicated writes) |
| Use case | Most OLTP databases (PostgreSQL, MySQL default) |

### Multi-Leader

```
Writes → [Leader 1] ⟷ [Leader 2] ⟷ [Leader 3]
          (Region A)    (Region B)    (Region C)
```

| Aspect | Detail |
|---|---|
| Write scalability | Each region has local write capability |
| Consistency | Eventual (conflict resolution required) |
| Conflict resolution | LWW, vector clocks, CRDTs, application-level |
| Use case | Multi-region active-active, offline-first apps |
| Systems | DynamoDB Global Tables, CockroachDB, Cassandra |

### Leaderless

```
Client writes to N replicas directly
Client reads from N replicas, takes most recent (quorum)
Write quorum: W replicas must acknowledge
Read quorum: R replicas must respond
Consistency when: W + R > N
```

| Aspect | Detail |
|---|---|
| Write scalability | Any node accepts writes |
| Consistency | Tunable (quorum configuration) |
| Availability | Very high (no single leader to fail) |
| Conflict handling | Read repair, anti-entropy, versioning |
| Use case | Highly available systems, Cassandra, Riak, DynamoDB |

---

## Write-Ahead Log (WAL)

### How It Works

```
1. Client sends write
2. Write appended to WAL on disk (sequential write = fast)
3. Write applied to in-memory data structures
4. Acknowledgment sent to client
5. Periodically: in-memory data flushed to main storage (checkpoint)
6. Old WAL segments discarded after checkpoint
```

### Why It Matters for Architecture

- **Durability:** Data survives crashes (replay WAL on recovery)
- **Replication foundation:** Followers consume WAL entries to replicate state
- **CDC source:** Change Data Capture reads from WAL to stream changes externally
- **Performance:** Sequential disk writes (WAL) are 100x faster than random writes

---

## Change Data Capture (CDC)

### Pattern

```
[Application] → writes → [Database]
                              │
                         [WAL / Transaction Log]
                              │
                      [CDC Connector (Debezium)]
                              │
                    [Message Broker (Kafka)]
                      /       |        \
               [Search]  [Cache]  [Analytics]
```

### Log-Based CDC Advantages

| Advantage | Detail |
|---|---|
| No performance impact | Reads from existing transaction log |
| Complete capture | Every insert, update, delete captured |
| No schema changes | No triggers, no audit columns needed |
| Low latency | Near-real-time change propagation |
| Ordered | Changes arrive in transaction order |

### Use Cases

| Use case | Pattern |
|---|---|
| Search index sync | DB → CDC → Kafka → Elasticsearch consumer |
| Cache invalidation | DB → CDC → Kafka → Redis invalidation consumer |
| Analytics pipeline | DB → CDC → Kafka → data warehouse consumer |
| Microservice data sync | DB → CDC → Kafka → other service consumer |
| Audit log | DB → CDC → Kafka → immutable audit store |

### Debezium Configuration Essentials

- **Snapshot mode:** `initial` (full snapshot on first start), `schema_only` (only schema, start from current WAL position)
- **Tombstone events:** Enable for Kafka log compaction (key with null value = delete)
- **Heartbeat:** Configure heartbeat interval to advance WAL position even during idle periods (prevents WAL accumulation)

---

## CQRS (Command Query Responsibility Segregation)

### When CQRS Is Warranted

| Criterion | Threshold |
|---|---|
| Read/write ratio | >10:1 (reads dominate) |
| Query patterns | Reads need different data shape than writes |
| Scale requirements | Read and write sides need independent scaling |
| Consistency tolerance | Reads can tolerate eventual consistency |

### Architecture

```
Commands (writes) → [Write Model] → [Primary DB (normalized)]
                                          │
                                     [CDC / Events]
                                          │
Queries (reads) ← [Read Model] ← [Read Store (denormalized)]
```

### Read Store Options

| Option | Best for |
|---|---|
| Materialized views (same DB) | Simple cases, low latency |
| Read replicas | Same query patterns, just more read capacity |
| Redis / cache | Extreme read performance, pre-computed results |
| Elasticsearch | Full-text search, complex filtering |
| Dedicated read database | Different data model optimized for queries |

### Trade-offs

| Benefit | Cost |
|---|---|
| Independent scaling of reads and writes | Operational complexity (two data stores) |
| Optimized read models | Eventual consistency between write and read |
| Different storage per access pattern | More code to maintain (projections, consumers) |

---

## Materialized Views

### Refresh Strategies

| Strategy | Freshness | Cost | Best for |
|---|---|---|---|
| Eager (on write) | Immediate | High write overhead | Small, critical views |
| Lazy (on read miss) | Stale until accessed | Read latency spike on miss | Rarely accessed views |
| Periodic (cron/scheduled) | Up to refresh interval stale | Predictable, batch efficient | Analytics dashboards |
| CDC-driven | Near-real-time | Moderate (streaming infrastructure) | Operational views, search indexes |

---

## Polyglot Persistence

### Pattern

Use multiple databases, each optimized for its access pattern:

```
Source of truth: PostgreSQL (normalized, ACID)
     │
     ├── Cache: Redis (hot data, sub-ms reads)
     ├── Search: Elasticsearch (full-text, faceted)
     ├── Analytics: ClickHouse (aggregations, time-series)
     └── Graph: Neo4j (relationship queries)
```

### Keeping Stores in Sync

| Approach | Consistency | Reliability |
|---|---|---|
| CDC + event streaming | Eventual (seconds) | High (retryable, ordered) |
| Dual write | Immediate (if both succeed) | Low (partial failure = inconsistency) |
| Application events | Eventual | Medium (depends on delivery guarantees) |

**Rule:** Never dual-write. Use the outbox pattern or CDC for reliable synchronization.

### When Polyglot Persistence Is Justified

- Different access patterns genuinely need different storage engines
- Single database cannot meet performance requirements for all query types
- Team has operational capacity to manage multiple data stores
- Data sync complexity is understood and accepted

---

## Connection Management

### Pool Sizing

**HikariCP formula:** `connections = (core_count × 2) + effective_spindle_count`

| Server | Cores | Storage | Pool size |
|---|---|---|---|
| 4-core, SSD | 4 | SSD (spindle=1) | 9 |
| 8-core, SSD | 8 | SSD (spindle=1) | 17 |
| 16-core, NVMe | 16 | NVMe (spindle=0) | 32 |

### Query Timeout Configuration

| Timeout type | Typical value | Purpose |
|---|---|---|
| Connection acquisition | 1-3 seconds | Detect pool exhaustion |
| Statement timeout | 5-30 seconds | Kill runaway queries |
| Idle connection timeout | 5-10 minutes | Return unused connections |
| Max connection lifetime | 30 minutes | Prevent stale connections |

### Slow Query Detection

- Log queries exceeding threshold (e.g., >100ms)
- Track query frequency and duration distribution
- Alert on sudden changes in query patterns
- Use `EXPLAIN ANALYZE` to understand slow query plans

---

## Index Design

### Principles

| Principle | Detail |
|---|---|
| Index columns in WHERE, JOIN, ORDER BY | These are the access paths |
| Column order in composite index matters | Most selective column first for equality; range column last |
| Covering index avoids table lookup | Include all columns needed by query in index |
| Partial index for filtered subsets | `CREATE INDEX ON orders(status) WHERE status = 'pending'` |
| Don't over-index | Each index slows writes and consumes storage |

### When NOT to Index

- Tables with very high write volume and few reads
- Columns with very low cardinality (boolean, status with 3 values) — unless combined with high-cardinality column
- Temporary/staging tables
- Tables that are frequently truncated and reloaded

---

## Storage Tiering

### Hot / Warm / Cold Strategy

| Tier | Access frequency | Storage type | Cost | Example |
|---|---|---|---|---|
| Hot | Frequent (current data) | SSD, in-memory | $$$ | Last 30 days of orders |
| Warm | Occasional (recent history) | Standard SSD, HDD | $$ | Last 1-2 years |
| Cold | Rare (archive/compliance) | Object storage (S3, GCS) | $ | Older than 2 years |

### Implementation Patterns

- **Time-based partitioning:** Partition tables by month/year. Move old partitions to cheaper storage.
- **TTL-based archival:** Automatic deletion or archival after retention period.
- **Tiered storage in databases:** Some databases support native tiering (e.g., TimescaleDB tiered storage, Elasticsearch ILM).

### Data Lifecycle

```
Write → Hot (SSD, indexed, queryable)
  → After 30 days → Warm (cheaper storage, still queryable)
    → After 1 year → Cold (object storage, batch queryable only)
      → After 7 years → Delete (or permanent archive for compliance)
```
