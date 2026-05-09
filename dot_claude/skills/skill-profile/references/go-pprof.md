# Go Profiling with pprof

## Enabling pprof

### For HTTP servers — `net/http/pprof`

Import as a side-effect to register handlers on `DefaultServeMux`:

```go
import _ "net/http/pprof"

func main() {
    // IMPORTANT: serve on a separate internal port, not the public API port
    go func() {
        log.Println(http.ListenAndServe("localhost:6060", nil))
    }()

    // Your application server on the public port
    http.ListenAndServe(":8080", appRouter)
}
```

If using a custom mux (chi, gorilla, etc.), register handlers explicitly:

```go
import "net/http/pprof"

debugMux := http.NewServeMux()
debugMux.HandleFunc("/debug/pprof/", pprof.Index)
debugMux.HandleFunc("/debug/pprof/cmdline", pprof.Cmdline)
debugMux.HandleFunc("/debug/pprof/profile", pprof.Profile)
debugMux.HandleFunc("/debug/pprof/symbol", pprof.Symbol)
debugMux.HandleFunc("/debug/pprof/trace", pprof.Trace)
go http.ListenAndServe("localhost:6060", debugMux)
```

### For CLI programs — `runtime/pprof`

```go
import (
    "os"
    "runtime/pprof"
)

func main() {
    // CPU profile
    f, _ := os.Create("cpu.pb.gz")
    defer f.Close()
    pprof.StartCPUProfile(f)
    defer pprof.StopCPUProfile()

    // ... program logic ...

    // Heap profile (at end or at specific point)
    hf, _ := os.Create("heap.pb.gz")
    defer hf.Close()
    pprof.WriteHeapProfile(hf)
}
```

### Collecting named profiles programmatically

```go
// Goroutine profile
p := pprof.Lookup("goroutine")
f, _ := os.Create("goroutine.pb.gz")
p.WriteTo(f, 0) // 0 = binary proto, 1 = human-readable text

// Mutex profile
p = pprof.Lookup("mutex")
p.WriteTo(f, 0)
```

---

## Profile Types in Detail

### CPU Profile

**What it captures**: Stack traces sampled at ~100Hz (every 10ms) via SIGPROF. Shows where CPU time is spent.

**Collection**:
```bash
# From running service (30s default)
go tool pprof http://localhost:6060/debug/pprof/profile?seconds=30

# Save to file
curl -o cpu.pb.gz 'http://localhost:6060/debug/pprof/profile?seconds=30'
```

**Interpretation**: High `flat` time = function itself is expensive. High `cum` time = function's callees are expensive. Start with `top -cum` to find the call chains, then `list <func>` to see line-level attribution.

### Heap Profile

**Four views** (controlled by `-sample_index`):

| View | Shows | Use for |
|---|---|---|
| `inuse_space` (default) | Bytes currently allocated and not freed | **Memory leaks** |
| `inuse_objects` | Object count currently allocated | Object leak detection |
| `alloc_space` | Total bytes ever allocated | **GC pressure** / allocation rate |
| `alloc_objects` | Total objects ever allocated | Allocation frequency |

**Collection**:
```bash
# Current heap (inuse_space by default)
go tool pprof http://localhost:6060/debug/pprof/heap

# Allocation rate view
go tool pprof -sample_index=alloc_space http://localhost:6060/debug/pprof/heap

# Compare two heap snapshots (leak detection)
go tool pprof -diff_base=heap1.pb.gz heap2.pb.gz
```

**Sampling**: Controlled by `runtime.MemProfileRate` (default: 1 sample per 512KB allocated). Set to 1 for every allocation (high overhead, debugging only). Set to 0 to disable.

### Goroutine Profile

**What it captures**: Stack traces of all live goroutines. Full snapshot, not sampled.

```bash
# Binary format
go tool pprof http://localhost:6060/debug/pprof/goroutine

# Human-readable with goroutine state
curl 'http://localhost:6060/debug/pprof/goroutine?debug=1'

# Verbose with wait reasons and creation site
curl 'http://localhost:6060/debug/pprof/goroutine?debug=2'
```

**What to look for**: Large groups of goroutines in the same state (e.g., 10,000 goroutines blocked on channel receive = likely leak). Growing goroutine count over time.

### Block Profile

**What it captures**: Duration goroutines spend blocked on synchronization primitives (channels, mutexes, select, waitgroups).

**Must enable explicitly**:
```go
runtime.SetBlockProfileRate(rate)
// rate = nanoseconds. rate=1 = every event (HIGH overhead).
// rate=1_000_000 (1ms) = reasonable for production diagnostics.
// rate=0 = disabled (default).
```

```bash
go tool pprof http://localhost:6060/debug/pprof/block
```

### Mutex Profile

**What it captures**: Duration goroutines wait to acquire a contested mutex.

**Must enable explicitly**:
```go
runtime.SetMutexProfileFraction(N)
// N=1 = every contention event. N=100 = 1% sampling.
// N=0 = disabled (default).
```

```bash
go tool pprof http://localhost:6060/debug/pprof/mutex
```

**Interpretation**: High contention on a mutex means goroutines are serialized. Consider sharding the data structure, using `sync.RWMutex` for read-heavy workloads, or lock-free alternatives with `sync/atomic`.

---

## pprof CLI Reference

### Starting pprof

```bash
# Interactive mode from URL
go tool pprof http://localhost:6060/debug/pprof/profile?seconds=30

# Interactive mode from file
go tool pprof cpu.pb.gz

# Web UI (recommended for exploration)
go tool pprof -http=:8080 cpu.pb.gz
```

### Essential Commands

```
top             # Top functions by flat time
top -cum        # Top functions by cumulative time (including callees)
top20 -cum      # Top 20 by cumulative
list <func>     # Source-level annotation for a function
weblist <func>  # Source annotation in browser (needs -http)
peek <func>     # Show callers and callees of a function
web             # Open SVG call graph in browser
traces          # Show all stack traces
tree            # Text rendering of call graph
disasm <func>   # Assembly-level annotation
```

### Filtering

```
# Focus on specific function (and its callers/callees)
top -cum -focus=handleRequest

# Ignore specific functions
top -cum -ignore=runtime

# Tag-based filtering (for labeled profiles)
top -tagfocus=endpoint=api/v1/users
```

### Diff Profiling

```bash
# Compare two profiles — shows delta
go tool pprof -diff_base=before.pb.gz after.pb.gz

# In the web UI
go tool pprof -http=:8080 -diff_base=before.pb.gz after.pb.gz
```

### Output Formats

```bash
go tool pprof -png cpu.pb.gz > profile.png
go tool pprof -svg cpu.pb.gz > profile.svg
go tool pprof -text cpu.pb.gz
go tool pprof -callgrind cpu.pb.gz > callgrind.out  # For KCachegrind
go tool pprof -proto cpu.pb.gz > profile.pb.gz      # Binary proto
```

### flat vs cum

- **flat**: Time spent in the function itself (excluding callees). High flat = the function body is expensive.
- **cum** (cumulative): Time spent in the function including all callees. High cum, low flat = the function delegates to expensive callees.

**Strategy**: Start with `top -cum` to find the expensive call chains. Then drill into the function with highest `flat` to find the actual hotspot.

---

## fgprof — Wall-Clock Profiling

Standard CPU profiling only sees on-CPU time. If goroutines are blocked on I/O, network, locks, or sleep — the CPU profiler shows nothing. `fgprof` samples all goroutines regardless of state, giving a wall-clock view.

### Setup

```go
import (
    _ "net/http/pprof"
    "github.com/felixge/fgprof"
)

func main() {
    http.DefaultServeMux.Handle("/debug/fgprof", fgprof.Handler())
    go http.ListenAndServe("localhost:6060", nil)
}
```

### Collection

```bash
go tool pprof http://localhost:6060/debug/fgprof?seconds=10
```

**When to use**: CPU profile shows low CPU utilization but requests are slow. fgprof reveals where time goes (network calls, database queries, file I/O, lock contention).

**Caveat**: Overhead increases with goroutine count. Avoid with >10,000 goroutines. Not suitable for continuous profiling.

---

## Continuous Profiling

### Grafana Pyroscope SDK

```go
import "github.com/grafana/pyroscope-go"

func main() {
    pyroscope.Start(pyroscope.Config{
        ApplicationName: "my-service",
        ServerAddress:   "http://pyroscope:4040",
        Logger:          pyroscope.StandardLogger,

        // Profile types to collect
        ProfileTypes: []pyroscope.ProfileType{
            pyroscope.ProfileCPU,
            pyroscope.ProfileAllocObjects,
            pyroscope.ProfileAllocSpace,
            pyroscope.ProfileInuseObjects,
            pyroscope.ProfileInuseSpace,
        },

        // Labels for filtering
        Tags: map[string]string{
            "env":     "production",
            "version": "v1.2.3",
            "region":  "us-east-1",
        },
    })
    defer pyroscope.Stop()
}
```

**Overhead**: ~2-5% CPU. Safe for production with CPU-only profiling. Memory profiling adds minimal overhead.

### Parca Agent (eBPF)

No code changes required. Deploys as a DaemonSet or sidecar. Uses eBPF to sample stack traces at 19Hz from kernel space.

```bash
# Install and run
parca-agent --remote-store-address=parca-server:7070 \
            --node=my-node \
            --sampling-ratio=1.0
```

**Overhead**: <1% CPU. Supports Go, C, C++, Rust (compiled languages with DWARF/frame pointers).

### Datadog Continuous Profiler

```go
import "gopkg.in/DataDog/dd-trace-go.v1/profiler"

func main() {
    profiler.Start(
        profiler.WithService("my-service"),
        profiler.WithEnv("production"),
        profiler.WithVersion("1.2.3"),
        profiler.WithProfileTypes(
            profiler.CPUProfile,
            profiler.HeapProfile,
            profiler.GoroutineProfile,
        ),
    )
    defer profiler.Stop()
}
```

---

## Profile-Guided Optimization (PGO) — Go 1.21+

PGO uses runtime CPU profiles to guide compiler optimizations. Typical improvement: **2-7% CPU reduction**.

### Workflow

1. **Build without PGO** and deploy to production.

2. **Collect a representative CPU profile** (30-60 seconds under typical load):
   ```bash
   curl -o default.pgo 'http://localhost:6060/debug/pprof/profile?seconds=60'
   ```

3. **Place the profile** in the main package directory as `default.pgo`:
   ```bash
   mv default.pgo ./cmd/myservice/default.pgo
   ```

4. **Rebuild** — Go automatically detects `default.pgo`:
   ```bash
   go build ./cmd/myservice
   ```

   Or specify explicitly:
   ```bash
   go build -pgo=/path/to/cpu.pprof ./cmd/myservice
   ```

5. **Deploy and re-profile** — PGO is iterative. A PGO-optimized binary may have different hotspots. Collect a new profile and rebuild for further gains.

### What PGO Optimizes

- **Aggressive inlining** of hot functions (beyond the normal budget)
- **Devirtualization** of hot interface calls to direct calls
- **Better register allocation** along hot paths

### Best Practices

- Commit `default.pgo` to the repository — it should be part of the build.
- Merge profiles from multiple replicas for better coverage: `go tool pprof -proto a.pprof b.pprof > merged.pgo`
- Re-collect profiles periodically as traffic patterns change.
- Verify improvement with benchmarks or production metrics.
