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

## Engine / Conversation Shutdown Lifecycle

> [!CAUTION]
> **Conversation.deinit MUST run before Engine.deinit.** The native conversation handle (`CConversationHandle`) depends on the native engine being alive. If `litert_lm_engine_delete` runs before `litert_lm_conversation_delete`, the conversation's handle becomes a dangling pointer → **EXC_BAD_ACCESS crash**.

### Correct Shutdown Pattern
```swift
func shutdown() {
    // Use withExtendedLifetime to guarantee ordering.
    // This is a compiler barrier — the engine won't be deallocated
    // until after the closure completes.
    if let engineRef = engine {
        withExtendedLifetime(engineRef) {
            conversation = nil  // Conversation.deinit runs HERE, while engine is alive
        }
    } else {
        conversation = nil
    }
    engine = nil  // NOW safe — conversation is already gone
}
```

### Incorrect Pattern
```swift
// ❌ WRONG: ARC ordering is not guaranteed
func shutdown() {
    conversation = nil  // May or may not dealloc immediately
    engine = nil        // If engine deallocs first → crash in Conversation.deinit
}

// ❌ ALSO WRONG: `_ = ref` can be optimized away
let engineRef = engine
conversation = nil
_ = engineRef  // Compiler may optimize this out
engine = nil
```

### XCTest Host App Conflict
When running XCTests on a physical device, the test runner launches the host app. If the app's `onAppear` auto-loads a model (e.g., `checkForLocalModels()`), it creates engine/conversation instances that compete for GPU resources with the test's own instances.

**Fix**: Guard auto-loading behind XCTest detection:
```swift
.onAppear {
    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
        return  // Skip auto-load when running under test harness
    }
    viewModel.checkForLocalModels()
}
```

## SamplerConfig

`SamplerConfig` controls the sampling strategy for token generation. It must be injected during conversation creation, not after.

### Usage
```swift
let samplerConfig = try SamplerConfig(topK: 1, topP: 1.0, temperature: 1.0, seed: 42)
let convConfig = ConversationConfig(systemMessage: Message("You are a helpful assistant.", role: .system), samplerConfig: samplerConfig)
let conversation = try await engine.createConversation(with: convConfig)
```

### Parameters
| Parameter | Default | Gallery v1.0.6 | Notes |
|-----------|---------|----------------|-------|
| `topK` | 64 | 1 (greedy) | topK=1 forces deterministic output |
| `topP` | 0.95 | 1.0 | No nucleus filtering |
| `temperature` | 1.0 | 1.0 | No temperature scaling |
| `seed` | 0 | — | 0 = non-deterministic; positive = reproducible generation |

> [!WARNING]
> **topK=1 (greedy) vs topK=64 (sampling) affects benchmark speed.** Greedy decoding is faster because the sampler does less work. When comparing against Gallery numbers, always use topK=1 for parity.

## ConversationConfig

`ConversationConfig` controls conversation-level settings including system messages, initial history, and tool definitions.

### Parameters
| Parameter | Type | Default | Notes |
|-----------|------|---------|-------|
| `systemMessage` | `Message?` | `nil` | Sets model persona/instructions. Auto-converts role to `.system`. |
| `initialMessages` | `[Message]` | `[]` | Pre-populate conversation history |
| `tools` | `[Tool]` | `[]` | Function calling tool definitions (NEW — see Tool Use section) |
| `samplerConfig` | `SamplerConfig?` | `nil` | Override sampler for this conversation |

> [!WARNING]
> Do NOT put a system message both in `systemMessage` AND in `initialMessages` — the SDK will throw an error for duplicate system messages.

## EngineConfig Updates (v0.13.0-dev)

New parameters available on `EngineConfig`:
| Parameter | Type | Default | Notes |
|-----------|------|---------|-------|
| `maxNumTokens` | `Int?` | `nil` | KV-cache size control. Throws if ≤ 0. |
| `cacheDir` | `String?` | `nil` | Cache directory for compiled artifacts |
| `audioBackend` | `Backend?` | `nil` | Separate backend for audio processing |

## Conversation API Updates (v0.13.0-dev)

New methods available on `Conversation`:
| Method | Signature | Notes |
|--------|-----------|-------|
| `cancel()` | `func cancel() throws` | Cancel ongoing inference. **Leaks stream context** — see Known Issues. |
| `renderMessageIntoString()` | `func renderMessageIntoString(_ message: Message) throws -> String` | Debug message rendering |
| `sendMessage` / `sendMessageStream` | `extraContext: [String: Any]?` parameter | Pass extra context alongside messages |

## Message Content Types (v0.13.0-dev)

The `Content` enum now supports multimodal input:
```swift
public enum Content {
    case text(String)
    case imageData(Data)     // Raw image bytes
    case imageFile(String)   // Image by file path
    case audioData(Data)     // Raw audio bytes
    case audioFile(String)   // Audio by file path
}
```

> [!TIP]
> Combined with Gemma 4 12B's native multimodal support (`supportsImage: true`, `supportsAudio: true`), these content types enable image and audio input without external preprocessing.

## Tool Use / Function Calling (v0.13.0-dev — NEW)

The SDK now supports native function calling via the `Tool` protocol:

```swift
struct GetWeatherTool: Tool {
    static let name = "get_current_weather"
    static let description = "Get the current weather"

    @ToolParam(description: "The city and state")
    var location: String

    @ToolParam(description: "Temperature unit")
    var unit: String = "celsius"  // default value = optional param

    func run() async throws -> Any {
        return ["temperature": 72, "unit": unit]
    }
}

// Pass tools to conversation:
let config = ConversationConfig(tools: [GetWeatherTool()])
let conversation = try await engine.createConversation(with: config)
```

### Key Points:
- `@ToolParam` property wrapper auto-generates OpenAPI-compliant JSON schemas
- `ToolManager` handles the tool call loop (up to 25 iterations) automatically
- `ExperimentalFlags.convertCamelToSnakeCaseInToolDescription` (default `true`) auto-converts Swift camelCase to snake_case
- Built-in `Role.tool` for tool response messages

> [!IMPORTANT]
> Tool calling is fully available in the SDK but **not yet integrated** in GemmaEdgeGallery. This is a high-priority feature for Gallery parity.

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
ExperimentalFlags.convertCamelToSnakeCaseInToolDescription = true  // NEW: auto snake_case for tool names
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
| **Gemma-4-12B-it (Dense)** | gemma-4-12B-it.litertlm | 6.50 GB | ✅ Desktop | ✅ XNNPACK | GPU+CPU (≥16GB RAM) | GPU+CPU | CPU only | ✅ | google/gemma-4-12b-it-litert-lm |

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
The project tracks LiteRT-LM `main` branch from the upstream Google repo:

```swift
// In Project.swift
.package(url: "https://github.com/google-ai-edge/LiteRT-LM.git", branch: "main")
// Currently resolved to commit aeefa9b
```

### Version History
| Commit | Date | Status | Notes |
|--------|------|--------|-------|
| `aeefa9b` | 2026-05-29 | **Current** | Main HEAD. Includes: `seed`, `systemMessage`, `tools`, `Capabilities`, multimodal Content types, `cancel()`, `extraContext`. Verified on macOS + iPhone 16 Pro Max. |
| `3a97cbf` | 2026-05-28 | Previous | Initial known-good. |

### New API Surface (v0.13.0-dev at aeefa9b)
| API | Status in App | Category |
|-----|---------------|----------|
| `SamplerConfig.seed` | ✅ Integrated | Reproducibility |
| `ConversationConfig.systemMessage` | ✅ Integrated | Persona/instructions |
| `ConversationConfig.tools` | 🟡 Available, not integrated | Function calling |
| `Content.imageData/imageFile` | 🟡 Available, not integrated | Multimodal |
| `Content.audioData/audioFile` | 🟡 Available, not integrated | Multimodal |
| `Capabilities` class | 🟡 Available, not integrated | Model capability queries |
| `EngineConfig.maxNumTokens` | 🟡 Available, not integrated | KV-cache control |
| `Conversation.cancel()` | ✅ Already using | Inference cancellation |
| `Conversation.renderMessageIntoString()` | 🟡 Available, not integrated | Debug rendering |

### Upgrade Procedure
1. Commit current working state
2. Run `swift package update` to pull latest
3. Build for macOS: `xcodebuild build -scheme GemmaEdgeGallery_macOS -quiet`
4. Build for iOS: `xcodebuild build -scheme GemmaEdgeGallery_iOS -destination generic/platform=iOS -quiet`
5. Run unit tests on simulator
6. If all pass, commit the updated `.package.resolved`
7. Run on-device benchmarks to verify no performance regressions

> [!TIP]
> The upstream repo URL changed from `nicklkfoster/LiteRT-LM` to `google-ai-edge/LiteRT-LM`. Use the google-ai-edge URL for the latest.

## Gallery Parity Benchmarks (Session 6 — 2026-05-31)

On-device results from iPhone 16 Pro Max, topK=1 greedy mode:

| Model | SDK Benchmark Decode | Gallery Decode | Delta |
|-------|---------------------|----------------|-------|
| Gemma 4 E2B Standard/GPU | **43.09 tok/s** (S4 wall) | 41.65 tok/s | ✅ **+3.5%** |
| Gemma 3n E2B HW/GPU | **25.71 tok/s** (SDK mode) | 25.57 tok/s | ✅ **+0.5%** |

Full results: `metrics/gallery_parity_results.md`

### Known Test Limitations

- **BenchmarkInfo nil on first turn** ✅ FIXED (Session 6): SDK doesn't report metrics for the first turn of each **session** (per-session, not per-engine). Fixed by NOT resetting after warmup — warmup is turn 1, benchmark is turn 2 with BenchmarkInfo available. The small warmup context (~20 tokens) is negligible for 256-token benchmarks.

- **Context accumulation** ✅ FIXED (Session 5): Reusing single `Conversation` caused context overflow on Run 3+. Fixed via `resetConversation()`.

- **resetConversation race condition** ✅ FIXED (Session 6): `sendMessageStream()` captured a local strong reference to `Conversation` in its inner Task. Even after `self.conversation = nil`, the Task held the reference, preventing `Conversation.deinit`. Fixed by tracking the active inference Task via `activeInferenceTask` and awaiting it in `resetConversation()`.

- **Metal sampler library** 📋 DOCUMENTED (Upstream):
  `libLiteRtTopKMetalSampler.dylib` not loaded at runtime. Root cause: Git LFS pointers in prebuilt/, xcframework excludes dylib. Falls back to C API. No impact for topK=1.

- **Gemma 3n decode gap** ✅ RESOLVED (Session 6): The -25% gap was **methodology difference**, not model variant. Using the SDK's `benchmark()` function (exact Gallery methodology), the HW variant achieves 25.71 tok/s — matching Gallery's 25.57 tok/s within 0.5%.

- **SDK benchmark() decode token cap**: The `benchmark()` function only generates 32 decode tokens despite requesting 256. This appears to be a model-level EOS constraint in synthetic benchmark mode.
