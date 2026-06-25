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

/// Integration tests for MockInstrumentedEngine failure modes.
///
/// Exercises configurable error injection: init failures, mid-stream errors,
/// warmup failures, fallback errors, cancellation, TTFT delays, and
/// multi-turn conversation tracking.
final class EngineFailureTests: XCTestCase {

    // MARK: - Shared Setup

    private var engine: MockInstrumentedEngine!

    private let defaultFlags = ExperimentalFlagsState(
        enableBenchmark: true,
        enableSpeculativeDecoding: nil,
        enableConversationConstrainedDecoding: false,
        visualTokenBudget: nil
    )

    override func setUp() {
        super.setUp()
        engine = MockInstrumentedEngine()
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    // MARK: - Init Failure

    /// Setting `initError` causes `initialize()` to throw.
    func testInitFailure() async {
        let expectedError = NSError(
            domain: "EngineFailureTests",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "Simulated init failure"]
        )
        engine.initError = expectedError

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
            XCTFail("Expected initialize() to throw when initError is set")
        } catch let error as NSError {
            XCTAssertEqual(error.code, 42, "Should propagate the exact error")
            XCTAssertEqual(error.domain, "EngineFailureTests")
        }

        XCTAssertFalse(engine.isReady, "Engine should NOT be ready after init failure")
        XCTAssertEqual(engine.initializeCallCount, 1, "initialize() should have been called once")
    }

    // MARK: - Mid-Stream Error

    /// Setting `errorAtChunkIndex = 3` emits the first 3 chunks, then throws.
    func testMidStreamError() async throws {
        engine.mockResponseChunks = ["A", "B", "C", "D", "E"]
        engine.errorAtChunkIndex = 3

        var receivedChunks: [String] = []
        let stream = engine.sendMessageStream("test prompt")

        do {
            for try await chunk in stream {
                receivedChunks.append(chunk)
            }
            XCTFail("Expected stream to throw after chunk index 3")
        } catch {
            // Expected mid-stream error
            XCTAssertEqual(receivedChunks.count, 3,
                "Should have received exactly 3 chunks before error. Got: \(receivedChunks)")
            XCTAssertEqual(receivedChunks, ["A", "B", "C"],
                "First 3 chunks should match. Got: \(receivedChunks)")
        }
    }

    // MARK: - Warmup Failure

    /// Setting `warmupError` causes `warmup()` to throw.
    func testWarmupFailure() async {
        let expectedError = NSError(
            domain: "EngineFailureTests",
            code: 99,
            userInfo: [NSLocalizedDescriptionKey: "Simulated warmup failure"]
        )
        engine.warmupError = expectedError

        do {
            try await engine.warmup()
            XCTFail("Expected warmup() to throw when warmupError is set")
        } catch let error as NSError {
            XCTAssertEqual(error.code, 99, "Should propagate the exact warmup error")
        }

        XCTAssertEqual(engine.warmupCallCount, 1, "warmup() should have been called once")
    }

    // MARK: - Fallback Both Fail

    /// Setting `fallbackError` causes `initializeWithFallback()` to throw,
    /// simulating both GPU and CPU backends failing.
    func testFallbackBothFail() async {
        let expectedError = NSError(
            domain: "EngineFailureTests",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Both backends failed"]
        )
        engine.fallbackError = expectedError

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
            XCTFail("Expected initializeWithFallback() to throw when fallbackError is set")
        } catch let error as NSError {
            XCTAssertEqual(error.domain, "EngineFailureTests",
                "Should propagate the exact fallback error")
        }

        XCTAssertFalse(engine.isReady,
            "Engine should NOT be ready when both backends fail")
    }

    // MARK: - Cancel Mid-Stream

    /// With `simulateCancelBehavior = true`, calling `cancelGeneration()` stops the stream.
    func testCancelMidStream() async throws {
        engine.mockResponseChunks = ["A", "B", "C", "D", "E", "F", "G", "H"]
        engine.simulateCancelBehavior = true
        engine.chunkDelay = 0.05  // Small delay so cancellation has time to take effect

        var receivedChunks: [String] = []
        let stream = engine.sendMessageStream("test prompt")

        // Collect chunks but cancel after receiving 2
        for try await chunk in stream {
            receivedChunks.append(chunk)
            if receivedChunks.count == 2 {
                engine.cancelGeneration()
            }
        }

        XCTAssertLessThan(receivedChunks.count, 8,
            "Stream should stop before all 8 chunks. Got \(receivedChunks.count)")
        XCTAssertGreaterThanOrEqual(receivedChunks.count, 2,
            "Should have received at least 2 chunks before cancel took effect")
    }

    // MARK: - TTFT Delay

    /// Setting `ttftDelay = 0.5` delays the first chunk by ~0.5 seconds.
    func testTTFTDelay() async throws {
        engine.mockResponseChunks = ["Hello", " world"]
        engine.ttftDelay = 0.5

        let stream = engine.sendMessageStream("test prompt")
        let startTime = CFAbsoluteTimeGetCurrent()
        var firstChunkTime: CFAbsoluteTime?

        for try await _ in stream {
            if firstChunkTime == nil {
                firstChunkTime = CFAbsoluteTimeGetCurrent()
            }
        }

        guard let ttft = firstChunkTime else {
            XCTFail("Should have received at least one chunk")
            return
        }

        let elapsed = ttft - startTime
        XCTAssertGreaterThanOrEqual(elapsed, 0.4,
            "TTFT should be at least ~0.4s (set to 0.5s). Got: \(String(format: "%.3f", elapsed))s")
        XCTAssertLessThan(elapsed, 1.5,
            "TTFT should not exceed 1.5s. Got: \(String(format: "%.3f", elapsed))s")
    }

    // MARK: - Multi-Turn Tracking

    /// Sending 3 messages records 3 entries in `conversationTurns`.
    func testMultiTurnTracking() async throws {
        let prompts = ["First question", "Second question", "Third question"]

        for prompt in prompts {
            let stream = engine.sendMessageStream(prompt)
            for try await _ in stream { /* consume stream */ }
        }

        XCTAssertEqual(engine.conversationTurns.count, 3,
            "Should have 3 conversation turns. Got: \(engine.conversationTurns.count)")
        XCTAssertEqual(engine.conversationTurns, prompts,
            "Conversation turns should match the prompts sent")
        XCTAssertEqual(engine.sendMessageCallCount, 3,
            "sendMessageStream should have been called 3 times")
    }

    // MARK: - Reset Clears Conversation

    /// After sending a message and resetting, conversation state is cleared.
    func testResetClearsConversation() async throws {
        // Send a message
        let stream = engine.sendMessageStream("Hello")
        for try await _ in stream { /* consume stream */ }

        XCTAssertEqual(engine.conversationTurns.count, 1,
            "Should have 1 turn before reset")
        XCTAssertNotNil(engine.lastPromptText,
            "lastPromptText should be set before reset")

        // Reset conversation
        try await engine.resetConversation()

        XCTAssertEqual(engine.resetConversationCallCount, 1,
            "resetConversation should have been called once")
        XCTAssertNil(engine.lastBenchmarkInfo,
            "lastBenchmarkInfo should be nil after reset")
        XCTAssertNil(engine.lastInferenceMetrics,
            "lastInferenceMetrics should be nil after reset")
    }
}
