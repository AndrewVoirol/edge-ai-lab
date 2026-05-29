---
name: LiteRT-LM Engine Guidelines
description: Strict rules for interacting with the Google LiteRT-LM SDK and preventing memory/concurrency bugs.
---

# LiteRT-LM SDK Guidelines

The Gemma Edge Gallery app runs large LLMs entirely on-device using `LiteRTLM`. Because these weights are massive (1.5GB+), there are strict memory mapping and threading rules that must be followed.

## 1. Security-Scoped Resource Lifetime (Memory Mapping)
When a user selects a `.litertlm` file using a Document Picker (`UIDocumentPickerViewController` or `.fileImporter`), iOS places it behind a security scope.
- **CRITICAL**: The `Engine` memory-maps (`mmap`) the weights directly from the filesystem to save RAM.
- You **MUST** call `startAccessingSecurityScopedResource()` on the URL before initializing the engine.
- You **MUST NOT** call `stopAccessingSecurityScopedResource()` until the engine is completely destroyed or a new model is loaded. 
- If you call `stopAccessing...` while the engine is still alive, the app will crash with `EXC_BAD_ACCESS` when it attempts to stream text.

## 2. Swift Concurrency & Main Thread Checker
The `Engine` generation functions can take several seconds and are highly CPU/GPU intensive.
- Any function that interacts with the `Engine` and mutates SwiftUI `@State` properties (like appending text to a string, or updating a status flag) **MUST** be annotated with `@MainActor`.
- If you update `@State` from a background thread during an async stream, Xcode will throw purple `Publishing changes from background threads is not allowed` warnings and the UI may glitch.

## 3. Performance Benchmarking APIs

### ExperimentalFlags (Static Struct)

- **MUST** call `ExperimentalFlags.optIntoExperimentalAPIs()` **BEFORE** setting any flag. Without this call, setting flags silently no-ops.
- `ExperimentalFlags.enableBenchmark: Bool` — enables `BenchmarkInfo` collection (default: `false`)
- `ExperimentalFlags.enableSpeculativeDecoding: Bool?` — enables speculative decode (default: `nil`)
- `ExperimentalFlags.enableConversationConstrainedDecoding: Bool` — enables constrained decoding (default: `false`)
- `ExperimentalFlags.visualTokenBudget: Int32?` — vision model token budget (default: `nil`)

### BenchmarkInfo

Returned by `conversation.getBenchmarkInfo()`. Fields:

- `initTimeInSecond: Double`
- `timeToFirstTokenInSecond: Double`
- `lastPrefillTokenCount: Int`
- `lastDecodeTokenCount: Int`
- `lastPrefillTokensPerSecond: Double`
- `lastDecodeTokensPerSecond: Double`

### Usage Pattern

```swift
// MUST opt in first
ExperimentalFlags.optIntoExperimentalAPIs()
ExperimentalFlags.enableBenchmark = true

// After inference completes:
let info = try conversation.getBenchmarkInfo()
// Access: info.lastDecodeTokensPerSecond, info.timeToFirstTokenInSecond, etc.
```

### Error Handling

- `getBenchmarkInfo()` throws `LiteRTLMError.conversation(.benchmarkNotEnabled)` if `enableBenchmark` is `false`.
- `getBenchmarkInfo()` throws `LiteRTLMError.conversation(.benchmarkInfoUnavailable)` if the native layer returns null.
- Always wrap in `do/catch`.

### Convenience Benchmark Function

```swift
benchmark(modelPath:backend:prefillTokens:decodeTokens:cacheDir:) async throws -> BenchmarkInfo
```

Runs a standalone benchmark without needing manual flag setup. Use this for quick one-shot performance measurements.
