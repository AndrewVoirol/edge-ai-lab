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

// MARK: - MLXEngineAdapter

// MLX requires Metal, which is unavailable on iOS Simulator.
// The real implementation is conditionally compiled; a stub is provided for Simulator.

#if canImport(MLX)
import MLX
import MLXLLM
import MLXLMCommon
import Tokenizers
import Hub

// MARK: - HuggingFace Integration (replaces MLXHuggingFace macros)

/// Downloads model snapshots from HuggingFace Hub via `HubApi`.
///
/// Conforms to `MLXLMCommon.Downloader` so it can be passed directly to
/// `LLMModelFactory.shared.loadContainer(from:using:configuration:)`.
private struct HubDownloader: MLXLMCommon.Downloader {
    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        let hub = HubApi()
        let repo = Hub.Repo(id: id)
        return try await hub.snapshot(
            from: repo,
            matching: patterns,
            progressHandler: progressHandler
        )
    }
}

/// Loads tokenizers from local model directories using `swift-transformers`' `AutoTokenizer`.
///
/// Bridges `Tokenizers.Tokenizer` (swift-transformers) → `MLXLMCommon.Tokenizer` so the
/// mlx-swift-lm model factory can load tokenizers without the `MLXHuggingFace` macro.
private struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await AutoTokenizer.from(modelFolder: directory)
        return TokenizerBridge(upstream)
    }
}

/// Bridges `Tokenizers.Tokenizer` → `MLXLMCommon.Tokenizer`.
///
/// The two `Tokenizer` protocols have slightly different method signatures
/// (`decode(tokens:)` vs `decode(tokenIds:)`). This bridge adapts between them.
private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}

/// MLX inference engine adapter — wraps `mlx-swift-lm` for on-device Metal GPU inference.
///
/// ## Design
///
/// - Uses the **containment pattern**: all MLX types (`ModelContainer`, `ChatSession`,
///   `MLXArray`) stay private inside this class. Only `Sendable` types cross the boundary.
/// - `@unchecked Sendable` because we manage thread safety through containment — all MLX
///   operations happen inside `Task`s that the adapter controls.
///
/// ## Lifecycle
///
/// 1. `loadModel(config:)` → downloads/loads model via `LLMModelFactory.shared.loadContainer()`
/// 2. `generateStream(prompt:config:)` → yields `.text`, `.metrics`, `.done` events
/// 3. `resetConversation()` → recreates `ChatSession` (clears KV cache + history)
/// 4. `shutdown()` → releases all resources and clears Metal memory cache
///
/// ## Memory
///
/// - `Memory.cacheLimit` controls the Metal buffer reclamation pool (default: 512 MB)
/// - `Memory.clearCache()` frees cached buffers on shutdown
/// - iOS targets require the `Increased Memory Limit` entitlement for models > 2 GB
final class MLXEngineAdapter: InferenceEngine, @unchecked Sendable {

    // MARK: - Private State (MLX types contained here — never exposed)

    /// The loaded model container. Holds weights, tokenizer, and config.
    private var modelContainer: ModelContainer?

    /// The active chat session. Maintains conversation history and KV cache.
    private var chatSession: ChatSession?

    /// The currently active generation task, for cancellation support.
    private var activeTask: Task<Void, Never>?

    /// Model metadata extracted after loading.
    private(set) var modelInfo: InferenceModelInfo?

    /// Performance metrics from the most recent generation.
    private(set) var lastPerformanceMetrics: EnginePerformanceMetrics?

    // MARK: - Download Progress (observable from UI)

    /// Download progress (0.0 → 1.0) during `loadModel`. Observable for UI binding.
    var downloadProgress: Double = 0.0

    // MARK: - InferenceEngine Conformance

    var isLoaded: Bool { modelContainer != nil }

    var runtimeType: RuntimeType { .mlx }

    var supportsToolCalling: Bool { true }

    var supportsVision: Bool { false } // Phase 4: VLM support

    // MARK: - Loading

    func loadModel(config: ModelLoadConfig) async throws {
        let configuration = ModelConfiguration(id: config.modelPath)

        let container = try await LLMModelFactory.shared.loadContainer(
            from: HubDownloader(),
            using: TransformersTokenizerLoader(),
            configuration: configuration
        ) { [weak self] progress in
            self?.downloadProgress = progress.fractionCompleted
        }

        self.modelContainer = container
        self.chatSession = ChatSession(container)

        // Configure Metal memory cache limit (512 MB — balances reuse vs. pressure).
        Memory.cacheLimit = 512 * 1024 * 1024

        modelInfo = InferenceModelInfo(
            name: config.modelPath.split(separator: "/").last.map(String.init) ?? config.modelPath,
            parameterCount: nil,
            quantization: nil,
            runtimeType: .mlx
        )
    }

    // MARK: - Generation

    func generateStream(
        prompt: String,
        config: GenerationConfig
    ) -> AsyncThrowingStream<GenerationEvent, Error> {
        guard let session = chatSession else {
            return AsyncThrowingStream { $0.finish(throwing: EngineError.notReady("MLX model not loaded")) }
        }

        // Set seed if provided (MLX uses a global seed, not per-generation).
        if let seed = config.seed {
            MLXRandom.seed(seed)
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var tokenCount = 0
                    let startTime = CFAbsoluteTimeGetCurrent()
                    var firstTokenTime: Double?

                    for try await token in session.streamResponse(to: prompt) {
                        if Task.isCancelled { break }

                        tokenCount += 1
                        if firstTokenTime == nil {
                            firstTokenTime = CFAbsoluteTimeGetCurrent() - startTime
                        }
                        continuation.yield(.text(token))
                    }

                    // Compute performance metrics from timing data.
                    // Phase 2 refinement: use lower-level MLXLMCommon.generate() API
                    // to get GenerateCompletionInfo with native prompt timing.
                    let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                    if tokenCount > 0 && elapsed > 0 {
                        let metrics = EnginePerformanceMetrics(
                            tokensPerSecond: Double(tokenCount) / elapsed,
                            promptTokensPerSecond: nil, // Requires lower-level API
                            timeToFirstToken: firstTokenTime,
                            peakMemoryBytes: nil,
                            tokenCount: tokenCount,
                            memoryDeltaMB: nil,
                            thermalStateChanged: nil,
                            runtimeType: .mlx
                        )
                        self.lastPerformanceMetrics = metrics
                        continuation.yield(.metrics(metrics))
                    }

                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            self.activeTask = task
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func generateBatch(prompt: String, config: GenerationConfig) async throws -> String {
        var result = ""
        for try await event in generateStream(prompt: prompt, config: config) {
            if case .text(let token) = event { result += token }
        }
        return result
    }

    // MARK: - Lifecycle

    func cancelGeneration() {
        activeTask?.cancel()
        activeTask = nil
    }

    func resetConversation() async throws {
        guard let container = modelContainer else { return }
        chatSession = ChatSession(container)
    }

    func shutdown() {
        activeTask?.cancel()
        activeTask = nil
        chatSession = nil
        modelContainer = nil
        Memory.clearCache()
        lastPerformanceMetrics = nil
        modelInfo = nil
        downloadProgress = 0.0
    }
}

#else

// MARK: - Stub for platforms without Metal (iOS Simulator)

/// Stub implementation for platforms where Metal is unavailable (iOS Simulator).
///
/// All operations throw `EngineError.notReady` immediately. Use `MockInferenceEngine`
/// with `runtimeType: .mlx` for unit testing on Simulator.
final class MLXEngineAdapter: InferenceEngine, @unchecked Sendable {

    var isLoaded: Bool { false }
    var runtimeType: RuntimeType { .mlx }
    var modelInfo: InferenceModelInfo? { nil }
    var lastPerformanceMetrics: EnginePerformanceMetrics? { nil }
    var supportsVision: Bool { false }
    var supportsToolCalling: Bool { false }
    var downloadProgress: Double { 0.0 }

    func loadModel(config: ModelLoadConfig) async throws {
        throw EngineError.notReady("MLX requires Metal — not available on iOS Simulator")
    }

    func generateStream(
        prompt: String,
        config: GenerationConfig
    ) -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: EngineError.notReady("MLX requires Metal")) }
    }

    func generateBatch(
        prompt: String,
        config: GenerationConfig
    ) async throws -> String {
        throw EngineError.notReady("MLX requires Metal")
    }

    func shutdown() { }
    func resetConversation() async throws { }
    func cancelGeneration() { }
}

#endif
