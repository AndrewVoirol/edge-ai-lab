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
import LiteRTLM

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Mock implementation of InstrumentedEngineProtocol for unit tests.
/// Returns configurable BenchmarkInfo values without requiring a real model file.
final class MockInstrumentedEngine: InstrumentedEngineProtocol {

    // MARK: - Configurable Behavior

    /// The BenchmarkInfo to return after inference. Set this before calling sendMessageStream.
    var mockBenchmarkInfo: BenchmarkInfo?

    /// The InferenceMetrics to return after inference. Set this before calling sendMessageStream.
    var mockInferenceMetrics: InferenceMetrics?

    /// The BackendResult to return from initializeWithFallback. Set this before calling.
    var mockBackendResult: BackendResult?

    /// The response chunks to stream back. Each string is yielded as a separate chunk.
    var mockResponseChunks: [String] = ["Hello", ", ", "world", "!"]

    /// If set, initialization will throw this error.
    var initError: Error?

    /// If set, inference will throw this error.
    var inferenceError: Error?

    /// Delay between response chunks (seconds). Default 0 for fast tests.
    var chunkDelay: TimeInterval = 0

    /// When set, the mock throws `inferenceError` (or a default NSError) after emitting
    /// this many chunks in sendMessageStream. Default nil (no mid-stream error).
    var errorAtChunkIndex: Int?

    /// When true, `cancelGeneration()` sets an internal flag that causes any running
    /// stream to stop emitting further chunks. Default false (current no-op preserved).
    var simulateCancelBehavior: Bool = false

    /// When set, `warmup()` throws this error instead of succeeding. Default nil.
    var warmupError: Error?

    /// When set, `initializeWithFallback()` throws this error (simulating both
    /// backends failing). Default nil.
    var fallbackError: Error?

    /// Delay before the FIRST chunk is emitted, distinct from `chunkDelay` which
    /// applies between subsequent chunks. Default 0.
    var ttftDelay: TimeInterval = 0

    // MARK: - Call Tracking

    /// Number of times initialize was called.
    private(set) var initializeCallCount = 0

    /// The last model path passed to initialize.
    private(set) var lastModelPath: String?

    /// The last flags passed to initialize.
    private(set) var lastFlags: ExperimentalFlagsState?

    /// Number of times sendMessageStream was called.
    private(set) var sendMessageCallCount = 0

    /// The last prompt text passed to sendMessageStream.
    private(set) var lastPromptText: String?

    /// The last sampler config passed to initialize.
    private(set) var lastSamplerConfig: SamplerConfig?

    /// Number of times shutdown was called.
    private(set) var shutdownCallCount = 0

    /// Number of times resetConversation was called.
    private(set) var resetConversationCallCount = 0

    /// Number of times warmup was called.
    private(set) var warmupCallCount = 0

    /// The last system message passed to initialize.
    private(set) var lastSystemMessage: String?

    /// The last image data passed to sendMessageStream.
    private(set) var lastImageData: Data?

    /// The last audio data passed to sendMessageStream.
    private(set) var lastAudioData: Data?

    /// Number of times multimodal sendMessageStream was called.
    private(set) var multimodalSendCallCount = 0

    /// The last enableThinking value passed to sendMessageStream.
    private(set) var lastEnableThinking: Bool = false

    /// The last tools array passed to initialize.
    private(set) var lastTools: [Tool]?

    /// The last supportsVision value passed to initialize.
    private(set) var lastSupportsVision: Bool = false

    /// The last supportsAudio value passed to initialize.
    private(set) var lastSupportsAudio: Bool = false

    /// Tracks every prompt sent via sendMessageStream for multi-turn test assertions.
    private(set) var conversationTurns: [String] = []

    /// Internal flag set by `cancelGeneration()` when `simulateCancelBehavior` is true.
    private var isCancelled = false

    // MARK: - Protocol Conformance

    var isReady = false
    private(set) var lastBenchmarkInfo: BenchmarkInfo?
    private(set) var lastInferenceMetrics: InferenceMetrics?
    private(set) var lastBackendResult: BackendResult?
    private(set) var modelLoadDurationMs: Double?
    private(set) var flagsState = ExperimentalFlagsState(
        enableBenchmark: true,
        enableSpeculativeDecoding: nil,
        enableConversationConstrainedDecoding: false,
        visualTokenBudget: nil
    )

    func initialize(
        modelPath: String,
        useGPU: Bool,
        cacheDir: String,
        flags: ExperimentalFlagsState,
        samplerConfig: SamplerConfig?,
        systemMessage: String?,
        tools: [Tool]?,
        supportsVision: Bool = false,
        supportsAudio: Bool = false
    ) async throws {
        initializeCallCount += 1
        lastModelPath = modelPath
        lastFlags = flags
        lastSamplerConfig = samplerConfig
        lastSystemMessage = systemMessage
        lastTools = tools
        lastSupportsVision = supportsVision
        lastSupportsAudio = supportsAudio
        flagsState = flags

        if let error = initError {
            throw error
        }

        isReady = true
    }

    func initializeWithFallback(
        modelPath: String,
        preferGPU: Bool,
        cacheDir: String,
        flags: ExperimentalFlagsState,
        samplerConfig: SamplerConfig?,
        systemMessage: String?,
        tools: [Tool]?,
        supportsVision: Bool = false,
        supportsAudio: Bool = false
    ) async throws -> BackendResult {
        // If fallbackError is set, simulate both backends failing
        if let error = fallbackError {
            throw error
        }

        // Delegate to regular initialize
        try await initialize(
            modelPath: modelPath,
            useGPU: preferGPU,
            cacheDir: cacheDir,
            flags: flags,
            samplerConfig: samplerConfig,
            systemMessage: systemMessage,
            tools: tools,
            supportsVision: supportsVision,
            supportsAudio: supportsAudio
        )

        let result = mockBackendResult ?? BackendResult(
            activeBackend: preferGPU ? .gpu : .cpu,
            didFallback: false,
            fallbackReason: nil,
            detectedCapability: .unknown
        )
        self.lastBackendResult = result
        return result
    }

    func sendMessageStream(_ text: String, enableThinking: Bool = false) -> AsyncThrowingStream<String, Error> {
        sendMessageCallCount += 1
        lastPromptText = text
        lastEnableThinking = enableThinking
        conversationTurns.append(text)

        // Reset cancellation flag at the start of each stream
        isCancelled = false

        let chunks = mockResponseChunks
        let delay = chunkDelay
        let error = inferenceError
        let benchmarkInfo = mockBenchmarkInfo
        let ttft = ttftDelay
        let errorAtIndex = errorAtChunkIndex

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
                        let midStreamError = self?.inferenceError
                            ?? NSError(
                                domain: "MockInstrumentedEngine",
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
                        // Preserve original behavior: chunkDelay applies to all chunks when ttftDelay is 0
                        try? await Task.sleep(for: .seconds(delay))
                    }

                    continuation.yield(chunk)
                }

                // Simulate benchmark capture
                self?.lastBenchmarkInfo = benchmarkInfo
                self?.lastInferenceMetrics = self?.mockInferenceMetrics

                continuation.finish()
            }
        }
    }

    func sendMessageStream(
        _ text: String,
        imageData: Data?,
        audioData: Data?,
        enableThinking: Bool = false
    ) -> AsyncThrowingStream<String, Error> {
        multimodalSendCallCount += 1
        lastImageData = imageData
        lastAudioData = audioData
        // Delegate to text-only path for response generation
        return sendMessageStream(text, enableThinking: enableThinking)
    }

    func resetConversation() async throws {
        resetConversationCallCount += 1
        lastBenchmarkInfo = nil
        lastInferenceMetrics = nil
    }

    func warmup() async throws {
        warmupCallCount += 1

        if let error = warmupError {
            throw error
        }

        // Simulate benchmark priming — set lastBenchmarkInfo after warmup
        lastBenchmarkInfo = mockBenchmarkInfo
    }

    func cancelGeneration() {
        // Mock cancellation: set internal flag when simulateCancelBehavior is enabled
        if simulateCancelBehavior {
            isCancelled = true
        }
    }

    func shutdown() async {
        shutdownCallCount += 1
        isReady = false
        lastBenchmarkInfo = nil
        lastInferenceMetrics = nil
        lastBackendResult = nil
    }

    // MARK: - Static Factory Methods

    /// Default config, fast responses — ideal for happy-path unit tests.
    static func happyPath() -> MockInstrumentedEngine {
        let engine = MockInstrumentedEngine()
        engine.mockResponseChunks = ["Hello", ", ", "world", "!"]
        return engine
    }

    /// Slow inference with realistic delays — useful for testing loading states and timeouts.
    static func slowInference() -> MockInstrumentedEngine {
        let engine = MockInstrumentedEngine()
        engine.ttftDelay = 2.0
        engine.chunkDelay = 0.5
        return engine
    }

    /// Engine that fails on initialization — useful for testing error handling paths.
    static func failingEngine() -> MockInstrumentedEngine {
        let engine = MockInstrumentedEngine()
        engine.initError = NSError(
            domain: "MockInstrumentedEngine",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Simulated initialization failure"]
        )
        return engine
    }

    /// Engine that fails mid-stream after 3 chunks — useful for testing partial response recovery.
    static func intermittentFailure() -> MockInstrumentedEngine {
        let engine = MockInstrumentedEngine()
        engine.errorAtChunkIndex = 3
        return engine
    }
}

// MARK: - InferenceEngine Conformance

/// Allows MockInstrumentedEngine to be used with ConversationViewModel (which now expects `any InferenceEngine`).
/// Maps InferenceEngine methods to the existing mock behavior.
extension MockInstrumentedEngine: InferenceEngine {

    var isLoaded: Bool { isReady }

    var modelInfo: InferenceModelInfo? {
        guard isReady else { return nil }
        return InferenceModelInfo(
            name: lastModelPath.map { ($0 as NSString).lastPathComponent } ?? "MockModel",
            parameterCount: nil,
            quantization: nil,
            runtimeType: .litertlm
        )
    }

    var runtimeType: RuntimeType { .litertlm }

    func loadModel(config: ModelLoadConfig) async throws {
        let flags = config.runtimeFlags?.toLiteRTFlags() ?? ExperimentalFlagsState(
            enableBenchmark: true,
            enableSpeculativeDecoding: nil,
            enableConversationConstrainedDecoding: false,
            visualTokenBudget: nil
        )
        // Bridge GenerationConfig → SamplerConfig for test assertions
        let samplerConfig: SamplerConfig? = try config.generationConfig.map { gen in
            try SamplerConfig(
                topK: gen.topK,
                topP: Float(gen.topP),
                temperature: Float(gen.temperature)
            )
        }
        try await initialize(
            modelPath: config.modelPath,
            useGPU: config.preferGPU,
            cacheDir: config.cacheDir ?? NSTemporaryDirectory(),
            flags: flags,
            samplerConfig: samplerConfig,
            systemMessage: config.systemMessage
        )
    }

    func generateStream(
        prompt: String,
        config: GenerationConfig
    ) -> AsyncThrowingStream<GenerationEvent, Error> {
        // Delegate to sendMessageStream and wrap String chunks as GenerationEvent
        let stringStream = sendMessageStream(prompt)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await chunk in stringStream {
                        continuation.yield(.text(chunk))
                    }
                    // Emit metrics if available
                    if let info = self.lastBenchmarkInfo {
                        let metrics = EnginePerformanceMetrics(
                            tokensPerSecond: info.lastDecodeTokensPerSecond,
                            promptTokensPerSecond: nil,
                            timeToFirstToken: info.timeToFirstTokenInSecond,
                            peakMemoryBytes: nil,
                            tokenCount: info.lastDecodeTokenCount,
                            memoryDeltaMB: nil,
                            thermalStateChanged: nil,
                            runtimeType: .litertlm
                        )
                        continuation.yield(.metrics(metrics))
                    }
                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func shutdown() {
        // InferenceEngine.shutdown() is sync; apply side effects directly
        shutdownCallCount += 1
        isReady = false
        lastBenchmarkInfo = nil
        lastInferenceMetrics = nil
        lastBackendResult = nil
    }

    var lastPerformanceMetrics: EnginePerformanceMetrics? {
        guard let info = lastBenchmarkInfo else { return nil }
        return EnginePerformanceMetrics(
            tokensPerSecond: info.lastDecodeTokensPerSecond,
            promptTokensPerSecond: nil,
            timeToFirstToken: info.timeToFirstTokenInSecond,
            peakMemoryBytes: nil,
            tokenCount: info.lastDecodeTokenCount,
            memoryDeltaMB: nil,
            thermalStateChanged: nil,
            runtimeType: .litertlm
        )
    }
}
