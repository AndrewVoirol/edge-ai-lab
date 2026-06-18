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

/// Tests for `ConversationStore` — the JSON file-based persistence layer.
///
/// Uses a temporary directory for each test to ensure isolation and prevent
/// interference with the real conversation storage.
final class ConversationStoreTests: XCTestCase {

    /// Temporary directory for test storage — cleaned up in tearDown.
    private var tempDir: URL!
    private var store: ConversationStore!

    @MainActor
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConversationStoreTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = ConversationStore(storageDirectory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Save & Load

    @MainActor
    func testSaveAndLoadConversation() throws {
        let conversation = makeTestConversation(title: "Test Save & Load")
        try store.save(conversation)

        let loaded = try store.load(id: conversation.id)
        XCTAssertEqual(loaded.id, conversation.id)
        XCTAssertEqual(loaded.title, conversation.title)
        XCTAssertEqual(loaded.messages.count, conversation.messages.count)
        XCTAssertEqual(loaded.config.modelName, conversation.config.modelName)
    }

    @MainActor
    func testSaveUpdatesIndex() throws {
        let conversation = makeTestConversation(title: "Index Test")
        XCTAssertTrue(store.indexEntries.isEmpty)

        try store.save(conversation)
        XCTAssertEqual(store.indexEntries.count, 1)
        XCTAssertEqual(store.indexEntries.first?.title, "Index Test")
    }

    @MainActor
    func testSaveExistingConversationUpdatesInPlace() throws {
        let id = UUID()
        let v1 = makeTestConversation(id: id, title: "Version 1")
        try store.save(v1)
        XCTAssertEqual(store.indexEntries.count, 1)

        let v2 = SavedConversation(
            id: id,
            title: "Version 2",
            config: v1.config,
            messages: v1.messages,
            summary: v1.summary,
            createdAt: v1.createdAt,
            lastModifiedAt: Date(),
            forkedFrom: nil
        )
        try store.save(v2)
        XCTAssertEqual(store.indexEntries.count, 1)
        XCTAssertEqual(store.indexEntries.first?.title, "Version 2")
    }

    // MARK: - Delete

    @MainActor
    func testDeleteRemovesFileAndIndex() throws {
        let conversation = makeTestConversation(title: "Delete Me")
        try store.save(conversation)
        XCTAssertEqual(store.indexEntries.count, 1)

        try store.delete(id: conversation.id)
        XCTAssertEqual(store.indexEntries.count, 0)

        XCTAssertThrowsError(try store.load(id: conversation.id))
    }

    @MainActor
    func testDeleteNonexistentIdDoesNotThrow() throws {
        try store.delete(id: UUID())
    }

    // MARK: - Rename

    @MainActor
    func testRenameUpdatesTitle() throws {
        let conversation = makeTestConversation(title: "Old Title")
        try store.save(conversation)

        try store.rename(id: conversation.id, newTitle: "New Title")

        let loaded = try store.load(id: conversation.id)
        XCTAssertEqual(loaded.title, "New Title")
        XCTAssertEqual(store.indexEntries.first?.title, "New Title")
    }

    // MARK: - Export

    @MainActor
    func testExportReturnsValidJSON() throws {
        let conversation = makeTestConversation(title: "Export Test")
        try store.save(conversation)

        let data = try store.exportJSON(id: conversation.id)
        XCTAssertGreaterThan(data.count, 0)

        // Verify it's valid JSON by decoding
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SavedConversation.self, from: data)
        XCTAssertEqual(decoded.id, conversation.id)
    }

    @MainActor
    func testExportNonexistentThrows() {
        XCTAssertThrowsError(try store.exportJSON(id: UUID()))
    }

    // MARK: - Load Nonexistent

    @MainActor
    func testLoadNonexistentThrows() {
        XCTAssertThrowsError(try store.load(id: UUID()))
    }

    // MARK: - Index Sorting

    @MainActor
    func testIndexSortedByLastModifiedDescending() throws {
        let earlier = makeTestConversation(title: "Earlier", lastModifiedAt: Date(timeIntervalSinceNow: -3600))
        let later = makeTestConversation(title: "Later", lastModifiedAt: Date())

        try store.save(earlier)
        try store.save(later)

        XCTAssertEqual(store.indexEntries.count, 2)
        XCTAssertEqual(store.indexEntries.first?.title, "Later")
        XCTAssertEqual(store.indexEntries.last?.title, "Earlier")
    }

    // MARK: - Index Persistence

    @MainActor
    func testIndexPersistedAndReloaded() throws {
        let conversation = makeTestConversation(title: "Persist Index")
        try store.save(conversation)

        // Create a new store pointing at the same directory
        let store2 = ConversationStore(storageDirectory: tempDir)
        XCTAssertEqual(store2.indexEntries.count, 1)
        XCTAssertEqual(store2.indexEntries.first?.title, "Persist Index")
    }

    // MARK: - Multiple Conversations

    @MainActor
    func testMultipleConversations() throws {
        for i in 0..<5 {
            let conv = makeTestConversation(title: "Conv \(i)")
            try store.save(conv)
        }
        XCTAssertEqual(store.indexEntries.count, 5)
    }

    // MARK: - Helpers

    private func makeTestConversation(
        id: UUID = UUID(),
        title: String = "Test",
        lastModifiedAt: Date = Date()
    ) -> SavedConversation {
        let config = ExperimentConfig(
            modelName: "Test Model E2B",
            modelFile: "test-model.litertlm",
            modelId: "test/test-model",
            architectureType: "Dense",
            modelVariant: "IT",
            backend: "GPU",
            didFallback: false,
            temperature: 1.0,
            topK: 64,
            topP: 0.95,
            seed: 0,
            thinkingEnabled: true,
            toolCallingEnabled: false,
            agentSkillsEnabled: false,
            mtpEnabled: false,
            benchmarkEnabled: true,
            systemMessage: nil,
            createdAt: Date()
        )

        let messages = [
            ChatMessage.user("Hello, how are you?"),
            ChatMessage.assistant("I'm doing well, thank you for asking!")
        ]

        let summary = ExperimentSummary.compute(from: messages)

        return SavedConversation(
            id: id,
            title: title,
            config: config,
            messages: messages,
            summary: summary,
            createdAt: Date(),
            lastModifiedAt: lastModifiedAt,
            forkedFrom: nil
        )
    }
}
