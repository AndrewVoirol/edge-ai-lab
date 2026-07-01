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


#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Integration tests for the smart backend fallback system using MockInferenceEngine.
///
/// These tests validate the fallback logic path:
///   loadModel(config:) → BackendResult (via lastBackendResult)
///
/// Covers GPU success, GPU→CPU fallback, both-fail error propagation,
/// metrics population, and the static factory convenience methods.
final class EngineFallbackTests: XCTestCase {

    // MARK: - Shared Setup

    private let defaultFlags = RuntimeFlags(
        enableBenchmark: true
    )

    // MARK: - GPU Succeeds (No Fallback)

    /// When no errors are set and GPU is preferred, init succeeds on GPU without fallback.
    func testGPUSucceedsNoFallback() async throws {
        let engine = MockInferenceEngine()

        try await engine.loadModel(config: ModelLoadConfig(
            modelPath: "/fake/model.litertlm",
            preferGPU: true,
            cacheDir: NSTemporaryDirectory(),
            runtimeFlags: defaultFlags
        ))

        XCTAssertTrue(engine.isLoaded, "Engine should be loaded after successful init")
        let result = engine.lastBackendResult
        XCTAssertNotNil(result, "lastBackendResult should be populated after load")
        XCTAssertEqual(result?.activeBackend, .gpu,
            "Active backend should be GPU when preferGPU is true and no errors")
        XCTAssertFalse(result?.didFallback ?? true,
            "Should not trigger fallback when GPU succeeds")
        XCTAssertNil(result?.fallbackReason,
            "No fallback reason expected when GPU succeeds")
    }

    // MARK: - GPU Fails → CPU Succeeds

    /// When `mockBackendResult` provides a CPU fallback result, the engine reports successful fallback.
    func testGPUFailsCPUSucceeds() async throws {
        let engine = MockInferenceEngine()
        // Configure the mock to return a CPU fallback result
        engine.mockBackendResult = BackendResult(
            activeBackend: .cpu,
            didFallback: true,
            fallbackReason: "GPU initialization failed: Metal not available",
            detectedCapability: .cpuOnly
        )

        try await engine.loadModel(config: ModelLoadConfig(
            modelPath: "/fake/model.litertlm",
            preferGPU: true,
            cacheDir: NSTemporaryDirectory(),
            runtimeFlags: defaultFlags
        ))

        XCTAssertTrue(engine.isLoaded, "Engine should be loaded after CPU fallback")
        let result = engine.lastBackendResult
        XCTAssertEqual(result?.activeBackend, .cpu,
            "Active backend should be CPU after fallback")
        XCTAssertTrue(result?.didFallback ?? false,
            "didFallback should be true when GPU fails and CPU succeeds")
        XCTAssertNotNil(result?.fallbackReason,
            "Fallback reason should explain why GPU was abandoned")
    }

    // MARK: - Both Backends Fail

    /// Setting `loadError` simulates both GPU and CPU failing, propagating the error.
    func testBothBackendsFail() async {
        let engine = MockInferenceEngine()
        engine.loadError = NSError(
            domain: "EngineFallbackTests",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Both GPU and CPU failed"]
        )

        do {
            try await engine.loadModel(config: ModelLoadConfig(
                modelPath: "/fake/model.litertlm",
                preferGPU: true,
                cacheDir: NSTemporaryDirectory(),
                runtimeFlags: defaultFlags
            ))
            XCTFail("Expected loadModel to throw when both backends fail")
        } catch let error as NSError {
            XCTAssertEqual(error.domain, "EngineFallbackTests",
                "Should propagate the exact error from fallback failure")
            XCTAssertTrue(error.localizedDescription.contains("Both GPU and CPU failed"),
                "Error message should describe the dual failure")
        }

        XCTAssertFalse(engine.isLoaded,
            "Engine should NOT be loaded when both backends fail")
    }

    // MARK: - Fallback Metrics

    /// After a successful `loadModel()`, `lastBackendResult` is populated.
    func testFallbackMetrics() async throws {
        let engine = MockInferenceEngine()
        engine.mockBackendResult = BackendResult(
            activeBackend: .gpu,
            didFallback: false,
            fallbackReason: nil,
            detectedCapability: .gpuAndCpu
        )

        XCTAssertNil(engine.lastBackendResult,
            "lastBackendResult should be nil before initialization")

        try await engine.loadModel(config: ModelLoadConfig(
            modelPath: "/fake/model.litertlm",
            preferGPU: true,
            cacheDir: NSTemporaryDirectory(),
            runtimeFlags: defaultFlags
        ))

        XCTAssertNotNil(engine.lastBackendResult,
            "lastBackendResult should be populated after loadModel")
        XCTAssertEqual(engine.lastBackendResult?.activeBackend, .gpu,
            "lastBackendResult should match configured mock result")
        XCTAssertEqual(engine.lastBackendResult?.detectedCapability, .gpuAndCpu,
            "Detected capability should match what was configured")
    }

    // MARK: - Factory: Happy Path

    /// `MockInferenceEngine.happyPath()` creates an engine that works out of the box.
    func testFactoryHappyPath() async throws {
        let engine = MockInferenceEngine.happyPath()

        // Load
        try await engine.loadModel(config: ModelLoadConfig(
            modelPath: "/fake/model.litertlm",
            preferGPU: false,
            cacheDir: NSTemporaryDirectory(),
            runtimeFlags: defaultFlags
        ))
        XCTAssertTrue(engine.isLoaded, "Happy path engine should be loaded after init")

        // Stream response
        var response = ""
        for try await event in engine.generateStream(prompt: "Hello", config: .default) {
            if case .text(let text) = event {
                response += text
            }
        }

        XCTAssertEqual(response, "Hello, world!",
            "Happy path should produce 'Hello, world!'. Got: '\(response)'")
    }

    // MARK: - Factory: Failing Engine

    /// `MockInferenceEngine.failingEngine()` creates an engine that fails on init.
    func testFactoryFailingEngine() async {
        let engine = MockInferenceEngine.failingEngine()

        do {
            try await engine.loadModel(config: ModelLoadConfig(
                modelPath: "/fake/model.litertlm",
                preferGPU: false,
                cacheDir: NSTemporaryDirectory(),
                runtimeFlags: defaultFlags
            ))
            XCTFail("Failing engine should throw on loadModel()")
        } catch {
            XCTAssertFalse(engine.isLoaded,
                "Failing engine should NOT be loaded after init failure")
            XCTAssertTrue(error.localizedDescription.contains("initialization failure"),
                "Error should describe init failure. Got: \(error.localizedDescription)")
        }
    }

    // MARK: - Factory: Intermittent Failure

    /// `MockInferenceEngine.intermittentFailure()` errors at chunk index 3.
    func testFactoryIntermittentFailure() async throws {
        let engine = MockInferenceEngine.intermittentFailure()

        // Load succeeds — the failure is mid-stream
        try await engine.loadModel(config: ModelLoadConfig(
            modelPath: "/fake/model.litertlm",
            preferGPU: false,
            cacheDir: NSTemporaryDirectory(),
            runtimeFlags: defaultFlags
        ))
        XCTAssertTrue(engine.isLoaded, "Intermittent engine should load successfully")

        // Stream should fail at chunk 3
        var receivedChunks: [String] = []
        let stream = engine.generateStream(prompt: "test", config: .default)

        do {
            for try await event in stream {
                if case .text(let chunk) = event {
                    receivedChunks.append(chunk)
                }
            }
            XCTFail("Expected mid-stream error at chunk index 3")
        } catch {
            XCTAssertEqual(receivedChunks.count, 3,
                "Should receive exactly 3 chunks before error. Got: \(receivedChunks.count)")
        }
    }
}
