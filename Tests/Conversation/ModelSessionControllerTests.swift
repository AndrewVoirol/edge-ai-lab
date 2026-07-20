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

import Testing
import Foundation

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Tests for ModelSessionController's initialization, sampler defaults,
/// lifecycle (cancel, shutdown), and status callbacks.
@Suite("ModelSessionController")
@MainActor
struct ModelSessionControllerTests {

    // MARK: - Helpers

    /// Creates a controller with a MockInferenceEngine and captures status messages.
    private static func makeController(
        engine: MockInferenceEngine = .happyPath()
    ) -> (ModelSessionController, MockInferenceEngine, [String]) {
        var statusMessages: [String] = []
        let controller = ModelSessionController(
            engine: engine,
            onStatusMessage: { message in
                statusMessages.append(message)
            }
        )
        return (controller, engine, statusMessages)
    }

    // MARK: - Initial State

    @Test("Initial state has no model loaded and no backend result")
    func testInitialState() {
        let engine = MockInferenceEngine.happyPath()
        let controller = ModelSessionController(
            engine: engine,
            onStatusMessage: { _ in }
        )

        #expect(controller.isLoadingModel == false)
        #expect(controller.activeModelURL == nil)
        #expect(controller.backendResult == nil)
        #expect(controller.activeCapabilityProfile == nil)
    }

    // MARK: - Default Sampler Values

    @Test("Default sampler values match SDK defaults")
    func testDefaultSamplerValues() {
        let engine = MockInferenceEngine.happyPath()
        let controller = ModelSessionController(
            engine: engine,
            onStatusMessage: { _ in }
        )

        #expect(controller.topK == 64)
        #expect(controller.topP == 0.95)
        #expect(controller.temperature == 1.0)
        #expect(controller.seed == 0)
    }

    // MARK: - Cancel Model Load

    @Test("cancelModelLoad sets isLoadingModel to false and posts status message")
    func testCancelModelLoad() {
        let engine = MockInferenceEngine.happyPath()
        var lastStatus = ""
        let controller = ModelSessionController(
            engine: engine,
            onStatusMessage: { lastStatus = $0 }
        )

        controller.cancelModelLoad()

        #expect(controller.isLoadingModel == false)
        #expect(lastStatus == "Model load cancelled")
    }

    // MARK: - Shutdown

    @Test("shutdown clears all model state")
    func testShutdown() async {
        let engine = MockInferenceEngine.happyPath()
        let controller = ModelSessionController(
            engine: engine,
            onStatusMessage: { _ in }
        )

        // Initialize first so there's state to clear
        await controller.initializeEngine(modelPath: "/path/to/test.litertlm")

        // Now shutdown
        await controller.shutdown()

        #expect(controller.activeModelURL == nil)
        #expect(controller.activeCapabilityProfile == nil)
        #expect(controller.backendResult == nil)
        #expect(engine.shutdownCallCount >= 1)
    }

    // MARK: - System Message

    @Test("systemMessage property is settable")
    func testSystemMessageComposition() {
        let engine = MockInferenceEngine.happyPath()
        let controller = ModelSessionController(
            engine: engine,
            onStatusMessage: { _ in }
        )

        controller.systemMessage = "You are a helpful assistant."
        #expect(controller.systemMessage == "You are a helpful assistant.")

        controller.systemMessage = ""
        #expect(controller.systemMessage == "")
    }

    // MARK: - Status Callback

    @Test("onStatusMessage callback fires during initialization")
    func testStatusCallbackFires() async {
        let engine = MockInferenceEngine.happyPath()
        var messages: [String] = []
        let controller = ModelSessionController(
            engine: engine,
            onStatusMessage: { messages.append($0) }
        )

        await controller.initializeEngine(modelPath: "/path/to/model.litertlm")

        #expect(messages.count >= 1, "Should have received at least one status message")
        #expect(messages.first == "Initializing Engine...", "First message should be 'Initializing Engine...'")
    }

    // MARK: - reinitializeIfNeeded Guard

    @Test("reinitializeIfNeeded returns without action when engine is not ready")
    func testReinitializeIfNeededGuard() async {
        let engine = MockInferenceEngine.happyPath()
        // engine.isLoaded is false by default
        #expect(engine.isLoaded == false)

        let controller = ModelSessionController(
            engine: engine,
            onStatusMessage: { _ in }
        )

        let flags = RuntimeFlags(
            enableBenchmark: true,
            enableSpeculativeDecoding: nil,
            enableConversationConstrainedDecoding: false,
            visualTokenBudget: nil
        )

        await controller.reinitializeIfNeeded(
            runtimeFlags: flags,
            useGPU: true
        )

        // Should not have called initialize since engine wasn't ready
        #expect(engine.loadModelCallCount == 0, "Should not reinitialize when engine is not ready")
    }

    // MARK: - Sampler Config via Engine

    @Test("Sampler properties are forwarded to engine during initialization")
    func testBuildSamplerConfigNormalValues() async {
        let engine = MockInferenceEngine.happyPath()
        let controller = ModelSessionController(
            engine: engine,
            onStatusMessage: { _ in }
        )

        controller.topK = 40
        controller.topP = 0.9
        controller.temperature = 0.8

        await controller.initializeEngine(modelPath: "/path/to/model.litertlm")

        #expect(engine.lastGenerationConfig != nil, "SamplerConfig should be passed to engine")
        #expect(engine.loadModelCallCount >= 1, "Engine should have been initialized")
    }
}
