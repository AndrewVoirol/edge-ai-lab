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

// MARK: - Model Readiness State Tests
//
// Tests for the chat tab state logic: the ViewModel correctly reports combined
// state (engine readiness + discovered models + conversation state) that the UI
// uses to decide what to display:
//
// - Engine not ready, no models → empty/onboarding state
// - Engine ready, empty conversation → hint cards available
// - Engine ready after reset → hint cards should reappear

@MainActor
final class ModelReadinessStateTests: XCTestCase {

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

    // MARK: - Empty State (No Engine, No Models)

    /// When the engine is not ready and no models are discovered, the UI should
    /// show the onboarding/empty state.
    func test_chatTabState_engineNotReady_noModels_emptyState() {
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore, conversationStore: .inMemory())

        XCTAssertFalse(vm.isEngineReady, "Engine should not be ready by default")
        XCTAssertTrue(vm.discoveredModels.isEmpty, "No models should be discovered by default")

        // This combined state tells the UI: show the onboarding/getting-started view
    }

    // MARK: - Engine Ready, Empty Conversation (Hint Cards)

    /// When the engine is ready and the conversation is empty, the UI should
    /// show hint cards (conversation starters).
    func test_chatTabState_engineReady_conversationEmpty_hintsAvailable() async {
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore, conversationStore: .inMemory())

        // Initialize engine to make it ready
        await vm.sessionController.initializeEngine(modelPath: "/path/to/model.litertlm")

        XCTAssertTrue(vm.isEngineReady, "Engine should be ready after initialization")
        XCTAssertTrue(
            vm.conversation.isEmpty,
            "Conversation should be empty before any user interaction"
        )

        // This combined state tells the UI: show hint cards / conversation starters
    }

    // MARK: - Engine Ready After Reset (Hint Cards Reappear)

    /// After newConversation(), the engine stays ready and the conversation is empty,
    /// so hint cards should reappear. This was the core observation gap bug —
    /// previously the UI would show "No Model Loaded" after a conversation reset.
    func test_chatTabState_engineReady_afterReset_staysReady() async {
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore, conversationStore: .inMemory())

        // Initialize and simulate a conversation
        await vm.sessionController.initializeEngine(modelPath: "/path/to/model.litertlm")
        XCTAssertTrue(vm.isEngineReady, "Precondition: engine should be ready")

        vm.conversation.append(.user("What is Swift?"))
        vm.conversation.append(.assistant())
        vm.conversation.updateLastAssistantMessage(content: "Swift is a programming language.", isStreaming: false)
        XCTAssertFalse(vm.conversation.isEmpty, "Precondition: conversation should have messages")

        // Reset conversation
        await vm.newConversation()

        // After reset: engine is still ready, conversation is empty → hint cards should show
        XCTAssertTrue(
            vm.isEngineReady,
            "Engine should remain ready after conversation reset — model is still loaded"
        )
        XCTAssertTrue(
            vm.conversation.isEmpty,
            "Conversation should be empty after reset — hint cards should reappear"
        )
    }
}
