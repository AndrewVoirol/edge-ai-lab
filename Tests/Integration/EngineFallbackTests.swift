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

/// Integration tests for the smart backend fallback system using MockInstrumentedEngine.
///
/// These tests validate the fallback logic path:
///   initializeWithFallback(preferGPU:) → BackendResult
///
/// Covers GPU success, GPU→CPU fallback, both-fail error propagation,
/// metrics population, and the static factory convenience methods.
final class EngineFallbackTests: XCTestCase {

    // MARK: - Shared Setup

    private let defaultFlags = ExperimentalFlagsState(
        enableBenchmark: true,
        enableSpeculativeDecoding: nil,
        enableConversationConstrainedDecoding: false,
        visualTokenBudget: nil
    )

    // MARK: - GPU Succeeds (No Fallback)

    /// When no errors are set and GPU is preferred, init succeeds on GPU without fallback.
    func testGPUSucceedsNoFallback() async throws {
        let engine = MockInstrumentedEngine()

        let result = try await engine.initializeWithFallback(
            modelPath: "/fake/model.litertlm",
            preferGPU: true,
            cacheDir: NSTemporaryDirectory(),
            flags: defaultFlags,
            samplerConfig: nil,
            systemMessage: nil,
            tools: nil
        )

        XCTAssertTrue(engine.isReady, "Engine should be ready after successful init")
        XCTAssertEqual(result.activeBackend, .gpu,
            "Active backend should be GPU when preferGPU is true and no errors")
        XCTAssertFalse(result.didFallback,
            "Should not trigger fallback when GPU succeeds")
        XCTAssertNil(result.fallbackReason,
            "No fallback reason expected when GPU succeeds")
    }

    // MARK: - GPU Fails → CPU Succeeds

    /// When `initError` is set (simulating GPU failure) but `mockBackendResult` provides
    /// a CPU fallback result, the engine reports successful fallback.
    func testGPUFailsCPUSucceeds() async throws {
        let engine = MockInstrumentedEngine()
        // Simulate: GPU init would fail, but fallback catches it and retries on CPU
        // The mock doesn't actually retry — we configure it to return a CPU fallback result
        engine.mockBackendResult = BackendResult(
            activeBackend: .cpu,
            didFallback: true,
            fallbackReason: "GPU initialization failed: Metal not available",
            detectedCapability: .cpuOnly
        )

        let result = try await engine.initializeWithFallback(
            modelPath: "/fake/model.litertlm",
            preferGPU: true,
            cacheDir: NSTemporaryDirectory(),
            flags: defaultFlags,
            samplerConfig: nil,
            systemMessage: nil,
            tools: nil
        )

        XCTAssertTrue(engine.isReady, "Engine should be ready after CPU fallback")
        XCTAssertEqual(result.activeBackend, .cpu,
            "Active backend should be CPU after fallback")
        XCTAssertTrue(result.didFallback,
            "didFallback should be true when GPU fails and CPU succeeds")
        XCTAssertNotNil(result.fallbackReason,
            "Fallback reason should explain why GPU was abandoned")
    }

    // MARK: - Both Backends Fail

    /// Setting `fallbackError` simulates both GPU and CPU failing, propagating the error.
    func testBothBackendsFail() async {
        let engine = MockInstrumentedEngine()
        engine.fallbackError = NSError(
            domain: "EngineFallbackTests",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Both GPU and CPU failed"]
        )

        do {
            _ = try await engine.initializeWithFallback(
                modelPath: "/fake/model.litertlm",
                preferGPU: true,
                cacheDir: NSTemporaryDirectory(),
                flags: defaultFlags,
                samplerConfig: nil,
                systemMessage: nil,
                tools: nil
            )
            XCTFail("Expected initializeWithFallback to throw when both backends fail")
        } catch let error as NSError {
            XCTAssertEqual(error.domain, "EngineFallbackTests",
                "Should propagate the exact error from fallback failure")
            XCTAssertTrue(error.localizedDescription.contains("Both GPU and CPU failed"),
                "Error message should describe the dual failure")
        }

        XCTAssertFalse(engine.isReady,
            "Engine should NOT be ready when both backends fail")
    }

    // MARK: - Fallback Metrics

    /// After a successful `initializeWithFallback()`, `lastBackendResult` is populated.
    func testFallbackMetrics() async throws {
        let engine = MockInstrumentedEngine()
        engine.mockBackendResult = BackendResult(
            activeBackend: .gpu,
            didFallback: false,
            fallbackReason: nil,
            detectedCapability: .gpuAndCpu
        )

        XCTAssertNil(engine.lastBackendResult,
            "lastBackendResult should be nil before initialization")

        let result = try await engine.initializeWithFallback(
            modelPath: "/fake/model.litertlm",
            preferGPU: true,
            cacheDir: NSTemporaryDirectory(),
            flags: defaultFlags,
            samplerConfig: nil,
            systemMessage: nil,
            tools: nil
        )

        XCTAssertNotNil(engine.lastBackendResult,
            "lastBackendResult should be populated after initializeWithFallback")
        XCTAssertEqual(engine.lastBackendResult?.activeBackend, result.activeBackend,
            "lastBackendResult should match the returned result")
        XCTAssertEqual(engine.lastBackendResult?.detectedCapability, .gpuAndCpu,
            "Detected capability should match what was configured")
    }

    // MARK: - Factory: Happy Path

    /// `MockInstrumentedEngine.happyPath()` creates an engine that works out of the box.
    func testFactoryHappyPath() async throws {
        let engine = MockInstrumentedEngine.happyPath()

        // Initialize
        try await engine.initialize(
            modelPath: "/fake/model.litertlm",
            useGPU: false,
            cacheDir: NSTemporaryDirectory(),
            flags: defaultFlags,
            samplerConfig: nil,
            systemMessage: nil,
            tools: nil
        )
        XCTAssertTrue(engine.isReady, "Happy path engine should be ready after init")

        // Stream response
        var response = ""
        for try await chunk in engine.sendMessageStream("Hello") {
            response += chunk
        }

        XCTAssertEqual(response, "Hello, world!",
            "Happy path should produce 'Hello, world!'. Got: '\(response)'")
    }

    // MARK: - Factory: Failing Engine

    /// `MockInstrumentedEngine.failingEngine()` creates an engine that fails on init.
    func testFactoryFailingEngine() async {
        let engine = MockInstrumentedEngine.failingEngine()

        do {
            try await engine.initialize(
                modelPath: "/fake/model.litertlm",
                useGPU: false,
                cacheDir: NSTemporaryDirectory(),
                flags: defaultFlags,
                samplerConfig: nil,
                systemMessage: nil,
                tools: nil
            )
            XCTFail("Failing engine should throw on initialize()")
        } catch {
            XCTAssertFalse(engine.isReady,
                "Failing engine should NOT be ready after init failure")
            XCTAssertTrue(error.localizedDescription.contains("initialization failure"),
                "Error should describe init failure. Got: \(error.localizedDescription)")
        }
    }

    // MARK: - Factory: Intermittent Failure

    /// `MockInstrumentedEngine.intermittentFailure()` errors at chunk index 3.
    func testFactoryIntermittentFailure() async throws {
        let engine = MockInstrumentedEngine.intermittentFailure()

        // Init succeeds — the failure is mid-stream
        try await engine.initialize(
            modelPath: "/fake/model.litertlm",
            useGPU: false,
            cacheDir: NSTemporaryDirectory(),
            flags: defaultFlags,
            samplerConfig: nil,
            systemMessage: nil,
            tools: nil
        )
        XCTAssertTrue(engine.isReady, "Intermittent engine should initialize successfully")

        // Stream should fail at chunk 3
        var receivedChunks: [String] = []
        let stream = engine.sendMessageStream("test")

        do {
            for try await chunk in stream {
                receivedChunks.append(chunk)
            }
            XCTFail("Expected mid-stream error at chunk index 3")
        } catch {
            XCTAssertEqual(receivedChunks.count, 3,
                "Should receive exactly 3 chunks before error. Got: \(receivedChunks.count)")
        }
    }
}
