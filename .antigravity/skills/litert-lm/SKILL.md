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
- Typical size: ~1.5-2GB per model
- The app will support multiple models with user selection
