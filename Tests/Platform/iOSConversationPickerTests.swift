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

// MARK: - iOS Conversation Picker Tests

/// Tests verifying the iOS conversation history picker functionality.
///
/// These tests ensure:
/// - ConversationStore can list saved conversations via indexEntries
/// - Conversations can be renamed via the store
/// - Conversations can be deleted via the store
/// - Index entries sort by lastModifiedAt descending
final class iOSConversationPickerTests: XCTestCase {

    private var tempDir: URL!
    private var store: ConversationStore!

    @MainActor
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("iOSConversationPickerTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = ConversationStore(storageDirectory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Listing

    @MainActor
    func testEmptyStoreHasNoEntries() {
        XCTAssertTrue(store.indexEntries.isEmpty, "Fresh store should have no entries")
    }

    @MainActor
    func testSavedConversationAppearsInIndex() throws {
        let conversation = makeTestConversation(title: "Test Chat")
        try store.save(conversation)
        XCTAssertEqual(store.indexEntries.count, 1)
        XCTAssertEqual(store.indexEntries.first?.title, "Test Chat")
    }

    @MainActor
    func testMultipleConversationsSortByLastModified() throws {
        let older = makeTestConversation(title: "Older", lastModifiedAt: Date().addingTimeInterval(-3600))
        let newer = makeTestConversation(title: "Newer", lastModifiedAt: Date())

        try store.save(older)
        try store.save(newer)

        XCTAssertEqual(store.indexEntries.count, 2)
        XCTAssertEqual(store.indexEntries.first?.title, "Newer", "Most recent should be first")
        XCTAssertEqual(store.indexEntries.last?.title, "Older")
    }

    // MARK: - Rename

    @MainActor
    func testRenameConversationUpdatesTitle() throws {
        let conversation = makeTestConversation(title: "Original Title")
        try store.save(conversation)

        try store.rename(id: conversation.id, newTitle: "Renamed Title")

        XCTAssertEqual(store.indexEntries.first?.title, "Renamed Title")
    }

    // MARK: - Delete

    @MainActor
    func testDeleteConversationRemovesFromIndex() throws {
        let conversation = makeTestConversation(title: "Delete Me")
        try store.save(conversation)
        XCTAssertEqual(store.indexEntries.count, 1)

        try store.delete(id: conversation.id)
        XCTAssertTrue(store.indexEntries.isEmpty, "Index should be empty after deletion")
    }

    // MARK: - Export

    @MainActor
    func testExportJSONReturnsData() throws {
        let conversation = makeTestConversation(title: "Export Test")
        try store.save(conversation)

        let data = try store.exportJSON(id: conversation.id)
        XCTAssertFalse(data.isEmpty, "Exported JSON should not be empty")

        // Verify it's valid JSON
        let json = try JSONSerialization.jsonObject(with: data)
        XCTAssertTrue(json is [String: Any], "Exported data should be a JSON object")
    }

    // MARK: - Index Entry Properties

    @MainActor
    func testIndexEntryContainsModelInfo() throws {
        let conversation = makeTestConversation(title: "Model Info Test")
        try store.save(conversation)

        let entry = try XCTUnwrap(store.indexEntries.first)
        XCTAssertFalse(entry.modelShortName.isEmpty, "Index entry should have a model name")
        XCTAssertGreaterThanOrEqual(entry.messageCount, 0, "Message count should be non-negative")
    }

    // MARK: - Helpers

    private func makeTestConversation(
        id: UUID = UUID(),
        title: String,
        lastModifiedAt: Date = Date()
    ) -> SavedConversation {
        let config = ExperimentConfig(
            modelName: "Test Model",
            modelFile: "test.litertlm",
            modelId: "test/test",
            architectureType: "Dense",
            modelVariant: "IT",
            backend: "GPU",
            didFallback: false,
            temperature: 1.0,
            topK: 64,
            topP: 0.95,
            seed: 0,
            thinkingEnabled: false,
            toolCallingEnabled: false,
            agentSkillsEnabled: false,
            mtpEnabled: false,
            benchmarkEnabled: false,
            systemMessage: nil,
            createdAt: lastModifiedAt.addingTimeInterval(-60)
        )

        let messages = [
            ChatMessage.user("Hello"),
            ChatMessage.assistant("Hi there!")
        ]

        let summary = ExperimentSummary.compute(from: messages)

        return SavedConversation(
            id: id,
            title: title,
            config: config,
            messages: messages,
            summary: summary,
            createdAt: lastModifiedAt.addingTimeInterval(-60),
            lastModifiedAt: lastModifiedAt,
            forkedFrom: nil
        )
    }
}
