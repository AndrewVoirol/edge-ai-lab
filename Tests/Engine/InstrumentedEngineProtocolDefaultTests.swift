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

/// Tests for InstrumentedEngineProtocol default implementations and BackendResult types.
///
/// Exercises:
/// - `BackendResult` struct construction and properties
/// - `BackendResult.ActiveBackend` enum raw values
/// - Protocol default convenience methods (shorter overloads forwarding correctly)
final class InstrumentedEngineProtocolDefaultTests: XCTestCase {

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

    // MARK: - BackendResult Construction

    func testBackendResultConstruction() {
        let result = BackendResult(
            activeBackend: .gpu,
            didFallback: false,
            fallbackReason: nil,
            detectedCapability: .gpuAndCpu
        )

        XCTAssertEqual(result.activeBackend, .gpu)
        XCTAssertFalse(result.didFallback)
        XCTAssertNil(result.fallbackReason)
        XCTAssertEqual(result.detectedCapability, .gpuAndCpu)
    }

    func testBackendResultWithFallback() {
        let result = BackendResult(
            activeBackend: .cpu,
            didFallback: true,
            fallbackReason: "GPU initialization failed: metal not available",
            detectedCapability: .cpuOnly
        )

        XCTAssertEqual(result.activeBackend, .cpu)
        XCTAssertTrue(result.didFallback)
        XCTAssertEqual(result.fallbackReason, "GPU initialization failed: metal not available")
        XCTAssertEqual(result.detectedCapability, .cpuOnly)
    }

    // MARK: - ActiveBackend Enum Raw Values

    func testActiveBackendRawValues() {
        XCTAssertEqual(BackendResult.ActiveBackend.gpu.rawValue, "gpu")
        XCTAssertEqual(BackendResult.ActiveBackend.cpu.rawValue, "cpu")

        // Round-trip from raw value
        XCTAssertEqual(BackendResult.ActiveBackend(rawValue: "gpu"), .gpu)
        XCTAssertEqual(BackendResult.ActiveBackend(rawValue: "cpu"), .cpu)
        XCTAssertNil(BackendResult.ActiveBackend(rawValue: "tpu"), "Unknown raw values should return nil")
    }

    // MARK: - Protocol Default: initialize (short overload → systemMessage=nil, tools=nil)

    func testInitializeShortOverloadForwardsCorrectly() async throws {
        // Call the shorter convenience overload (no systemMessage, no tools)
        try await engine.initialize(
            modelPath: "/fake/model.litertlm",
            useGPU: true,
            cacheDir: NSTemporaryDirectory(),
            flags: defaultFlags,
            samplerConfig: nil
        )

        // Verify it forwarded to the full overload with nil defaults
        XCTAssertEqual(engine.initializeCallCount, 1, "Should call initialize exactly once")
        XCTAssertEqual(engine.lastModelPath, "/fake/model.litertlm")
        XCTAssertNil(engine.lastSystemMessage, "Short overload should forward nil systemMessage")
        XCTAssertNil(engine.lastTools, "Short overload should forward nil tools")
        XCTAssertFalse(engine.lastSupportsVision, "Short overload should forward supportsVision=false")
        XCTAssertFalse(engine.lastSupportsAudio, "Short overload should forward supportsAudio=false")
        XCTAssertTrue(engine.isReady, "Engine should be ready after successful init")
    }

    // MARK: - Protocol Default: initialize (systemMessage overload → tools=nil)

    func testInitializeWithSystemMessageOverloadForwardsCorrectly() async throws {
        // Call the overload that includes systemMessage but not tools
        try await engine.initialize(
            modelPath: "/fake/model.litertlm",
            useGPU: false,
            cacheDir: NSTemporaryDirectory(),
            flags: defaultFlags,
            samplerConfig: nil,
            systemMessage: "You are a helpful assistant."
        )

        XCTAssertEqual(engine.initializeCallCount, 1)
        XCTAssertEqual(engine.lastSystemMessage, "You are a helpful assistant.",
            "systemMessage overload should forward the system message")
        XCTAssertNil(engine.lastTools, "systemMessage overload should forward nil tools")
        XCTAssertFalse(engine.lastSupportsVision)
        XCTAssertFalse(engine.lastSupportsAudio)
    }

    // MARK: - Protocol Default: sendMessageStream (no enableThinking)

    func testSendMessageStreamShortOverload() async throws {
        engine.mockResponseChunks = ["Alpha", "Beta"]

        // Call the convenience overload without enableThinking
        let stream = engine.sendMessageStream("Hello")
        var chunks: [String] = []
        for try await chunk in stream {
            chunks.append(chunk)
        }

        XCTAssertEqual(chunks, ["Alpha", "Beta"])
        XCTAssertEqual(engine.sendMessageCallCount, 1)
        XCTAssertEqual(engine.lastPromptText, "Hello")
        XCTAssertFalse(engine.lastEnableThinking,
            "Short overload should forward enableThinking=false")
    }

    // MARK: - Protocol Default: sendMessageStream multimodal (no enableThinking)

    func testSendMessageStreamMultimodalShortOverload() async throws {
        engine.mockResponseChunks = ["Response"]
        let fakeImage = Data([0xFF, 0xD8, 0xFF])

        // Call the multimodal convenience overload without enableThinking
        let stream = engine.sendMessageStream("Describe this", imageData: fakeImage, audioData: nil)
        var chunks: [String] = []
        for try await chunk in stream {
            chunks.append(chunk)
        }

        XCTAssertEqual(chunks, ["Response"])
        XCTAssertEqual(engine.multimodalSendCallCount, 1)
        XCTAssertEqual(engine.lastImageData, fakeImage,
            "Image data should be forwarded")
        XCTAssertNil(engine.lastAudioData)
        XCTAssertFalse(engine.lastEnableThinking,
            "Short multimodal overload should forward enableThinking=false")
    }

    // MARK: - Protocol Default: initializeWithFallback (short overload)

    func testInitializeWithFallbackShortOverload() async throws {
        // Call the shorter initializeWithFallback (no systemMessage, no tools)
        let result = try await engine.initializeWithFallback(
            modelPath: "/fake/model.litertlm",
            preferGPU: true,
            cacheDir: NSTemporaryDirectory(),
            flags: defaultFlags,
            samplerConfig: nil
        )

        XCTAssertEqual(engine.initializeCallCount, 1)
        XCTAssertNil(engine.lastSystemMessage,
            "Short fallback overload should forward nil systemMessage")
        XCTAssertNil(engine.lastTools,
            "Short fallback overload should forward nil tools")
        XCTAssertEqual(result.activeBackend, .gpu,
            "Should use preferred GPU backend when no errors")
        XCTAssertFalse(result.didFallback)
    }

    // MARK: - Protocol Default: initializeWithFallback (systemMessage overload)

    func testInitializeWithFallbackSystemMessageOverload() async throws {
        let result = try await engine.initializeWithFallback(
            modelPath: "/fake/model.litertlm",
            preferGPU: false,
            cacheDir: NSTemporaryDirectory(),
            flags: defaultFlags,
            samplerConfig: nil,
            systemMessage: "Be concise."
        )

        XCTAssertEqual(engine.lastSystemMessage, "Be concise.")
        XCTAssertNil(engine.lastTools)
        XCTAssertEqual(result.activeBackend, .cpu,
            "Should use CPU when preferGPU=false")
    }

    // MARK: - BackendCapability Properties

    func testBackendCapabilitySupportsGPUProperty() {
        // Verify the supportsGPU computed property on detectedCapability
        let gpuResult = BackendResult(
            activeBackend: .gpu,
            didFallback: false,
            fallbackReason: nil,
            detectedCapability: .gpuOnly
        )
        XCTAssertTrue(gpuResult.detectedCapability.supportsGPU)
        XCTAssertFalse(gpuResult.detectedCapability.supportsCPU)

        let bothResult = BackendResult(
            activeBackend: .gpu,
            didFallback: false,
            fallbackReason: nil,
            detectedCapability: .gpuAndCpu
        )
        XCTAssertTrue(bothResult.detectedCapability.supportsGPU)
        XCTAssertTrue(bothResult.detectedCapability.supportsCPU)

        let unknownResult = BackendResult(
            activeBackend: .cpu,
            didFallback: true,
            fallbackReason: "Probe failed",
            detectedCapability: .unknown
        )
        XCTAssertFalse(unknownResult.detectedCapability.supportsGPU)
        XCTAssertFalse(unknownResult.detectedCapability.supportsCPU)
    }
}
