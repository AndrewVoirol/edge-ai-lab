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

**Session reset**: `ChatSession` has NO explicit reset method. To reset conversation state (clear KV cache and history), **recreate the session**: `session = ChatSession(container)`.

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

**`topK` is NOT a direct property** on `GenerateParameters`. It may be available at the sampler level but is not guaranteed. Map `topK` to `topP` equivalent for MLX.

**`seed`**: Not in `GenerateParameters`. Use `MLXRandom.seed(42)` separately.

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
.package(product: "MLXHuggingFace"), // HuggingFace Hub integration (downloads)
```

Package source: `https://github.com/ml-explore/mlx-swift-lm.git` tracking `main` branch.

Minimum platform requirements: macOS 14+ / iOS 17+ (but project targets macOS 27 / iOS 27).
