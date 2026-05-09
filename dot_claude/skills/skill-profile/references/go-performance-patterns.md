# Go Performance Patterns

## Reducing Allocations

### Pre-Allocate Slices

```go
// BAD: repeated grow-and-copy
var results []Item
for _, raw := range inputs {
    results = append(results, parse(raw))
}

// GOOD: single allocation
results := make([]Item, 0, len(inputs))
for _, raw := range inputs {
    results = append(results, parse(raw))
}
```

When the exact size is known:
```go
results := make([]Item, len(inputs))
for i, raw := range inputs {
    results[i] = parse(raw)
}
```

### Pre-Allocate Maps

```go
// BAD: grows internally multiple times
m := make(map[string]int)
for _, item := range items {
    m[item.Key] = item.Value
}

// GOOD: sized hint
m := make(map[string]int, len(items))
for _, item := range items {
    m[item.Key] = item.Value
}
```

### strings.Builder Over Concatenation

```go
// BAD: O(n^2) allocations
var s string
for _, part := range parts {
    s += part
}

// GOOD: single allocation
var sb strings.Builder
sb.Grow(estimatedSize) // Optional: pre-allocate buffer
for _, part := range parts {
    sb.WriteString(part)
}
result := sb.String()
```

### Avoid Interface Boxing in Hot Paths

```go
// BAD: allocates for boxing on every call
func process(v interface{}) { ... }
func hot() {
    for _, x := range data {
        process(x) // x gets boxed — heap allocation
    }
}

// GOOD: use concrete type or generics
func process(v int) { ... } // concrete type, no boxing

// Or with generics (Go 1.18+)
func process[T any](v T) { ... } // monomorphized, no boxing
```

### Value Receivers for Small Structs

```go
// Small struct — value receiver avoids escape
type Point struct{ X, Y float64 }

func (p Point) Distance(other Point) float64 {
    dx := p.X - other.X
    dy := p.Y - other.Y
    return math.Sqrt(dx*dx + dy*dy)
}

// Large struct — pointer receiver is fine (avoids copy overhead)
type Config struct { /* many fields */ }
func (c *Config) Validate() error { ... }
```

Rule of thumb: structs ≤ 3-4 words (24-32 bytes) — value receiver. Larger — pointer receiver.

### Struct Field Ordering

```go
// BAD: padding wastes memory (on 64-bit: 24 bytes)
type Unaligned struct {
    A bool    // 1 byte + 7 padding
    B int64   // 8 bytes
    C bool    // 1 byte + 7 padding
}

// GOOD: no padding (on 64-bit: 16 bytes)
type Aligned struct {
    B int64   // 8 bytes
    A bool    // 1 byte
    C bool    // 1 byte + 6 padding
}
```

Order fields from largest to smallest to minimize padding. Matters when allocating millions of structs.

---

## sync.Pool

Reuse short-lived, frequently allocated objects to reduce GC pressure.

```go
var bufPool = sync.Pool{
    New: func() interface{} {
        return new(bytes.Buffer)
    },
}

func handleRequest(data []byte) {
    buf := bufPool.Get().(*bytes.Buffer)
    defer func() {
        buf.Reset() // MUST reset before returning
        bufPool.Put(buf)
    }()

    buf.Write(data)
    // use buf...
}
```

### Best Practices

- **Always Reset before Put.** Returning dirty objects causes bugs and memory leaks.
- **Don't store long-lived references.** Pool contents are collected on every GC. Only use for short-lived objects.
- **Good candidates**: byte buffers, encoders/decoders, temporary structs, gzip writers.
- **Bad candidates**: database connections, file handles (use a connection pool instead).
- **Don't over-pool.** Profile first. sync.Pool adds complexity — only use when allocation profiling shows a clear hotspot.

### Typed Pool (Go 1.18+ generics)

```go
type Pool[T any] struct {
    pool sync.Pool
}

func NewPool[T any](newFunc func() T) *Pool[T] {
    return &Pool[T]{
        pool: sync.Pool{New: func() interface{} { return newFunc() }},
    }
}

func (p *Pool[T]) Get() T    { return p.pool.Get().(T) }
func (p *Pool[T]) Put(v T)   { p.pool.Put(v) }
```

---

## String and Byte Manipulation

### strconv vs fmt

```go
// BAD: fmt uses reflection, allocates
s := fmt.Sprintf("%d", n)

// GOOD: strconv is direct, often zero-alloc
s := strconv.Itoa(n)
s := strconv.FormatInt(n, 10)
s := strconv.FormatFloat(f, 'f', -1, 64)
```

### Byte-Level String Building

```go
// For maximum performance, work with []byte directly
buf := make([]byte, 0, 256)
buf = append(buf, "prefix:"...)
buf = strconv.AppendInt(buf, int64(n), 10)
buf = append(buf, ",key="...)
buf = append(buf, key...)
result := string(buf) // single allocation for final string
```

### Avoid Repeated string↔[]byte Conversions

```go
// BAD: allocates on every conversion
data := []byte(myString)
result := string(data)

// Pattern: work in one type throughout, convert once at boundaries
func processBytes(data []byte) []byte { ... }

input := []byte(requestBody) // convert once
output := processBytes(input) // work in []byte
responseBody := string(output) // convert once
```

---

## Map Performance

### Clear and Reuse (Go 1.21+)

```go
// Reuse map memory across iterations
m := make(map[string]int, expectedSize)
for _, batch := range batches {
    clear(m) // Keeps allocated buckets, resets contents
    for _, item := range batch {
        m[item.Key] = item.Value
    }
    processBatch(m)
}
```

### Alternatives for Small Maps

For maps with <10 entries, a sorted slice with binary search or a flat array can be faster due to cache locality:

```go
// Small lookup table — array indexed by enum
type Color int
const (
    Red Color = iota
    Green
    Blue
    colorCount
)

var colorNames [colorCount]string = [colorCount]string{
    Red:   "red",
    Green: "green",
    Blue:  "blue",
}

// O(1) lookup, no hashing, cache-friendly
name := colorNames[myColor]
```

### Map Iteration Order

Map iteration in Go is randomized. If you need deterministic order (e.g., for checksums, tests), sort keys first:

```go
keys := make([]string, 0, len(m))
for k := range m {
    keys = append(keys, k)
}
sort.Strings(keys)
for _, k := range keys {
    process(k, m[k])
}
```

---

## Concurrency Patterns for Performance

### Bounded Worker Pool

```go
func processItems(ctx context.Context, items []Item, concurrency int) error {
    g, ctx := errgroup.WithContext(ctx)
    g.SetLimit(concurrency)

    for _, item := range items {
        g.Go(func() error {
            return processItem(ctx, item)
        })
    }
    return g.Wait()
}
```

### Sharded Data Structures

Reduce mutex contention by sharding:

```go
type ShardedMap[K comparable, V any] struct {
    shards [256]struct {
        mu sync.RWMutex
        m  map[K]V
    }
}

func (sm *ShardedMap[K, V]) shard(key K) *struct {
    mu sync.RWMutex
    m  map[K]V
} {
    h := fnv.New32a()
    binary.Write(h, binary.LittleEndian, key)
    return &sm.shards[h.Sum32()%256]
}

func (sm *ShardedMap[K, V]) Get(key K) (V, bool) {
    s := sm.shard(key)
    s.mu.RLock()
    defer s.mu.RUnlock()
    v, ok := s.m[key]
    return v, ok
}
```

### Atomic vs Mutex

```go
// Counters, flags, simple values — use atomic
var counter atomic.Int64
counter.Add(1)
val := counter.Load()

// Complex state (multiple fields that must be consistent) — use mutex
var mu sync.Mutex
mu.Lock()
state.A = newA
state.B = newB // Must be consistent with A
mu.Unlock()
```

### sync.RWMutex for Read-Heavy Workloads

```go
var (
    mu    sync.RWMutex
    cache map[string]Result
)

func get(key string) (Result, bool) {
    mu.RLock() // Multiple readers allowed
    defer mu.RUnlock()
    r, ok := cache[key]
    return r, ok
}

func set(key string, val Result) {
    mu.Lock() // Exclusive access
    defer mu.Unlock()
    cache[key] = val
}
```

**When RWMutex helps**: Read-to-write ratio > 10:1. For lower ratios, a regular Mutex may be faster (RWMutex has higher per-operation overhead).

---

## Interface Costs and Generics

### Interface Method Call Overhead

Interface method calls use indirect dispatch (vtable lookup). They are **not inlineable** by the compiler (without PGO devirtualization). In hot loops this adds up.

```go
// Indirect call — not inlineable
type Writer interface { Write([]byte) (int, error) }
func writeAll(w Writer, data []byte) { w.Write(data) }

// Direct call — inlineable if small enough
func writeAll(w *bytes.Buffer, data []byte) { w.Write(data) }
```

### When Generics Help

Generics produce monomorphized code for value types — no boxing, no indirect calls:

```go
// Generic — no interface overhead for concrete types
func Max[T constraints.Ordered](a, b T) T {
    if a > b { return a }
    return b
}

// Equivalent interface version would box values and use indirect comparison
```

**When generics don't help**: If the function body is large or the generic is instantiated with many types, code size increases. Measure, don't assume.

---

## Compiler Optimizations

### Inlining

The compiler inlines small functions. Check with:
```bash
go build -gcflags='-m' ./...
# Output: "can inline funcName" or "funcName: function too complex"
```

**Help inlining**:
- Keep hot functions small (< ~80 AST nodes)
- Avoid `defer` in very hot functions (adds inlining cost — improved in Go 1.22+)
- Avoid `recover()` (prevents inlining)

**Testing without inlining**:
```go
//go:noinline
func myFunc() { ... } // Force no-inline for benchmarking
```

### Bounds Check Elimination (BCE)

The compiler eliminates bounds checks when it can prove the index is in range:

```go
// Compiler eliminates bounds check for s[i] in the loop
for i := 0; i < len(s); i++ {
    s[i] = process(s[i])
}

// Hint for manual bounds check elimination
_ = s[n-1] // Proves to compiler that s has at least n elements
for i := 0; i < n; i++ {
    s[i] = process(s[i]) // No bounds check
}
```

---

## I/O Performance

### bufio for Reducing Syscalls

```go
// BAD: syscall per Write
f, _ := os.Create("output.txt")
for _, line := range lines {
    f.Write([]byte(line))
}

// GOOD: batched syscalls
f, _ := os.Create("output.txt")
w := bufio.NewWriterSize(f, 64*1024) // 64KB buffer
for _, line := range lines {
    w.WriteString(line)
}
w.Flush()
```

### HTTP Client Connection Pooling

```go
client := &http.Client{
    Transport: &http.Transport{
        MaxIdleConns:        100,
        MaxIdleConnsPerHost: 10,              // Default is 2 — too low
        IdleConnTimeout:     90 * time.Second,
        DisableKeepAlives:   false,           // Must be false for pooling
    },
    Timeout: 30 * time.Second,
}
```

**Critical**: Always read and close the response body, even on error — otherwise connections aren't returned to the pool:

```go
resp, err := client.Do(req)
if err != nil { return err }
defer resp.Body.Close()
io.Copy(io.Discard, resp.Body) // Drain body to enable connection reuse
```

### io.Copy and sendfile

`io.Copy` uses `sendfile(2)` when copying between `*os.File` and `*net.TCPConn` — zero-copy in kernel space:

```go
// This uses sendfile automatically when possible
io.Copy(conn, file)
```

Don't wrap file/conn in bufio when using io.Copy — it defeats the sendfile optimization.
