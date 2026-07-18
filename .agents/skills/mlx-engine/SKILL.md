---
name: mlx-engine
description: >
  Rules and patterns for working with the MLX inference engine in Edge AI Lab.
  Covers MLXEngineAdapter lifecycle, mlx-swift-lm API patterns, Metal memory
  management, Swift concurrency constraints, iOS Simulator guards, and
  GenerateCompletionInfo metrics. Activate when implementing, modifying, or
  debugging MLX engine code.
---

# MLX Engine Skill

## Core Architecture

Edge AI Lab uses a dual-runtime architecture:

```
InferenceEngine (protocol, runtime-agnostic)
├── LiteRTEngineAdapter → InstrumentedEngine → LiteRTLM SDK
└── MLXEngineAdapter → mlx-swift-lm (MLXLLM, MLXLMCommon, MLXVLM)
```

`MLXEngineAdapter` conforms to `InferenceEngine` and wraps `mlx-swift-lm`. It is a sealed containment boundary — all MLX-specific types (`MLXArray`, `ModelContainer`, `ChatSession`) stay inside; only `Sendable` Swift types cross the boundary.

## mlx-swift-lm API Reference (v3.x)

### Model Loading

```swift
import MLXLLM
import MLXLMCommon
import MLXHuggingFace

// Load from HuggingFace with progress
let container = try await LLMModelFactory.shared.loadContainer(
    configuration: ModelConfiguration(id: "mlx-community/gemma-4-e2b-it-4bit")
) { progress in
    // progress.fractionCompleted (0.0 → 1.0)
}

// For VLMs: use VLMModelFactory.shared.loadContainer(...)
```

**NEVER use**: `loadModel(id:)` — this is an outdated API from pre-3.x versions. The current API is `LLMModelFactory.shared.loadContainer(configuration:)`.

### Chat Session

```swift
let session = ChatSession(container)

// Stream response
for try await text in session.streamResponse(to: "Hello") {
    output += text
}
```

**Session reset**: `ChatSession` has NO explicit reset method. To reset conversation state (clear KV cache and history), **recreate the session**: `session = ChatSession(container)`. Preserve `instructions`, `tools`, `toolDispatch`, and `generateParameters` when recreating.

### Chat Session — Sampling Parameters

```swift
// Set sampling params directly on the session (mutable public var)
session.generateParameters.temperature = 0.6
session.generateParameters.topP = 0.9
session.generateParameters.topK = 40
session.generateParameters.maxTokens = 1024
session.generateParameters.repetitionPenalty = 1.1
session.generateParameters.seed = 42
```

### Chat Session — Tool Calling

```swift
// Set tool schemas on the session
session.tools = mlxToolSpecs  // [ToolSpec] from MLXToolBridge

// Wire automatic tool dispatch
session.toolDispatch = { toolCall in
    let name = toolCall.function.name
    let arguments = toolCall.function.arguments.mapValues { $0.anyValue }
    return try await MLXToolBridge.executeToolCall(toolName: name, arguments: arguments, tools: appTools)
}

// Use streamDetails() for native Generation events (text + tool calls + metrics)
for try await generation in session.streamDetails(to: prompt) {
    switch generation {
    case .chunk(let text): ...
    case .toolCall(let toolCall): ...
    case .info(let completionInfo): ...
    }
}
```

### Generation Stream (Advanced — with tool calls + metrics)

```swift
for await item in try MLXLMCommon.generate(input: input, parameters: params, context: context) {
    switch item {
    case .chunk(let string):          // Text token
    case .info(let completionInfo):   // GenerateCompletionInfo (metrics)
    case .toolCall(let call):         // Tool call detected
    }
}
```

### Performance Metrics — `GenerateCompletionInfo`

Metrics are emitted as `.info` case in the generation stream:

```swift
info.promptTime              // seconds to process prompt (prefill)
info.generationTime          // seconds for token generation
info.promptTokenCount        // number of prompt tokens
info.generationTokenCount    // number of generated tokens
info.promptTokensPerSecond   // promptTokenCount / promptTime
info.tokensPerSecond         // generationTokenCount / generationTime
info.stopReason              // .stop, .length, .cancelled
```

### Generation Parameters

```swift
var params = GenerateParameters()
params.temperature = 0.6     // Default: 0.6
params.topP = 1.0            // Default: 1.0 (nucleus sampling)
params.repetitionPenalty = 1.1  // Optional, MLX-only
params.maxTokens = 1024      // Optional
```

**`topK`** is a direct property on `GenerateParameters` as `topK: Int` (default: 0, which disables).

**`seed`**: Available as `GenerateParameters.seed: UInt64?`. When set, the sampler's RNG is seeded deterministically.

### Tool Calling

```swift
// Define tool with typed input/output
let tool = Tool<MyInput, MyOutput>(handler: { input in ... })

// ToolCallProcessor auto-detects model-specific formats
let processor = ToolCallProcessor(format: .gemma, tools: [tool])
```

Tool calls arrive as `.toolCall(ToolCall)` in the generation stream.

## Memory Management — CRITICAL

### Correct API (Memory enum)

```swift
import MLX

Memory.memoryLimit = 20 * 1024 * 1024 * 1024  // 20 GB
Memory.cacheLimit = 512 * 1024 * 1024          // 512 MB
Memory.clearCache()                             // Free cached buffers
let snapshot = Memory.snapshot()                 // Inspect memory state
```

**NEVER use**: `MLX.GPU.set(memoryLimit:)`, `MLX.GPU.set(cacheLimit:)`, `MLX.GPU.clearCache()` — these are outdated API names from older documentation. The correct API is on the `Memory` enum.

### Metal Buffer Caching

MLX caches Metal buffers for reuse. After inference, `Memory.snapshot()` may show high resident memory — **this is NOT a leak**. The buffers are recycled for subsequent inference calls. Set `Memory.cacheLimit` to control pool size.

### iOS Memory

- Add `Increased Memory Limit` entitlement for iOS target
- Gemma 4 E2B 4-bit needs ~3-4 GB total (weights + KV cache + OS)
- Without the entitlement, iOS may kill the app mid-inference

## Swift Concurrency — `MLXArray` Containment

### The Problem

`MLXArray` is **NOT `Sendable`**. It wraps non-thread-safe C++ objects. In Swift 6 strict concurrency mode, passing `MLXArray` across actor boundaries causes compiler errors.

### The Solution: Containment Pattern

```swift
final class MLXEngineAdapter: InferenceEngine, @unchecked Sendable {
    // ✅ MLX types stay INSIDE the adapter — never exposed
    private var modelContainer: ModelContainer?
    private var chatSession: ChatSession?
    
    // ✅ Only Sendable types cross the boundary
    func generateStream(...) -> AsyncThrowingStream<GenerationEvent, Error> {
        // GenerationEvent contains String, EnginePerformanceMetrics,
        // AppToolCall — all Sendable
    }
}
```

**Rules:**
1. `MLXArray`, `ModelContainer`, `ChatSession` are PRIVATE properties only
2. All public methods return `Sendable` types
3. `@unchecked Sendable` on the class — we manage thread safety by containment
4. Never store `MLXArray` in a property that other types access

## iOS Simulator — Compile-Time Guards

MLX requires Metal, which is **unavailable on iOS Simulator**. Use `#if canImport(MLX)` guards:

```swift
#if canImport(MLX)
import MLX
import MLXLLM
import MLXLMCommon

final class MLXEngineAdapter: InferenceEngine, @unchecked Sendable {
    // Real implementation
}
#else
/// Stub for platforms without Metal (iOS Simulator)
final class MLXEngineAdapter: InferenceEngine, @unchecked Sendable {
    var isLoaded: Bool { false }
    var runtimeType: RuntimeType { .mlx }
    func loadModel(config: ModelLoadConfig) async throws {
        throw EngineError.notReady("MLX requires Metal — not available on Simulator")
    }
    // ... stub all other methods
}
#endif
```

**Testing**: On Simulator, use `MockInferenceEngine(runtimeType: .mlx)` for unit tests. Real MLX tests require macOS or a physical iOS device.

## Lifecycle Rules

1. **One engine per conversation** — create a new `MLXEngineAdapter` for each model session
2. **Shutdown before switching models** — call `shutdown()` then `Memory.clearCache()` before loading a new model
3. **Cancellation** — cancel the active `Task` and check `Task.isCancelled` in the generation loop
4. **Cold start** — first inference has JIT compilation overhead. Subsequent calls are faster.

## Package Dependencies

In `Project.swift`, the following products are needed:

```swift
.package(product: "MLXLLM"),       // LLM implementations
.package(product: "MLXLMCommon"),   // Shared types (ChatSession, GenerateParameters)
.package(product: "MLXVLM"),       // Vision Language Models (Phase 4)
.package(product: "Tokenizers"),    // HuggingFace tokenizer loading
.package(product: "Hub"),           // HuggingFace Hub download client
```

Package source: `https://github.com/ml-explore/mlx-swift-lm.git` pinned to `.upToNextMajor(from: "3.31.3")`.

> **Note:** The project does NOT use `MLXHuggingFace` product. Instead, `MLXEngineAdapter` implements
> its own `HubDownloader` (conforming to `MLXLMCommon.Downloader`) and `TransformersTokenizerLoader`
> to avoid the macro dependency.

Minimum platform requirements: macOS 14+ / iOS 17+ (but project targets macOS 27 / iOS 27).

## Model Architecture Mapping — config.json `model_type`

The `model_type` field in a model's `config.json` controls which architecture class the SDK loads. **Never patch this field** — the architectures have fundamentally different weight structures:

| `model_type` | SDK Architecture | Vision Pipeline | Audio Weights | Weight Sanitization |
|---|---|---|---|---|
| `gemma4` | `Gemma4` | SigLIP (standard) | **Stripped** by `sanitize()` | Drops `audio_tower`, `embed_audio` keys |
| `gemma4_unified` | `Gemma4Unified` | Patchify + position IDs | **Preserved** | Keeps all weight keys |

**Critical rule:** Do NOT change `model_type` to "fix" audio support. The `Gemma4` and `Gemma4Unified` architectures expect different weight tensor shapes for vision encoding. Switching model_type causes all vision prompts to return empty responses (tested: 92%→4% Multimodal regression).

### Tool Call Format Inference

The `ToolCallFormat.infer(from:)` method uses prefix matching on `model_type`:
- `"gemma4"` prefix → `.gemma4` format (matches both `gemma4` and `gemma4_unified`)
- `"gemma"` exact → `.gemma` format

Tool calling format is preserved regardless of model_type value, as long as the prefix matches.

## MLX Audio Status (Pinned Commit d2424294a6c3)

Audio inference is a **known SDK limitation** at the pinned commit:

1. `Gemma4.sanitize(weights:)` strips `audio_tower` and `embed_audio` weight keys (line 2131-2133)
2. `Gemma4UnifiedProcessor.prepare()` only processes images — no mel spectrogram/STFT extraction exists (line 3060-3110)
3. No audio processing code exists in `Libraries/MLXVLM/` or `Libraries/MLXLMCommon/`
4. Audio `Data` is correctly written to temp WAV files and passed to `UserInput.Audio`, but the processor ignores it

**Audio prompts will return:** `"Please provide the audio you are referring to."` — This is NOT our infrastructure; it's the SDK's processor not extracting audio features.

**Do NOT attempt:** Config.json model_type patches, custom audio processors, or workarounds that modify the model's configuration. Wait for upstream `mlx-swift-lm` to implement mel spectrogram extraction in `Gemma4Processor`.

## Multimodal Diagnostics

The adapter includes diagnostic logging for multimodal inputs:
```
[MLXEngine] 🎵 Wrote temp audio: <UUID>.wav (<bytes> bytes)
[MLXEngine] 📎 Multimodal input: <N> image(s), <M> audio(s)
```
If audio prompts fail, check these logs first to verify data reaches the engine before investigating the SDK.

## Engine Capability Flags

MLXEngineAdapter exposes capability properties that gate eval prompt routing:

| Flag | Current Value | Effect |
|---|---|---|
| `supportsVision` | `true` (VLM models) | Image prompts sent to engine |
| `supportsAudio` | `true` (declared) | Audio data passed to SDK (but SDK ignores it) |
| `supportsToolCalling` | `true` | Tool schemas registered, toolDispatch wired |

**A missing capability flag causes SILENT eval failures** — empty responses scored as 0%. Always verify all three flags when adding or modifying engine adapters.

