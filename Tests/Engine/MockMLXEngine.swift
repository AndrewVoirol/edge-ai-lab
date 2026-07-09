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

// MARK: - MockMLXEngine

/// A mock `InferenceEngine` configured with `.mlx` runtime type.
///
/// Use this for unit tests that need an MLX-flavored engine without requiring
/// Metal or actual model loading. Configurable responses and call tracking.
///
/// ## Usage
///
/// ```swift
/// let mock = MockMLXEngine()
/// mock.responses = ["Hello", " World"]
/// let engine: any InferenceEngine = mock
/// for try await event in engine.generateStream(prompt: "Hi", config: .default) {
///     // Receives .text("Hello"), .text(" World"), .done
/// }
/// ```
final class MockMLXEngine: InferenceEngine, @unchecked Sendable {

    // MARK: - Configurable Behavior

    /// Text tokens to emit during generation. Each string becomes a `.text()` event.
    var responses: [String] = []

    /// If non-nil, `loadModel` will throw this error instead of succeeding.
    var loadError: Error?

    /// If non-nil, `generateStream` will throw this error after emitting tokens.
    var generateError: Error?

    /// Performance metrics to emit at end of generation. Nil = no metrics event.
    var metricsToEmit: EnginePerformanceMetrics?

    // MARK: - Call Tracking

    /// Number of times `loadModel` was called.
    var loadModelCallCount = 0

    /// Number of times `generateStream` was called.
    var generateStreamCallCount = 0

    /// Number of times `generateBatch` was called.
    var generateBatchCallCount = 0

    /// Number of times `shutdown` was called.
    var shutdownCallCount = 0

    /// Number of times `resetConversation` was called.
    var resetConversationCallCount = 0

    /// Number of times `cancelGeneration` was called.
    var cancelGenerationCallCount = 0

    /// The last prompt passed to `generateStream`.
    var lastPrompt: String?

    /// The last config passed to `generateStream`.
    var lastConfig: GenerationConfig?

    /// The last config passed to `loadModel`.
    var lastLoadConfig: ModelLoadConfig?

    // MARK: - InferenceEngine State

    private(set) var modelInfo: InferenceModelInfo?
    private(set) var lastPerformanceMetrics: EnginePerformanceMetrics?

    var isLoaded: Bool { modelInfo != nil }
    var runtimeType: RuntimeType { .mlx }
    var supportsToolCalling: Bool { true }
    var supportsVision: Bool { false }

    // MARK: - InferenceEngine Methods

    func loadModel(config: ModelLoadConfig) async throws {
        loadModelCallCount += 1
        lastLoadConfig = config

        if let error = loadError {
            throw error
        }

        modelInfo = InferenceModelInfo(
            name: "mock-mlx-model",
            parameterCount: "2B",
            quantization: "4bit",
            runtimeType: .mlx
        )
    }

    func generateStream(
        prompt: String,
        config: GenerationConfig
    ) -> AsyncThrowingStream<GenerationEvent, Error> {
        generateStreamCallCount += 1
        lastPrompt = prompt
        lastConfig = config

        guard isLoaded else {
            return AsyncThrowingStream {
                $0.finish(throwing: EngineError.notReady("Mock MLX engine not loaded"))
            }
        }

        let tokens = responses
        let error = generateError
        let metrics = metricsToEmit

        return AsyncThrowingStream { continuation in
            Task {
                for token in tokens {
                    continuation.yield(.text(token))
                }

                if let error {
                    continuation.finish(throwing: error)
                    return
                }

                if let metrics {
                    self.lastPerformanceMetrics = metrics
                    continuation.yield(.metrics(metrics))
                }

                continuation.yield(.done)
                continuation.finish()
            }
        }
    }

    func generateBatch(
        prompt: String,
        config: GenerationConfig
    ) async throws -> String {
        generateBatchCallCount += 1
        var result = ""
        for try await event in generateStream(prompt: prompt, config: config) {
            if case .text(let token) = event { result += token }
        }
        return result
    }

    func shutdown() async {
        shutdownCallCount += 1
        modelInfo = nil
        lastPerformanceMetrics = nil
    }

    func resetConversation() async throws {
        resetConversationCallCount += 1
    }

    func cancelGeneration() {
        cancelGenerationCallCount += 1
    }
}
