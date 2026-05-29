import XCTest
import LiteRTLM

#if os(iOS)
@testable import GemmaEdgeGallery_iOS
#elseif os(macOS)
@testable import GemmaEdgeGallery_macOS
#endif

/// Integration performance tests requiring a real model file.
/// These tests are in the PerformanceTests.xctestplan and should only be run
/// on provisioned machines with a model file available.
///
/// NOTE: Set the `PERFORMANCE_TEST_MODEL_PATH` environment variable to the
/// absolute path of your .litertlm model file before running these tests.
final class PerformanceTests: XCTestCase {

    /// Path to the model file. Set via environment variable.
    private var modelPath: String? {
        ProcessInfo.processInfo.environment["PERFORMANCE_TEST_MODEL_PATH"]
    }

    override func setUp() {
        super.setUp()
        guard modelPath != nil else {
            // Skip performance tests when no model is available
            // This prevents CI failures when model isn't provisioned
            return
        }
    }

    // MARK: - Model Load Performance

    func testModelLoadPerformance() throws {
        guard let modelPath = modelPath else {
            throw XCTSkip("PERFORMANCE_TEST_MODEL_PATH not set — skipping model-dependent test")
        }

        let metrics: [XCTMetric] = [
            XCTMemoryMetric(),
            XCTCPUMetric(),
            XCTClockMetric()
        ]

        let options = XCTMeasureOptions()
        options.iterationCount = 3 // Model load is expensive, limit iterations

        measure(metrics: metrics, options: options) {
            let engine = InstrumentedEngine()
            let expectation = self.expectation(description: "Engine initialized")

            Task { @MainActor in
                let fileManager = FileManager.default
                let cacheDir = fileManager.temporaryDirectory
                    .appendingPathComponent("perf_test_cache_\(UUID().uuidString)").path

                let flags = ExperimentalFlagsState(
                    enableBenchmark: true,
                    enableSpeculativeDecoding: nil,
                    enableConversationConstrainedDecoding: false,
                    visualTokenBudget: nil
                )

                do {
                    try await engine.initialize(
                        modelPath: modelPath,
                        useGPU: true,
                        cacheDir: cacheDir,
                        flags: flags
                    )
                } catch {
                    XCTFail("Engine initialization failed: \(error)")
                }
                engine.shutdown()
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 120)
        }
    }

    // MARK: - Inference Performance

    func testInferencePerformance() throws {
        guard let modelPath = modelPath else {
            throw XCTSkip("PERFORMANCE_TEST_MODEL_PATH not set — skipping model-dependent test")
        }

        let metrics: [XCTMetric] = [
            XCTMemoryMetric(),
            XCTCPUMetric(),
            XCTClockMetric()
        ]

        let options = XCTMeasureOptions()
        options.iterationCount = 3

        // Initialize engine once outside the measure block
        let engine = InstrumentedEngine()
        let initExpectation = expectation(description: "Engine initialized for inference test")

        Task { @MainActor in
            let cacheDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("perf_test_inference_\(UUID().uuidString)").path
            let flags = ExperimentalFlagsState(
                enableBenchmark: true,
                enableSpeculativeDecoding: nil,
                enableConversationConstrainedDecoding: false,
                visualTokenBudget: nil
            )
            try await engine.initialize(
                modelPath: modelPath,
                useGPU: true,
                cacheDir: cacheDir,
                flags: flags
            )
            initExpectation.fulfill()
        }
        wait(for: [initExpectation], timeout: 120)

        // Measure inference
        measure(metrics: metrics, options: options) {
            let inferExpectation = self.expectation(description: "Inference completed")

            Task { @MainActor in
                var response = ""
                for try await chunk in engine.sendMessageStream("Explain quantum computing in one sentence.") {
                    response += chunk
                }
                XCTAssertFalse(response.isEmpty, "Expected non-empty response")

                // Log benchmark info for metrics store
                if let info = engine.lastBenchmarkInfo {
                    let store = MetricsStore()
                    let entry = MetricsStore.createEntry(
                        from: info,
                        modelName: (modelPath as NSString).lastPathComponent,
                        flags: engine.flagsState
                    )
                    try? store.append(entry: entry)
                }
                inferExpectation.fulfill()
            }

            wait(for: [inferExpectation], timeout: 300)
        }

        engine.shutdown()
    }
}
