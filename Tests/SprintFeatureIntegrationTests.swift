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
@testable import GemmaEdgeGallery_iOS
#elseif os(macOS)
@testable import GemmaEdgeGallery_macOS
#endif

// MARK: - Sprint Feature Integration Tests

/// Integration tests verifying end-to-end behavior of v1.0 sprint features.
/// These tests cover gaps not addressed by unit-level tests:
/// - T1: enableThinking passed through generateText → sendMessageStream
/// - T1: Thinking tag stripping in generateText when thinking is disabled
/// - T3: Vision/audio backend configuration passed through engine init
/// - Conversation auto-save after inference completes
/// - Sampler didSet auto-reinit triggers
final class SprintFeatureIntegrationTests: XCTestCase {

    private var mockEngine: MockInstrumentedEngine!
    private var metricsStore: MetricsStore!
    private var metricsFileURL: URL!
    private var conversationStoreDir: URL!

    @MainActor
    override func setUp() {
        super.setUp()
        mockEngine = MockInstrumentedEngine()
        metricsFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_sprint_metrics_\(UUID().uuidString).json")
        metricsStore = MetricsStore(fileURL: metricsFileURL)
        conversationStoreDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_conversations_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: conversationStoreDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: metricsFileURL)
        try? FileManager.default.removeItem(at: conversationStoreDir)
        super.tearDown()
    }

    // MARK: - T1: enableThinking Passed Through generateText

    /// Verify that when thinking mode is enabled, generateText passes
    /// enableThinking=true to the engine's sendMessageStream.
    @MainActor
    func testGenerateTextPassesEnableThinkingTrue() async {
        let store = ConversationStore(storageDirectory: conversationStoreDir)
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore, conversationStore: store)
        vm.experimentalFlags.enableThinking = true
        mockEngine.isReady = true
        mockEngine.mockResponseChunks = ["Hello"]

        vm.prompt = "What is 2+2?"
        await vm.generateText()

        XCTAssertTrue(
            mockEngine.lastEnableThinking,
            "generateText should pass enableThinking=true when thinking mode is ON"
        )
    }

    /// Verify that when thinking mode is disabled, generateText passes
    /// enableThinking=false to the engine's sendMessageStream.
    @MainActor
    func testGenerateTextPassesEnableThinkingFalse() async {
        let store = ConversationStore(storageDirectory: conversationStoreDir)
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore, conversationStore: store)
        vm.experimentalFlags.enableThinking = false
        mockEngine.isReady = true
        mockEngine.mockResponseChunks = ["Hello"]

        vm.prompt = "What is 2+2?"
        await vm.generateText()

        XCTAssertFalse(
            mockEngine.lastEnableThinking,
            "generateText should pass enableThinking=false when thinking mode is OFF"
        )
    }

    // MARK: - T1: Thinking Tag Stripping When Disabled

    /// When thinking mode is disabled and the model emits <think> tags,
    /// they should be stripped from the visible response.
    @MainActor
    func testThinkingTagsStrippedInGenerateTextWhenDisabled() async {
        let store = ConversationStore(storageDirectory: conversationStoreDir)
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore, conversationStore: store)
        vm.experimentalFlags.enableThinking = false
        mockEngine.isReady = true
        mockEngine.mockResponseChunks = ["<think>", "internal reasoning", "</think>", "The answer is 4."]

        vm.prompt = "What is 2+2?"
        await vm.generateText()

        let lastMessage = vm.conversation.messages.last
        XCTAssertNotNil(lastMessage)
        XCTAssertFalse(
            lastMessage?.content.contains("<think>") ?? true,
            "Response should not contain <think> tags when thinking is disabled"
        )
        XCTAssertFalse(
            lastMessage?.content.contains("</think>") ?? true,
            "Response should not contain </think> tags when thinking is disabled"
        )
        XCTAssertTrue(
            lastMessage?.content.contains("The answer is 4.") ?? false,
            "Response content after stripping should be preserved"
        )
    }

    /// When thinking mode is disabled and model emits alternate <|think|> tags,
    /// they should also be stripped from the visible response.
    @MainActor
    func testAlternateThinkingTagsStrippedInGenerateText() async {
        let store = ConversationStore(storageDirectory: conversationStoreDir)
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore, conversationStore: store)
        vm.experimentalFlags.enableThinking = false
        mockEngine.isReady = true
        mockEngine.mockResponseChunks = ["<|think|>", "reasoning here", "</think>", "Final answer."]

        vm.prompt = "Question?"
        await vm.generateText()

        let content = vm.conversation.messages.last?.content ?? ""
        XCTAssertFalse(content.contains("<|think|>"), "Alternate thinking tags should be stripped")
        XCTAssertTrue(content.contains("Final answer."), "Non-thinking content should be preserved")
    }

    /// When thinking mode is enabled, <think> tags should be parsed into
    /// separate thinking content, not stripped.
    @MainActor
    func testThinkingContentParsedWhenEnabled() async {
        let store = ConversationStore(storageDirectory: conversationStoreDir)
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore, conversationStore: store)
        vm.experimentalFlags.enableThinking = true
        mockEngine.isReady = true
        mockEngine.mockResponseChunks = ["<think>", "I need to calculate", "</think>", "The answer is 4."]

        vm.prompt = "What is 2+2?"
        await vm.generateText()

        let lastMessage = vm.conversation.messages.last
        XCTAssertNotNil(lastMessage)
        // The response (non-thinking) content should have the answer
        XCTAssertTrue(
            lastMessage?.content.contains("The answer is 4.") ?? false,
            "Response content should contain the non-thinking portion"
        )
        // The thinking content should be captured separately
        XCTAssertNotNil(lastMessage?.thinkingContent, "Thinking content should be captured when thinking is enabled")
        XCTAssertTrue(
            lastMessage?.thinkingContent?.contains("I need to calculate") ?? false,
            "Thinking content should contain the reasoning text"
        )
    }

    // MARK: - T3: Vision/Audio Backend Configuration

    /// When a model supports vision, supportsVision=true should be passed to the engine.
    @MainActor
    func testVisionCapabilityPassedToEngine() async {
        let store = ConversationStore(storageDirectory: conversationStoreDir)
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore, conversationStore: store)

        // Load a known vision-capable model
        await vm.initializeEngine(modelPath: "/path/to/gemma-4-E2B-it.litertlm")

        let metadata = ModelRegistry.lookup(path: "/path/to/gemma-4-E2B-it.litertlm")
        if let metadata = metadata, metadata.supportsImage {
            XCTAssertTrue(
                mockEngine.lastSupportsVision,
                "supportsVision should be true for vision-capable models"
            )
        }
    }

    /// When a model does NOT support vision, supportsVision=false should be passed.
    @MainActor
    func testNonVisionModelPassesFalse() async {
        let store = ConversationStore(storageDirectory: conversationStoreDir)
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore, conversationStore: store)

        // Load an unknown model (not in registry)
        await vm.initializeEngine(modelPath: "/path/to/unknown-model.litertlm")

        XCTAssertFalse(
            mockEngine.lastSupportsVision,
            "supportsVision should be false for unknown models"
        )
        XCTAssertFalse(
            mockEngine.lastSupportsAudio,
            "supportsAudio should be false for unknown models"
        )
    }

    /// When multimodal data is attached, the multimodal sendMessageStream should be called.
    @MainActor
    func testMultimodalSendCalledWithImageData() async {
        let store = ConversationStore(storageDirectory: conversationStoreDir)
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore, conversationStore: store)
        mockEngine.isReady = true
        mockEngine.mockResponseChunks = ["I see an image."]

        vm.prompt = "Describe this image"
        vm.selectedImageData = Data([0xFF, 0xD8, 0xFF]) // Fake JPEG header

        await vm.generateText()

        XCTAssertEqual(mockEngine.multimodalSendCallCount, 1, "Should use multimodal send when image is attached")
        XCTAssertNotNil(mockEngine.lastImageData, "Image data should be passed to engine")
    }

    // MARK: - Conversation Auto-Save After Inference

    /// After generateText completes, the conversation should be auto-saved
    /// to the ConversationStore.
    @MainActor
    func testConversationAutoSavedAfterInference() async {
        let store = ConversationStore(storageDirectory: conversationStoreDir)
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore, conversationStore: store)
        mockEngine.isReady = true
        mockEngine.mockResponseChunks = ["Hello there!"]

        XCTAssertTrue(store.indexEntries.isEmpty, "Store should start empty")

        vm.prompt = "Hi"
        await vm.generateText()

        XCTAssertEqual(
            store.indexEntries.count, 1,
            "Conversation should be auto-saved after inference completes"
        )
    }

    /// Auto-save should NOT occur for archived (read-only) conversations.
    @MainActor
    func testNoAutoSaveForArchivedConversation() async {
        let store = ConversationStore(storageDirectory: conversationStoreDir)
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore, conversationStore: store)
        mockEngine.isReady = true
        mockEngine.mockResponseChunks = ["Hello!"]
        vm.isViewingArchivedConversation = true

        vm.prompt = "Hi"
        await vm.generateText()

        XCTAssertTrue(
            store.indexEntries.isEmpty,
            "Archived conversations should not be auto-saved"
        )
    }

    // MARK: - Sampler didSet Auto-Reinit

    /// Changing topK should trigger engine reinitialization via didSet.
    @MainActor
    func testTopKChangeTriggersReinit() async {
        let store = ConversationStore(storageDirectory: conversationStoreDir)
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore, conversationStore: store)
        // Use handleModelSelection so activeModelURL is set (required by reinitializeEngineIfNeeded guard)
        let testModelURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-model.litertlm")
        FileManager.default.createFile(atPath: testModelURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: testModelURL) }
        await vm.handleModelSelection(testModelURL)
        let initialCount = mockEngine.initializeCallCount

        vm.topK = 32
        // Give the async didSet task time to fire
        try? await Task.sleep(for: .milliseconds(500))

        XCTAssertGreaterThan(
            mockEngine.initializeCallCount, initialCount,
            "Changing topK should trigger engine reinitialization"
        )
    }

    /// Changing temperature should trigger engine reinitialization via didSet.
    @MainActor
    func testTemperatureChangeTriggersReinit() async {
        let store = ConversationStore(storageDirectory: conversationStoreDir)
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore, conversationStore: store)
        let testModelURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-model-temp.litertlm")
        FileManager.default.createFile(atPath: testModelURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: testModelURL) }
        await vm.handleModelSelection(testModelURL)
        let initialCount = mockEngine.initializeCallCount

        vm.temperature = 0.5
        try? await Task.sleep(for: .milliseconds(500))

        XCTAssertGreaterThan(
            mockEngine.initializeCallCount, initialCount,
            "Changing temperature should trigger engine reinitialization"
        )
    }

    /// Changing systemMessage should trigger engine reinitialization via didSet.
    @MainActor
    func testSystemMessageChangeTriggersReinit() async {
        let store = ConversationStore(storageDirectory: conversationStoreDir)
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore, conversationStore: store)
        let testModelURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-model-sys.litertlm")
        FileManager.default.createFile(atPath: testModelURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: testModelURL) }
        await vm.handleModelSelection(testModelURL)
        let initialCount = mockEngine.initializeCallCount

        vm.systemMessage = "You are a pirate."
        try? await Task.sleep(for: .milliseconds(500))

        XCTAssertGreaterThan(
            mockEngine.initializeCallCount, initialCount,
            "Changing systemMessage should trigger engine reinitialization"
        )
    }

    // MARK: - Pad Token Stripping

    /// <pad> tokens should be stripped from responses in all modes.
    @MainActor
    func testPadTokensStrippedFromResponse() async {
        let store = ConversationStore(storageDirectory: conversationStoreDir)
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore, conversationStore: store)
        vm.experimentalFlags.enableThinking = false
        mockEngine.isReady = true
        mockEngine.mockResponseChunks = ["Hello", "<pad>", " world", "<pad>"]

        vm.prompt = "Test"
        await vm.generateText()

        let content = vm.conversation.messages.last?.content ?? ""
        XCTAssertFalse(content.contains("<pad>"), "<pad> tokens should be stripped from response")
        XCTAssertTrue(content.contains("Hello"), "Non-pad content should be preserved")
        XCTAssertTrue(content.contains(" world"), "Non-pad content should be preserved")
    }

    // MARK: - Delete Confirmation State

    /// Verify that conversation deletion removes it from the store and clears active state.
    @MainActor
    func testDeleteConversationClearsActiveState() async {
        let store = ConversationStore(storageDirectory: conversationStoreDir)
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore, conversationStore: store)
        mockEngine.isReady = true
        mockEngine.mockResponseChunks = ["Hello!"]

        // Generate a conversation
        vm.prompt = "Hi"
        await vm.generateText()

        let savedId = vm.activeConversationId
        XCTAssertNotNil(savedId, "Should have an active conversation ID after inference")
        XCTAssertEqual(store.indexEntries.count, 1)

        // Delete it
        vm.deleteConversation(id: savedId!)

        XCTAssertNil(vm.activeConversationId, "Active conversation ID should be cleared after delete")
        XCTAssertTrue(store.indexEntries.isEmpty, "Store should be empty after delete")
    }

    // MARK: - Hint Card Badge Colors

    /// Verify that badge colors are distinct from each other.
    @MainActor
    func testBadgeColorsAreDistinct() {
        // These are the four badge colors used for hint cards
        let colors = [
            AppColors.accentCyan,       // Chat hint
            AppColors.badgeVision,      // Image hint
            AppColors.toolCall,         // Tools hint
            AppColors.badgeThinking     // Thinking hint
        ]

        // Verify all 4 colors are present and unique
        for i in 0..<colors.count {
            for j in (i + 1)..<colors.count {
                XCTAssertNotEqual(
                    colors[i], colors[j],
                    "Badge colors at indices \(i) and \(j) should be distinct"
                )
            }
        }
    }

    // MARK: - Benchmark Panel Default Expanded

    /// Verify benchmark stats panel defaults to expanded.
    @MainActor
    func testBenchmarkPanelDefaultExpanded() {
        let store = ConversationStore(storageDirectory: conversationStoreDir)
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore, conversationStore: store)
        XCTAssertTrue(
            vm.experimentalFlags.enableBenchmark,
            "Benchmark should be enabled by default"
        )
    }

    // MARK: - Conversation Fork

    /// Verify forking creates a new conversation with copied messages.
    @MainActor
    func testForkConversationCreatesNewEntry() async {
        let store = ConversationStore(storageDirectory: conversationStoreDir)
        let vm = ConversationViewModel(engine: mockEngine, metricsStore: metricsStore, conversationStore: store)
        mockEngine.isReady = true
        mockEngine.mockResponseChunks = ["Hello!"]

        // Generate a conversation
        vm.prompt = "Hi"
        await vm.generateText()

        let originalId = vm.activeConversationId!
        XCTAssertEqual(store.indexEntries.count, 1)

        // Fork it
        vm.forkConversation(id: originalId)

        XCTAssertEqual(store.indexEntries.count, 2, "Forking should create a second conversation")
        XCTAssertNotEqual(vm.activeConversationId, originalId, "Active ID should change to the fork")
        XCTAssertFalse(vm.isViewingArchivedConversation, "Fork should not be in archived mode")
    }
}
