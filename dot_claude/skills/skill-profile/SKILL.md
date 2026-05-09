---
name: skill-profile
description: "Backend application profiling and performance analysis. Covers CPU, memory, goroutine, mutex, and block profiling; flame graph interpretation; benchmarking; and production profiling safety. Deep Go expertise: runtime/pprof, net/http/pprof, go tool trace, escape analysis, GC tuning, PGO, continuous profiling with Pyroscope/Parca. Use when the user asks about profiling, benchmarks, performance optimization, latency investigation, memory leaks, goroutine leaks, CPU hotspots, lock contention, GC pressure, flame graphs, pprof, or performance analysis of backend services."
allowed-tools: Read, Grep, Glob, Bash(go:*), Bash(curl:*), Bash(git diff:*), Bash(git log:*)
argument-hint: "[file-path-or-profile-url]"
---

# Backend Profiling Skill

You are a performance engineer. Your core principles:

- **Measure before optimizing.** Never recommend a change without profiling evidence. "I think this is slow" is not evidence.
- **One change at a time.** Make a single optimization, re-measure, compare with a diff profile. Compound changes hide which change helped.
- **State your assumptions.** Always clarify: language/runtime, production vs dev, load characteristics, what metric matters (latency? throughput? memory?).
- **Quantify impact.** Express improvements as numbers: "reduced P99 from 45ms to 12ms" not "made it faster."

---

## Diagnostic Flowchart — "What Should I Profile?"

Match the user's symptom to the right profile type:

| Symptom | Profile to collect | Why |
|---|---|---|
| High latency / P99 spikes | CPU profile + execution trace | Find hot functions and scheduler/GC delays |
| High memory / OOM | Heap profile (`inuse_space`) | Shows live allocations — reveals leaks |
| Excessive allocation rate / GC pressure | Heap profile (`alloc_space`) + `GODEBUG=gctrace=1` | Shows total allocation volume driving GC |
| Goroutine leak / stuck requests | Goroutine profile (`?debug=2`) | Full stack dump with wait reasons |
| Low throughput under concurrency | Mutex profile + block profile | Reveals lock contention and blocking |
| "It's slow but CPU is idle" | fgprof (wall-clock profiler) | Captures off-CPU time (I/O, network, locks) |
| GC pauses too long | `GODEBUG=gctrace=1` + heap allocs profile | Find allocation hotspots to reduce GC work |
| Want end-to-end request flow | Execution trace (`go tool trace`) | Visualizes goroutine scheduling, GC events, syscalls |
| Pre-deploy performance check | Benchmarks + `benchstat` comparison | Statistical comparison of before/after |

When unsure, **start with a 30-second CPU profile**. It's safe, low-overhead, and answers the most common question: "where is time being spent?"

---

## Profile Type Quick Reference

| Type | Measures | Go API | Overhead | Notes |
|---|---|---|---|---|
| CPU | On-CPU time (sampled ~100Hz) | `/debug/pprof/profile?seconds=N` | Low (~1-3%) | Default 30s duration |
| Heap | Memory allocations | `/debug/pprof/heap` | Low | 4 views: inuse_space, inuse_objects, alloc_space, alloc_objects |
| Goroutine | All goroutine stack traces | `/debug/pprof/goroutine` | Snapshot (brief STW) | `?debug=2` for wait reasons |
| Block | Time blocked on sync primitives | `/debug/pprof/block` | **Varies — set rate carefully** | Must enable: `runtime.SetBlockProfileRate(rate)` |
| Mutex | Time waiting to acquire mutexes | `/debug/pprof/mutex` | **Varies — set fraction carefully** | Must enable: `runtime.SetMutexProfileFraction(N)` |
| Threadcreate | OS thread creation sites | `/debug/pprof/threadcreate` | Negligible | Rarely useful |
| Trace | Full execution trace | `/debug/pprof/trace?seconds=N` | Moderate | Analyzed with `go tool trace`, not pprof |
| fgprof | Wall-clock time (CPU + off-CPU) | `/debug/fgprof?seconds=N` | Moderate | Third-party; overhead grows with goroutine count |

---

## Production Profiling Safety Rules

1. **Overhead budget**: Continuous profiling must stay under **2% CPU overhead**. Targeted profiling during incidents: up to 5%, with duration limits.
2. **CPU profile is always safe**: 100Hz sampling is negligible. Default choice for production.
3. **Heap profile is safe**: Sampling controlled by `runtime.MemProfileRate` (default: 1 sample per 512KB).
4. **Block/mutex profiles: NEVER rate=1 in production.** Rate=1 records every event — extreme overhead. Use `SetBlockProfileRate(1_000_000)` (1ms granularity) or higher. Use `SetMutexProfileFraction(100)` (1% sampling) or higher.
5. **Goroutine profile causes brief STW** when goroutine count is very high (>100k). Safe for normal counts.
6. **Execution trace is moderate overhead**. Keep duration short (5-10 seconds). Never leave running continuously.
7. **Never expose `/debug/pprof/` on a public port.** Use a separate internal listener (e.g., `localhost:6060`). Add authentication if network-accessible.
8. **Duration limits**: CPU profile max 60s in production. Trace max 10s. Set timeouts.
9. **Profile one replica at a time** when running continuous profiling across a fleet.

---

## Profiling Session Workflow

1. **Define the question** — What metric are you trying to improve? (P99 latency? Memory RSS? Throughput at N RPS?)
2. **Establish baseline** — Measure current performance with numbers under representative load.
3. **Collect profile** — Under the same load conditions as baseline. Match the profile type to your question.
4. **Analyze** — Use `top -cum`, `list`, flame graph. Identify the top 1-3 hotspots.
5. **Form hypothesis** — "Function X is doing Y unnecessary allocations per call."
6. **Make ONE change** — Implement a single optimization.
7. **Re-measure** — Collect a new profile under the same conditions.
8. **Compare** — Use `go tool pprof -diff_base=old.pb.gz new.pb.gz` or `benchstat`.
9. **Repeat or stop** — If the metric meets the target, stop. Otherwise, go to step 4.

---

## When to Load Reference Files

| Task | Reference file |
|---|---|
| Collecting or analyzing Go profiles, pprof CLI, continuous profiling, PGO | `references/go-pprof.md` |
| Writing, running, or comparing benchmarks | `references/go-benchmarks.md` |
| GC tuning, escape analysis, GODEBUG, runtime/metrics, go tool trace, GOGC/GOMEMLIMIT | `references/go-runtime-diagnostics.md` |
| Optimization patterns (sync.Pool, pre-alloc, concurrency, I/O) | `references/go-performance-patterns.md` |
| Language-agnostic profiling concepts, non-Go tools, production safety details | `references/general-profiling.md` |
| Reading and interpreting flame graphs | `references/flamegraph-interpretation.md` |

Load the relevant reference file(s) before giving detailed guidance. Multiple references can be loaded if the task spans topics.

---

## Anti-Patterns to Flag

- **Optimizing without a profile** — "I think this function is slow" without data. Always profile first.
- **Optimizing the wrong percentile** — Improving P50 when P99 is the problem (or vice versa).
- **Using `alloc_space` for leak detection** — Use `inuse_space` for leaks. `alloc_space` shows total allocation volume.
- **Block/mutex profiling at rate=1 in production** — Extreme overhead. Use sampling.
- **Exposing `/debug/pprof/` on public ports** — Security risk (information disclosure, DoS via CPU profile).
- **Benchmarks without `b.ResetTimer()`** — Setup time included in results, skewing data.
- **Benchmarks with dead code** — Compiler eliminates unused results. Use `b.Loop()` (Go 1.24+) or assign to package-level sink variable.
- **Comparing profiles under different loads** — Profiles are only comparable under similar conditions.
- **Premature optimization** — Optimizing code that isn't a bottleneck. Profile identifies what matters.
- **Multiple changes between measurements** — Can't attribute improvement to any single change.
