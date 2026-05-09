# Go Benchmarks

## Writing Benchmarks

### Basic Structure

```go
func BenchmarkMyFunction(b *testing.B) {
    // Setup (not timed)
    input := prepareInput()

    b.ResetTimer() // Exclude setup from measurement

    // Go 1.24+: preferred — prevents dead-code elimination automatically
    for b.Loop() {
        myFunction(input)
    }
}
```

### Pre-Go 1.24 Pattern

```go
func BenchmarkMyFunction(b *testing.B) {
    input := prepareInput()
    b.ResetTimer()

    // Must prevent dead-code elimination manually
    var result int
    for i := 0; i < b.N; i++ {
        result = myFunction(input)
    }
    _ = result // or assign to package-level var
}

// Package-level sink prevents compiler from eliminating the call
var benchSink int
```

### Timer Control

```go
func BenchmarkWithExpensiveSetup(b *testing.B) {
    b.StopTimer()
    data := expensiveSetup() // Not counted
    b.StartTimer()

    for b.Loop() {
        process(data)
    }
}
```

### Throughput Benchmarks

```go
func BenchmarkRead(b *testing.B) {
    data := make([]byte, 4096)
    b.SetBytes(int64(len(data))) // Report MB/s in output

    for b.Loop() {
        reader.Read(data)
    }
}
```

### Allocation Tracking

```go
func BenchmarkAllocations(b *testing.B) {
    b.ReportAllocs() // Always show B/op and allocs/op

    for b.Loop() {
        _ = makeSlice()
    }
}
```

### Custom Metrics

```go
func BenchmarkCustomMetric(b *testing.B) {
    var totalItems int
    for b.Loop() {
        totalItems += processItems()
    }
    b.ReportMetric(float64(totalItems)/float64(b.N), "items/op")
}
```

---

## Running Benchmarks

### Common Flags

```bash
# Run all benchmarks, show allocations
go test -bench=. -benchmem ./...

# Run specific benchmark
go test -bench=BenchmarkMyFunction -benchmem ./pkg/handler/

# Skip unit tests (only benchmarks)
go test -bench=. -run=^$ -benchmem ./...

# Multiple iterations for statistical significance
go test -bench=. -benchmem -count=10 ./...

# Custom duration per benchmark
go test -bench=. -benchtime=5s ./...

# Custom iteration count
go test -bench=. -benchtime=1000x ./...

# Set GOMAXPROCS
go test -bench=. -cpu=1,2,4,8 ./...
```

### Reading Output

```
BenchmarkMyFunc-8    1234567    890.1 ns/op    256 B/op    3 allocs/op
│                │        │           │             │              │
│                │        │           │             │              └─ Heap allocations per op
│                │        │           │             └─ Bytes allocated per op
│                │        │           └─ Nanoseconds per operation
│                │        └─ Number of iterations run
│                └─ GOMAXPROCS
└─ Benchmark name
```

---

## Profiling Benchmarks

Generate profiles from benchmarks for deep analysis:

```bash
# CPU profile
go test -bench=BenchmarkMyFunc -cpuprofile=cpu.pb.gz ./pkg/handler/

# Memory profile
go test -bench=BenchmarkMyFunc -memprofile=mem.pb.gz ./pkg/handler/

# Block profile
go test -bench=BenchmarkMyFunc -blockprofile=block.pb.gz ./pkg/handler/

# Mutex profile
go test -bench=BenchmarkMyFunc -mutexprofile=mutex.pb.gz ./pkg/handler/

# Execution trace
go test -bench=BenchmarkMyFunc -trace=trace.out ./pkg/handler/

# Multiple profiles at once
go test -bench=BenchmarkMyFunc -cpuprofile=cpu.pb.gz -memprofile=mem.pb.gz -benchmem ./pkg/handler/

# Analyze
go tool pprof cpu.pb.gz
go tool pprof -http=:8080 mem.pb.gz
go tool trace trace.out
```

---

## Comparing Benchmarks with benchstat

### Installation

```bash
go install golang.org/x/perf/cmd/benchstat@latest
```

### Workflow

```bash
# Run old version
go test -bench=. -benchmem -count=10 ./... > old.txt

# Make changes, then run new version
go test -bench=. -benchmem -count=10 ./... > new.txt

# Compare
benchstat old.txt new.txt
```

### Reading benchstat Output

```
goos: linux
goarch: amd64
pkg: myapp/handler
                 │  old.txt   │              new.txt              │
                 │   sec/op   │   sec/op     vs base              │
MyFunc-8           890.1n ± 2%   456.7n ± 1%  -48.69% (p=0.000)
OtherFunc-8        123.4n ± 3%   121.2n ± 2%   -1.78% (p=0.052)

                 │  old.txt   │            new.txt             │
                 │    B/op    │    B/op     vs base            │
MyFunc-8           256.0 ± 0%     0.0 ± 0%  -100.00% (p=0.000)
```

- **p-value**: < 0.05 means the difference is statistically significant.
- **± N%**: Coefficient of variation across runs. High variation (>5%) = noisy benchmark.
- Always use `-count=N` with N >= 5 (10 is better) for reliable statistics.

---

## Sub-Benchmarks

### Table-Driven Pattern

```go
func BenchmarkProcess(b *testing.B) {
    cases := []struct {
        name string
        size int
    }{
        {"small", 100},
        {"medium", 10_000},
        {"large", 1_000_000},
    }

    for _, tc := range cases {
        b.Run(tc.name, func(b *testing.B) {
            data := make([]int, tc.size)
            b.ResetTimer()
            for b.Loop() {
                process(data)
            }
        })
    }
}
```

### Parallel Benchmarks

```go
func BenchmarkParallelHandler(b *testing.B) {
    handler := setupHandler()

    b.RunParallel(func(pb *testing.PB) {
        req := buildRequest() // Each goroutine gets its own
        for pb.Next() {
            handler.ServeHTTP(httptest.NewRecorder(), req)
        }
    })
}
```

---

## Common Benchmark Pitfalls

### 1. Dead-Code Elimination

The compiler may eliminate calls whose results are unused:

```go
// BAD: compiler may optimize away entirely
for i := 0; i < b.N; i++ {
    computeHash(data) // result unused — compiler removes it
}

// GOOD (Go 1.24+): b.Loop() prevents this
for b.Loop() {
    computeHash(data)
}

// GOOD (pre-1.24): assign to package-level sink
var hashSink uint64
func BenchmarkHash(b *testing.B) {
    for i := 0; i < b.N; i++ {
        hashSink = computeHash(data)
    }
}
```

### 2. Setup Inside the Loop

```go
// BAD: measures setup + function
for b.Loop() {
    data := generateTestData(1000) // expensive setup
    process(data)
}

// GOOD: setup once outside
data := generateTestData(1000)
b.ResetTimer()
for b.Loop() {
    process(data)
}
```

### 3. Shared Mutable State

```go
// BAD: first iteration modifies input for all subsequent iterations
data := []int{3, 1, 4, 1, 5}
for b.Loop() {
    sort.Ints(data) // data is already sorted after first iteration
}

// GOOD: fresh copy each iteration
original := []int{3, 1, 4, 1, 5}
for b.Loop() {
    data := make([]int, len(original))
    copy(data, original)
    sort.Ints(data)
}
```

### 4. Running with `-race`

The race detector adds significant overhead (2-10x slowdown). Never benchmark with `-race` enabled — results will be distorted.

### 5. Insufficient Runs for benchstat

```bash
# BAD: single run, no statistical power
go test -bench=. > results.txt

# GOOD: multiple runs
go test -bench=. -count=10 > results.txt
```

### 6. Not Controlling Environment

- Close other CPU-intensive programs
- Pin to specific CPUs if possible: `taskset -c 0 go test -bench=.`
- Disable CPU frequency scaling for consistent results
- Use `-benchtime=3s` or higher for very fast operations

---

## testing.AllocsPerRun

For quick allocation checks outside of benchmarks:

```go
func TestAllocations(t *testing.T) {
    allocs := testing.AllocsPerRun(100, func() {
        myFunction()
    })
    if allocs > 0 {
        t.Errorf("expected zero allocations, got %f", allocs)
    }
}
```

Useful for enforcing zero-allocation contracts in hot paths.
