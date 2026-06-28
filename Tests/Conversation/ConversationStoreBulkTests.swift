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

/// Tests for `ConversationStore` bulk delete operations:
/// `deleteAll()`, `deleteMultiple(ids:)`, and `deleteOlderThan(_:)`.
///
/// Uses a temporary directory for each test to ensure isolation.
final class ConversationStoreBulkTests: XCTestCase {

    private var tempDir: URL!
    private var store: ConversationStore!

    @MainActor
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConversationStoreBulkTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = ConversationStore(storageDirectory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - deleteAll

    @MainActor
    func testDeleteAllRemovesAllConversations() throws {
        try store.save(makeTestConversation(title: "First"))
        try store.save(makeTestConversation(title: "Second"))
        try store.save(makeTestConversation(title: "Third"))
        XCTAssertEqual(store.indexEntries.count, 3)

        let count = try store.deleteAll()
        XCTAssertEqual(count, 3)
        XCTAssertTrue(store.indexEntries.isEmpty)
    }

    @MainActor
    func testDeleteAllOnEmptyStoreReturnsZero() throws {
        XCTAssertTrue(store.indexEntries.isEmpty)
        let count = try store.deleteAll()
        XCTAssertEqual(count, 0)
    }

    @MainActor
    func testDeleteAllRemovesFilesFromDisk() throws {
        let conv = makeTestConversation(title: "Disk Check")
        try store.save(conv)

        let fileURL = tempDir.appendingPathComponent("\(conv.id.uuidString).json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        _ = try store.deleteAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    // MARK: - deleteMultiple

    @MainActor
    func testDeleteMultipleRemovesSpecifiedConversations() throws {
        let conv1 = makeTestConversation(title: "Keep")
        let conv2 = makeTestConversation(title: "Delete Me 1")
        let conv3 = makeTestConversation(title: "Delete Me 2")
        try store.save(conv1)
        try store.save(conv2)
        try store.save(conv3)
        XCTAssertEqual(store.indexEntries.count, 3)

        let count = try store.deleteMultiple(ids: [conv2.id, conv3.id])
        XCTAssertEqual(count, 2)
        XCTAssertEqual(store.indexEntries.count, 1)
        XCTAssertEqual(store.indexEntries.first?.id, conv1.id)
    }

    @MainActor
    func testDeleteMultipleWithEmptySetIsNoop() throws {
        try store.save(makeTestConversation(title: "Survivor"))
        XCTAssertEqual(store.indexEntries.count, 1)

        let count = try store.deleteMultiple(ids: [])
        XCTAssertEqual(count, 0)
        XCTAssertEqual(store.indexEntries.count, 1)
    }

    @MainActor
    func testDeleteMultipleWithNonexistentIdsSucceeds() throws {
        try store.save(makeTestConversation(title: "Still Here"))
        let count = try store.deleteMultiple(ids: [UUID(), UUID()])
        // Non-existent files count as "deleted" (file already gone)
        XCTAssertEqual(count, 2)
        XCTAssertEqual(store.indexEntries.count, 1)
    }

    // MARK: - deleteOlderThan

    @MainActor
    func testDeleteOlderThanRemovesOldConversations() throws {
        let oldDate = Calendar.current.date(byAdding: .day, value: -60, to: Date())!
        let recentDate = Date()

        let oldConv = makeTestConversation(title: "Old Chat", lastModifiedAt: oldDate)
        let recentConv = makeTestConversation(title: "Recent Chat", lastModifiedAt: recentDate)
        try store.save(oldConv)
        try store.save(recentConv)
        XCTAssertEqual(store.indexEntries.count, 2)

        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let count = try store.deleteOlderThan(cutoff)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(store.indexEntries.count, 1)
        XCTAssertEqual(store.indexEntries.first?.title, "Recent Chat")
    }

    @MainActor
    func testDeleteOlderThanWithNoOldConversationsReturnsZero() throws {
        let recentConv = makeTestConversation(title: "Just Now", lastModifiedAt: Date())
        try store.save(recentConv)

        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let count = try store.deleteOlderThan(cutoff)
        XCTAssertEqual(count, 0)
        XCTAssertEqual(store.indexEntries.count, 1)
    }

    @MainActor
    func testDeleteOlderThanWithAllOldConversationsDeletesAll() throws {
        let oldDate = Calendar.current.date(byAdding: .day, value: -100, to: Date())!
        try store.save(makeTestConversation(title: "Old 1", lastModifiedAt: oldDate))
        try store.save(makeTestConversation(title: "Old 2", lastModifiedAt: oldDate))

        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let count = try store.deleteOlderThan(cutoff)
        XCTAssertEqual(count, 2)
        XCTAssertTrue(store.indexEntries.isEmpty)
    }

    // MARK: - Index Persistence After Bulk Delete

    @MainActor
    func testDeleteAllPersistsEmptyIndex() throws {
        try store.save(makeTestConversation(title: "Temp"))
        _ = try store.deleteAll()

        // Re-create store from same directory to verify index persistence
        let newStore = ConversationStore(storageDirectory: tempDir)
        XCTAssertTrue(newStore.indexEntries.isEmpty)
    }

    @MainActor
    func testDeleteMultiplePersistsSurvivors() throws {
        let survivor = makeTestConversation(title: "Survivor")
        let victim = makeTestConversation(title: "Victim")
        try store.save(survivor)
        try store.save(victim)

        _ = try store.deleteMultiple(ids: [victim.id])

        // Re-create store from same directory
        let newStore = ConversationStore(storageDirectory: tempDir)
        XCTAssertEqual(newStore.indexEntries.count, 1)
        XCTAssertEqual(newStore.indexEntries.first?.id, survivor.id)
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
            createdAt: Date(),
            lastModifiedAt: lastModifiedAt,
            forkedFrom: nil
        )
    }
}
