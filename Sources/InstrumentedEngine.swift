import Foundation
import LiteRTLM
import os

// MARK: - Protocol

/// Protocol defining the interface for an instrumented LLM inference engine.
/// Wraps LiteRTLM Engine/Conversation with signpost emission and benchmark capture.
/// Unit tests inject `MockInstrumentedEngine`, integration tests use `InstrumentedEngine`.
protocol InstrumentedEngineProtocol: AnyObject {
    /// Whether the engine has been initialized and is ready for conversation.
    var isReady: Bool { get }

    /// The most recent BenchmarkInfo from the last completed inference, or nil.
    var lastBenchmarkInfo: BenchmarkInfo? { get }

    /// The most recent device-level inference metrics (thermal, memory, per-token latency).
    var lastInferenceMetrics: InferenceMetrics? { get }

    /// The current experimental flags state.
    var flagsState: ExperimentalFlagsState { get }

    /// The result of the last backend initialization attempt.
    var lastBackendResult: BackendResult? { get }

    /// Initialize the engine with a model file.
    /// - Parameters:
    ///   - modelPath: Filesystem path to the .litertlm model file.
    ///   - useGPU: Whether to use GPU backend (true) or CPU (false).
    ///   - cacheDir: Cache directory path for the engine.
    ///   - flags: Experimental flags configuration to apply.
    ///   - samplerConfig: Optional sampler configuration (topK, topP, temperature).
    ///     If nil, uses the SDK's defaults.
    ///   - systemMessage: Optional system message for model persona.
    ///   - tools: Optional array of Tool definitions for function calling.
    func initialize(
        modelPath: String,
        useGPU: Bool,
        cacheDir: String,
        flags: ExperimentalFlagsState,
        samplerConfig: SamplerConfig?,
        systemMessage: String?,
        tools: [Tool]?
    ) async throws

    /// Initialize with smart fallback: try the preferred backend, fall back if it fails.
    /// - Parameters:
    ///   - modelPath: Filesystem path to the .litertlm model file.
    ///   - preferGPU: Whether GPU is the preferred backend.
    ///   - cacheDir: Cache directory path for the engine.
    ///   - flags: Experimental flags configuration to apply.
    ///   - samplerConfig: Optional sampler configuration (topK, topP, temperature).
    ///   - systemMessage: Optional system message for model persona.
    ///   - tools: Optional array of Tool definitions for function calling.
    /// - Returns: The result describing which backend was actually used.
    func initializeWithFallback(
        modelPath: String,
        preferGPU: Bool,
        cacheDir: String,
        flags: ExperimentalFlagsState,
        samplerConfig: SamplerConfig?,
        systemMessage: String?,
        tools: [Tool]?
    ) async throws -> BackendResult

    /// Send a message and receive a streamed response.
    /// - Parameter text: The user's prompt text.
    /// - Returns: An AsyncThrowingStream of response text chunks.
    func sendMessageStream(_ text: String) -> AsyncThrowingStream<String, Error>

    /// Send a multimodal message (text + optional image/audio) and receive a streamed response.
    /// - Parameters:
    ///   - text: The user's prompt text.
    ///   - imageData: Optional JPEG/PNG image data for vision-capable models.
    ///   - audioData: Optional audio data for audio-capable models.
    /// - Returns: An AsyncThrowingStream of response text chunks.
    func sendMessageStream(
        _ text: String,
        imageData: Data?,
        audioData: Data?
    ) -> AsyncThrowingStream<String, Error>

    /// Create a fresh conversation on the existing engine, resetting the context window.
    /// The engine stays alive (preserving model weights), only the conversation is recreated.
    /// - Throws: An error if the engine is not initialized or conversation creation fails.
    func resetConversation() async throws

    /// Send a short throwaway prompt to prime the SDK's benchmark subsystem.
    /// After warmup completes, `getBenchmarkInfo()` will return non-nil on subsequent turns.
    /// The warmup response is discarded. Call `resetConversation()` after warmup to get
    /// a clean context for the real benchmark.
    func warmup() async throws

    /// Cancel any currently active inference generation.
    func cancelGeneration()

    /// Tear down the engine and free resources.
    func shutdown() async
}

// MARK: - Backend Result

/// Describes the outcome of a backend initialization attempt.
struct BackendResult: Sendable {
    /// The backend that was actually activated.
    let activeBackend: ActiveBackend
    /// Whether the engine fell back from the preferred backend.
    let didFallback: Bool
    /// The error from the preferred backend, if fallback occurred.
    let fallbackReason: String?
    /// The detected capability of the model on this platform.
    let detectedCapability: BackendCapability

    enum ActiveBackend: String, Sendable {
        case gpu
        case cpu
    }
}

// MARK: - Protocol Defaults

extension InstrumentedEngineProtocol {
    /// Default systemMessage and tools to nil for callers that don't need them.
    func initialize(
        modelPath: String,
        useGPU: Bool,
        cacheDir: String,
        flags: ExperimentalFlagsState,
        samplerConfig: SamplerConfig?
    ) async throws {
        try await initialize(
            modelPath: modelPath,
            useGPU: useGPU,
            cacheDir: cacheDir,
            flags: flags,
            samplerConfig: samplerConfig,
            systemMessage: nil,
            tools: nil
        )
    }

    /// Default tools to nil for callers that don't need tool calling.
    func initialize(
        modelPath: String,
        useGPU: Bool,
        cacheDir: String,
        flags: ExperimentalFlagsState,
        samplerConfig: SamplerConfig?,
        systemMessage: String?
    ) async throws {
        try await initialize(
            modelPath: modelPath,
            useGPU: useGPU,
            cacheDir: cacheDir,
            flags: flags,
            samplerConfig: samplerConfig,
            systemMessage: systemMessage,
            tools: nil
        )
    }

    func initializeWithFallback(
        modelPath: String,
        preferGPU: Bool,
        cacheDir: String,
        flags: ExperimentalFlagsState,
        samplerConfig: SamplerConfig?
    ) async throws -> BackendResult {
        try await initializeWithFallback(
            modelPath: modelPath,
            preferGPU: preferGPU,
            cacheDir: cacheDir,
            flags: flags,
            samplerConfig: samplerConfig,
            systemMessage: nil,
            tools: nil
        )
    }

    /// Default tools to nil for callers that don't need tool calling.
    func initializeWithFallback(
        modelPath: String,
        preferGPU: Bool,
        cacheDir: String,
        flags: ExperimentalFlagsState,
        samplerConfig: SamplerConfig?,
        systemMessage: String?
    ) async throws -> BackendResult {
        try await initializeWithFallback(
            modelPath: modelPath,
            preferGPU: preferGPU,
            cacheDir: cacheDir,
            flags: flags,
            samplerConfig: samplerConfig,
            systemMessage: systemMessage,
            tools: nil
        )
    }

    /// Default multimodal sendMessageStream delegates to text-only.
    func sendMessageStream(
        _ text: String,
        imageData: Data?,
        audioData: Data?
    ) -> AsyncThrowingStream<String, Error> {
        // Default: ignore image/audio, just send text
        sendMessageStream(text)
    }
}

// MARK: - Concrete Implementation

/// Concrete implementation wrapping LiteRTLM Engine + Conversation with
/// os_signpost instrumentation and BenchmarkInfo capture.
final class InstrumentedEngine: InstrumentedEngineProtocol {

    // MARK: - Signpost Infrastructure

    private static let subsystem = "com.andrewvoirol.GemmaEdgeGallery.performance"

    private static let modelLoadLog = OSLog(subsystem: subsystem, category: "model-load")
    private static let inferenceLog = OSLog(subsystem: subsystem, category: "inference")
    private static let firstTokenLog = OSLog(subsystem: subsystem, category: "first-token")

    /// Console logger for runtime diagnostics (visible in Xcode debug console and Console.app).
    /// Complements os_signpost, which only appears in Instruments.
    private static let logger = Logger(subsystem: subsystem, category: "engine")

    // MARK: - State

    private var engine: Engine?
    private var conversation: Conversation?
    private(set) var lastBenchmarkInfo: BenchmarkInfo?
    private(set) var lastInferenceMetrics: InferenceMetrics?
    private(set) var lastBackendResult: BackendResult?
    private(set) var flagsState: ExperimentalFlagsState = ExperimentalFlagsState(
        enableBenchmark: true,
        enableSpeculativeDecoding: nil,
        enableConversationConstrainedDecoding: false,
        visualTokenBudget: nil
    )
    /// The sampler config used for the current conversation.
    private var activeSamplerConfig: SamplerConfig?
    /// The system message for the current conversation.
    private var activeSystemMessage: String?
    /// The tools used for the current conversation (function calling).
    private var activeTools: [Tool]?
    /// Tracks the active inference Task so resetConversation() can await its completion.
    /// This is critical because the Task captures a local strong reference to the Conversation,
    /// and the native session won't be deleted until that reference is released.
    private var activeInferenceTask: Task<Void, Never>?

    var isReady: Bool { conversation != nil }

    // MARK: - Initialization

    func initialize(
        modelPath: String,
        useGPU: Bool,
        cacheDir: String,
        flags: ExperimentalFlagsState,
        samplerConfig: SamplerConfig? = nil,
        systemMessage: String? = nil,
        tools: [Tool]? = nil
    ) async throws {
        // Tear down any existing engine first
        await shutdown()

        self.flagsState = flags
        self.activeSamplerConfig = samplerConfig
        self.activeSystemMessage = systemMessage
        self.activeTools = tools

        let modelFilename = (modelPath as NSString).lastPathComponent
        Self.logger.info("⏳ Engine init: \(modelFilename, privacy: .public) backend=\(useGPU ? "GPU" : "CPU", privacy: .public) tools=\(tools?.count ?? 0) sampler=\(samplerConfig != nil ? "custom" : "default", privacy: .public)")

        // Configure experimental flags — MUST opt in first
        ExperimentalFlags.optIntoExperimentalAPIs()
        flags.applyToGlobalFlags()

        // Begin model load signpost
        let signpostID = OSSignpostID(log: Self.modelLoadLog)
        os_signpost(.begin, log: Self.modelLoadLog, name: "ModelLoad", signpostID: signpostID,
                    "Loading model from %{public}s with GPU=%{public}d",
                    (modelPath as NSString).lastPathComponent, useGPU ? 1 : 0)

        do {
            let config = try EngineConfig(
                modelPath: modelPath,
                backend: useGPU ? .gpu : .cpu(),
                cacheDir: cacheDir
            )

            let newEngine = Engine(engineConfig: config)
            try await newEngine.initialize()

            self.engine = newEngine

            // Create conversation with optional sampler config, system message, and tools
            let sysMsg: Message? = systemMessage.flatMap { text in
                text.isEmpty ? nil : Message(text, role: .system)
            }
            let convConfig = ConversationConfig(
                systemMessage: sysMsg,
                tools: tools ?? [],
                samplerConfig: samplerConfig
            )
            self.conversation = try await newEngine.createConversation(with: convConfig)

            Self.logger.info("✅ Engine ready: \(modelFilename, privacy: .public) backend=\(useGPU ? "GPU" : "CPU", privacy: .public)")
            os_signpost(.end, log: Self.modelLoadLog, name: "ModelLoad", signpostID: signpostID,
                        "Model loaded successfully")
        } catch {
            Self.logger.error("❌ Engine init FAILED: \(error.localizedDescription, privacy: .public)")
            os_signpost(.end, log: Self.modelLoadLog, name: "ModelLoad", signpostID: signpostID,
                        "Model load FAILED: %{public}s", error.localizedDescription)
            throw error
        }
    }

    // MARK: - Inference

    func sendMessageStream(_ text: String) -> AsyncThrowingStream<String, Error> {
        guard let conversation = conversation else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: InstrumentedEngineError.notInitialized)
            }
        }

        let stream: AsyncThrowingStream<String, Error>
        var continuation: AsyncThrowingStream<String, Error>.Continuation!
        stream = AsyncThrowingStream { continuation = $0 }

        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                try? self?.conversation?.cancel()
                self?.activeInferenceTask?.cancel()
            }
        }

        // Store the Task so resetConversation() can await its completion.
        // The Task captures `conversation` (the local binding), which prevents
        // Conversation.deinit from running until the Task body returns.
        //
        // IMPORTANT: This Task intentionally does NOT use @MainActor. The SDK's
        // sendMessageStream() loop (including any internal tool-calling iterations)
        // runs on a background cooperative thread pool, keeping the UI responsive
        // Wait, prioritizing inference at .userInitiated prevents iOS from starvation 
        // down to background QoS, which drops performance to zero.
        let task = Task(priority: .userInitiated) { [conversation, weak self] in
            Self.logger.info("🚀 Inference start: prompt=\(text.prefix(80), privacy: .public)...")
            let signpostID = OSSignpostID(log: Self.inferenceLog)
            os_signpost(.begin, log: Self.inferenceLog, name: "Inference", signpostID: signpostID,
                        "Starting inference for prompt length %{public}d", text.count)

            // Capture device metrics at inference start
            let startSnapshot = DeviceMetrics.captureSnapshot()
            var tokenTimestamps: [CFAbsoluteTime] = []
            let inferenceStartTime = CFAbsoluteTimeGetCurrent()
            var isFirstToken = true

            do {
                for try await chunk in conversation.sendMessageStream(Message(text)) {
                    if Task.isCancelled {
                        break
                    }
                    if let firstContent = chunk.contents.first {
                        switch firstContent {
                        case .text(let responseText):
                            // Record timestamp for per-token latency
                            tokenTimestamps.append(CFAbsoluteTimeGetCurrent())

                            if isFirstToken {
                                Self.logger.info("⚡ First token received")
                                os_signpost(.event, log: Self.firstTokenLog, name: "FirstToken",
                                            "First token received")
                                isFirstToken = false
                            }
                            continuation.yield(responseText)
                        default:
                            break
                        }
                    }
                }

                if Task.isCancelled {
                    os_signpost(.end, log: Self.inferenceLog, name: "Inference", signpostID: signpostID,
                                "Inference cancelled early")
                    continuation.finish()
                    return
                }

                // Capture device metrics at inference end
                let endSnapshot = DeviceMetrics.captureSnapshot()

                // Calculate per-token latency intervals
                var tokenLatenciesMs: [Double] = []
                if !tokenTimestamps.isEmpty {
                    // First token latency: time from inference start to first token
                    tokenLatenciesMs.append((tokenTimestamps[0] - inferenceStartTime) * 1000.0)
                    // Subsequent tokens: inter-token intervals
                    for i in 1..<tokenTimestamps.count {
                        tokenLatenciesMs.append((tokenTimestamps[i] - tokenTimestamps[i - 1]) * 1000.0)
                    }
                }

                // Build metrics and capture benchmark — hop to MainActor for state updates only
                let metrics = InferenceMetrics(
                    startSnapshot: startSnapshot,
                    endSnapshot: endSnapshot,
                    tokenLatenciesMs: tokenLatenciesMs,
                    totalTokenCount: tokenTimestamps.count
                )
                let benchmarkEnabled = self?.flagsState.enableBenchmark ?? false
                let benchmarkInfo: BenchmarkInfo? = benchmarkEnabled
                    ? (try? conversation.getBenchmarkInfo())
                    : nil

                await MainActor.run { [weak self] in
                    self?.lastInferenceMetrics = metrics
                    self?.lastBenchmarkInfo = benchmarkInfo
                }

                Self.logger.info("✅ Inference complete: \(tokenTimestamps.count) tokens")
                os_signpost(.end, log: Self.inferenceLog, name: "Inference", signpostID: signpostID,
                            "Inference completed")
                continuation.finish()
            } catch {
                // Still capture metrics on failure for debugging
                let endSnapshot = DeviceMetrics.captureSnapshot()
                let failureMetrics = InferenceMetrics(
                    startSnapshot: startSnapshot,
                    endSnapshot: endSnapshot,
                    tokenLatenciesMs: [],
                    totalTokenCount: 0
                )

                await MainActor.run { [weak self] in
                    self?.lastInferenceMetrics = failureMetrics
                }

                Self.logger.error("❌ Inference FAILED: \(error.localizedDescription, privacy: .public)")
                os_signpost(.end, log: Self.inferenceLog, name: "Inference", signpostID: signpostID,
                            "Inference FAILED: %{public}s", error.localizedDescription)
                continuation.finish(throwing: error)
            }
        }
        self.activeInferenceTask = task

        return stream
    }

    /// Multimodal inference: send text with optional image and/or audio data.
    /// Uses the LiteRT-LM SDK's Content.imageData() and Content.audioData() APIs.
    func sendMessageStream(
        _ text: String,
        imageData: Data?,
        audioData: Data?
    ) -> AsyncThrowingStream<String, Error> {
        // If no multimodal data, delegate to text-only path
        guard imageData != nil || audioData != nil else {
            return sendMessageStream(text)
        }

        guard let conversation = conversation else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: InstrumentedEngineError.notInitialized)
            }
        }

        let stream: AsyncThrowingStream<String, Error>
        var continuation: AsyncThrowingStream<String, Error>.Continuation!
        stream = AsyncThrowingStream { continuation = $0 }

        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                try? self?.conversation?.cancel()
                self?.activeInferenceTask?.cancel()
            }
        }

        let task = Task(priority: .userInitiated) { [conversation, weak self] in
            let signpostID = OSSignpostID(log: Self.inferenceLog)
            let modalityLabel = [
                imageData != nil ? "image" : nil,
                audioData != nil ? "audio" : nil
            ].compactMap { $0 }.joined(separator: "+")
            os_signpost(.begin, log: Self.inferenceLog, name: "MultimodalInference", signpostID: signpostID,
                        "Starting multimodal inference (text+%{public}s) prompt length %{public}d",
                        modalityLabel, text.count)

            let startSnapshot = DeviceMetrics.captureSnapshot()
            var tokenTimestamps: [CFAbsoluteTime] = []
            let inferenceStartTime = CFAbsoluteTimeGetCurrent()
            var isFirstToken = true

            do {
                // Build multimodal content parts
                var contents: [Content] = [.text(text)]
                if let imgData = imageData {
                    contents.append(.imageData(imgData))
                }
                if let audData = audioData {
                    contents.append(.audioData(audData))
                }
                let message = Message(contents: contents)

                for try await chunk in conversation.sendMessageStream(message) {
                    if Task.isCancelled { break }
                    if let firstContent = chunk.contents.first {
                        switch firstContent {
                        case .text(let responseText):
                            tokenTimestamps.append(CFAbsoluteTimeGetCurrent())
                            if isFirstToken {
                                os_signpost(.event, log: Self.firstTokenLog, name: "FirstToken",
                                            "First multimodal token received")
                                isFirstToken = false
                            }
                            continuation.yield(responseText)
                        default:
                            break
                        }
                    }
                }

                if Task.isCancelled {
                    os_signpost(.end, log: Self.inferenceLog, name: "MultimodalInference", signpostID: signpostID,
                                "Multimodal inference cancelled early")
                    continuation.finish()
                    return
                }

                let endSnapshot = DeviceMetrics.captureSnapshot()
                var tokenLatenciesMs: [Double] = []
                if !tokenTimestamps.isEmpty {
                    tokenLatenciesMs.append((tokenTimestamps[0] - inferenceStartTime) * 1000.0)
                    for i in 1..<tokenTimestamps.count {
                        tokenLatenciesMs.append((tokenTimestamps[i] - tokenTimestamps[i - 1]) * 1000.0)
                    }
                }

                // Build metrics and capture benchmark — hop to MainActor for state updates only
                let metrics = InferenceMetrics(
                    startSnapshot: startSnapshot,
                    endSnapshot: endSnapshot,
                    tokenLatenciesMs: tokenLatenciesMs,
                    totalTokenCount: tokenTimestamps.count
                )
                let benchmarkEnabled = self?.flagsState.enableBenchmark ?? false
                let benchmarkInfo: BenchmarkInfo? = benchmarkEnabled
                    ? (try? conversation.getBenchmarkInfo())
                    : nil

                await MainActor.run { [weak self] in
                    self?.lastInferenceMetrics = metrics
                    self?.lastBenchmarkInfo = benchmarkInfo
                }

                os_signpost(.end, log: Self.inferenceLog, name: "MultimodalInference", signpostID: signpostID,
                            "Multimodal inference completed (%{public}d tokens)", tokenTimestamps.count)
                continuation.finish()
            } catch {
                let endSnapshot = DeviceMetrics.captureSnapshot()
                let failureMetrics = InferenceMetrics(
                    startSnapshot: startSnapshot,
                    endSnapshot: endSnapshot,
                    tokenLatenciesMs: [],
                    totalTokenCount: 0
                )

                await MainActor.run { [weak self] in
                    self?.lastInferenceMetrics = failureMetrics
                }

                os_signpost(.end, log: Self.inferenceLog, name: "MultimodalInference", signpostID: signpostID,
                            "Multimodal inference FAILED: %{public}s", error.localizedDescription)
                continuation.finish(throwing: error)
            }
        }
        self.activeInferenceTask = task

        return stream
    }

    // MARK: - Conversation Reset

    func resetConversation() async throws {
        guard let engine = engine else {
            throw InstrumentedEngineError.notInitialized
        }

        // CRITICAL: The LiteRT-LM engine only supports ONE session at a time.
        // We must fully delete the existing conversation (native session) BEFORE
        // creating a new one, or the engine returns:
        //   "FAILED_PRECONDITION: A session already exists."
        //
        // Root cause: sendMessageStream() captures a local strong reference to the
        // Conversation in its Task closure. Even after `self.conversation = nil`,
        // the Task holds the reference, preventing Conversation.deinit from running.
        // We MUST await the Task's completion to release that reference.

        // Step 1: Wait for any active inference Task to complete.
        // This releases the Task's captured Conversation reference.
        if let task = activeInferenceTask {
            await task.value
            activeInferenceTask = nil
        }

        // Step 2: Nil the conversation to trigger Conversation.deinit.
        // At this point, `self.conversation` is the only remaining strong reference.
        // withExtendedLifetime ensures the engine stays alive during deinit.
        autoreleasepool {
            withExtendedLifetime(engine) {
                conversation = nil
            }
        }
        lastBenchmarkInfo = nil
        lastInferenceMetrics = nil

        // Step 3: Create a fresh conversation with the same sampler config, system message, and tools.
        let sysMsg: Message? = activeSystemMessage.flatMap { text in
            text.isEmpty ? nil : Message(text, role: .system)
        }
        let convConfig = ConversationConfig(
            systemMessage: sysMsg,
            tools: activeTools ?? [],
            samplerConfig: activeSamplerConfig
        )
        self.conversation = try await engine.createConversation(with: convConfig)
    }

    // MARK: - Warmup

    func warmup() async throws {
        guard conversation != nil else {
            throw InstrumentedEngineError.notInitialized
        }

        // Send a minimal prompt to prime the benchmark subsystem.
        // The SDK's BenchmarkInfo is nil on the first conversation turn;
        // this throwaway inference forces the internal counters to initialize.
        for try await _ in sendMessageStream("Hi") {
            // Discard all response tokens
        }
    }

    // MARK: - Cancellation

    func cancelGeneration() {
        activeInferenceTask?.cancel()
        // Proactively interrupt the LiteRTLM C++ generation loop.
        // If we only cancel the Swift Task, the C++ execution might 
        // block synchronously and ignore the Task.isCancelled flag.
        try? conversation?.cancel()
    }

    // MARK: - Shutdown

    func shutdown() async {
        // Cancel any active inference task to release its captured Conversation reference.
        activeInferenceTask?.cancel()
        if let task = activeInferenceTask {
            _ = await task.result
            activeInferenceTask = nil
        }

        // IMPORTANT: The native conversation handle depends on the engine being alive.
        // We must ensure Conversation.deinit (which calls litert_lm_conversation_delete)
        // runs BEFORE Engine.deinit (which calls litert_lm_engine_delete).
        // withExtendedLifetime is a compiler barrier that guarantees the engine
        // won't be deallocated while the conversation is being cleaned up.
        if let engineRef = engine {
            withExtendedLifetime(engineRef) {
                conversation = nil
            }
        } else {
            conversation = nil
        }
        engine = nil
        lastBenchmarkInfo = nil
        lastInferenceMetrics = nil
        lastBackendResult = nil
        activeSamplerConfig = nil
        activeSystemMessage = nil
        activeTools = nil
    }

    // MARK: - Smart Backend Initialization with Fallback

    func initializeWithFallback(
        modelPath: String,
        preferGPU: Bool,
        cacheDir: String,
        flags: ExperimentalFlagsState,
        samplerConfig: SamplerConfig? = nil,
        systemMessage: String? = nil,
        tools: [Tool]? = nil
    ) async throws -> BackendResult {
        // Check known model registry first for pre-verified guidance
        let recommendation = ModelRegistry.recommendedBackend(for: modelPath)

        let shouldTryGPU: Bool
        switch recommendation {
        case .gpu:
            shouldTryGPU = true
        case .cpu:
            shouldTryGPU = false
        case .probeRequired:
            shouldTryGPU = preferGPU
        }

        // Attempt primary backend
        do {
            try await initialize(
                modelPath: modelPath,
                useGPU: shouldTryGPU,
                cacheDir: cacheDir,
                flags: flags,
                samplerConfig: samplerConfig,
                systemMessage: systemMessage,
                tools: tools
            )

            let result = BackendResult(
                activeBackend: shouldTryGPU ? .gpu : .cpu,
                didFallback: shouldTryGPU != preferGPU,
                fallbackReason: shouldTryGPU != preferGPU
                    ? "Known model metadata indicates \(shouldTryGPU ? "GPU" : "CPU") is optimal for this platform."
                    : nil,
                detectedCapability: determineCapability(
                    requestedGPU: shouldTryGPU,
                    gpuSucceeded: shouldTryGPU,
                    cpuSucceeded: !shouldTryGPU
                )
            )
            self.lastBackendResult = result
            return result

        } catch {
            let primaryError = error.localizedDescription

            // Attempt fallback to the other backend
            let fallbackUseGPU = !shouldTryGPU
            do {
                try await initialize(
                    modelPath: modelPath,
                    useGPU: fallbackUseGPU,
                    cacheDir: cacheDir,
                    flags: flags,
                    samplerConfig: samplerConfig,
                    systemMessage: systemMessage,
                    tools: tools
                )

                let result = BackendResult(
                    activeBackend: fallbackUseGPU ? .gpu : .cpu,
                    didFallback: true,
                    fallbackReason: "\(shouldTryGPU ? "GPU" : "CPU") failed: \(primaryError). Fell back to \(fallbackUseGPU ? "GPU" : "CPU").",
                    detectedCapability: determineCapability(
                        requestedGPU: shouldTryGPU,
                        gpuSucceeded: fallbackUseGPU,
                        cpuSucceeded: !fallbackUseGPU
                    )
                )
                self.lastBackendResult = result
                return result

            } catch {
                // Both backends failed
                self.lastBackendResult = nil
                throw InstrumentedEngineError.bothBackendsFailed(
                    primaryBackend: shouldTryGPU ? "GPU" : "CPU",
                    primaryError: primaryError,
                    fallbackBackend: fallbackUseGPU ? "GPU" : "CPU",
                    fallbackError: error.localizedDescription
                )
            }
        }
    }

    /// Determine backend capability from probe results.
    private func determineCapability(
        requestedGPU: Bool,
        gpuSucceeded: Bool,
        cpuSucceeded: Bool
    ) -> BackendCapability {
        switch (gpuSucceeded, cpuSucceeded) {
        case (true, true):   return .gpuAndCpu
        case (true, false):  return .gpuOnly
        case (false, true):  return .cpuOnly
        case (false, false): return .unknown
        }
    }
}

// MARK: - Errors

enum InstrumentedEngineError: LocalizedError {
    case notInitialized
    case bothBackendsFailed(
        primaryBackend: String,
        primaryError: String,
        fallbackBackend: String,
        fallbackError: String
    )

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Engine is not initialized. Load a model first."
        case let .bothBackendsFailed(primary, primaryErr, fallback, fallbackErr):
            return "Both backends failed. \(primary): \(primaryErr). \(fallback): \(fallbackErr)"
        }
    }
}
