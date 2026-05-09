# Go Runtime Diagnostics

## GODEBUG Environment Variable

### gctrace=1 — GC Event Tracing

```bash
GODEBUG=gctrace=1 ./myservice
```

**Output format**:
```
gc 1405 @6.045s 11%: 0.058+1.020+0.043 ms clock, 0.070+0.775/1.440/2.370+0.051 ms cpu, 7->11->6 MB, 10 MB goal, 8 P
```

**Field breakdown**:
| Field | Meaning |
|---|---|
| `gc 1405` | GC cycle number |
| `@6.045s` | Seconds since program start |
| `11%` | Percentage of time spent in GC since start |
| `0.058+1.020+0.043 ms clock` | Wall-clock time: STW sweep termination + concurrent mark/scan + STW mark termination |
| `0.070+0.775/1.440/2.370+0.051 ms cpu` | CPU time: STW sweep term + (assist/background/idle GC) + STW mark term |
| `7->11->6 MB` | Heap before GC → heap at GC trigger → live heap after GC |
| `10 MB goal` | Target heap size |
| `8 P` | Number of processors used |

**What to look for**:
- **High GC percentage** (>25%): Too many allocations. Profile with `alloc_space` to find hotspots.
- **Growing live heap** (third number in MB triplet): Possible memory leak.
- **Long STW pauses** (first and third clock numbers): Consider GOGC tuning or reducing pointer-heavy structures.
- **Frequent GC cycles**: Allocating too much too fast.

### schedtrace — Scheduler Tracing

```bash
GODEBUG=schedtrace=1000 ./myservice  # Print every 1000ms
```

**Output format**:
```
SCHED 1000ms: gomaxprocs=8 idleprocs=4 threads=12 spinningthreads=1 needspinning=0 idlethreads=3 runqueue=0 [2 0 0 0 0 0 0 0]
```

| Field | Meaning |
|---|---|
| `gomaxprocs=8` | Number of Ps (logical processors) |
| `idleprocs=4` | Ps with no goroutine to run |
| `threads=12` | OS threads created |
| `spinningthreads=1` | Threads looking for goroutines to steal |
| `runqueue=0` | Goroutines in the global run queue |
| `[2 0 0 0 ...]` | Per-P local run queue lengths |

**What to look for**:
- **Large run queue values**: Goroutines waiting for CPU. May need more GOMAXPROCS or less goroutine creation.
- **idleprocs = gomaxprocs**: All processors idle. Application is I/O bound or has no work.
- **threads >> gomaxprocs**: Many threads stuck in syscalls (cgo, blocking I/O).

### Other GODEBUG Settings

```bash
# Detailed scheduler info (very verbose)
GODEBUG=schedtrace=1000,scheddetail=1 ./myservice

# Allocation tracing (every alloc/free — EXTREMELY expensive, dev only)
GODEBUG=allocfreetrace=1 ./myservice

# Force MADV_DONTNEED (for accurate RSS monitoring)
GODEBUG=madvdontneed=1 ./myservice

# Combine multiple settings
GODEBUG=gctrace=1,schedtrace=5000 ./myservice
```

---

## Escape Analysis

### Checking Escape Decisions

```bash
# Basic escape analysis output
go build -gcflags='-m' ./...

# Verbose (shows reasoning)
go build -gcflags='-m -m' ./...

# For a specific package
go build -gcflags='-m' ./pkg/handler/
```

### What Causes Heap Escapes

```go
// 1. Returning a pointer to a local variable
func newItem() *Item {
    item := Item{Name: "test"} // escapes: returned as pointer
    return &item
}

// 2. Storing in an interface (boxing)
func log(v interface{}) { // v must be heap-allocated
    fmt.Println(v)
}
func caller() {
    x := 42
    log(x) // x escapes: boxed into interface{}
}

// 3. Closure capturing a variable
func startWorker() {
    data := loadData() // escapes: captured by goroutine closure
    go func() {
        process(data)
    }()
}

// 4. Slice growing beyond compile-time known capacity
func collect() []int {
    var s []int // escapes: append may grow beyond SSA tracking
    for i := 0; i < n; i++ {
        s = append(s, i)
    }
    return s
}

// 5. Sending to a channel
func send(ch chan *Item) {
    item := &Item{} // escapes: sent to channel
    ch <- item
}

// 6. Storing in a struct field that escapes
type Server struct { handler Handler }
func newServer() *Server {
    h := &myHandler{} // escapes: stored in Server which escapes
    return &Server{handler: h}
}
```

### Avoiding Unnecessary Escapes

```go
// Use value types for small structs (stays on stack)
func processItem(item Item) Result { ... }  // value receiver, no escape

// Pre-allocate with known capacity
func collect(n int) []int {
    s := make([]int, 0, n) // compiler may keep on stack if n is small enough
    for i := 0; i < n; i++ {
        s = append(s, i)
    }
    return s
}

// Use generics instead of interface{} (Go 1.18+)
func logValue[T any](v T) { ... } // no boxing
```

**Why it matters**: Every heap allocation creates work for the GC. Hot-path functions that allocate on every call create GC pressure proportional to throughput.

---

## runtime.ReadMemStats

```go
var m runtime.MemStats
runtime.ReadMemStats(&m) // Note: triggers STW, avoid calling frequently

// Key fields
fmt.Printf("HeapAlloc:    %d MB\n", m.HeapAlloc/1024/1024)      // Live heap bytes
fmt.Printf("HeapSys:      %d MB\n", m.HeapSys/1024/1024)        // Heap bytes obtained from OS
fmt.Printf("HeapIdle:     %d MB\n", m.HeapIdle/1024/1024)       // Heap bytes in idle spans
fmt.Printf("HeapReleased: %d MB\n", m.HeapReleased/1024/1024)   // Heap bytes returned to OS
fmt.Printf("StackInuse:   %d MB\n", m.StackInuse/1024/1024)     // Stack bytes in use
fmt.Printf("NumGC:        %d\n", m.NumGC)                        // Completed GC cycles
fmt.Printf("PauseTotalNs: %d ms\n", m.PauseTotalNs/1_000_000)   // Total GC pause time
fmt.Printf("Mallocs:      %d\n", m.Mallocs)                      // Total allocations
fmt.Printf("Frees:        %d\n", m.Frees)                        // Total frees
fmt.Printf("LiveObjects:  %d\n", m.Mallocs-m.Frees)              // Currently live objects

// Last GC pause
fmt.Printf("LastGCPause:  %d us\n", m.PauseNs[(m.NumGC+255)%256]/1000)
```

**Caveat**: `ReadMemStats` causes a brief STW (stop-the-world). Don't call it in hot paths or at high frequency. For continuous monitoring, prefer `runtime/metrics`.

---

## runtime/metrics Package (Go 1.16+)

Preferred over `ReadMemStats` for production monitoring — no STW, structured access.

```go
import "runtime/metrics"

// Key metrics to monitor
metricsToRead := []string{
    "/gc/cycles/total:gc-cycles",          // Total GC cycles
    "/gc/heap/allocs:bytes",               // Cumulative bytes allocated
    "/gc/heap/frees:bytes",                // Cumulative bytes freed
    "/gc/pauses:seconds",                  // GC pause duration distribution
    "/memory/classes/heap/free:bytes",     // Free heap memory
    "/memory/classes/heap/objects:bytes",  // Live heap object bytes
    "/memory/classes/total:bytes",         // Total memory mapped
    "/sched/goroutines:goroutines",        // Current goroutine count
}

samples := make([]metrics.Sample, len(metricsToRead))
for i, name := range metricsToRead {
    samples[i].Name = name
}
metrics.Read(samples)

for _, s := range samples {
    switch s.Value.Kind() {
    case metrics.KindUint64:
        fmt.Printf("%s = %d\n", s.Name, s.Value.Uint64())
    case metrics.KindFloat64:
        fmt.Printf("%s = %f\n", s.Name, s.Value.Float64())
    case metrics.KindFloat64Histogram:
        // Distribution data (e.g., GC pause durations)
        hist := s.Value.Float64Histogram()
        fmt.Printf("%s: %d buckets\n", s.Name, len(hist.Buckets))
    }
}
```

### Exposing as Prometheus Metrics

Many Prometheus client libraries auto-export Go runtime metrics from this package. With the official client:

```go
import "github.com/prometheus/client_golang/prometheus/collectors"

// Register Go runtime collector (uses runtime/metrics internally)
reg := prometheus.NewRegistry()
reg.MustRegister(collectors.NewGoCollector())
```

---

## go tool trace

### Collecting Traces

```bash
# From a running HTTP server
curl -o trace.out 'http://localhost:6060/debug/pprof/trace?seconds=5'

# From a test
go test -trace=trace.out ./...
```

Programmatically:
```go
import "runtime/trace"

f, _ := os.Create("trace.out")
defer f.Close()
trace.Start(f)
defer trace.Stop()
```

### Analyzing

```bash
go tool trace trace.out
# Opens browser UI with:
# - Goroutine analysis
# - Network blocking profile
# - Synchronization blocking profile
# - Syscall blocking profile
# - Scheduler latency profile
# - User-defined tasks and regions
```

### What to Look For

| Pattern | Indicates |
|---|---|
| Red/orange blocks in timeline | GC STW pauses |
| Goroutines in "Runnable" state for long periods | CPU saturation or scheduler congestion |
| Many goroutines in "Blocked" state | Contention on channels/mutexes |
| Long syscall blocks | Slow I/O operations |
| Network poll waits | Slow upstream services or DNS |
| GC assist spikes | Goroutines forced to help GC (high allocation rate) |

### User-Defined Tasks and Regions

```go
import "runtime/trace"

func handleRequest(ctx context.Context, req *Request) {
    ctx, task := trace.NewTask(ctx, "handleRequest")
    defer task.End()

    // Annotate sub-operations
    trace.WithRegion(ctx, "parseInput", func() {
        parseInput(req)
    })

    trace.WithRegion(ctx, "queryDB", func() {
        queryDB(ctx, req.ID)
    })

    trace.Log(ctx, "requestID", req.ID)
}
```

These show up in the trace viewer as labeled spans, making it easy to correlate runtime events with application logic.

---

## GOGC and GOMEMLIMIT

### GOGC — GC Target Ratio

Controls how aggressively the GC runs. Default: `GOGC=100` (GC triggers when heap is 2x the live heap size).

```bash
GOGC=50 ./myservice   # GC at 1.5x live heap (more frequent GC, less memory)
GOGC=200 ./myservice  # GC at 3x live heap (less frequent GC, more memory)
GOGC=off ./myservice  # Disable GC entirely (use with GOMEMLIMIT)
```

Programmatically:
```go
import "runtime/debug"
old := debug.SetGCPercent(200) // Returns previous value
```

### GOMEMLIMIT — Soft Memory Limit (Go 1.19+)

Sets a soft limit on total Go memory. GC runs more aggressively as usage approaches the limit.

```bash
GOMEMLIMIT=512MiB ./myservice
GOMEMLIMIT=1GiB ./myservice
```

Programmatically:
```go
debug.SetMemoryLimit(512 << 20) // 512 MiB
```

### Container Pattern

For memory-constrained containers, set GOMEMLIMIT to ~90% of the container's memory limit and disable GOGC:

```bash
# Container with 1GB memory limit
GOGC=off GOMEMLIMIT=900MiB ./myservice
```

This lets Go use all available memory while the GC keeps usage under the limit. The GC only runs when actually needed (approaching the limit), reducing CPU overhead.

**Warning**: Always leave headroom (10-20%) for non-heap memory (goroutine stacks, OS buffers, cgo). Setting GOMEMLIMIT equal to the container limit risks OOM kills.

---

## Useful Runtime Functions

```go
runtime.NumGoroutine()          // Current goroutine count
runtime.NumCPU()                // Available logical CPUs
runtime.GOMAXPROCS(0)           // Read current GOMAXPROCS (0 = read-only)
runtime.GOMAXPROCS(4)           // Set GOMAXPROCS

runtime.GC()                    // Force GC cycle (rarely needed)
debug.FreeOSMemory()            // Force returning memory to OS (rarely needed)

// Stack dump of current goroutine
buf := make([]byte, 1<<16)
n := runtime.Stack(buf, false)  // false = current goroutine only
fmt.Printf("%s\n", buf[:n])

// Stack dump of ALL goroutines
n = runtime.Stack(buf, true)    // true = all goroutines
fmt.Printf("%s\n", buf[:n])

// Memory limit and GC tuning
debug.SetGCPercent(100)         // Set GOGC
debug.SetMemoryLimit(1 << 30)   // Set GOMEMLIMIT (1 GiB)
```
