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
import os

// MARK: - MLXEngineAdapter

// MLX requires Metal, which is unavailable on iOS Simulator.
// The real implementation is conditionally compiled; a stub is provided for Simulator.

#if canImport(MLX) && !targetEnvironment(simulator)
import MLX
import MLXLLM
import MLXLMCommon
import MLXVLM
import Tokenizers
import Hub
import CoreImage

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

    // MARK: - Signpost Infrastructure

    /// Modern OSSignposter for Instruments visibility.
    /// Category "mlx" groups all MLX engine signposts together in the timeline.
    private static let signposter = OSSignposter(
        subsystem: "com.andrewvoirol.EdgeAILab",
        category: "mlx"
    )

    /// Structured logger for runtime diagnostics (visible in Console.app + Xcode debug console).
    private static let logger = Logger(
        subsystem: "com.andrewvoirol.EdgeAILab",
        category: "mlx"
    )

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

    /// Device-level inference metrics (thermal, memory, per-token latency).
    /// Matches the instrumentation that InstrumentedEngine provides for LiteRT.
    private(set) var lastInferenceMetrics: InferenceMetrics?

    // MARK: - Download Progress (observable from UI)

    /// Download progress (0.0 → 1.0) during `loadModel`. Observable for UI binding.
    var downloadProgress: Double = 0.0

    // MARK: - InferenceEngine Conformance

    var isLoaded: Bool { modelContainer != nil }

    var runtimeType: RuntimeType { .mlx }

    var supportsToolCalling: Bool { true }

    private(set) var supportsVision: Bool = false

    /// Error from VLM loading attempt, if VLM loading failed and fell back to text-only LLM.
    /// Nil if VLM loaded successfully or if the model isn't a VLM.
    /// Used by EvalRunner and diagnostics to surface why vision isn't available.
    private(set) var vlmLoadError: Error?

    // MARK: - Loading

    /// Detects whether a local model directory is a VLM by checking for vision processor configs.
    /// Delegates to `MLXVLMDetectionHelper` (a testable enum namespace).
    private static func isVLMModel(at directory: URL) -> Bool {
        MLXVLMDetectionHelper.isVLMModel(at: directory)
    }

    func loadModel(config: ModelLoadConfig) async throws {
        let modelLabel = config.modelPath.split(separator: "/").last.map(String.init) ?? config.modelPath
        Self.logger.info("⏳ MLX load: \(modelLabel, privacy: .public)")

        let signpostState = Self.signposter.beginInterval(
            "ModelLoad",
            id: Self.signposter.makeSignpostID(),
            "Loading \(modelLabel, privacy: .public)"
        )

        let container: ModelContainer

        // Determine if modelPath is a local directory or a HuggingFace repo ID.
        // Three cases:
        //   1. Local directory (downloaded MLX model) → load from disk
        //   2. Local path that exists but isn't a valid directory → error (e.g., stub file from failed download)
        //   3. HuggingFace repo ID (e.g., "mlx-community/gemma-4-E2B-it-4bit") → download via Hub
        let isLocalPath = config.modelPath.hasPrefix("/") || config.modelPath.hasPrefix("~")
        let modelURL = URL(fileURLWithPath: config.modelPath)

        var vlmLoadedSuccessfully = false

        if isLocalPath {
            // Local path — must be a valid directory with MLX model files
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: config.modelPath, isDirectory: &isDir)

            guard exists, isDir.boolValue else {
                // Path exists as a regular file (e.g., download stub) or doesn't exist at all
                let reason = exists
                    ? "Path exists but is not a directory. The MLX model may not be fully downloaded."
                    : "Model directory not found at path."
                throw EngineError.notReady(reason)
            }

            // Try VLMModelFactory first for models with vision processor configs.
            // Fall back to LLMModelFactory if VLM loading fails.
            // LLMModelFactory's Gemma4Model has a sanitize(weights:) method that
            // strips the language_model. prefix and drops vision/audio keys, so it
            // can load VLM-structured weights for text-only inference.
            if Self.isVLMModel(at: modelURL) {
                do {
                    container = try await VLMModelFactory.shared.loadContainer(
                        from: modelURL,
                        using: TransformersTokenizerLoader()
                    )
                    vlmLoadedSuccessfully = true
                    Self.logger.info("✅ VLM loaded: vision pipeline active for \(modelLabel, privacy: .public)")
                } catch {
                    // VLM loading failed — fall back to text-only LLM.
                    // This loses multimodal (image/audio) input but preserves text inference.
                    self.vlmLoadError = error
                    Self.logger.warning("⚠️ VLM load failed (\(String(describing: error), privacy: .public)), falling back to text-only LLM for \(modelLabel, privacy: .public)")
                    container = try await LLMModelFactory.shared.loadContainer(
                        from: modelURL,
                        using: TransformersTokenizerLoader()
                    )
                }
            } else {
                container = try await LLMModelFactory.shared.loadContainer(
                    from: modelURL,
                    using: TransformersTokenizerLoader()
                )
            }
            self.downloadProgress = 1.0
        } else {
            // HuggingFace repo ID — download via Hub API
            let configuration = ModelConfiguration(id: config.modelPath)
            // Same try-VLM-catch-LLM pattern for HF downloads.
            if config.supportsVision {
                do {
                    container = try await VLMModelFactory.shared.loadContainer(
                        from: HubDownloader(),
                        using: TransformersTokenizerLoader(),
                        configuration: configuration
                    ) { [weak self] progress in
                        self?.downloadProgress = progress.fractionCompleted
                    }
                    vlmLoadedSuccessfully = true
                    Self.logger.info("✅ VLM loaded (HF): vision pipeline active for \(modelLabel, privacy: .public)")
                } catch {
                    self.vlmLoadError = error
                    Self.logger.warning("⚠️ VLM load failed (HF) (\(String(describing: error), privacy: .public)), falling back to text-only LLM for \(modelLabel, privacy: .public)")
                    container = try await LLMModelFactory.shared.loadContainer(
                        from: HubDownloader(),
                        using: TransformersTokenizerLoader(),
                        configuration: configuration
                    ) { [weak self] progress in
                        self?.downloadProgress = progress.fractionCompleted
                    }
                }
            } else {
                container = try await LLMModelFactory.shared.loadContainer(
                    from: HubDownloader(),
                    using: TransformersTokenizerLoader(),
                    configuration: configuration
                ) { [weak self] progress in
                    self?.downloadProgress = progress.fractionCompleted
                }
            }
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

        // Build additionalContext for Jinja template variables.
        // The Gemma 4 chat template checks `enable_thinking` to inject the
        // thinking prompt (`<|think|>`). Without this, thinking mode silently
        // produces output without `<think>` tags.
        var templateContext: [String: any Sendable]?
        if let flags = config.runtimeFlags, flags.enableThinking {
            templateContext = ["enable_thinking": true]
        }

        // Create ChatSession with tools, system instructions, and sampling params.
        let session = ChatSession(
            container,
            instructions: config.systemMessage,
            generateParameters: genParams,
            additionalContext: templateContext,
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
                print("[MLXEngine] 🔧 Tool dispatch: \(name) with args: \(arguments)")
                do {
                    let result = try await MLXToolBridge.executeToolCall(
                        toolName: name,
                        arguments: arguments,
                        tools: tools
                    )
                    print("[MLXEngine] ✅ Tool \(name) returned: \(result.prefix(200))")
                    return result
                } catch {
                    print("[MLXEngine] ❌ Tool \(name) failed: \(error)")
                    throw error
                }
            }
        }

        self.chatSession = session

        // Configure Metal memory cache limits from RuntimeFlags, or use defaults.
        if let cacheLimit = config.runtimeFlags?.metalCacheLimit {
            Memory.cacheLimit = cacheLimit
        } else {
            // Default: 512 MB — balances buffer reuse vs. memory pressure.
            Memory.cacheLimit = 512 * 1024 * 1024
        }
        if let memLimit = config.runtimeFlags?.metalMemoryLimit {
            Memory.memoryLimit = memLimit
        }

        modelInfo = InferenceModelInfo(
            name: modelLabel,
            parameterCount: nil,
            quantization: nil,
            runtimeType: .mlx
        )

        // Set vision capability: only true if the metadata says vision is supported
        // AND the VLM model factory actually loaded successfully. If VLM loading
        // fell back to LLMModelFactory, the vision weights were stripped —
        // claiming vision support would cause silent failures on image prompts.
        self.supportsVision = config.supportsVision && vlmLoadedSuccessfully

        Self.logger.info("✅ MLX ready: \(modelLabel, privacy: .public)")
        Self.signposter.endInterval("ModelLoad", signpostState, "Model loaded successfully")
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
                let signpostState = Self.signposter.beginInterval(
                    "Inference",
                    id: Self.signposter.makeSignpostID(),
                    "prompt=\(prompt.prefix(80), privacy: .public)"
                )
                // Capture device state at inference start for delta metrics
                // (declared outside do/catch so failure path can also use it)
                let startSnapshot = DeviceMetrics.captureSnapshot()
                do {
                    var tokenCount = 0
                    let startTime = CFAbsoluteTimeGetCurrent()
                    var firstTokenTime: Double?
                    var tokenTimestamps: [Double] = []

                    // Use streamDetails() for native Generation events:
                    // .chunk(String), .toolCall(ToolCall), .info(GenerateCompletionInfo)
                    //
                    // When imageData is present (VLM mode), convert Data → CIImage →
                    // UserInput.Image for the vision pipeline. The processor handles
                    // resizing/tokenization based on the model's config.
                    let images: [UserInput.Image] = (config.imageData ?? []).compactMap { data in
                        guard let ciImage = CIImage(data: data) else {
                            // Skip invalid image data silently — don't crash the stream.
                            return nil
                        }
                        return .ciImage(ciImage)
                    }

                    // Convert raw audio Data to UserInput.Audio for the audio pipeline.
                    // UserInput.Audio only supports .url(URL) and .array(MLXArray) — no
                    // direct Data case. Write each audio clip to a temp WAV file and pass
                    // via .url(). The SDK's AVFoundation-based AudioProcessing reads from
                    // the file URL and resamples as needed.
                    let audios: [UserInput.Audio] = (config.audioData ?? []).compactMap { data in
                        let tempDir = FileManager.default.temporaryDirectory
                        let tempURL = tempDir.appendingPathComponent(UUID().uuidString + ".wav")
                        do {
                            try data.write(to: tempURL)
                            return .url(tempURL)
                        } catch {
                            Self.logger.warning("⚠️ Failed to write temp audio file: \(error.localizedDescription, privacy: .public)")
                            return nil
                        }
                    }

                    for try await generation in session.streamDetails(
                        to: prompt,
                        images: images,
                        audios: audios
                    ) {
                        if Task.isCancelled { break }

                        switch generation {
                        case .chunk(let text):
                            tokenCount += 1
                            let now = CFAbsoluteTimeGetCurrent()
                            tokenTimestamps.append(now)
                            if firstTokenTime == nil {
                                firstTokenTime = now - startTime
                                Self.signposter.emitEvent(
                                    "FirstToken",
                                    "TTFT=\(String(format: "%.1f", firstTokenTime! * 1000))ms"
                                )
                                Self.logger.info("⚡ MLX first token: \(String(format: "%.1f", firstTokenTime! * 1000), privacy: .public)ms")
                            }
                            continuation.yield(.text(text))

                        case .toolCall(let toolCall):
                            // Convert MLXLMCommon.ToolCall → AppToolCall for consumers.
                            // Arguments are [String: JSONValue]; wrap in AnyCodable
                            // to preserve type fidelity (integers, booleans, nested objects).
                            let args = toolCall.function.arguments.reduce(
                                into: [String: AnyCodable]()
                            ) { result, pair in
                                result[pair.key] = AnyCodable(pair.value.anyValue)
                            }
                            let appToolCall = AppToolCall(
                                id: toolCall.id ?? UUID().uuidString,
                                toolName: toolCall.function.name,
                                arguments: args
                            )
                            continuation.yield(.toolCall(appToolCall))

                        case .info(let completionInfo):
                            // Capture device state at inference end
                            let endSnapshot = DeviceMetrics.captureSnapshot()

                            // Build per-token latency arrays matching InstrumentedEngine's format
                            let ttftMs: Double?
                            var decodeLatenciesMs: [Double] = []
                            if !tokenTimestamps.isEmpty {
                                ttftMs = (tokenTimestamps[0] - startTime) * 1000.0
                                for i in 1..<tokenTimestamps.count {
                                    decodeLatenciesMs.append(
                                        (tokenTimestamps[i] - tokenTimestamps[i - 1]) * 1000.0
                                    )
                                }
                            } else {
                                ttftMs = nil
                            }

                            // Build device-level InferenceMetrics
                            let inferenceMetrics = InferenceMetrics(
                                startSnapshot: startSnapshot,
                                endSnapshot: endSnapshot,
                                ttftMs: ttftMs,
                                decodeLatenciesMs: decodeLatenciesMs,
                                totalTokenCount: tokenTimestamps.count
                            )
                            self.lastInferenceMetrics = inferenceMetrics

                            // Build enriched EnginePerformanceMetrics from native
                            // GenerateCompletionInfo + device snapshots
                            let metrics = EnginePerformanceMetrics(
                                tokensPerSecond: completionInfo.tokensPerSecond,
                                promptTokensPerSecond: completionInfo.promptTokensPerSecond,
                                timeToFirstToken: firstTokenTime,
                                peakMemoryBytes: nil,
                                tokenCount: completionInfo.generationTokenCount,
                                memoryDeltaMB: inferenceMetrics.memoryDeltaMB,
                                thermalStateChanged: inferenceMetrics.thermalStateChanged,
                                runtimeType: .mlx,
                                promptTokenCount: completionInfo.promptTokenCount,
                                proposedDraftTokens: completionInfo.proposedDraftTokens,
                                acceptedDraftTokens: completionInfo.acceptedDraftTokens,
                                passthroughReason: completionInfo.passthroughReason,
                                promptTimeSeconds: completionInfo.promptTime,
                                generateTimeSeconds: completionInfo.generateTime
                            )
                            self.lastPerformanceMetrics = metrics
                            continuation.yield(.metrics(metrics))
                        }
                    }

                    continuation.yield(.done)
                    continuation.finish()
                    let ttftDisplay = firstTokenTime.map { String(format: "%.0fms", $0 * 1000) } ?? "n/a"
                    Self.signposter.endInterval(
                        "Inference", signpostState,
                        "\(tokenCount) tok, \(self.lastPerformanceMetrics?.tokensPerSecond ?? 0, format: .fixed(precision: 1)) tok/s, TTFT=\(ttftDisplay, privacy: .public)"
                    )
                } catch {
                    Self.signposter.endInterval(
                        "Inference", signpostState,
                        "FAILED: \(error.localizedDescription, privacy: .public)"
                    )
                    // Still capture failure metrics for debugging
                    let endSnapshot = DeviceMetrics.captureSnapshot()
                    self.lastInferenceMetrics = InferenceMetrics(
                        startSnapshot: startSnapshot,
                        endSnapshot: endSnapshot,
                        ttftMs: nil,
                        decodeLatenciesMs: [],
                        totalTokenCount: 0
                    )
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

    func shutdown() async {
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

    func shutdown() async { }
    func resetConversation() async throws { }
    func cancelGeneration() { }
    func warmup() async throws { /* Metal not available — no-op */ }
}

#endif
