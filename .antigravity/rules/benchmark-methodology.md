# Benchmark Methodology

When running or analyzing benchmarks, follow these standards for consistent, comparable results across sessions.

## Canonical Benchmark Configuration

To compare results across our app, the AI Edge Gallery, and HuggingFace model cards, use these standardized configurations:

### Gallery Parity Config (Default)
| Parameter | Value | Rationale |
|---|---|---|
| Prefill tokens | 256 | Matches Gallery v1.0.6 |
| Decode tokens | 256 | Matches Gallery v1.0.6 |
| Number of runs | 3 | Matches Gallery v1.0.6 |
| Accelerator | GPU | Primary benchmark target |
| MTP | OFF (baseline), then ON (parity) | Two-pass approach |
| Warm-up | Discard first run for MTP tests | MTP has 30-40x cold-start |
| Averaging | Mean (with individual values reported) | Gallery uses median |

### HuggingFace Comparison Config
| Parameter | Value |
|---|---|
| Prefill tokens | 1024 |
| Decode tokens | 256 |
| Context length | 2048 |

## Key Methodology Differences to Watch

| Factor | Gallery | HuggingFace | Our App |
|---|---|---|---|
| topK | 1 (greedy) | Not specified | 64 (SDK default) |
| topP | 1.0 | Not specified | 0.95 |
| MTP | ON by default | Not specified | OFF by default |
| Primary model | Gemma-3n-E2B-it / Gemma-4-E2B-it | Varies | Gemma-4-E2B-it |

> [!WARNING]
> **topK=1 (greedy) vs topK=64 (sampling) affects benchmark speed.** Greedy decoding is typically faster because the sampler does less work. When comparing against Gallery numbers, note this discrepancy.

> [!NOTE]
> **Gemma 4 12B (6.5GB)** is available for benchmarking. It requires ≥16GB device RAM and is only recommended for GPU backends. Configs 9-10 in the automation matrix target 12B.

## Test Classes

| Test Class | Purpose | Token Config |
|---|---|---|
| `PerformanceTests` | XCTMetric-based (memory, CPU, clock) | Short prompt |
| `SimulatorCompatibilityTests` | Model/backend compatibility matrix | Short prompt |
| `GalleryParityBenchmarkTests` | Gallery-comparable benchmarks | 256 prefill, 256 decode, 3 runs |
| `SmartFallbackIntegrationTests` | End-to-end registry→engine→inference | Short prompt |

## Reporting Standards

When reporting benchmark results:
1. **Always include the configuration** — prefill tokens, decode tokens, MTP on/off, backend, device
2. **Report individual run values** alongside averages
3. **Note the model variant** — Standard vs Mobile GPU vs HW
4. **Specify the device** — iPhone model and chip (e.g., "iPhone 16 Pro Max / A18 Pro")
5. **Timestamp results** — SDK versions and model files change over time
6. **Capture BenchmarkInfo** when available — it's SDK-native and most accurate
7. **Use wall-clock for MTP** — BenchmarkInfo returns nil with MTP enabled

## Known Caveats

1. **Short prompts understate prefill throughput** — GPU parallelism needs ≥256 tokens to saturate the pipeline
2. **MTP nullifies BenchmarkInfo** — Fall back to `os_signpost` or wall-clock timing
3. **CPU inference fails silently for Mobile GPU models** — They have no XNNPACK subgraph; Gallery reports zeros
4. **MTP cold-start is ~30-40x slower** — Always note whether you're measuring first init or warm init
5. **Simulator GPU is unreliable** — Always use CPU on simulator; GPU produces degenerate output
6. **LiteRT-LM C++ Deallocation Deadlocks** — Re-initializing or mutating the engine configurations within a single process lifecycle can trigger deadlocks or segmentation faults (`SIGSEGV`) in the underlying binary C++ LiteRT-LM framework. **Always** run multi-configuration benchmarks in isolated process launches (e.g., using `-RunMatrixBenchmark <id>`) to allow the OS to cleanly reclaim C++ handles on exit.
7. **Strict 256-Token Generation Cap** — For metrics parity with the Gallery baseline and to prevent OOM/timeouts on local devices, benchmarks must consume the streaming API (`sendMessageStream`) and cooperatively break as soon as exactly 256 decode tokens are output.
8. **12B model memory pressure** — The 12B model requires ≥16GB RAM. On iOS devices with less memory, the system may OOM-kill the process. Use `increased-memory-limit` entitlement and test on supported hardware only.
9. **SamplerConfig.seed for reproducibility** — Set `seed` to a non-zero value (e.g., `42`) for reproducible benchmark runs. Default `0` means non-deterministic.

