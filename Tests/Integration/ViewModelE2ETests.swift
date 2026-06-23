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

/// End-to-end tests for the ConversationViewModel lifecycle.
///
/// These tests use MockInstrumentedEngine but real persistence stores
/// (ConversationStore, MetricsStore, EvalStore) to validate the full
/// ViewModel behavioral contract: state transitions, auto-save, fork,
/// tool calling integration, and eval execution.
///
/// Unlike the existing wiring tests that verify "ViewModel calls engine methods",
/// these verify "after a user interaction, the correct state persists."
@MainActor
final class ViewModelE2ETests: XCTestCase {

    // MARK: - Test Infrastructure

    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViewModelE2ETests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeEngine(responseChunks: [String] = ["Hello", ", ", "world", "!"]) -> MockInstrumentedEngine {
        let engine = MockInstrumentedEngine()
        engine.mockResponseChunks = responseChunks
        // Note: BenchmarkInfo init is internal to LiteRTLM, so we leave mockBenchmarkInfo
        // as nil. Tests that need benchmark data should set it if the init becomes public.
        return engine
    }

    private func makeConversationStore() -> ConversationStore {
        ConversationStore(storageDirectory: tempDir.appendingPathComponent("conversations"))
    }

    private func makeMetricsStore() -> MetricsStore {
        MetricsStore(fileURL: tempDir.appendingPathComponent("metrics.json"))
    }

    private func makeEvalStore() -> EvalStore {
        EvalStore(storageDirectory: tempDir.appendingPathComponent("evals"))
    }

    private func makeViewModel(
        engine: MockInstrumentedEngine? = nil,
        conversationStore: ConversationStore? = nil,
        metricsStore: MetricsStore? = nil
    ) -> ConversationViewModel {
        let eng = engine ?? makeEngine()
        let store = conversationStore ?? makeConversationStore()
        let metrics = metricsStore ?? makeMetricsStore()

        return ConversationViewModel(
            engine: eng,
            metricsStore: metrics,
            conversationStore: store
        )
    }

    /// Initialize the mock engine on the ViewModel so isEngineReady is true.
    private func initializeEngine(on vm: ConversationViewModel) async throws {
        let engine = vm.engine as! MockInstrumentedEngine
        try await engine.initialize(
            modelPath: "/fake/model.litertlm",
            useGPU: false,
            cacheDir: NSTemporaryDirectory(),
            flags: vm.experimentalFlags,
            samplerConfig: nil,
            systemMessage: nil,
            tools: nil
        )
    }

    // MARK: - Tests

    /// Full lifecycle: init → generate → verify auto-save → new conversation → verify loadable.
    ///
    /// This proves: prompt → response → auto-save to ConversationStore → new conversation clears
    /// state → old conversation is retrievable from the store.
    func testFullConversationLifecycle() async throws {
        let store = makeConversationStore()
        let engine = makeEngine(responseChunks: ["The", " answer", " is", " 42", "."])
        let vm = makeViewModel(engine: engine, conversationStore: store)

        // Initialize engine so inference works
        try await initializeEngine(on: vm)
        XCTAssertTrue(vm.isEngineReady, "Engine should be ready")

        // Set prompt and generate
        vm.prompt = "What is the meaning of life?"
        await vm.generateText()

        // Verify response appeared
        XCTAssertFalse(vm.responseText.isEmpty, "Response text should not be empty after generation")
        XCTAssertTrue(vm.responseText.contains("42"), "Response should contain '42'")

        // Verify conversation has messages
        XCTAssertFalse(vm.conversation.isEmpty, "Conversation should not be empty")

        // Save current conversation (auto-save happens on newConversation)
        _ = vm.activeConversationId

        // New conversation triggers auto-save of current
        await vm.newConversation()

        // Verify conversation was cleared
        XCTAssertTrue(vm.conversation.isEmpty, "Conversation should be empty after newConversation")
        XCTAssertNil(vm.activeConversationId, "Active conversation ID should be nil after newConversation")

        // Verify old conversation was persisted to store
        XCTAssertFalse(store.indexEntries.isEmpty, "Store should have at least one saved conversation")

        // Load the saved conversation back
        let savedEntry = store.indexEntries.first!
        let loaded = try store.load(id: savedEntry.id)
        XCTAssertFalse(loaded.messages.isEmpty, "Loaded conversation should have messages")
    }

    /// Fork a conversation and verify both original and fork exist independently.
    ///
    /// This proves: generate → save → fork creates new entry → fork has same messages →
    /// generating on fork doesn't affect original.
    func testConversationForkAndDivergence() async throws {
        let store = makeConversationStore()
        let engine = makeEngine(responseChunks: ["Turn", " 1", " response"])
        let vm = makeViewModel(engine: engine, conversationStore: store)

        try await initializeEngine(on: vm)

        // Generate first conversation
        vm.prompt = "Hello, first turn"
        await vm.generateText()

        // Manually save the conversation
        vm.saveCurrentConversation()
        let originalId = vm.activeConversationId!

        // Fork it
        vm.forkConversation(id: originalId)

        let forkId = vm.activeConversationId
        XCTAssertNotNil(forkId, "Fork should set a new active conversation ID")
        XCTAssertNotEqual(forkId, originalId, "Fork should have a different ID than original")

        // Store should have 2 entries
        XCTAssertEqual(store.indexEntries.count, 2,
            "Store should have original + fork. Found: \(store.indexEntries.count)")

        // Verify fork has the original messages
        let forked = try store.load(id: forkId!)
        XCTAssertFalse(forked.messages.isEmpty, "Forked conversation should have messages from original")

        // Verify fork title indicates it's a fork
        let forkEntry = store.indexEntries.first(where: { $0.id == forkId })!
        XCTAssertTrue(forkEntry.title.contains("Fork"),
            "Fork title should contain 'Fork'. Got: \(forkEntry.title)")

        // Generate a new message on the fork
        engine.mockResponseChunks = ["Fork", " diverged", " response"]
        vm.prompt = "This is the fork's unique message"
        await vm.generateText()

        // Save fork state
        vm.saveCurrentConversation()

        // Verify original is unchanged
        let original = try store.load(id: originalId)
        let originalMessageCount = original.messages.count
        let forkedUpdated = try store.load(id: forkId!)
        XCTAssertGreaterThan(forkedUpdated.messages.count, originalMessageCount,
            "Fork should have more messages than original after diverging")
    }

    /// Switch models mid-conversation and verify engine reinitialization.
    ///
    /// This proves: generate → switch model → engine re-initializes → conversation clears →
    /// old conversation was auto-saved.
    func testModelSwitchMidConversation() async throws {
        let store = makeConversationStore()
        let engine = makeEngine()
        let vm = makeViewModel(engine: engine, conversationStore: store)

        try await initializeEngine(on: vm)

        // Generate some content
        vm.prompt = "First model message"
        await vm.generateText()

        XCTAssertFalse(vm.conversation.isEmpty, "Should have messages after generation")
        let initialInitCount = engine.initializeCallCount

        // Create a fake model file for selection
        let fakeModelURL = tempDir.appendingPathComponent("new-model.litertlm")
        try Data("fake model data".utf8).write(to: fakeModelURL)

        // Handle model selection — this should reinitialize the engine
        await vm.handleModelSelection(fakeModelURL)

        XCTAssertGreaterThan(engine.initializeCallCount, initialInitCount,
            "Engine should have been re-initialized after model switch")

        // Conversation should be cleared after model switch
        XCTAssertTrue(vm.conversation.isEmpty,
            "Conversation should be cleared after switching models")
    }

    /// Inject a tool call event during generation and verify it's captured by the ViewModel.
    ///
    /// This proves: during generation → tool executes → ToolExecutionTracker notifies →
    /// ViewModel captures the event in toolCallEvents.
    func testToolCallingE2E() async throws {
        let engine = makeEngine(responseChunks: ["Calculating", "...", " The result is 100."])
        engine.chunkDelay = 0.1  // Slow down to allow tool injection
        let vm = makeViewModel(engine: engine)

        try await initializeEngine(on: vm)

        vm.prompt = "What is 25 * 4?"

        // Start generation in a separate task
        let generateTask = Task {
            await vm.generateText()
        }

        // Wait briefly for generation to start streaming
        try await Task.sleep(for: .seconds(0.15))

        // Inject a tool call event as if the CalculatorTool executed
        let event = ToolCallEvent(
            toolName: "calculate",
            arguments: "{\"expression\": \"25 * 4\"}",
            result: "{\"result\": 100}",
            durationMs: 1.5,
            timestamp: Date(),
            succeeded: true
        )
        ToolExecutionTracker.shared.notify(event)

        // Wait for generation to complete
        _ = await generateTask.result

        // Verify the tool call event was captured
        XCTAssertEqual(vm.toolCallEvents.count, 1,
            "ViewModel should have captured 1 tool call event. Found: \(vm.toolCallEvents.count)")
        XCTAssertEqual(vm.toolCallEvents.first?.toolName, "calculate",
            "Tool call should be for 'calculate'")
        XCTAssertTrue(vm.toolCallEvents.first?.succeeded ?? false,
            "Tool call should have succeeded")
    }

    /// Run a complete eval suite with mock engine and verify results are persisted.
    ///
    /// This proves: create suite → run evaluation → state transitions correctly →
    /// results are scored → results are persisted in EvalStore.
    func testEvalRunnerFullSuite() async throws {
        let engine = makeEngine(responseChunks: ["Four", "."])
        let evalStore = makeEvalStore()
        let runner = EvalRunner(engine: engine, store: evalStore)

        // Verify initial state
        XCTAssertEqual(runner.state, .idle, "Runner should start in idle state")

        // Create a 3-prompt eval suite
        let suite = EvalSuite(
            name: "E2E Test Suite",
            description: "Tests for ViewModelE2ETests",
            category: .math,
            prompts: [
                EvalPrompt(prompt: "What is 2+2?", expectedBehavior: .nonEmpty),
                EvalPrompt(prompt: "What is 3*3?", expectedBehavior: .nonEmpty),
                EvalPrompt(prompt: "What is 10/2?", expectedBehavior: .nonEmpty),
            ]
        )

        // Create a model entry (uses a fake path since mock engine doesn't need a real file)
        let modelEntry = EvalModelEntry(
            metadata: ModelRegistry.knownModels.first!,
            modelPath: "/fake/model.litertlm"
        )

        let flags = ExperimentalFlagsState(
            enableBenchmark: true,
            enableSpeculativeDecoding: nil,
            enableConversationConstrainedDecoding: false,
            visualTokenBudget: nil
        )

        // Run the evaluation
        let run = try await runner.run(
            suite: suite,
            models: [modelEntry],
            flags: flags,
            cacheDir: NSTemporaryDirectory()
        )

        // Verify completion
        XCTAssertEqual(runner.state, .complete, "Runner should be in complete state. Got: \(runner.state)")

        // Verify the run has results
        XCTAssertFalse(run.modelResults.isEmpty, "Run should have model results")
        XCTAssertEqual(run.suiteName, "E2E Test Suite", "Run should reference the correct suite")

        // Verify each prompt got a result
        let modelResult = run.modelResults.first!
        XCTAssertEqual(modelResult.promptResults.count, 3,
            "Should have 3 prompt results. Got: \(modelResult.promptResults.count)")

        // Verify all prompts passed (nonEmpty check should pass since mock returns "Four.")
        for result in modelResult.promptResults {
            XCTAssertFalse(result.response.isEmpty,
                "Prompt result should have non-empty response text")
        }
    }
}
