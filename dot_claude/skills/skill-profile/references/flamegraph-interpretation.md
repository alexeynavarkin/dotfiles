# Flame Graph Interpretation

## What Is a Flame Graph

Flame graphs are visualizations of hierarchical profiling data, invented by Brendan Gregg. They show where a program spends time (or allocates memory) by displaying aggregated stack traces.

### Axes

- **X-axis**: Population (proportion of samples). **NOT time.** Frames are sorted alphabetically, not chronologically. Width = frequency in the profile.
- **Y-axis**: Stack depth. Bottom = root (e.g., `main`). Top = leaf functions (where execution actually happens).
- **Width**: Proportional to the number of samples containing that function. Wider = more frequently sampled = more time/allocations.
- **Color**: Usually random or by category (Go runtime vs application code). **Not meaningful** unless explicitly configured.

### Key Insight

**Look at the top.** The widest frames at the top of the graph are leaf functions — they represent where time is actually spent (or allocations actually happen). A wide frame at the bottom just means it's a common entry point (e.g., `main`, `http.Handler`).

---

## Flame Graph Types

### CPU Flame Graph

Shows where CPU time is spent. Generated from CPU profiles (sampling at ~100Hz).

```bash
# Generate from Go pprof
go tool pprof -http=:8080 cpu.pb.gz
# Navigate to "Flame Graph" view
```

### Off-CPU Flame Graph

Shows where goroutines/threads are blocked (I/O, network, locks, sleep). Generated from block profiles, wall-clock profiles (fgprof), or trace data.

Useful when: CPU utilization is low but latency is high.

### Memory Flame Graph

Shows allocation sites. Generated from heap profiles (`alloc_space` for allocation rate, `inuse_space` for current memory).

```bash
go tool pprof -http=:8080 -sample_index=alloc_space heap.pb.gz
```

### Differential Flame Graph

Compares two profiles. Highlights regressions (red/wider) and improvements (blue/narrower).

```bash
go tool pprof -http=:8080 -diff_base=before.pb.gz after.pb.gz
```

---

## How to Read a Flame Graph

### Step-by-Step Strategy

1. **Scan the top edge** for the widest plateaus. These are the leaf functions consuming the most CPU/memory.

2. **Measure width** — if a top-level frame takes 20%+ of the total width, it's a significant hotspot worth investigating.

3. **Trace downward** from a wide top frame to understand the call chain that leads to it.

4. **Ignore narrow spikes** — they represent functions called rarely. Focus on the wide bars.

5. **Compare widths, not heights.** A deep but narrow stack is not a problem. A shallow but wide frame is.

6. **Look for unexpected width** — `runtime.mallocgc` taking 30% means allocation overhead. `encoding/json.Marshal` taking 25% means serialization is a bottleneck.

### Self-Time vs Total-Time

- **Self-time** (flat): The portion of a bar's width that has no child bars above it. This is time spent in the function's own code.
- **Total-time** (cumulative): The full width of the bar, including all callees.

A function with wide total-time but no self-time is just a dispatcher — its callees are the bottleneck.

---

## Common Patterns in Go Flame Graphs

### GC Domination

**Pattern**: Wide bars for `runtime.gcBGMarkWorker`, `runtime.mallocgc`, `runtime.gcDrain`, `runtime.gcMarkDone`.

**Meaning**: Application is allocation-heavy. GC is consuming significant CPU.

**Action**:
- Profile with `alloc_space` to find allocation hotspots
- Reduce allocations: pre-allocate, use sync.Pool, avoid interface boxing
- Tune GOGC (higher value = less frequent GC) or set GOMEMLIMIT
- Check escape analysis (`-gcflags='-m'`)

### Lock Contention

**Pattern**: Wide bars for `sync.(*Mutex).Lock`, `sync.(*RWMutex).RLock`, `runtime.semacquire`, `runtime.lock2`.

**Meaning**: Goroutines spending significant time waiting for locks.

**Action**:
- Profile with mutex profiler to find the contended lock
- Consider sharding the protected data structure
- Switch to `sync.RWMutex` if reads >> writes
- Use `sync/atomic` for simple counters/flags
- Reduce critical section size (do less work while holding the lock)

### Serialization Hotspot

**Pattern**: Wide bars for `encoding/json.Marshal`, `encoding/json.Unmarshal`, `proto.Marshal`, `fmt.Sprintf`.

**Meaning**: Serialization/deserialization is a major CPU consumer.

**Action**:
- For JSON: consider `github.com/goccy/go-json`, `github.com/bytedance/sonic`, or `github.com/segmentio/encoding`
- For protobuf: use `vtprotobuf` for generated fast marshaling
- Cache serialized results when inputs repeat
- Avoid `fmt.Sprintf` in hot paths — use `strconv` or `strings.Builder`
- Consider binary formats if human-readability isn't needed

### Syscall Heavy

**Pattern**: Wide bars for `syscall.Syscall`, `syscall.Syscall6`, `runtime.entersyscall`.

**Meaning**: Application is making many system calls (file I/O, network, etc.).

**Action**:
- Use `bufio.Writer`/`bufio.Reader` to batch I/O
- Check for unnecessary file opens/closes in loops
- Connection pooling for network calls
- `io.Copy` for file-to-socket transfers (uses `sendfile`)

### Goroutine Scheduling Overhead

**Pattern**: Wide bars for `runtime.mcall`, `runtime.schedule`, `runtime.findRunnable`, `runtime.park_m`.

**Meaning**: Too many goroutines competing for execution or frequent goroutine switches.

**Action**:
- Check goroutine count (`runtime.NumGoroutine()`)
- Use bounded worker pools instead of goroutine-per-request
- Reduce channel operations in tight loops
- Check for goroutine leaks (goroutines that never exit)

### Reflection Overhead

**Pattern**: Wide bars for `reflect.Value.call`, `reflect.Value.Set`, `reflect.TypeOf`, `reflect.DeepEqual`.

**Meaning**: Reflection-heavy code in hot paths.

**Action**:
- Replace `reflect.DeepEqual` with type-specific comparison
- Use code generation instead of reflection (e.g., `go generate`)
- Use generics (Go 1.18+) to eliminate reflection-based dispatch
- Cache reflected types/values if they don't change

### String Operations

**Pattern**: Wide bars for `runtime.stringtoslicebyte`, `runtime.slicebytetostring`, `runtime.concatstrings`, `runtime.rawstringtmp`.

**Meaning**: Excessive string ↔ []byte conversions or string concatenation.

**Action**:
- Use `strings.Builder` for concatenation
- Work in `[]byte` throughout, convert once at boundaries
- Use `strconv.AppendInt` etc. to build into existing buffers
- Check for unnecessary `string([]byte)` in loops

---

## Differential Flame Graphs

### Generating

```bash
# Collect before profile
curl -o before.pb.gz 'http://localhost:6060/debug/pprof/profile?seconds=30'

# Deploy changes

# Collect after profile (same load conditions!)
curl -o after.pb.gz 'http://localhost:6060/debug/pprof/profile?seconds=30'

# View diff
go tool pprof -http=:8080 -diff_base=before.pb.gz after.pb.gz
```

### Reading

- **Red/wider bars**: Functions that got slower (more samples in "after").
- **Blue/narrower bars**: Functions that got faster (fewer samples in "after").
- **Gray/unchanged**: No significant change.

**Critical**: Both profiles must be collected under **the same load conditions** for the diff to be meaningful.

---

## Tools for Flame Graphs

| Tool | Notes |
|---|---|
| **pprof web UI** (`go tool pprof -http=:8080`) | Built-in, supports flame graph and icicle views |
| **Speedscope** (speedscope.app) | Browser-based, supports many formats, left-heavy and sandwich views |
| **Pyroscope UI** | Timeline + flame graph, comparison mode |
| **Grafana flame graph panel** | Integrates with Pyroscope/Tempo data sources |
| **FlameScope** | Subsecond flame graph analysis for pattern detection |

### Icicle Graphs

Icicle graphs are inverted flame graphs — roots at the top, leaves at the bottom. Same data, different visual emphasis. pprof web UI uses icicle layout by default. Both views are useful — choose whichever makes the call chain clearer for your analysis.
