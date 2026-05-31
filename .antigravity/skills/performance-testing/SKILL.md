---
name: performance-testing
description: "Guidelines for running performance tests, capturing metrics, and managing the JSON metrics store for trend tracking. Activate when working with tests, benchmarks, or performance analysis."
---

# Performance Testing Framework

## Test Architecture: Two Layers

Tests are organized into two test plans for selective execution:

| Test Plan | Purpose | Model Required | Speed | Files |
|---|---|---|---|---|
| **UnitTests** | Logic validation with mocks | ❌ No | Fast (seconds) | `GemmaEdgeGalleryTests.swift`, `MockInstrumentedEngine.swift` |
| **PerformanceTests** | Real inference benchmarking | ✅ Yes | Slow (minutes) | `PerformanceTests.swift` |

### InstrumentedEngineProtocol
All tests use the `InstrumentedEngineProtocol` abstraction:
- **Unit tests** inject `MockInstrumentedEngine` — fast, deterministic, no model needed
- **Performance tests** use `InstrumentedEngine` — real LiteRT-LM inference with signposts

> [!IMPORTANT]
> **Never call LiteRTLM APIs directly from test code.** Always go through `InstrumentedEngineProtocol`.

## Running Tests

### Unit Tests (fast, no model)
```
MCP Server: xcodebuild-mcp
Tool: simulator test
Args: scheme=GemmaEdgeGallery_iOS, workspace=GemmaEdgeGallery.xcworkspace, testPlan=UnitTests
```

### Performance Tests

Performance tests auto-discover models and select the appropriate backend:

#### Model Discovery (Option C: env var + fallback)
1. `PERFORMANCE_TEST_MODEL_PATH` env var — highest priority (CI/automation)
2. `models/` directory relative to project root — local macOS dev
3. App Documents directory — simulator/device with provisioned model

> [!TIP]
> The Desktop GPU+CPU model (`gemma-4-E2B-it.litertlm`) is preferred over the Mobile GPU variant — it supports both CPU and GPU backends.

> [!IMPORTANT]
> **Physical device tests run inside the app sandbox via `TEST_HOST`.** The test runner is hosted by the app process, meaning model files must be in the app's Documents directory — not the test bundle. This also means `#filePath` does NOT resolve to the project directory on physical devices; it points into the app container. Use `FileManager` APIs to locate files at runtime.

#### Backend Auto-Selection
- **macOS / Physical iOS device:** GPU (Metal)
- **iOS Simulator:** CPU (XNNPACK) — Metal shader translation on the simulator produces corrupted tensor computations

#### Running via XcodeBuildMCP
```
# No env var needed (auto-discovers model)
MCP Server: xcodebuild-mcp
Tool: test_sim
Args: extraArgs=["-only-testing:GemmaEdgeGallery_iOSTests/PerformanceTests"]

# With explicit model path (CI)
MCP Server: xcodebuild-mcp
Tool: test_sim
Args: extraArgs=["-only-testing:GemmaEdgeGallery_iOSTests/PerformanceTests"],
      testRunnerEnv={"PERFORMANCE_TEST_MODEL_PATH": "/path/to/model.litertlm"}
```

#### Platform Compatibility (Verified)

| Model | Backend | macOS | iOS Simulator | iOS Device |
|---|---|---|---|---|
| `gemma-4-E2B-it` | GPU | ✅ 33.8 tok/s | ❌ crash | ✅ loads on iPhone 16 Pro Max |
| `gemma-4-E2B-it` | CPU | ✅ 30.8 tok/s | ✅ 29.4 tok/s | ✅ 23.7 tok/s |
| `gemma-4-E2B-it-web` | GPU | ✅ | ❌ degenerate | ✅ **42.9 tok/s** |
| `gemma-4-E2B-it-web` | CPU | ❌ no subgraph | ❌ no subgraph | ❌ no subgraph |
| `gemma-3n-E2B-it` | GPU | ⚠️ untested | ❌ crash | ✅ 24.0 tok/s |

> [!WARNING]
> GPU inference on the iOS Simulator crashes or produces degenerate output. This is a known Apple limitation — the simulator translates Metal shaders to the host Mac GPU, which is not bit-identical. See [Apple docs](https://developer.apple.com/documentation/metal/developing_metal_apps_that_run_in_simulator). Always use CPU backend on the simulator.

## Metrics Store

Test results are automatically captured to `metrics/history.json` by a PostToolUse hook after every test execution via XcodeBuildMCP.

### Schema
Each entry in `metrics/history.json`:
```json
{
  "timestamp": "2026-05-29T20:00:00Z",
  "testPlan": "PerformanceTests",
  "results": [
    {
      "suite": "PerformanceTests",
      "test": "testInferenceLatency",
      "status": "passed",
      "durationMs": 1234
    }
  ],
  "flags": {
    "enableBenchmark": true,
    "enableSpeculativeDecoding": null,
    "enableConversationConstrainedDecoding": false
  },
  "model": "gemma-4-E2B-it-web.litertlm",
  "device": "iPhone 16 Pro Simulator"
}
```

### Purpose
The metrics store enables trend tracking across:
- Model changes (drop in different models, compare performance)
- Feature additions/removals (impact on latency/memory)
- Flag configurations (speculative decoding impact)
- Device variations (simulator vs device)

## os_signpost Categories

The `InstrumentedEngine` emits signposts under subsystem `com.andrewvoirol.GemmaEdgeGallery.performance`:

| Category | Signpost | What It Measures |
|---|---|---|
| `model-load` | `ModelLoad` | Time from engine init to model ready |
| `inference` | `Inference` | Full inference duration (prompt to completion) |
| `first-token` | `FirstToken` | Time to first token (TTFT) |

## Baseline Methodology
- No hard CI/CD failures on regressions
- Metrics are append-only for trend analysis
- Agents query `metrics/history.json` to detect regressions
- Human review for significant regressions

## Multi-Model Test Matrix

When testing across multiple models, use this matrix to ensure coverage:

| Model | File | Test on macOS | Test on iOS Device | Test on Simulator |
|---|---|---|---|---|
| Gemma-4-E2B-it (Standard) | gemma-4-E2B-it.litertlm | GPU ✅ + CPU ✅ | GPU ✅ + CPU ✅ | CPU only ✅ |
| Gemma-4-E2B-it (Mobile GPU) | gemma-4-E2B-it-web.litertlm | GPU ⚠️ untested | GPU ✅ | ❌ Cannot run |
| Gemma-4-E4B-it (Standard) | gemma-4-E4B-it.litertlm | GPU ✅ + CPU ✅ | CPU only ✅ | CPU only ✅ |
| Gemma-4-E4B-it (Mobile GPU) | gemma-4-E4B-it-web.litertlm | GPU ⚠️ untested | GPU ✅ | ❌ Cannot run |
| Gemma-3n-E2B-it | gemma-3n-E2B-it-int4.litertlm | GPU ⚠️ untested | GPU ✅ | ❌ Cannot run |
| Gemma-3n-E2B-HW | gemma-3n-E2B-HW.litertlm | GPU ⚠️ untested | GPU ✅ | ❌ Cannot run |

> [!TIP]
> Start with `gemma-4-E2B-it.litertlm` (Desktop GPU+CPU) — it's the only model that works on all platforms with CPU fallback. Then add Mobile GPU variants for iOS device GPU testing.

## GPU Verification Procedures (Physical Devices)

GPU inference on physical iOS devices requires specific model variants. Follow this procedure:

### Pre-Flight Checks
1. Ensure you have a `-web` or `-int4` model variant (mobile Metal shaders)
2. Verify the device has sufficient RAM (check `minDeviceMemoryInGb` in model catalog)
3. Confirm the model is provisioned to the app's Documents directory

### Provisioning Models to Physical Devices
Use `devicectl` to copy model files into the app's Documents directory on a physical device:
```bash
# List connected devices
xcrun devicectl list devices

# Copy model to app container
xcrun devicectl device copy-to \
  --device <device-identifier> \
  /path/to/local/model.litertlm \
  --bundle-id com.andrewvoirol.GemmaEdgeGallery \
  --domain-type appDataContainer \
  --domain-path Documents/model.litertlm
```

### GPU Test Procedure
```bash
# 1. Build and deploy to physical device
xcodebuildmcp device build --scheme GemmaEdgeGallery_iOS

# 2. Run performance tests targeting GPU
xcodebuildmcp device test --scheme GemmaEdgeGallery_iOS \
  --test-plan PerformanceTests \
  --testRunnerEnv PERFORMANCE_TEST_MODEL_PATH=/path/to/gemma-4-E2B-it-web.litertlm
```

### Verification Checklist
- [ ] Engine initialization succeeds (no `failedToCreateEngine`)
- [ ] First token appears within expected TTFT range
- [ ] Output is coherent (not degenerate/garbage)
- [ ] Decode speed is in expected range (>30 tok/s for E2B on modern devices)
- [ ] No memory warnings or crashes during inference
- [ ] `BenchmarkInfo` captures valid prefill and decode metrics

### Common GPU Failures
| Symptom | Cause | Fix |
|---|---|---|
| `failedToCreateEngine` | Shader compilation failure | Try `-web` or `-int4` variant (note: Desktop GPU+CPU model GPU works on iPhone 16 Pro Max) |
| Degenerate output | Simulator Metal shader translation | Use CPU backend on simulator |
| OOM crash | Model too large for device RAM | Use smaller variant (E2B vs E4B) |
| Slow performance | CPU fallback activated silently | Check logs for backend selection |

## MTP Benchmarking Methodology

Multi-Token Prediction (MTP) via speculative decoding can dramatically improve prefill speed. Benchmark MTP impact with this methodology:

> [!WARNING]
> **MTP Cold-Start Penalty:** Enabling MTP incurs a ~30-40x cold-start initialization penalty on first engine creation (e.g., ~30s vs ~0.8s without MTP). This is a one-time cost per engine init — subsequent inferences are fast. Always discard the first run when benchmarking MTP.

> [!CAUTION]
> **`BenchmarkInfo` returns `nil` with MTP enabled.** When `enableSpeculativeDecoding = true`, the `BenchmarkInfo` struct from LiteRT-LM returns `nil` for prefill/decode metrics. You must measure performance via `os_signpost` timestamps or wall-clock timing instead of relying on `BenchmarkInfo`.

> [!CAUTION]
> **MTP + CPU backend CRASHES on iOS device.** Enabling speculative decoding with a CPU backend on a physical iOS device causes an SDK crash at an external symbol. Only use MTP with GPU backend on device. (MTP + CPU works fine on macOS — 35.5s for 101 tokens.)

### Test Configuration
```swift
// Test 1: Baseline (no MTP)
ExperimentalFlags.optIntoExperimentalAPIs()
ExperimentalFlags.enableBenchmark = true
ExperimentalFlags.enableSpeculativeDecoding = false

// Test 2: With MTP
ExperimentalFlags.optIntoExperimentalAPIs()
ExperimentalFlags.enableBenchmark = true
ExperimentalFlags.enableSpeculativeDecoding = true
```

### Metrics to Compare
| Metric | Without MTP | With MTP | Expected Improvement |
|---|---|---|---|
| Prefill speed (tok/s) | ~71 | ~305 | ~4.3x |
| Decode speed (tok/s) | ~39 | ~39 | Minimal change |
| TTFT (seconds) | ~3.6 | ~0.87 | ~4x faster |
| Cold-start init time | ~0.8s | ~25-30s | ~30-40x penalty |

### Methodology
1. Use fixed prompt (256 tokens prefill, 256 tokens decode)
2. Run minimum 3 iterations, discard first run (cold start — especially important with MTP due to ~30-40x init penalty)
3. Report median values
4. Test on same device, same model variant, same backend
5. Record both MTP-on and MTP-off results in the same session
6. When MTP is enabled, use `os_signpost` timing — `BenchmarkInfo` returns `nil` with speculative decoding

## Updated Baseline Numbers

### Gallery Benchmark (Reference Target — Session 3b, 2026-05-31)
Captured by user from iOS Gallery app v1.0.6 on iPhone 16 Pro Max:

| Model | Accel | Prefill (tok/s) | Decode (tok/s) | TTFT (s) | Init (ms) | Config |
|---|---|---|---|---|---|---|
| Gemma-4-E2B-it | GPU | **360.35** | **41.65** | **0.74** | **9192** | 256 prefill/decode, 3 runs |
| Gemma-3n-E2B-it | GPU | **392.86** | **25.57** | **0.70** | **8194** | 256 prefill/decode, 3 runs |
| Gemma-4-E2B-it | CPU | 0.00 | 0.00 | 0.00 | 0.00 | CPU fails silently |

> [!WARNING]
> **CPU accelerator returns all zeros** in the Gallery for Gemma 4 E2B. This confirms that CPU inference is unsupported or crashes silently for this model variant. The model's `.litertlm` file only contains GPU (Artisan Metal) shaders with no XNNPACK CPU subgraph.

> [!NOTE]
> **Gallery init times (9.2s / 8.2s) include MTP drafter compilation.** The Gallery enables MTP by default, and the "first init time" metric includes the drafter model compilation. This aligns with the ~30-40x cold-start penalty observed in our tests.

### GemmaEdgeGallery Baselines (Verified)

| Model | Platform | Backend | Decode (tok/s) | Notes |
|---|---|---|---|---|
| gemma-4-E2B-it | macOS | GPU | 33.8 | Desktop Metal shaders |
| gemma-4-E2B-it | macOS | CPU | 30.8 | XNNPACK |
| gemma-4-E2B-it | iOS Simulator | CPU | 29.4 | XNNPACK (only safe option) |
| gemma-4-E2B-it | iOS Device | CPU | 24.3 | XNNPACK fallback |
| gemma-4-E2B-it-web | iOS Device | GPU | 42.9 | Mobile Metal shaders |
| gemma-3n-E2B-it | iOS Device | GPU | 24.0 | Mobile Metal shaders |
| gemma-3n-E2B-it-web | iOS Device | GPU | 43.5 | Mobile Metal shaders (web variant) |

> [!IMPORTANT]
> The Gallery achieves 305 tok/s prefill because it uses MTP (speculative decoding). Our 42.9 tok/s decode on iOS GPU is competitive for decode speed but we need MTP enabled to match prefill throughput.

### macOS Benchmark Baselines (Session 2)

| Model | Backend | Decode (tok/s) | Prefill (tok/s) | TTFT (s) |
|---|---|---|---|---|
| gemma-4-E2B-it | GPU | 109.9 | 324.8 | 0.058 |
| gemma-4-E2B-it-web | GPU | 113.1 | 123.7 | 0.138 |
| gemma-3n-E2B-HW | GPU | 78.6 | 89.8 | 0.191 |
| gemma-4-E2B-it | CPU | 32.9 | 83.8 | 0.221 |

#### macOS MTP Baselines (Effective Throughput)

| Model | Backend | Effective tok/s | Tokens | Wall Time |
|---|---|---|---|---|
| gemma-4-E2B-it-web | GPU + MTP | ~101 | 101 | 1.00s |
| gemma-3n-E2B-HW | GPU + MTP | ~68 | 101 | 1.48s |
| gemma-4-E2B-it | CPU + MTP | ~18 | 101 | 5.59s |

### iOS Simulator Expected Behavior

> [!WARNING]
> Simulator GPU inference is unreliable across all model variants. The simulator translates Metal shaders to the host Mac GPU, which produces non-deterministic results.

| Model | Backend | Simulator Behavior |
|---|---|---|
| Desktop GPU+CPU (`gemma-4-E2B-it`) | GPU | ❌ Fails — desktop Metal shaders can't compile in simulated GPU |
| Mobile GPU (`gemma-4-E2B-it-web`) | GPU | ⚠️ Loads but produces degenerate output |
| Gemma 3n (`gemma-3n-E2B-HW`) | GPU | ⚠️ Loads, inference runs but may produce degenerate output |
| Desktop GPU+CPU (`gemma-4-E2B-it`) | CPU | ⚠️ Loads but may crash (SEGV in SDK) |
| Any model | CPU + MTP | ❌ Crashes (same as device — MTP + CPU is not supported) |

## Model-Aware Test Configuration

Tests should automatically adapt based on the model being tested:

```swift
// Model-aware test setup
let modelFile = discoveredModelPath.lastPathComponent
let metadata = ModelRegistry.lookup(filename: modelFile)

switch (metadata?.backendCapability, PlatformSupport.currentPlatform) {
case (.gpuOnly, .simulator):
    XCTFail("GPU-only model cannot run on simulator")
case (.gpuOnly, _):
    // Force GPU, no fallback available
    config.backend = .gpu
case (.gpuAndCpu, .simulator):
    // Force CPU on simulator
    config.backend = .cpu()
case (.gpuAndCpu, _):
    // Use GPU with CPU fallback
    config.backend = .gpu  // initializeWithFallback handles the rest
default:
    config.backend = .cpu()
}
```

### Configuration per Model
| Model Variant | Simulator Config | Device Config | macOS Config |
|---|---|---|---|
| Desktop GPU+CPU (`*.litertlm`) | CPU only | GPU + CPU (GPU works, 16.8 tok/s decode) | GPU primary, CPU fallback |
| Mobile GPU (`*-web.litertlm`) | Skip test | GPU only | Skip or GPU (untested) |
| INT4 (`*-int4.litertlm`) | Skip test | GPU only | Skip or GPU (untested) |
