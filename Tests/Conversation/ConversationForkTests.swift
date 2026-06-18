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

/// Tests for conversation forking, smart title generation, and experiment summary computation.
final class ConversationForkTests: XCTestCase {

    // MARK: - Smart Title Generation

    func testSmartTitleWithUserMessage() {
        let config = makeTestConfig(modelName: "Gemma 4 E2B")
        let messages = [ChatMessage.user("Explain quantum entanglement")]
        let title = SavedConversation.generateTitle(config: config, messages: messages)
        XCTAssertTrue(title.hasPrefix("E2B"))
        XCTAssertTrue(title.contains("Explain quantum entanglement"))
    }

    func testSmartTitleTruncatesLongPrompt() {
        let config = makeTestConfig(modelName: "Gemma 4 12B")
        let longPrompt = "This is a very long prompt that should be truncated at a word boundary because it exceeds the maximum length"
        let messages = [ChatMessage.user(longPrompt)]
        let title = SavedConversation.generateTitle(config: config, messages: messages)
        XCTAssertTrue(title.hasPrefix("12B"))
        XCTAssertTrue(title.contains("…"))
        XCTAssertLessThan(title.count, 60)  // 12B prefix + separator + truncated text
    }

    func testSmartTitleNoUserMessage() {
        let config = makeTestConfig(modelName: "Gemma 4 E4B")
        let messages: [ChatMessage] = []
        let title = SavedConversation.generateTitle(config: config, messages: messages)
        XCTAssertEqual(title, "E4B · New Experiment")
    }

    func testSmartTitleEmptyPrompt() {
        let config = makeTestConfig(modelName: "Gemma 4 E2B")
        let messages = [ChatMessage.user("")]
        let title = SavedConversation.generateTitle(config: config, messages: messages)
        XCTAssertEqual(title, "E2B · New Experiment")
    }

    // MARK: - Experiment Summary

    func testSummaryComputeFromMessages() {
        let messages = [
            ChatMessage.user("Hello"),
            ChatMessage.assistant("Hi there!"),
            ChatMessage.user("How are you?"),
            ChatMessage.assistant("I'm good!")
        ]
        let summary = ExperimentSummary.compute(from: messages)
        XCTAssertEqual(summary.messageCount, 4)
        XCTAssertEqual(summary.totalToolCalls, 0)
    }

    func testSummaryWithBenchmarkData() {
        var msg1 = ChatMessage.assistant("Response 1")
        msg1.benchmarkInfo = ChatMessage.BenchmarkSnapshot(
            decodeTokensPerSecond: 10.0,
            timeToFirstToken: 0.5,
            tokenCount: 100
        )
        var msg2 = ChatMessage.assistant("Response 2")
        msg2.benchmarkInfo = ChatMessage.BenchmarkSnapshot(
            decodeTokensPerSecond: 20.0,
            timeToFirstToken: 0.3,
            tokenCount: 200
        )

        let messages = [ChatMessage.user("Q1"), msg1, ChatMessage.user("Q2"), msg2]
        let summary = ExperimentSummary.compute(from: messages)

        XCTAssertNotNil(summary.averageDecodeSpeed)
        XCTAssertEqual(summary.averageDecodeSpeed!, 15.0, accuracy: 0.1)
        XCTAssertEqual(summary.totalTokens, 300)
    }

    func testSummaryEmptyMessages() {
        let summary = ExperimentSummary.compute(from: [])
        XCTAssertEqual(summary.messageCount, 0)
        XCTAssertNil(summary.averageDecodeSpeed)
        XCTAssertEqual(summary.totalToolCalls, 0)
    }

    // MARK: - Conversation Fork Round-Trip

    @MainActor
    func testForkCreatesNewId() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForkTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = ConversationStore(storageDirectory: tempDir)
        let original = makeTestConversation(title: "Original")
        try store.save(original)

        // Fork: create new ID, same content, reference original
        let forkedId = UUID()
        let forked = SavedConversation(
            id: forkedId,
            title: "Fork of \(original.title)",
            config: original.config,
            messages: original.messages,
            summary: original.summary,
            createdAt: Date(),
            lastModifiedAt: Date(),
            forkedFrom: original.id
        )
        try store.save(forked)

        XCTAssertEqual(store.indexEntries.count, 2)

        let loadedFork = try store.load(id: forkedId)
        XCTAssertEqual(loadedFork.forkedFrom, original.id)
        XCTAssertNotEqual(loadedFork.id, original.id)
        XCTAssertEqual(loadedFork.messages.count, original.messages.count)
    }

    // MARK: - Helpers

    private func makeTestConfig(modelName: String = "Test Model") -> ExperimentConfig {
        ExperimentConfig(
            modelName: modelName,
            modelFile: "test.litertlm",
            modelId: nil,
            architectureType: nil,
            modelVariant: nil,
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
            benchmarkEnabled: false,
            systemMessage: nil,
            createdAt: Date()
        )
    }

    private func makeTestConversation(title: String) -> SavedConversation {
        let config = makeTestConfig()
        let messages = [
            ChatMessage.user("Hello"),
            ChatMessage.assistant("Hi!")
        ]
        let summary = ExperimentSummary.compute(from: messages)
        return SavedConversation(
            id: UUID(),
            title: title,
            config: config,
            messages: messages,
            summary: summary,
            createdAt: Date(),
            lastModifiedAt: Date(),
            forkedFrom: nil
        )
    }
}
