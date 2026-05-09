# Messaging and Streaming

## Message Queues vs Event Streams

### Fundamental Difference

| Aspect | Message Queue | Event Stream |
|---|---|---|
| Model | Point-to-point (one consumer per message) | Publish-subscribe (multiple consumers) |
| After consumption | Message deleted | Message retained (configurable period) |
| Replay | Not possible (message gone) | Possible (seek to any offset) |
| Consumer model | Broker pushes to consumer | Consumer pulls at own pace |
| Ordering | Per-queue (FIFO) | Per-partition |
| Throughput | Moderate (per-message ack overhead) | Very high (batch-oriented) |

### When to Use What

| Scenario | Choice | Why |
|---|---|---|
| Task distribution (background jobs) | Queue (SQS, RabbitMQ) | Work item consumed once, then done |
| Event sourcing | Stream (Kafka) | Need complete event history, replay |
| Multiple independent consumers | Stream (Kafka) | Each consumer group reads independently |
| Request-reply pattern | Queue (RabbitMQ) | Built-in reply-to semantics |
| Simple decoupling, low volume | Queue (SQS) | Simpler operations, managed service |
| High-throughput event log | Stream (Kafka, Redpanda) | Optimized for append-only, high volume |
| CDC propagation | Stream (Kafka) | Ordered, replayable, multi-consumer |

---

## Delivery Guarantees

### Three Levels

| Guarantee | How | Risk |
|---|---|---|
| At-most-once | Send and forget (no retry) | Message may be lost |
| At-least-once | Retry until acknowledged | Message may be processed multiple times |
| Exactly-once | At-least-once + idempotent consumer | No loss, no duplicates (requires work) |

### Achieving Exactly-Once Processing

True exactly-once delivery is nearly impossible in distributed systems. Instead, achieve **effectively-once** through:

```
At-least-once delivery (broker retries)
  + Idempotent consumer (deduplicates on processing)
  = Effectively-once processing
```

### Kafka Exactly-Once (Transactions)

```
Producer:
  enable.idempotence=true          // Deduplicates producer retries
  transactional.id=my-producer     // Enables transactions

Consumer:
  isolation.level=read_committed   // Only see committed messages

Transaction flow:
  1. producer.beginTransaction()
  2. producer.send(record1)
  3. producer.send(record2)
  4. producer.sendOffsetsToTransaction(offsets)  // Atomic with messages
  5. producer.commitTransaction()
```

All messages in a transaction are atomically committed (all visible or none).

---

## Dead Letter Queues (DLQ)

### Pattern

```
Main Queue → Consumer → Process
                │
           (fails N times)
                │
                ▼
          Dead Letter Queue → Investigation → Manual replay
```

### Configuration

| Parameter | Typical value | Purpose |
|---|---|---|
| Max retries before DLQ | 3-5 | Avoid infinite retry loops |
| DLQ retention period | 14-30 days | Time for investigation |
| DLQ alarm threshold | >0 messages | Alert on poison messages |

### DLQ Processing Workflow

1. **Alert** on messages arriving in DLQ
2. **Investigate** the message: check payload, error logs, downstream service state
3. **Fix** the root cause (bug, data issue, service outage)
4. **Replay** messages from DLQ back to main queue
5. **Monitor** for the same failure pattern

### FIFO Queue + DLQ Caveat

Moving a message to DLQ breaks ordering. The message is removed from its position in the FIFO. If order matters, consider:
- Blocking the entire queue until the message succeeds (dangerous but preserves order)
- Using per-key ordering (partition key) so only one key's messages are affected

---

## Ordering Guarantees

### Levels of Ordering

| Level | Guarantee | How | Trade-off |
|---|---|---|---|
| No ordering | Messages may arrive in any order | Multiple partitions, any assignment | Maximum throughput |
| Partition-level | Messages with same key ordered within partition | Hash key → partition | Good balance |
| Global | All messages globally ordered | Single partition | Severe throughput limit |

### Kafka Partition-Level Ordering

```
Topic: orders (8 partitions)

Producer sends with key=user_id:
  user_123 → hash("user_123") % 8 = partition 3
  user_456 → hash("user_456") % 8 = partition 7

All events for user_123 are in partition 3, in order.
Events for different users may be in different partitions, unordered relative to each other.
```

**Rule:** Choose the partition key carefully. All messages with the same key go to the same partition (and thus the same consumer).

### When Global Order Matters

Almost never. Ask: "Do I need ALL messages ordered, or just messages for the same entity?"

Usually partition-level ordering (per user, per account, per order) is sufficient.

---

## Consumer Groups

### How They Work (Kafka)

```
Topic: events (6 partitions)
Consumer Group: my-service (3 consumers)

Assignment:
  Consumer 1: partitions 0, 1
  Consumer 2: partitions 2, 3
  Consumer 3: partitions 4, 5
```

- Each partition assigned to exactly one consumer in the group
- Adding consumer: triggers rebalance, partitions redistributed
- Max useful consumers = number of partitions
- Consumer failure: partitions reassigned to surviving consumers

### Scaling

| Consumers | Partitions | Result |
|---|---|---|
| 3 consumers | 6 partitions | 2 partitions each (optimal) |
| 6 consumers | 6 partitions | 1 partition each (maximum parallelism) |
| 8 consumers | 6 partitions | 2 consumers idle (over-provisioned) |

**Rule:** Number of partitions = maximum parallelism for a consumer group. Plan partition count for future scaling.

### Consumer Lag Monitoring

```
Consumer lag = latest offset - consumer's committed offset

If lag is growing: consumer can't keep up with production rate
If lag is stable: consumer matches production rate
If lag is zero: consumer is caught up
```

**Alert thresholds:**
- Warning: lag > 1000 messages (or > 30 seconds)
- Critical: lag > 10000 messages (or > 5 minutes)

---

## Fan-Out / Fan-In Patterns

### Fan-Out: One Event → Multiple Consumers

**Kafka approach:** Multiple consumer groups subscribe to same topic.
```
Topic: order-events
  → Consumer Group: billing-service     (independent offset)
  → Consumer Group: inventory-service   (independent offset)
  → Consumer Group: notification-service (independent offset)
  → Consumer Group: analytics-service   (independent offset)
```

Each group reads all messages independently. Message stored once.

**AWS approach:** SNS → multiple SQS queues.
```
SNS Topic: order-events
  → SQS: billing-queue
  → SQS: inventory-queue
  → SQS: notification-queue
```

### Fan-In: Multiple Sources → Single Stream

```
Service A → produces → Topic: audit-events
Service B → produces → Topic: audit-events
Service C → produces → Topic: audit-events

Consumer: audit-service reads all events from audit-events topic
```

Use fan-in for centralized logging, audit trails, and aggregated analytics.

---

## Technology Comparison

| Feature | Kafka | RabbitMQ | SQS | NATS |
|---|---|---|---|---|
| Model | Log-based stream | Message queue + streams | Managed queue | Message bus |
| Ordering | Per-partition | Per-queue | Per-group (FIFO) or none | Per-subject |
| Retention | Configurable (days-months) | Until consumed | 4-14 days | In-memory (default) |
| Replay | Yes (seek to offset) | No (unless using streams) | No | JetStream: yes |
| Throughput | Very high (1M+ msg/s per cluster) | Moderate (10K-100K msg/s) | High (managed, scales) | Very high (10M+ msg/s) |
| Latency | Low (2-10ms) | Very low (<1ms) | Moderate (20-100ms) | Ultra-low (<1ms) |
| Exactly-once | Yes (transactions) | No (at-least-once) | No (at-least-once) | JetStream: at-least-once |
| Operations | Complex (ZK/KRaft, brokers) | Moderate | None (managed) | Simple |
| Best for | Event streaming, CDC, high throughput | Task queues, request-reply | Simple queuing, serverless | Real-time messaging, IoT |

### Selection Guide

| Priority | Choose |
|---|---|
| Operational simplicity | SQS (managed) or NATS (simple) |
| High throughput + replay | Kafka or Redpanda |
| Low latency messaging | NATS or RabbitMQ |
| Task distribution | RabbitMQ or SQS |
| Event sourcing | Kafka |
| Already on AWS, simple needs | SQS + SNS |

---

## Event Schema Evolution

### Compatibility Types

| Type | Rule | Safe changes |
|---|---|---|
| Backward compatible | New schema can read old data | Add optional fields, add defaults |
| Forward compatible | Old schema can read new data | Remove optional fields |
| Full compatible | Both directions | Add/remove optional fields with defaults |

### Schema Registry

```
Producer → serialize with schema v3 → Kafka → deserialize with schema v3 → Consumer
                                                        ↑
                                               Schema Registry
                                          (stores all schema versions,
                                           enforces compatibility)
```

### Best Practices

- **Always use a schema** (protobuf, Avro, JSON Schema). Schemaless events cause runtime failures.
- **Set compatibility mode** to BACKWARD (consumers can always read older events).
- **Never remove required fields** or change field types without a migration plan.
- **Version your events:** Include event type and version in the message envelope.

```json
{
  "event_type": "OrderCreated",
  "event_version": 3,
  "timestamp": "2024-01-15T10:30:00Z",
  "data": { ... }
}
```
