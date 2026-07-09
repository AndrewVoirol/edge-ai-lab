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

// MARK: - LiteRTEngineAdapter

/// Adapts the existing `InstrumentedEngine` to the runtime-agnostic `InferenceEngine` protocol.
///
/// This adapter bridges the LiteRT-LM SDK's types (`SamplerConfig`, `ExperimentalFlagsState`)
/// to the generic `GenerationConfig` and `ModelLoadConfig` types used by `InferenceEngine`.
///
/// ## Design Decisions
///
/// - **Wrapper, not extension:** `InstrumentedEngine` imports `LiteRTLM` heavily and has
///   a different lifecycle model (init → initialize → sendMessageStream). Making it conform
///   directly to `InferenceEngine` would pollute it with adapter logic. A wrapper keeps
///   concerns separated.
///
/// - **Sendable conformance:** The adapter is `@unchecked Sendable` because the underlying
///   `InstrumentedEngine` manages its own concurrency via `MainActor` and `Task` internally.
///   The adapter itself holds no mutable state beyond the engine reference.
///
/// - **GenerationConfig → SamplerConfig mapping:** LiteRT-LM's `SamplerConfig` supports
///   `topK`, `topP`, `temperature`, and `seed`. We map from `GenerationConfig` at load time
///   since LiteRT-LM binds sampler config to the conversation, not individual turns.
///
/// - **WebGPU sampler warning (expected):** At engine init, the LiteRT-LM SDK logs:
///   `"libLiteRtTopKWebGpuSampler.dylib not found"`. This is **normal** — the WebGPU sampler
///   is an optional runtime accelerator that is intentionally excluded from the xcframework
///   distributed via SPM. (The `prebuilt/` directory in the upstream repo contains Git LFS
///   pointers, but these are irrelevant — SPM fetches remotely-hosted xcframework ZIPs, not
///   local dylibs.) The SDK falls back to a statically linked C API sampler with no functional
///   or performance impact.
final class LiteRTEngineAdapter: InferenceEngine, @unchecked Sendable {

    // MARK: - State

    /// The wrapped LiteRT-LM engine.
    private let engine: InstrumentedEngine

    /// The model info extracted after loading.
    private(set) var modelInfo: InferenceModelInfo?

    /// The sampler config applied to the current conversation.
    private var activeSamplerConfig: SamplerConfig?

    /// Cached performance metrics from the last generation.
    private(set) var lastPerformanceMetrics: EnginePerformanceMetrics?

    /// Backend result from LiteRT-LM initialization (GPU/CPU fallback info).
    var lastBackendResult: BackendResult? { engine.lastBackendResult }

    /// Device-level inference metrics from the wrapped engine.
    var lastInferenceMetrics: InferenceMetrics? { engine.lastInferenceMetrics }

    // MARK: - Init

    /// Creates an adapter wrapping a new `InstrumentedEngine`.
    init() {
        self.engine = InstrumentedEngine()
    }

    /// Creates an adapter wrapping an existing `InstrumentedEngine`.
    /// Useful for tests or when the engine is already configured.
    init(wrapping engine: InstrumentedEngine) {
        self.engine = engine
    }

    // MARK: - InferenceEngine

    var isLoaded: Bool { engine.isReady }

    var runtimeType: RuntimeType { .litertlm }

    var supportsToolCalling: Bool { true }

    func loadModel(config: ModelLoadConfig) async throws {
        // Build sampler config from GenerationConfig if provided.
        let samplerConfig: SamplerConfig?
        if let genConfig = config.generationConfig {
            samplerConfig = try LiteRTEngineAdapter.makeSamplerConfig(from: genConfig)
        } else {
            samplerConfig = activeSamplerConfig
        }

        // Use runtime flags from config, converting to LiteRT-LM's native format.
        let flags: ExperimentalFlagsState
        if let rf = config.runtimeFlags {
            flags = rf.toLiteRTFlags()
        } else {
            flags = ExperimentalFlagsState(
                enableBenchmark: true,
                enableSpeculativeDecoding: nil,
                enableConversationConstrainedDecoding: false,
                visualTokenBudget: nil
            )
        }

        // Determine cache directory.
        let cacheDir = config.cacheDir ?? NSTemporaryDirectory()

        // Bridge AppTool → LiteRTLM.Tool if tools are provided.
        // AppTool → LiteRT Tool bridging deferred until AppTool rollout is complete.
        // Tools are currently assembled by ModelSessionController.buildActiveTools()
        // and passed via loadWithLiteRTConfig(). This path is for future direct
        // InferenceEngine consumers that bypass the session controller.
        let tools: [Tool]?
        if let appTools = config.tools {
            // Register tools for lookup during execution
            LiteRTToolBridgeRegistry.shared.registerAll(appTools)
            tools = nil
        } else {
            tools = nil
        }

        // Use smart fallback initialization.
        _ = try await engine.initializeWithFallback(
            modelPath: config.modelPath,
            preferGPU: config.preferGPU,
            cacheDir: cacheDir,
            flags: flags,
            samplerConfig: samplerConfig,
            systemMessage: config.systemMessage,
            tools: tools,
            supportsVision: config.supportsVision,
            supportsAudio: config.supportsAudio
        )

        // Extract model info from the path.
        let filename = (config.modelPath as NSString).lastPathComponent
        let name = (filename as NSString).deletingPathExtension
        modelInfo = InferenceModelInfo(
            name: name,
            parameterCount: nil,
            quantization: nil,
            runtimeType: .litertlm
        )
    }

    func generateStream(
        prompt: String,
        config: GenerationConfig
    ) -> AsyncThrowingStream<GenerationEvent, Error> {
        guard engine.isReady else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: EngineError.notReady(
                    "LiteRT-LM engine is not initialized. Call loadModel() first."
                ))
            }
        }

        // Wrap the existing String stream into GenerationEvent stream.
        // Note: LiteRT-LM binds sampling parameters to the conversation at creation time,
        // not per-turn. If the caller needs different parameters, they would need to
        // call loadModel() again with a new config.
        let textStream = engine.sendMessageStream(prompt)

        return AsyncThrowingStream { continuation in
            Task { [weak self] in
                do {
                    for try await chunk in textStream {
                        continuation.yield(.text(chunk))
                    }

                    // After the stream completes, extract benchmark metrics if available.
                    if let benchmarkInfo = self?.engine.lastBenchmarkInfo {
                        let metrics = EnginePerformanceMetrics(
                            tokensPerSecond: benchmarkInfo.lastDecodeTokensPerSecond,
                            promptTokensPerSecond: benchmarkInfo.lastPrefillTokensPerSecond,
                            timeToFirstToken: benchmarkInfo.timeToFirstTokenInSecond,
                            peakMemoryBytes: nil,
                            tokenCount: benchmarkInfo.lastDecodeTokenCount,
                            memoryDeltaMB: self?.engine.lastInferenceMetrics?.memoryDeltaMB,
                            thermalStateChanged: self?.engine.lastInferenceMetrics?.thermalStateChanged,
                            runtimeType: .litertlm,
                            promptTokenCount: benchmarkInfo.lastPrefillTokenCount,
                            initTimeSeconds: benchmarkInfo.initTimeInSecond
                        )
                        self?.lastPerformanceMetrics = metrics
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

    // generateBatch uses the default implementation from InferenceEngine extension
    // (collects .text events into a single string).

    // MARK: - Lifecycle

    func shutdown() async {
        await engine.shutdown()
    }

    func resetConversation() async throws {
        try await engine.resetConversation()
    }

    func cancelGeneration() {
        engine.cancelGeneration()
    }

    func warmup() async throws {
        try await engine.warmup()
    }
}

// MARK: - LiteRT-Specific Extensions

extension LiteRTEngineAdapter {

    /// LiteRT-specific benchmark info from the last completed inference.
    var lastBenchmarkInfo: BenchmarkInfo? { engine.lastBenchmarkInfo }

    /// The current experimental flags state from the wrapped LiteRT engine.
    var flagsState: ExperimentalFlagsState { engine.flagsState }

    /// Initialize the LiteRT engine directly (bypassing the `InferenceEngine` abstraction).
    ///
    /// Used by `DeveloperAutomationHarness` for benchmark and eval automation flows
    /// that need direct control over backend selection (GPU vs CPU).
    func initializeLiteRT(
        modelPath: String,
        useGPU: Bool,
        cacheDir: String,
        flags: ExperimentalFlagsState,
        samplerConfig: SamplerConfig?
    ) async throws {
        try await engine.initialize(
            modelPath: modelPath,
            useGPU: useGPU,
            cacheDir: cacheDir,
            flags: flags,
            samplerConfig: samplerConfig,
            systemMessage: nil,
            tools: nil,
            supportsVision: false,
            supportsAudio: false
        )
    }

    /// Load a model with LiteRT-specific configuration.
    ///
    /// This is used during Phase 2 Core when `ModelSessionController` still builds
    /// `[Tool]` (LiteRTLM type) and `SamplerConfig` directly. Once tools migrate to
    /// `AppTool` in Phase 2 Consumers, this method will be replaced by the generic
    /// `loadModel(config:)` path.
    ///
    /// - Parameters:
    ///   - modelPath: Path to the model file.
    ///   - preferGPU: Whether to prefer GPU backend.
    ///   - cacheDir: Cache directory for engine artifacts.
    ///   - flags: Experimental flags configuration.
    ///   - samplerConfig: LiteRT-LM sampler config.
    ///   - systemMessage: Optional system message.
    ///   - tools: LiteRT-LM Tool array (existing tool conformance).
    ///   - supportsVision: Whether the model supports images.
    ///   - supportsAudio: Whether the model supports audio.
    /// - Returns: The `BackendResult` from initialization (backend used, fallback info).
    @discardableResult
    func loadWithLiteRTConfig(
        modelPath: String,
        preferGPU: Bool,
        cacheDir: String,
        flags: ExperimentalFlagsState,
        samplerConfig: SamplerConfig?,
        systemMessage: String?,
        tools: [Tool]?,
        supportsVision: Bool,
        supportsAudio: Bool,
        maxNumTokens: Int? = nil
    ) async throws -> BackendResult {
        let result = try await engine.initializeWithFallback(
            modelPath: modelPath,
            preferGPU: preferGPU,
            cacheDir: cacheDir,
            flags: flags,
            samplerConfig: samplerConfig,
            systemMessage: systemMessage,
            tools: tools,
            supportsVision: supportsVision,
            supportsAudio: supportsAudio,
            maxNumTokens: maxNumTokens
        )
        // BackendResult is now set on engine.lastBackendResult by initializeWithFallback,
        // and surfaced via the protocol-level computed property.

        // Extract model info
        let filename = (modelPath as NSString).lastPathComponent
        let name = (filename as NSString).deletingPathExtension
        modelInfo = InferenceModelInfo(
            name: name,
            parameterCount: nil,
            quantization: nil,
            runtimeType: .litertlm
        )

        return result
    }
}

// MARK: - GenerationConfig → SamplerConfig Mapping

extension LiteRTEngineAdapter {

    /// Convert a `GenerationConfig` to a LiteRT-LM `SamplerConfig`.
    ///
    /// This is a one-way mapping since `SamplerConfig` is a LiteRT-LM SDK type.
    /// Only the parameters that LiteRT-LM supports are mapped; diffusion-specific
    /// parameters (`diffusionSteps`, `diffusionSchedule`) and MLX-specific
    /// parameters (`repetitionPenalty`) are silently ignored.
    static func makeSamplerConfig(from config: GenerationConfig) throws -> SamplerConfig {
        try SamplerConfig(
            topK: config.topK,
            topP: Float(config.topP),
            temperature: Float(config.temperature)
        )
    }
}

