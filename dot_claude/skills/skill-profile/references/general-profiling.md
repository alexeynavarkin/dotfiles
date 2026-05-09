# General Backend Profiling

## Profiling Types Taxonomy

| Type | Measures | Key Question |
|---|---|---|
| **CPU** | Time spent executing on CPU | "Where is compute time going?" |
| **Memory (heap)** | Heap allocations — live objects or total allocated | "What's using memory? Is there a leak?" |
| **Thread/Goroutine** | Thread/goroutine state and stack traces | "Are threads leaking? What are they doing?" |
| **Block/Contention** | Time waiting on locks, channels, sync primitives | "What's causing concurrency bottlenecks?" |
| **Wall-clock** | Total elapsed time (CPU + I/O + waiting) | "Where does real time go, including off-CPU?" |
| **Syscall/I/O** | System call frequency and duration | "How much time is spent in kernel/I/O?" |

### Sampling vs Instrumentation

| Approach | Overhead | Accuracy | Production-safe |
|---|---|---|---|
| **Sampling** | Low (1-5%) | Statistical — may miss short-lived events | Yes |
| **Instrumentation** | High (10-50%+) | Exact — captures every event | Generally no |

**Default to sampling** for production. Use instrumentation only in development or for targeted debugging.

---

## Continuous vs On-Demand Profiling

### Continuous Profiling

Always-on, low-overhead sampling that captures performance data over time.

**Advantages**:
- Catches intermittent issues (3 AM CPU spikes, weekend memory leaks)
- Historical data for trend analysis and regression detection
- No need to reproduce the issue to diagnose it
- Enables before/after comparison across deployments

**Overhead budget**: < 2% CPU for continuous collection. Typically 19 Hz sampling rate.

**Tools**: Grafana Pyroscope, Parca, Datadog Continuous Profiler, Google Cloud Profiler.

### On-Demand Profiling

Triggered manually or by alerts during incidents.

**When to use**:
- Deep investigation of a specific issue
- Higher-fidelity data needed (higher sampling rate)
- First-time profiling of a service

**Overhead**: 2-10% acceptable for short durations (30-60 seconds).

---

## Key Metrics Framework

### RED Method (for services)

| Metric | What it measures |
|---|---|
| **R**ate | Requests per second |
| **E**rrors | Error rate (errors/second or error percentage) |
| **D**uration | Latency distribution (P50, P90, P99) |

### USE Method (for resources)

| Metric | What it measures |
|---|---|
| **U**tilization | Percentage of time the resource is busy |
| **S**aturation | Queue length — work waiting because resource is busy |
| **E**rrors | Error count on the resource |

Apply USE to: CPU, memory, disk I/O, network, locks.

### Latency Percentiles

| Percentile | Meaning | Use for |
|---|---|---|
| **P50** (median) | Half of requests faster, half slower | General baseline |
| **P90** | 90% of requests faster than this | Service-level indicator |
| **P95** | 95% of requests faster than this | Common SLO target |
| **P99** | 99% of requests faster than this | Tail latency — user-facing quality |
| **P99.9** | 99.9% faster | Critical for high-traffic services |

**Why percentiles > averages**: An average of 100ms hides that 5% of users might see 2000ms. A single slow database query per 100 requests won't move the average but will make P99 terrible.

### Amdahl's Law for Optimization Priority

If a function accounts for 30% of CPU time, the maximum possible improvement from optimizing it is 30%. Optimizing a function that accounts for 1% of CPU time is rarely worthwhile.

**Always profile first** to identify the top contributors before optimizing.

---

## Tools by Language

### Go
- **pprof** (`runtime/pprof`, `net/http/pprof`): Built-in, zero-dependency profiling
- **go tool trace**: Execution trace for scheduler and GC analysis
- **fgprof**: Wall-clock profiler (CPU + off-CPU time)
- **Pyroscope Go SDK**: Continuous profiling with push-based collection
- **Parca Agent**: eBPF-based, no code changes, <1% overhead

### Java/JVM
- **async-profiler** (recommended): Low-overhead, avoids safepoint bias, supports CPU + allocation + lock profiling
- **Java Flight Recorder (JFR)**: Built into JDK 11+, continuous profiling with minimal overhead
- **VisualVM**: GUI-based profiling and monitoring
- **JVM flags**: `-XX:+UnlockDiagnosticVMOptions -XX:+DebugNonSafepoints` for accurate profiling

### Python
- **py-spy**: Sampling profiler, reads process memory directly, no code changes, production-safe
- **Scalene**: CPU + memory + GPU profiler with line-level granularity
- **cProfile**: Built-in, instrumentation-based (higher overhead)
- **Austin**: Frame stack sampler for CPython

### Node.js
- **`--prof` flag**: V8's built-in CPU profiler, outputs to `v8.log`
- **0x**: Flame graph generator for Node.js
- **clinic.js**: Automated diagnosis (doctor, bubbleprof, flame)

### Rust
- **cargo-flamegraph**: Wrapper around perf + flamegraph generation
- **perf**: System-level profiling (Linux)
- **flamegraph-rs**: Rust implementation of flame graph generation

### System-Level (any language)
- **Linux perf**: Hardware performance counters, tracepoints, software events
- **eBPF/bpftrace**: Programmable kernel-space tracing, minimal overhead
- **strace/dtrace**: System call tracing (strace has high overhead — use perf-trace in production)

---

## Production Profiling Safety

### Overhead Budgets

| Profiling mode | Acceptable overhead | Duration |
|---|---|---|
| Continuous (always-on) | < 2% CPU | Indefinite |
| Targeted investigation | < 5% CPU | 30-60 seconds |
| Deep analysis (staging) | < 10% CPU | As needed |

### Safety Checklist

1. **Separate profiling port from public API** — Never expose profiling endpoints on the application's public port.
2. **Authentication on profiling endpoints** — Restrict access. Profile data contains internal function names, file paths, and potentially sensitive logic.
3. **Sampling rate limits** — Enforce minimum sampling intervals (e.g., 10ms for CPU profiling = 100 Hz max).
4. **Duration limits** — Cap CPU profile duration (60s max) and trace duration (10s max) in production.
5. **Circuit breaker** — Auto-disable profiling if latency increases > 5% over baseline. Cooldown period before re-enabling.
6. **Profile one replica at a time** — Don't profile all instances simultaneously.
7. **Resource limits for profiler sidecars** — CPU: 200m, Memory: 256Mi as starting limits.
8. **Data retention** — Implement retention policies for profile data (7-14 days typical for continuous profiling).

### Never in Production

- Block/mutex profiling at rate=1 (every event)
- Allocation tracing (`allocfreetrace=1`)
- Instrumentation-based profiling
- Execution traces longer than 10 seconds

---

## Statistical Significance

### Why Single Profiles Are Misleading

A single 30-second CPU profile is a statistical sample. Short-lived functions may not appear. Background GC or OS scheduling can skew results.

### Collecting Reliable Data

1. **Multiple samples**: Collect 3-5 profiles under the same conditions and look for consistency.
2. **Representative load**: Profile under realistic traffic patterns, not synthetic benchmarks (unless benchmarking).
3. **Stable environment**: Avoid profiling during deployments, autoscaling events, or other disruptions.
4. **Sufficient duration**: CPU profiles should be at least 30 seconds. Shorter profiles have higher variance.

### Noise Sources

| Source | Impact | Mitigation |
|---|---|---|
| GC timing | Spikes in allocation-related functions | Collect longer profiles; check gctrace |
| OS scheduling | Thread preemption artifacts | Use isolated CPUs or profile longer |
| Thermal throttling | Variable CPU speed | Monitor CPU frequency; climate-controlled environment |
| Background processes | Competing for CPU/memory | Minimize co-located workloads |
| Network jitter | Variable I/O latency | Profile compute-bound paths separately |

### Before/After Comparison

Always compare under the same conditions:
- Same load pattern and concurrency
- Same hardware/container resources
- Same dataset or similar data distribution
- Multiple runs with statistical comparison (benchstat for Go)
