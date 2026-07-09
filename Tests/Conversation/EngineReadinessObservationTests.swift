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

// MARK: - Engine Readiness Observation Tests
//
// Verifies the observation gap fix: `isEngineReady` is now a tracked stored property
// (`private(set) var isEngineReady: Bool = false`) instead of a computed property
// derived from `engine.isReady`. The ViewModel updates it via the
// `sessionController.onEngineReadyChanged` callback.
//
// This ensures SwiftUI views properly observe engine readiness changes.

@MainActor
final class EngineReadinessObservationTests: XCTestCase {

    private var mockEngine: MockInferenceEngine!
    private var metricsStore: MetricsStore!
    private var metricsFileURL: URL!

    override func setUp() {
        super.setUp()
        mockEngine = MockInferenceEngine()

        metricsFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_metrics_\(UUID().uuidString).json")
        metricsStore = MetricsStore(fileURL: metricsFileURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: metricsFileURL)
        super.tearDown()
    }

    // MARK: - Default State

    /// A freshly created ViewModel should report isEngineReady == false.
    func test_isEngineReady_defaultsFalse() {
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore, conversationStore: .inMemory())
        XCTAssertFalse(vm.isEngineReady)
    }

    // MARK: - Callback-Driven Updates

    /// The onEngineReadyChanged callback should set the tracked property to true.
    func test_engineReadyCallback_setsTrackedProperty() {
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore, conversationStore: .inMemory())

        // The ViewModel wires onEngineReadyChanged during init.
        // Invoke the callback with `true` to simulate engine becoming ready.
        vm.sessionController.onEngineReadyChanged?(true)
        XCTAssertTrue(vm.isEngineReady, "Callback with true should set isEngineReady to true")

        // Invoke with `false` to simulate engine becoming not ready.
        vm.sessionController.onEngineReadyChanged?(false)
        XCTAssertFalse(vm.isEngineReady, "Callback with false should set isEngineReady to false")
    }

    // MARK: - New Conversation Preserves Readiness

    /// newConversation() should NOT reset isEngineReady when the model stays loaded.
    /// This was the core observation gap bug: resetting the conversation should not
    /// make the UI think the engine is unloaded.
    func test_newConversation_keepsEngineReady_true() async {
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore, conversationStore: .inMemory())

        // Initialize the engine so it becomes ready (via the sessionController path)
        await vm.sessionController.initializeEngine(modelPath: "/path/to/model.litertlm")
        XCTAssertTrue(vm.isEngineReady, "Engine should be ready after init")

        // Add some conversation state to verify it gets cleared
        vm.conversation.append(.user("Hi"))
        vm.conversation.append(.assistant())
        vm.conversation.updateLastAssistantMessage(content: "Hello!", isStreaming: false)

        // Reset conversation — model stays loaded
        await vm.newConversation()

        // The key assertion: engine readiness must survive conversation reset
        XCTAssertTrue(
            vm.isEngineReady,
            "isEngineReady should remain true after newConversation() — the model is still loaded"
        )
        // Verify the conversation itself was cleared
        XCTAssertTrue(vm.conversation.isEmpty, "Conversation should be empty after reset")
    }

    // MARK: - Shutdown Clears Readiness

    /// shutdown() should set isEngineReady to false since the engine is released.
    func test_shutdown_setsEngineReady_false() async {
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore, conversationStore: .inMemory())

        // Make the engine ready via the callback
        vm.sessionController.onEngineReadyChanged?(true)
        XCTAssertTrue(vm.isEngineReady, "Precondition: engine should be ready")

        // Shutdown releases the engine
        await vm.shutdown()

        XCTAssertFalse(
            vm.isEngineReady,
            "isEngineReady should be false after shutdown()"
        )
    }
}
