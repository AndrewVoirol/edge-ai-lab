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
final class LiteRTEngineAdapter: InferenceEngine, @unchecked Sendable {

    // MARK: - State

    /// The wrapped LiteRT-LM engine.
    private let engine: InstrumentedEngine

    /// The model info extracted after loading.
    private(set) var modelInfo: InferenceModelInfo?

    /// The sampler config applied to the current conversation.
    private var activeSamplerConfig: SamplerConfig?

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

    func loadModel(config: ModelLoadConfig) async throws {
        // Build a sampler config if we have one cached from a prior generate call.
        // LiteRT-LM binds sampler config at conversation creation time.
        let samplerConfig = activeSamplerConfig

        // Determine cache directory — use the provided one or fall back to tmp.
        let cacheDir = config.cacheDir ?? NSTemporaryDirectory()

        // Default flags: benchmarking enabled, other experimental features off.
        let flags = ExperimentalFlagsState(
            enableBenchmark: true,
            enableSpeculativeDecoding: nil,
            enableConversationConstrainedDecoding: false,
            visualTokenBudget: nil
        )

        // Use smart fallback initialization.
        _ = try await engine.initializeWithFallback(
            modelPath: config.modelPath,
            preferGPU: config.preferGPU,
            cacheDir: cacheDir,
            flags: flags,
            samplerConfig: samplerConfig
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
    ) -> AsyncThrowingStream<String, Error> {
        guard engine.isReady else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: EngineError.notReady(
                    "LiteRT-LM engine is not initialized. Call loadModel() first."
                ))
            }
        }

        // Note: LiteRT-LM binds sampling parameters to the conversation at creation time,
        // not per-turn. If the caller needs different parameters, they would need to
        // call loadModel() again with a new config. For now, we use whatever was set
        // at conversation creation.
        return engine.sendMessageStream(prompt)
    }

    // generateBatch uses the default implementation from InferenceEngine extension
    // (collects stream into a single string).
}

// MARK: - GenerationConfig → SamplerConfig Mapping

extension LiteRTEngineAdapter {

    /// Convert a `GenerationConfig` to a LiteRT-LM `SamplerConfig`.
    ///
    /// This is a one-way mapping since `SamplerConfig` is a LiteRT-LM SDK type.
    /// Only the parameters that LiteRT-LM supports are mapped; diffusion-specific
    /// parameters (`diffusionSteps`, `diffusionSchedule`) are silently ignored.
    static func makeSamplerConfig(from config: GenerationConfig) throws -> SamplerConfig {
        try SamplerConfig(
            topK: config.topK,
            topP: Float(config.topP),
            temperature: Float(config.temperature)
        )
    }
}
