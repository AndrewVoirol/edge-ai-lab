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

import XCTest
import LiteRTLM

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Integration performance tests requiring a real model file.
/// These tests are in the PerformanceTests.xctestplan and should only be run
/// on provisioned machines with a model file available.
///
/// Model discovery (Option C):
///   1. `PERFORMANCE_TEST_MODEL_PATH` environment variable (highest priority, CI/automation)
///   2. Project `models/` directory (local dev, macOS tests)
///   3. App Documents directory (simulator/device with provisioned model)
///
/// Backend selection:
///   - Prefers GPU on macOS and physical iOS devices
///   - Falls back to CPU on iOS Simulator (Metal shader translation is not
///     bit-identical to device GPU — see Apple docs:
///     https://developer.apple.com/documentation/metal/developing_metal_apps_that_run_in_simulator)
final class PerformanceTests: XCTestCase {

    // MARK: - Model Discovery (Option C: env var + fallback)

    /// Discovers the first available .litertlm model file.
    /// Priority: env var → project models/ dir → app Documents dir.
    private var modelPath: String? {
        // 1. Explicit env var (CI/automation) — highest priority
        if let envPath = ProcessInfo.processInfo.environment["PERFORMANCE_TEST_MODEL_PATH"],
           FileManager.default.fileExists(atPath: envPath) {
            return envPath
        }

        // 2. Convention: models/ directory relative to project root (macOS tests)
        let projectModels = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/Benchmarking/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
            .appendingPathComponent("models")
        if let model = findFirstModel(in: projectModels) {
            return model
        }

        // 3. App's Documents directory (simulator/device when model is provisioned)
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           let model = findFirstModel(in: docs) {
            return model
        }

        return nil
    }

    /// Finds the best .litertlm model for the current platform.
    ///
    /// Verified compatibility matrix (from platform support testing):
    /// - macOS + GPU:      standard ✅, web ✅
    /// - iOS device + GPU: standard ❌, web ✅
    /// - iOS sim + CPU:    standard ✅, web ❌
    ///
    /// So: iOS device prefers web model (GPU), everything else prefers standard.
    private func findFirstModel(in directory: URL) -> String? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return nil }

        let models = files.filter { $0.pathExtension == "litertlm" }

        #if os(iOS) && !targetEnvironment(simulator)
        // Physical iOS device: prefer web model (GPU-compatible on A-series)
        if let web = models.first(where: { $0.lastPathComponent.contains("-web") }) {
            return web.path
        }
        // Fall back to standard model (will use CPU)
        return models.first?.path
        #else
        // macOS and iOS Simulator: prefer standard model (CPU+GPU support)
        if let standard = models.first(where: { !$0.lastPathComponent.contains("-web") }) {
            return standard.path
        }
        return models.first?.path
        #endif
    }

    // MARK: - Backend Selection

    /// Determines the appropriate GPU/CPU backend for the current platform and model.
    ///
    /// Verified behavior:
    /// - macOS:           GPU (Metal) ✅ — both models work
    /// - iOS device:      GPU (Metal) ✅ — only with web model (selected by findFirstModel)
    /// - iOS Simulator:   CPU (XNNPACK) ✅ — Metal shader translation corrupts inference
    private var shouldUseGPU: Bool {
        #if targetEnvironment(simulator)
        return false  // Metal not reliable on simulator; use CPU (XNNPACK)
        #else
        return true   // Native GPU on macOS and physical iOS devices
        #endif
    }

    // MARK: - Cache Directory

    /// Creates a temporary cache directory for the engine's XNNPACK weight cache.
    /// The directory must exist before engine initialization.
    private func createCacheDir(prefix: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    override func setUpWithError() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("E2E test requires real Metal GPU — skipping on iOS Simulator")
        #endif
        try super.setUpWithError()
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
            throw XCTSkip("No model file available — skipping model-dependent test")
        }

        let useGPU = shouldUseGPU
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
                let cacheDir = try self.createCacheDir(prefix: "perf_test_cache")

                let flags = ExperimentalFlagsState(
                    enableBenchmark: true,
                    enableSpeculativeDecoding: nil,
                    enableConversationConstrainedDecoding: false,
                    visualTokenBudget: nil
                )

                do {
                    try await engine.initialize(
                        modelPath: modelPath,
                        useGPU: useGPU,
                        cacheDir: cacheDir.path,
                        flags: flags
                    )
                } catch {
                    XCTFail("Engine initialization failed: \(error)")
                }
                await engine.shutdown()
                try? FileManager.default.removeItem(at: cacheDir)
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 120)
        }
    }

    // MARK: - Inference Performance

    func testInferencePerformance() throws {
        guard let modelPath = modelPath else {
            throw XCTSkip("No model file available — skipping model-dependent test")
        }

        let useGPU = shouldUseGPU
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
        var cacheDir: URL?

        Task { @MainActor in
            cacheDir = try self.createCacheDir(prefix: "perf_test_inference")
            let flags = ExperimentalFlagsState(
                enableBenchmark: true,
                enableSpeculativeDecoding: nil,
                enableConversationConstrainedDecoding: false,
                visualTokenBudget: nil
            )
            try await engine.initialize(
                modelPath: modelPath,
                useGPU: useGPU,
                cacheDir: cacheDir!.path,
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

        let shutdownExpectation = expectation(description: "Engine shutdown")
        Task { @MainActor in
            await engine.shutdown()
            shutdownExpectation.fulfill()
        }
        wait(for: [shutdownExpectation], timeout: 30)
        if let cacheDir = cacheDir {
            try? FileManager.default.removeItem(at: cacheDir)
        }
    }
}
