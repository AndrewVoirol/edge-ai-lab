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
    func initialize(
        modelPath: String,
        useGPU: Bool,
        cacheDir: String,
        flags: ExperimentalFlagsState
    ) async throws

    /// Initialize with smart fallback: try the preferred backend, fall back if it fails.
    /// - Parameters:
    ///   - modelPath: Filesystem path to the .litertlm model file.
    ///   - preferGPU: Whether GPU is the preferred backend.
    ///   - cacheDir: Cache directory path for the engine.
    ///   - flags: Experimental flags configuration to apply.
    /// - Returns: The result describing which backend was actually used.
    func initializeWithFallback(
        modelPath: String,
        preferGPU: Bool,
        cacheDir: String,
        flags: ExperimentalFlagsState
    ) async throws -> BackendResult

    /// Send a message and receive a streamed response.
    /// - Parameter text: The user's prompt text.
    /// - Returns: An AsyncThrowingStream of response text chunks.
    func sendMessageStream(_ text: String) -> AsyncThrowingStream<String, Error>

    /// Tear down the engine and free resources.
    func shutdown()
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

// MARK: - Concrete Implementation

/// Concrete implementation wrapping LiteRTLM Engine + Conversation with
/// os_signpost instrumentation and BenchmarkInfo capture.
final class InstrumentedEngine: InstrumentedEngineProtocol {

    // MARK: - Signpost Infrastructure

    private static let subsystem = "com.andrewvoirol.GemmaEdgeGallery.performance"

    private static let modelLoadLog = OSLog(subsystem: subsystem, category: "model-load")
    private static let inferenceLog = OSLog(subsystem: subsystem, category: "inference")
    private static let firstTokenLog = OSLog(subsystem: subsystem, category: "first-token")

    // MARK: - State

    private var engine: Engine?
    private var conversation: Conversation?
    private(set) var lastBenchmarkInfo: BenchmarkInfo?
    private(set) var lastBackendResult: BackendResult?
    private(set) var flagsState: ExperimentalFlagsState = ExperimentalFlagsState(
        enableBenchmark: true,
        enableSpeculativeDecoding: nil,
        enableConversationConstrainedDecoding: false,
        visualTokenBudget: nil
    )

    var isReady: Bool { conversation != nil }

    // MARK: - Initialization

    func initialize(
        modelPath: String,
        useGPU: Bool,
        cacheDir: String,
        flags: ExperimentalFlagsState
    ) async throws {
        // Tear down any existing engine first
        shutdown()

        self.flagsState = flags

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
            self.conversation = try await newEngine.createConversation()

            os_signpost(.end, log: Self.modelLoadLog, name: "ModelLoad", signpostID: signpostID,
                        "Model loaded successfully")
        } catch {
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

        return AsyncThrowingStream { continuation in
            Task { @MainActor in
                let signpostID = OSSignpostID(log: Self.inferenceLog)
                os_signpost(.begin, log: Self.inferenceLog, name: "Inference", signpostID: signpostID,
                            "Starting inference for prompt length %{public}d", text.count)

                var isFirstToken = true

                do {
                    for try await chunk in conversation.sendMessageStream(Message(text)) {
                        if let firstContent = chunk.contents.first {
                            switch firstContent {
                            case .text(let responseText):
                                if isFirstToken {
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

                    // Capture BenchmarkInfo after stream completes
                    if self.flagsState.enableBenchmark {
                        do {
                            self.lastBenchmarkInfo = try conversation.getBenchmarkInfo()
                        } catch {
                            // Gracefully degrade — benchmark data unavailable but inference succeeded
                            self.lastBenchmarkInfo = nil
                        }
                    }

                    os_signpost(.end, log: Self.inferenceLog, name: "Inference", signpostID: signpostID,
                                "Inference completed")
                    continuation.finish()
                } catch {
                    os_signpost(.end, log: Self.inferenceLog, name: "Inference", signpostID: signpostID,
                                "Inference FAILED: %{public}s", error.localizedDescription)
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Shutdown

    func shutdown() {
        conversation = nil
        engine = nil
        lastBenchmarkInfo = nil
        lastBackendResult = nil
    }

    // MARK: - Smart Backend Initialization with Fallback

    func initializeWithFallback(
        modelPath: String,
        preferGPU: Bool,
        cacheDir: String,
        flags: ExperimentalFlagsState
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
                flags: flags
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
                    flags: flags
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
