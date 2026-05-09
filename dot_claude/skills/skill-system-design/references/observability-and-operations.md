# Observability and Operations

## Three Pillars

| Pillar | What | Cost | Strength |
|---|---|---|---|
| Metrics | Aggregated numerical data over time | Low (fixed cardinality) | Trends, alerting, dashboards |
| Logs | Detailed event records | High at scale (volume) | Debugging specific incidents |
| Traces | Request flow across services | Moderate (sampling helps) | Understanding distributed call chains |

### When to Use Each

| Question | Use |
|---|---|
| "Is the system healthy right now?" | Metrics (dashboard) |
| "Why did this specific request fail?" | Traces + logs |
| "What changed that caused the spike?" | Metrics (diff before/after) + logs |
| "Where is time being spent in this request?" | Traces (span timing) |
| "How many errors happened in the last hour?" | Metrics (counter) |
| "What was the exact error message?" | Logs |

---

## SLIs, SLOs, SLAs

### Definitions

| Term | What | Who sets it | Example |
|---|---|---|---|
| SLI (Indicator) | Measured metric of service quality | Engineering | 99.2% of requests succeed in <200ms |
| SLO (Objective) | Target for the SLI | Engineering + Product | 99.5% of requests should succeed in <200ms |
| SLA (Agreement) | Contract with customers, with consequences | Business + Legal | We guarantee 99.9% uptime or credits |

### Choosing Good SLIs

| Service type | SLI candidates |
|---|---|
| Request-serving | Availability (non-5xx), latency (P50, P99), correctness |
| Data processing pipeline | Freshness (data age), completeness (% processed), throughput |
| Storage | Availability, latency, durability |

**Rule:** SLIs should measure what users experience, not internal system metrics. "Database CPU < 80%" is not an SLI. "99% of queries complete in <100ms" is.

### Error Budget

```
SLO: 99.9% availability
Error budget: 0.1% = 43.2 minutes/month

Budget remaining = 43.2 - actual_downtime_minutes
```

**Error budget policy:**
- Budget remaining > 50%: Ship features freely, take calculated risks
- Budget remaining 20-50%: Proceed with caution, ensure rollback plans
- Budget remaining < 20%: Only ship reliability improvements
- Budget exhausted: Feature freeze until budget replenishes next period

---

## RED Method (for Services)

| Metric | What to measure | Alert on |
|---|---|---|
| **R**ate | Requests per second | Sudden drops (outage) or spikes (attack/traffic surge) |
| **E**rrors | Failed requests per second (and error rate %) | Error rate exceeding threshold (e.g., >1%) |
| **D**uration | Latency distribution (P50, P95, P99) | P99 exceeding SLO target |

**Apply to:** Every service that serves requests. Consistent across services for uniform observability.

---

## USE Method (for Resources)

| Metric | What to measure | Alert on |
|---|---|---|
| **U**tilization | % of time resource is busy | Sustained >80% |
| **S**aturation | Degree of queuing (work that can't be served) | Queue depth growing |
| **E**rrors | Error count from the resource | Any non-zero (for hardware errors) |

**Apply to:** CPU, memory, disk, network, GPU, thread pools, connection pools, message queues.

**Combination:** USE for infrastructure layer + RED for application layer = comprehensive monitoring.

---

## OpenTelemetry

### Core Concepts

```
Trace: End-to-end journey of a single request
  └── Span: A single operation within the trace
        ├── Attributes: key-value metadata (http.method, db.statement)
        ├── Events: timestamped log entries within the span
        └── Status: ok, error, unset
```

### Context Propagation

```
Client → [traceparent: 00-<trace-id>-<span-id>-01] → Service A
Service A → [traceparent: 00-<trace-id>-<new-span-id>-01] → Service B
```

W3C Trace Context header carries trace ID across service boundaries. All spans with the same trace ID form one trace.

### Sampling Strategies

| Strategy | How | Pros | Cons |
|---|---|---|---|
| Head-based | Decide at request start (random %) | Simple, low overhead | May miss interesting traces |
| Tail-based | Decide after trace completes | Can keep errors/slow traces | Higher overhead, requires collector buffering |
| Rate-based | Keep N traces per second | Predictable cost | May miss patterns in high-traffic endpoints |
| Always-on | 100% sampling | Complete data | Expensive at scale |

**Recommendation:** Head-based sampling at 1-10% for production. 100% for errors and slow requests (tail-based for these).

### Instrumentation Approach

1. **Automatic instrumentation** for HTTP servers/clients, database drivers, message brokers
2. **Manual instrumentation** for business logic spans (e.g., "process-payment", "validate-order")
3. **Semantic conventions** for attribute names (follow OpenTelemetry standard)

---

## Alerting

### Symptom-Based Alerting

**Bad (cause-based):** "Alert when CPU > 80%"
**Good (symptom-based):** "Alert when P99 latency > 500ms for 5 minutes"

Symptom-based alerts fire when users are affected. Cause-based alerts create noise — high CPU doesn't always mean degraded service.

### Multi-Window, Multi-Burn-Rate Alerting

For SLO-based alerting, detect different severities at different speeds:

| Window | Burn rate | Meaning | Action |
|---|---|---|---|
| 5 minutes | 14.4x | Burning entire monthly budget in 5 hours | Page immediately |
| 30 minutes | 6x | Burning budget in ~3.5 days | Page |
| 6 hours | 1x | Consuming at budget rate | Ticket |

**Formula:** `burn_rate = error_rate / (1 - SLO)`

```
SLO: 99.9% → allowed error rate: 0.1%
If actual error rate: 1.44% → burn rate = 1.44% / 0.1% = 14.4x
```

### Alert Fatigue Prevention

- **Group related alerts.** Don't fire 10 alerts for one incident.
- **Require action.** Every alert should have a clear action. If no action → make it a dashboard metric, not an alert.
- **Tune thresholds.** False alarms erode trust. Adjust based on history.
- **Escalation policy.** Page → if not acked in 5m → escalate to secondary → if not acked → escalate to manager.

---

## Deployment Strategies

### Canary Deployment

```
Step 1: Deploy to 1-5% of traffic
Step 2: Monitor for 15-30 minutes (error rate, latency, business metrics)
Step 3: If healthy → increase to 25% → 50% → 100%
Step 4: If unhealthy → rollback to 0%
```

**Automated canary analysis:** Compare canary metrics to baseline (control group) using statistical tests. Tools: Kayenta (Netflix/Spinnaker), Flagger (Kubernetes).

### Blue-Green Deployment

```
Before: Router → Blue (v1.0) [active]
                 Green (v1.1) [testing]
After:  Router → Green (v1.1) [active]
                 Blue (v1.0) [standby/rollback]
```

Instant rollback by switching router. 2x infrastructure cost during deployment.

### Feature Flags

Decouple deployment from feature release:

```
deploy(code_with_new_feature)       // Feature is deployed but OFF
enable_flag("new_checkout", 5%)     // Enable for 5% of users
monitor_metrics()                   // Watch for issues
enable_flag("new_checkout", 100%)   // Full rollout
remove_flag("new_checkout")         // Clean up
```

**Flag lifecycle:** Temporary flags should have expiration dates. Permanent flags become tech debt.

---

## Incident Response

### Lifecycle

```
1. Detect    → Monitoring alerts fire
2. Triage    → Assess severity, assign incident commander
3. Mitigate  → Restore service (rollback, failover, scale up)
4. Resolve   → Fix root cause
5. Postmortem → Document, learn, prevent recurrence
```

### Mitigation Priority

**First priority:** Restore service, not find root cause.

| Mitigation | When |
|---|---|
| Rollback last deploy | Deploy correlated with incident start |
| Failover to standby | Primary region/instance unhealthy |
| Scale up | Resource exhaustion under load |
| Feature flag disable | New feature causing errors |
| Rate limit | Traffic spike or attack |
| Restart | Service in bad state (memory leak, deadlock) |

### Postmortem Structure

1. **Summary:** What happened, duration, impact
2. **Timeline:** Key events with timestamps
3. **Root cause:** What actually broke and why
4. **Contributing factors:** What made it worse (monitoring gap, slow detection)
5. **Action items:** Concrete, assigned, with deadlines
6. **What went well:** What worked in the response

**Blameless:** Focus on systems and processes, not individuals.

---

## Security at Scale

### Zero-Trust Networking

**Principle:** Never trust, always verify. Every request authenticated and authorized, regardless of network location.

| Component | Implementation |
|---|---|
| Service identity | mTLS certificates, SPIFFE workload identity |
| Authentication | mTLS for service-to-service, JWT/OAuth for users |
| Authorization | Per-request policy evaluation (OPA, Istio authorization) |
| Encryption | TLS everywhere, encrypt at rest |
| Network segmentation | Allow-list policies, deny by default |

### mTLS (Mutual TLS)

Both client and server present certificates:
```
Client → [client cert] → Server (verifies client identity)
Server → [server cert] → Client (verifies server identity)
```

**Service mesh integration:** Istio/Linkerd handle mTLS automatically. No application code changes.

### API Gateway Patterns

| Function | How |
|---|---|
| Authentication | Validate JWT/API key before forwarding to backend |
| Rate limiting | Token bucket per client/endpoint |
| Request validation | Schema validation, payload size limits |
| TLS termination | Handle HTTPS at gateway, plain HTTP internally |
| Routing | Path-based routing to backend services |

---

## Cost Optimization

### Right-Sizing

- **Monitor actual resource usage** (CPU, memory, disk) over 14+ days
- **Right-size instances:** Most instances are over-provisioned by 30-50%
- **Downsize gradually:** Reduce by one size, monitor for 1 week, repeat

### Instance Strategy

| Strategy | Savings | Best for |
|---|---|---|
| On-demand | Baseline (0%) | Unpredictable, short-term workloads |
| Reserved (1-3 year) | 30-75% | Steady baseline workloads |
| Spot / preemptible | 60-90% | Stateless, fault-tolerant, batch jobs |
| Savings plans | 20-50% | Flexible commitment across instance types |

**Hybrid strategy:** Reserved for baseline + spot for elastic + on-demand for spike overflow.

### Data Transfer Costs

- Cross-region transfer: $0.01-0.02/GB (adds up fast at scale)
- Same-region, cross-AZ: $0.01/GB
- Same AZ: Free
- **Optimize:** Colocate communicating services in same AZ. Use compression. Cache at edge.

### Storage Tiering

| Tier | AWS example | Cost (approx) | Access |
|---|---|---|---|
| Hot | EBS gp3, S3 Standard | $$$ | Frequent |
| Warm | S3 Infrequent Access | $$ | Monthly |
| Cold | S3 Glacier | $ | Rarely |
| Archive | S3 Glacier Deep Archive | ¢ | Almost never |

Automate lifecycle policies to move data through tiers based on access patterns and age.
