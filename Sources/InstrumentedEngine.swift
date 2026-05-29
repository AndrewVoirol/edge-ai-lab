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

    /// Send a message and receive a streamed response.
    /// - Parameter text: The user's prompt text.
    /// - Returns: An AsyncThrowingStream of response text chunks.
    func sendMessageStream(_ text: String) -> AsyncThrowingStream<String, Error>

    /// Tear down the engine and free resources.
    func shutdown()
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
    }
}

// MARK: - Errors

enum InstrumentedEngineError: LocalizedError {
    case notInitialized

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Engine is not initialized. Load a model first."
        }
    }
}
