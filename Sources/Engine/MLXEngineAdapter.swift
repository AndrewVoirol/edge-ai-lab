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
/// 1. `loadModel(config:)` → downloads/loads model, creates ChatSession with tools + sampling
/// 2. `generateStream(prompt:config:)` → yields `.text`, `.toolCall`, `.metrics`, `.done` events
/// 3. `resetConversation()` → recreates `ChatSession` (clears KV cache + history)
/// 4. `shutdown()` → releases all resources and clears Metal memory cache
///
/// ## Tool Calling
///
/// Uses `ChatSession`'s native `tools` + `toolDispatch` mechanism:
/// - Tools are converted to `ToolSpec` via `MLXToolBridge.convertToMLXFormat()`
/// - `streamDetails()` yields `Generation.toolCall(ToolCall)` events
/// - Tool dispatch results are fed back via `Chat.Message.tool()` automatically
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

    /// The app-level tools registered at load time, for tool dispatch lookups.
    private var registeredTools: [any AppTool] = []

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

    var supportsVision: Bool { false }  // TODO: Phase 4 — wire MLXVLM via VLMModelFactory

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

        // Build GenerateParameters from config.
        var genParams = GenerateParameters()
        if let gen = config.generationConfig {
            genParams.temperature = Float(gen.temperature)
            genParams.topP = Float(gen.topP)
            genParams.topK = gen.topK
            genParams.maxTokens = gen.maxTokens
            if let penalty = gen.repetitionPenalty {
                genParams.repetitionPenalty = Float(penalty)
            }
            if let seed = gen.seed {
                genParams.seed = seed
            }
        }

        // Convert AppTool → ToolSpec for ChatSession.
        var mlxTools: [ToolSpec]?
        if let appTools = config.tools, !appTools.isEmpty {
            self.registeredTools = appTools
            mlxTools = MLXToolBridge.convertToMLXFormat(appTools)
        }

        // Create ChatSession with tools, system instructions, and sampling params.
        let session = ChatSession(
            container,
            instructions: config.systemMessage,
            generateParameters: genParams,
            tools: mlxTools
        )

        // Wire tool dispatch: when ChatSession detects a tool call in model output,
        // this closure executes the matching AppTool and returns the result string.
        // ChatSession automatically feeds the result back as a Chat.Message.tool()
        // and re-runs generation.
        if !self.registeredTools.isEmpty {
            let tools = self.registeredTools
            session.toolDispatch = { toolCall in
                let name = toolCall.function.name
                // Convert [String: JSONValue] → [String: Any] for AppTool.execute
                let arguments = toolCall.function.arguments.mapValues { $0.anyValue }
                return try await MLXToolBridge.executeToolCall(
                    toolName: name,
                    arguments: arguments,
                    tools: tools
                )
            }
        }

        self.chatSession = session

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

        // Apply per-generation sampling parameters.
        // ChatSession.generateParameters is a mutable public var.
        session.generateParameters.temperature = Float(config.temperature)
        session.generateParameters.topP = Float(config.topP)
        session.generateParameters.topK = config.topK
        session.generateParameters.maxTokens = config.maxTokens
        if let penalty = config.repetitionPenalty {
            session.generateParameters.repetitionPenalty = Float(penalty)
        }
        if let seed = config.seed {
            session.generateParameters.seed = seed
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var tokenCount = 0
                    let startTime = CFAbsoluteTimeGetCurrent()
                    var firstTokenTime: Double?

                    // Use streamDetails() for native Generation events:
                    // .chunk(String), .toolCall(ToolCall), .info(GenerateCompletionInfo)
                    for try await generation in session.streamDetails(to: prompt) {
                        if Task.isCancelled { break }

                        switch generation {
                        case .chunk(let text):
                            tokenCount += 1
                            if firstTokenTime == nil {
                                firstTokenTime = CFAbsoluteTimeGetCurrent() - startTime
                            }
                            continuation.yield(.text(text))

                        case .toolCall(let toolCall):
                            // Convert MLXLMCommon.ToolCall → AppToolCall for consumers.
                            // Note: arguments are [String: JSONValue]; convert to strings
                            // for AppToolCall's [String: String] contract.
                            let args = toolCall.function.arguments.reduce(
                                into: [String: String]()
                            ) { result, pair in
                                result[pair.key] = "\(pair.value)"
                            }
                            let appToolCall = AppToolCall(
                                id: toolCall.id ?? UUID().uuidString,
                                toolName: toolCall.function.name,
                                arguments: args
                            )
                            continuation.yield(.toolCall(appToolCall))

                        case .info(let completionInfo):
                            // Build EnginePerformanceMetrics from native
                            // GenerateCompletionInfo — gives us promptTokensPerSecond
                            // natively instead of manual timing.
                            let metrics = EnginePerformanceMetrics(
                                tokensPerSecond: completionInfo.tokensPerSecond,
                                promptTokensPerSecond: completionInfo.promptTokensPerSecond,
                                timeToFirstToken: firstTokenTime,
                                peakMemoryBytes: nil,
                                tokenCount: completionInfo.generationTokenCount,
                                memoryDeltaMB: nil,
                                thermalStateChanged: nil,
                                runtimeType: .mlx
                            )
                            self.lastPerformanceMetrics = metrics
                            continuation.yield(.metrics(metrics))
                        }
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
        // Preserve tools and system instructions when recreating session.
        let session = ChatSession(container, instructions: chatSession?.instructions)
        if !registeredTools.isEmpty {
            session.tools = chatSession?.tools
            let tools = self.registeredTools
            session.toolDispatch = { toolCall in
                let name = toolCall.function.name
                let arguments = toolCall.function.arguments.mapValues { $0.anyValue }
                return try await MLXToolBridge.executeToolCall(
                    toolName: name,
                    arguments: arguments,
                    tools: tools
                )
            }
        }
        if let oldParams = chatSession?.generateParameters {
            session.generateParameters = oldParams
        }
        chatSession = session
    }

    func shutdown() {
        activeTask?.cancel()
        activeTask = nil
        chatSession = nil
        modelContainer = nil
        registeredTools = []
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
    func warmup() async throws { /* Metal not available — no-op */ }
}

#endif
