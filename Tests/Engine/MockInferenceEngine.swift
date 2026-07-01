// Copyright 2026 Andrew Voirol. Apache-2.0
// Copyright 2026 Andrew Voirol
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Runtime-agnostic mock engine for unit tests.
///
/// Replaces the legacy `MockInstrumentedEngine` which had dual conformance to both
/// `InstrumentedEngineProtocol` (LiteRT-specific) and `InferenceEngine`. This mock
/// conforms ONLY to `InferenceEngine`, making tests independent of LiteRT-LM SDK types.
///
/// ## Migration from MockInstrumentedEngine
///
/// | MockInstrumentedEngine | MockInferenceEngine |
/// |------------------------|---------------------|
/// | `sendMessageCallCount` | `generateStreamCallCount` |
/// | `initializeCallCount` | `loadModelCallCount` |
/// | `lastFlags` | `lastRuntimeFlags` |
/// | `lastSamplerConfig` | `lastGenerationConfig` |
/// | `lastPromptText` | `lastPrompt` |
/// | `initError` | `loadError` |
/// | `inferenceError` | `generateError` |
/// | `.happyPath()` | `.happyPath()` |
/// | `.failingEngine()` | `.failingEngine()` |
final class MockInferenceEngine: InferenceEngine {

    // MARK: - Configurable Behavior

    /// The response chunks to stream back. Each string is yielded as `.text(chunk)`.
    var mockResponseChunks: [String] = ["Hello", ", ", "world", "!"]

    /// Performance metrics to emit as `.metrics()` event after generation completes.
    var mockPerformanceMetrics: EnginePerformanceMetrics?

    /// The BackendResult to return from loadModel. Set before calling.
    var mockBackendResult: BackendResult?

    /// The InferenceMetrics to populate after generation. Set before calling.
    var mockInferenceMetrics: InferenceMetrics?

    /// If set, loadModel will throw this error.
    var loadError: Error?

    /// If set, generateStream will throw this error.
    var generateError: Error?

    /// Delay between response chunks (seconds). Default 0 for fast tests.
    var chunkDelay: TimeInterval = 0

    /// Delay before the FIRST chunk is emitted, distinct from `chunkDelay`.
    var ttftDelay: TimeInterval = 0

    /// When set, the mock throws `generateError` (or a default NSError) after emitting
    /// this many chunks. Default nil (no mid-stream error).
    var errorAtChunkIndex: Int?

    /// When true, `cancelGeneration()` sets an internal flag that causes any running
    /// stream to stop emitting further chunks.
    var simulateCancelBehavior: Bool = false

    /// When set, `warmup()` throws this error instead of succeeding.
    var warmupError: Error?

    // MARK: - Call Tracking

    /// Number of times loadModel was called.
    private(set) var loadModelCallCount = 0

    /// Number of times generateStream was called.
    private(set) var generateStreamCallCount = 0

    /// Number of times shutdown was called.
    private(set) var shutdownCallCount = 0

    /// Number of times resetConversation was called.
    private(set) var resetConversationCallCount = 0

    /// Number of times warmup was called.
    private(set) var warmupCallCount = 0

    /// Number of times cancelGeneration was called.
    private(set) var cancelGenerationCallCount = 0

    /// The last ModelLoadConfig passed to loadModel.
    private(set) var lastLoadConfig: ModelLoadConfig?

    /// The last model path passed to loadModel (convenience accessor).
    private(set) var lastModelPath: String?

    /// The last GenerationConfig passed to generateStream.
    private(set) var lastGenerationConfig: GenerationConfig?

    /// The last RuntimeFlags passed via ModelLoadConfig.
    private(set) var lastRuntimeFlags: RuntimeFlags?

    /// The last prompt text passed to generateStream.
    private(set) var lastPrompt: String?

    /// The last system message passed to loadModel.
    private(set) var lastSystemMessage: String?

    /// Tracks every prompt sent via generateStream for multi-turn test assertions.
    private(set) var conversationTurns: [String] = []

    /// Internal flag set by `cancelGeneration()` when `simulateCancelBehavior` is true.
    private var isCancelled = false

    // MARK: - Derived Tracking (from ModelLoadConfig / GenerationConfig)

    /// Whether the last loadModel had supportsVision=true.
    var lastSupportsVision: Bool {
        lastLoadConfig?.supportsVision ?? false
    }

    /// Whether the last loadModel had supportsAudio=true.
    var lastSupportsAudio: Bool {
        lastLoadConfig?.supportsAudio ?? false
    }

    /// Whether the last generateStream had enableThinking enabled.
    /// Derived from the last GenerationConfig or RuntimeFlags.
    var lastEnableThinking: Bool = false

    /// Number of multimodal generate calls (where imageData was present).
    private(set) var multimodalSendCallCount = 0

    /// The last image data passed via GenerationConfig.
    private(set) var lastImageData: Data?

    // MARK: - Protocol Conformance

    /// Whether the engine is loaded and ready.
    var isLoaded: Bool = false

    /// Model info, populated after loadModel.
    private(set) var modelInfo: InferenceModelInfo?

    /// The runtime type this mock simulates. Configurable for testing engine-switching logic.
    var runtimeType: RuntimeType

    /// Backend result from most recent load.
    private(set) var lastBackendResult: BackendResult?

    /// Device-level inference metrics from most recent generation.
    private(set) var lastInferenceMetrics: InferenceMetrics?

    /// Performance metrics from most recent generation.
    private(set) var lastPerformanceMetrics: EnginePerformanceMetrics?

    // MARK: - Init

    init(runtimeType: RuntimeType = .litertlm) {
        self.runtimeType = runtimeType
    }

    // MARK: - Loading

    func loadModel(config: ModelLoadConfig) async throws {
        loadModelCallCount += 1
        lastLoadConfig = config
        lastModelPath = config.modelPath
        lastRuntimeFlags = config.runtimeFlags
        lastSystemMessage = config.systemMessage
        lastGenerationConfig = config.generationConfig

        if let error = loadError {
            throw error
        }

        isLoaded = true

        let filename = (config.modelPath as NSString).lastPathComponent
        let name = (filename as NSString).deletingPathExtension
        modelInfo = InferenceModelInfo(
            name: name,
            parameterCount: nil,
            quantization: nil,
            runtimeType: runtimeType
        )

        // Set backend result after successful load
        lastBackendResult = mockBackendResult ?? BackendResult(
            activeBackend: config.preferGPU ? .gpu : .cpu,
            didFallback: false,
            fallbackReason: nil,
            detectedCapability: .unknown
        )
    }

    // MARK: - Generation

    func generateStream(
        prompt: String,
        config: GenerationConfig
    ) -> AsyncThrowingStream<GenerationEvent, Error> {
        generateStreamCallCount += 1
        lastPrompt = prompt
        lastGenerationConfig = config
        conversationTurns.append(prompt)

        // Track multimodal and thinking calls
        if let images = config.imageData, !images.isEmpty {
            multimodalSendCallCount += 1
            lastImageData = images.first
        }

        // Reset cancellation flag at the start of each stream
        isCancelled = false

        let chunks = mockResponseChunks
        let delay = chunkDelay
        let error = generateError
        let ttft = ttftDelay
        let errorAtIndex = errorAtChunkIndex
        let metrics = mockPerformanceMetrics
        let inferenceMetrics = mockInferenceMetrics

        return AsyncThrowingStream { continuation in
            Task { [weak self] in
                if let error = error {
                    continuation.finish(throwing: error)
                    return
                }

                for (index, chunk) in chunks.enumerated() {
                    // Check for simulated cancellation
                    if self?.simulateCancelBehavior == true && self?.isCancelled == true {
                        continuation.finish()
                        return
                    }

                    // Check for mid-stream error injection
                    if let errorIdx = errorAtIndex, index >= errorIdx {
                        let midStreamError = self?.generateError
                            ?? NSError(
                                domain: "MockInferenceEngine",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Simulated mid-stream inference error"]
                            )
                        continuation.finish(throwing: midStreamError)
                        return
                    }

                    // Apply TTFT delay before the first chunk
                    if index == 0 && ttft > 0 {
                        try? await Task.sleep(for: .seconds(ttft))
                    }

                    // Apply inter-chunk delay for subsequent chunks
                    if index > 0 && delay > 0 {
                        try? await Task.sleep(for: .seconds(delay))
                    } else if index == 0 && delay > 0 && ttft == 0 {
                        try? await Task.sleep(for: .seconds(delay))
                    }

                    continuation.yield(.text(chunk))
                }

                // Populate metrics after generation
                self?.lastInferenceMetrics = inferenceMetrics

                // Emit performance metrics event if configured
                if let metrics = metrics {
                    self?.lastPerformanceMetrics = metrics
                    continuation.yield(.metrics(metrics))
                }

                continuation.yield(.done)
                continuation.finish()
            }
        }
    }

    // MARK: - Lifecycle

    func shutdown() {
        shutdownCallCount += 1
        isLoaded = false
        lastBackendResult = nil
        lastInferenceMetrics = nil
        lastPerformanceMetrics = nil
    }

    func resetConversation() async throws {
        resetConversationCallCount += 1
        lastInferenceMetrics = nil
        lastPerformanceMetrics = nil
    }

    func cancelGeneration() {
        cancelGenerationCallCount += 1
        if simulateCancelBehavior {
            isCancelled = true
        }
    }

    func warmup() async throws {
        warmupCallCount += 1
        if let error = warmupError {
            throw error
        }
    }

    // MARK: - Static Factory Methods

    /// Default config, fast responses — ideal for happy-path unit tests.
    static func happyPath(runtimeType: RuntimeType = .litertlm) -> MockInferenceEngine {
        let engine = MockInferenceEngine(runtimeType: runtimeType)
        engine.mockResponseChunks = ["Hello", ", ", "world", "!"]
        return engine
    }

    /// Slow inference with realistic delays — useful for testing loading states and timeouts.
    static func slowInference(runtimeType: RuntimeType = .litertlm) -> MockInferenceEngine {
        let engine = MockInferenceEngine(runtimeType: runtimeType)
        engine.ttftDelay = 2.0
        engine.chunkDelay = 0.5
        return engine
    }

    /// Engine that fails on load — useful for testing error handling paths.
    static func failingEngine(runtimeType: RuntimeType = .litertlm) -> MockInferenceEngine {
        let engine = MockInferenceEngine(runtimeType: runtimeType)
        engine.loadError = NSError(
            domain: "MockInferenceEngine",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Simulated initialization failure"]
        )
        return engine
    }

    /// Engine that fails mid-stream after 3 chunks — useful for testing partial response recovery.
    static func intermittentFailure(runtimeType: RuntimeType = .litertlm) -> MockInferenceEngine {
        let engine = MockInferenceEngine(runtimeType: runtimeType)
        engine.errorAtChunkIndex = 3
        return engine
    }

    /// MLX engine mock — pre-configured with `.mlx` runtime type.
    static func mlxEngine() -> MockInferenceEngine {
        let engine = MockInferenceEngine(runtimeType: .mlx)
        engine.mockResponseChunks = ["Hello", " from", " MLX", "!"]
        return engine
    }
}
