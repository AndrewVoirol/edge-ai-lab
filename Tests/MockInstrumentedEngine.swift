import Foundation
import LiteRTLM

#if os(iOS)
@testable import GemmaEdgeGallery_iOS
#elseif os(macOS)
@testable import GemmaEdgeGallery_macOS
#endif

/// Mock implementation of InstrumentedEngineProtocol for unit tests.
/// Returns configurable BenchmarkInfo values without requiring a real model file.
final class MockInstrumentedEngine: InstrumentedEngineProtocol {

    // MARK: - Configurable Behavior

    /// The BenchmarkInfo to return after inference. Set this before calling sendMessageStream.
    var mockBenchmarkInfo: BenchmarkInfo?

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

    // MARK: - Protocol Conformance

    private(set) var isReady = false
    private(set) var lastBenchmarkInfo: BenchmarkInfo?
    private(set) var lastBackendResult: BackendResult?
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
        samplerConfig: SamplerConfig?
    ) async throws {
        initializeCallCount += 1
        lastModelPath = modelPath
        lastFlags = flags
        lastSamplerConfig = samplerConfig
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
        samplerConfig: SamplerConfig?
    ) async throws -> BackendResult {
        // Delegate to regular initialize
        try await initialize(
            modelPath: modelPath,
            useGPU: preferGPU,
            cacheDir: cacheDir,
            flags: flags,
            samplerConfig: samplerConfig
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

    func sendMessageStream(_ text: String) -> AsyncThrowingStream<String, Error> {
        sendMessageCallCount += 1
        lastPromptText = text

        let chunks = mockResponseChunks
        let delay = chunkDelay
        let error = inferenceError
        let benchmarkInfo = mockBenchmarkInfo

        return AsyncThrowingStream { continuation in
            Task {
                if let error = error {
                    continuation.finish(throwing: error)
                    return
                }

                for chunk in chunks {
                    if delay > 0 {
                        try? await Task.sleep(for: .seconds(delay))
                    }
                    continuation.yield(chunk)
                }

                // Simulate benchmark capture
                self.lastBenchmarkInfo = benchmarkInfo

                continuation.finish()
            }
        }
    }

    func shutdown() {
        shutdownCallCount += 1
        isReady = false
        lastBenchmarkInfo = nil
        lastBackendResult = nil
    }
}
