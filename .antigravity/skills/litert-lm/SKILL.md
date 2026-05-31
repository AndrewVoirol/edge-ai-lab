---
name: litert-lm
description: "Strict rules for interacting with the Google LiteRT-LM SDK and preventing memory/concurrency bugs. Activate when working with Engine, Conversation, BenchmarkInfo, or ExperimentalFlags."
---

# LiteRT-LM Engine Guidelines

This app runs Gemma 4 models on-device using the `LiteRT-LM` library. These rules prevent crashes, memory corruption, and concurrency bugs.

## Security-Scoped Resource Lifetime

> [!CAUTION]
> The LiteRT-LM engine uses `mmap` to map the model file into memory. If the security-scoped resource is released while the engine is alive, the app **will crash** with a `SIGBUS` signal.

### Rules
1. **MUST** call `url.startAccessingSecurityScopedResource()` **before** creating `EngineConfig`
2. **MUST NOT** call `url.stopAccessingSecurityScopedResource()` while the `Engine` or `Conversation` is alive
3. Store the URL and only call `stopAccessing...` in `shutdown()` or `deinit`
4. The model file stays mapped for the entire lifetime of the engine

### Correct Pattern
```swift
// ✅ Correct: start before engine, stop after shutdown
url.startAccessingSecurityScopedResource()
let config = try EngineConfig(modelPath: url.path, ...)
let engine = Engine(engineConfig: config)
try await engine.initialize()
// ... use engine ...
engine = nil  // or shutdown()
url.stopAccessingSecurityScopedResource()  // NOW it's safe
```

### Incorrect Pattern
```swift
// ❌ WRONG: releasing resource while engine is alive
url.startAccessingSecurityScopedResource()
let engine = Engine(...)
url.stopAccessingSecurityScopedResource()  // 💥 SIGBUS crash
try await engine.initialize()  // mmap'd memory is now invalid
```

## Swift Concurrency & @MainActor

- All `@State` mutations **must** be `@MainActor`
- The `InstrumentedEngine` wraps inference in `Task { @MainActor in ... }`
- `Engine.initialize()` and `Conversation.sendMessageStream()` are `async` — always `await` them
- Never block the main thread with synchronous engine operations

## ExperimentalFlags API

> [!IMPORTANT]
> You **MUST** call `ExperimentalFlags.optIntoExperimentalAPIs()` before setting any experimental flag. Failure to do so will silently ignore all flag settings.

### Available Flags
```swift
// Call this FIRST — once, before any flags
ExperimentalFlags.optIntoExperimentalAPIs()

// Then set flags
ExperimentalFlags.enableBenchmark = true          // Enables BenchmarkInfo capture
ExperimentalFlags.enableSpeculativeDecoding = true // Speculative decoding
ExperimentalFlags.enableConversationConstrainedDecoding = false
ExperimentalFlags.visualTokenBudget = 256          // For multimodal models
```

### ExperimentalFlagsState
The `ExperimentalFlagsState` struct encapsulates flag configuration:
```swift
struct ExperimentalFlagsState {
    var enableBenchmark: Bool
    var enableSpeculativeDecoding: Bool?
    var enableConversationConstrainedDecoding: Bool
    var visualTokenBudget: Int?
    
    func applyToGlobalFlags() { ... }  // Sets ExperimentalFlags globals
}
```

## BenchmarkInfo API

After inference completes, retrieve performance data:
```swift
let benchmarkInfo = try conversation.getBenchmarkInfo()
// Properties:
//   benchmarkInfo.prefillTokens     — Number of prompt tokens processed
//   benchmarkInfo.prefillTime       — Time to process prompt (seconds)
//   benchmarkInfo.decodeTokens      — Number of output tokens generated
//   benchmarkInfo.decodeTime        — Time to generate output (seconds)
```

- Only available when `ExperimentalFlags.enableBenchmark = true`
- Call **after** the response stream completes, not during
- Gracefully handle failures — benchmark data is best-effort

## Model Files
- File extension: `.litertlm`
- Location: `models/` directory (gitignored, locally provisioned)
- Typical size: ~2.0-3.7GB per model
- The app supports multiple models with user selection via `ModelRegistry`

## Model Variant Compatibility Matrix

| Model | File | Size | GPU | CPU | iOS Device | macOS | Simulator | MTP | Source |
|---|---|---|---|---|---|---|---|---|---|
| Gemma-3n-E2B-it | gemma-3n-E2B-it-int4.litertlm | 3.39 GB | ✅ Mobile | ❌ | GPU-only (24.0 tok/s) | GPU Only | GPU Only | ✅ | google/gemma-3n-E2B-it-litert-lm |
| Gemma-3n-E2B-HW | gemma-3n-E2B-HW.litertlm | 2.83 GB | ✅ Mobile | ❌ | GPU-only (24.0 tok/s) | GPU Only (78.6 tok/s) | GPU Only (degenerate) | ✅ | google/gemma-3n-E2B-it-litert-lm |
| Gemma-4-E2B-it (Standard) | gemma-4-E2B-it.litertlm | 2.59 GB | ✅ Desktop | ✅ XNNPACK | GPU (16.8 tok/s) + CPU (24.3 tok/s) | GPU+CPU | CPU only | ✅ | litert-community/gemma-4-E2B-it-litert-lm |
| Gemma-4-E2B-it (Mobile GPU) | gemma-4-E2B-it-web.litertlm | 2.01 GB | ✅ Mobile | ❌ | GPU-only (43.5 tok/s) | GPU Only (113.1 tok/s) | GPU Only (degenerate) | ✅ | litert-community/gemma-4-E2B-it-litert-lm |
| Gemma-4-E4B-it (Standard) | gemma-4-E4B-it.litertlm | 3.66 GB | ✅ Desktop | ✅ XNNPACK | GPU+CPU | GPU+CPU | CPU only | ✅ | litert-community/gemma-4-E4B-it-litert-lm |
| Gemma-4-E4B-it (Mobile GPU) | gemma-4-E4B-it-web.litertlm | 2.97 GB | ✅ Mobile | ❌ | GPU-only | GPU Only | GPU Only (degenerate) | ✅ | litert-community/gemma-4-E4B-it-litert-lm |

> [!NOTE]
> **Standard models** use desktop Metal GPU shaders — they work on both macOS and iOS devices (verified on iPhone 16 Pro Max, loads in ~2.33s on GPU). **Web/mobile models** use mobile Metal shaders optimized for A-series chips — they work on iOS devices but have no CPU fallback.

## Backend Selection Rules per Platform

### macOS
- Use `.gpu` for standard models — desktop Metal shaders are compatible with Apple Silicon Macs
- Standard models support both GPU and CPU, giving maximum flexibility
- Web variants are untested on macOS

### iOS Device
- Use `.gpu` for all model variants — standard models load successfully on GPU on A-series iOS chips (verified on iPhone 16 Pro Max)
- Standard models support both GPU and CPU, giving fallback flexibility via `initializeWithFallback()`
- Web/mobile GPU variants (`-web`, `-int4`, `-HW`) have no CPU subgraph — if GPU fails, there is no fallback

### iOS Simulator
- **Always use `.cpu()`** — Metal shader translation is unreliable
- Only standard models work (they have XNNPACK CPU subgraphs)
- Web/mobile variants cannot run on the simulator at all

## MTP / Speculative Decoding

Multi-Token Prediction (MTP) uses speculative decoding to significantly improve prefill throughput.

### Enablement
```swift
// MUST opt in first
ExperimentalFlags.optIntoExperimentalAPIs()
ExperimentalFlags.enableSpeculativeDecoding = true
```

### Requirements
- Model must have `capabilities: ["speculative_decoding"]` in its allowlist config
- All models in the current catalog support MTP

### Performance Impact
- **Prefill speed**: ~305 tok/s with MTP vs ~71 tok/s without (4.3x improvement)
- **Decode speed**: Gemma 3n GPU = 24.0 tok/s, Web GPU = 43.5 tok/s, Standard CPU = 24.3 tok/s
- **Recommended**: Enable for GPU backends where speculative overhead is negligible
- Gallery iOS app achieves 305.45 tok/s prefill and 39.23 tok/s decode with MTP on iPhone 16 Pro Max

### Caveats
- **Cold-start init penalty**: ~30-40× longer initialization time on the first MTP-enabled load (engine compiles speculative graphs)
- **BenchmarkInfo returns nil with MTP**: `conversation.getBenchmarkInfo()` returns `nil` when speculative decoding is active — benchmark capture is incompatible with MTP in the current SDK version

> [!CAUTION]
> **MTP + CPU backend CRASHES on iOS device.** Enabling `enableSpeculativeDecoding = true` with a CPU backend on a physical iOS device causes an SDK crash at an external symbol. Only use MTP with GPU backend on device. (MTP + CPU on macOS works fine — ~18 tok/s effective.)

## SDK Version Management

### Current Configuration
The project currently pins LiteRT-LM to `branch: main` at a specific commit:

```swift
// In Project.swift
.package(url: "https://github.com/nicklkfoster/LiteRT-LM", branch: "main")
// Pinned to commit 3a97cbf in .package.resolved
```

### Recommended Configuration
For stability, keep the current pin to the known-good commit:

```swift
// Current known-good configuration (commit 3a97cbf)
.package(url: "https://github.com/nicklkfoster/LiteRT-LM", branch: "main")
// Pinned to commit 3a97cbf in .package.resolved
```

### Version Notes
- **Commit `3a97cbf`**: Known-good commit with Swift APIs, Metal GPU support, tested on all platforms
- **`branch: main`**: Gets latest changes but may include breaking API changes
- When upgrading, test on all platforms (macOS, iOS device, simulator) before committing

> [!TIP]
> If you switch to `from: "0.12.0"`, run `tuist generate` and resolve any API differences. The branch-based pin at commit `3a97cbf` is known-good with the current codebase.
