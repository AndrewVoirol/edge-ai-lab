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

import Foundation
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - Conversation Property Tests

@Suite("Conversation Properties")
struct ConversationPropertySwiftTests {

    // MARK: - Helpers

    /// Create a minimal ExperimentConfig for testing.
    private static func makeConfig(
        modelName: String = "Gemma 4 E2B · Desktop GPU+CPU",
        backend: String = "GPU",
        thinkingEnabled: Bool = false,
        toolCallingEnabled: Bool = false
    ) -> ExperimentConfig {
        ExperimentConfig(
            modelName: modelName,
            modelFile: "gemma-4-E2B-it.litertlm",
            modelId: "litert-community/gemma-4-E2B-it-litert-lm",
            architectureType: "MoE Edge (2B effective)",
            modelVariant: "IT",
            backend: backend,
            didFallback: false,
            temperature: 1.0,
            topK: 40,
            topP: 0.95,
            seed: 0,
            thinkingEnabled: thinkingEnabled,
            toolCallingEnabled: toolCallingEnabled,
            agentSkillsEnabled: false,
            mtpEnabled: false,
            benchmarkEnabled: false,
            systemMessage: nil,
            createdAt: Date()
        )
    }

    /// Create a minimal ExperimentSummary for testing.
    private static func makeSummary(
        messageCount: Int = 2,
        totalTokens: Int = 100,
        averageDecodeSpeed: Double? = 30.0,
        totalToolCalls: Int = 0
    ) -> ExperimentSummary {
        ExperimentSummary(
            averageDecodeSpeed: averageDecodeSpeed,
            totalTokens: totalTokens,
            messageCount: messageCount,
            lastActivityDate: Date(),
            totalToolCalls: totalToolCalls,
            experimentDuration: 5.0
        )
    }

    /// Create a SavedConversation with controlled parameters.
    private static func makeConversation(
        title: String = "E2B · Test conversation",
        messages: [ChatMessage] = [.user("Hello"), .assistant("Hi there!")],
        config: ExperimentConfig? = nil,
        createdAt: Date = Date(),
        lastModifiedAt: Date = Date(),
        forkedFrom: UUID? = nil
    ) -> SavedConversation {
        let cfg = config ?? makeConfig()
        return SavedConversation(
            id: UUID(),
            title: title,
            config: cfg,
            messages: messages,
            summary: ExperimentSummary.compute(from: messages),
            createdAt: createdAt,
            lastModifiedAt: lastModifiedAt,
            forkedFrom: forkedFrom
        )
    }

    // MARK: - SavedConversation Stored Properties

    @Suite("SavedConversation Properties")
    struct SavedConversationTests {

        @Test("All stored properties are accessible after init")
        func storedProperties() {
            let id = UUID()
            let created = Date(timeIntervalSince1970: 1000)
            let modified = Date(timeIntervalSince1970: 2000)
            let forkId = UUID()
            let messages = [ChatMessage.user("Hello")]
            let config = makeConfig()
            let summary = makeSummary()

            let convo = SavedConversation(
                id: id,
                title: "Test Title",
                config: config,
                messages: messages,
                summary: summary,
                createdAt: created,
                lastModifiedAt: modified,
                forkedFrom: forkId
            )

            #expect(convo.id == id)
            #expect(convo.title == "Test Title")
            #expect(convo.messages.count == 1)
            #expect(convo.createdAt == created)
            #expect(convo.lastModifiedAt == modified)
            #expect(convo.forkedFrom == forkId)
        }

        @Test("forkedFrom is nil when not a fork")
        func forkedFromNil() {
            let convo = makeConversation(forkedFrom: nil)
            #expect(convo.forkedFrom == nil)
        }

        @Test("forkedFrom preserves UUID when set")
        func forkedFromPreserved() {
            let parentId = UUID()
            let convo = makeConversation(forkedFrom: parentId)
            #expect(convo.forkedFrom == parentId)
        }
    }

    // MARK: - SavedConversation Codable

    @Suite("SavedConversation Codable")
    struct SavedConversationCodableTests {

        private func makeEncoder() -> JSONEncoder {
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            return enc
        }

        private func makeDecoder() -> JSONDecoder {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            return dec
        }

        @Test("Round-trip preserves all fields")
        func fullRoundTrip() throws {
            let original = makeConversation(
                title: "E2B · Explain quantum entanglement"
            )
            let data = try makeEncoder().encode(original)
            let decoded = try makeDecoder().decode(SavedConversation.self, from: data)

            #expect(decoded.id == original.id)
            #expect(decoded.title == original.title)
            #expect(decoded.messages.count == original.messages.count)
            #expect(decoded.config.modelName == original.config.modelName)
            #expect(decoded.config.backend == original.config.backend)
            #expect(decoded.summary.messageCount == original.summary.messageCount)
        }

        @Test("Round-trip preserves forkedFrom UUID")
        func forkedFromRoundTrip() throws {
            let parentId = UUID()
            let original = makeConversation(forkedFrom: parentId)
            let data = try makeEncoder().encode(original)
            let decoded = try makeDecoder().decode(SavedConversation.self, from: data)

            #expect(decoded.forkedFrom == parentId)
        }

        @Test("Round-trip with nil forkedFrom")
        func nilForkedFromRoundTrip() throws {
            let original = makeConversation(forkedFrom: nil)
            let data = try makeEncoder().encode(original)
            let decoded = try makeDecoder().decode(SavedConversation.self, from: data)

            #expect(decoded.forkedFrom == nil)
        }

        @Test("Messages preserve role and content through round-trip")
        func messagesContentRoundTrip() throws {
            let messages: [ChatMessage] = [
                .user("What is 2+2?"),
                .assistant("The answer is 4."),
                .system("You are a math tutor"),
            ]
            let original = makeConversation(messages: messages)
            let data = try makeEncoder().encode(original)
            let decoded = try makeDecoder().decode(SavedConversation.self, from: data)

            #expect(decoded.messages.count == 3)
            #expect(decoded.messages[0].role == .user)
            #expect(decoded.messages[0].content == "What is 2+2?")
            #expect(decoded.messages[1].role == .assistant)
            #expect(decoded.messages[1].content == "The answer is 4.")
            #expect(decoded.messages[2].role == .system)
        }
    }

    // MARK: - ExperimentSummary.compute()

    @Suite("ExperimentSummary Compute")
    struct ExperimentSummaryComputeTests {

        @Test("Empty messages produce zero counts and nil speed")
        func emptyMessages() {
            let summary = ExperimentSummary.compute(from: [])
            #expect(summary.messageCount == 0)
            #expect(summary.totalTokens == 0)
            #expect(summary.averageDecodeSpeed == nil)
            #expect(summary.totalToolCalls == 0)
            #expect(summary.experimentDuration == nil)
        }

        @Test("Single user message has count 1 and nil speed")
        func singleUserMessage() {
            let messages = [ChatMessage.user("Hello")]
            let summary = ExperimentSummary.compute(from: messages)
            #expect(summary.messageCount == 1)
            #expect(summary.averageDecodeSpeed == nil)
            #expect(summary.totalTokens == 0)
            #expect(summary.experimentDuration == nil)
        }

        @Test("Assistant message with benchmark contributes to averageDecodeSpeed")
        func assistantWithBenchmark() {
            var msg = ChatMessage.assistant("Response")
            msg.benchmarkInfo = ChatMessage.BenchmarkSnapshot(
                decodeTokensPerSecond: 40.0,
                timeToFirstToken: 0.1,
                tokenCount: 50
            )
            let summary = ExperimentSummary.compute(from: [.user("Hi"), msg])
            #expect(summary.averageDecodeSpeed == 40.0)
            #expect(summary.totalTokens == 50)
            #expect(summary.messageCount == 2)
        }

        @Test("Multiple assistant messages average decode speed correctly")
        func multipleAssistantAverage() {
            var msg1 = ChatMessage.assistant("First")
            msg1.benchmarkInfo = ChatMessage.BenchmarkSnapshot(
                decodeTokensPerSecond: 20.0,
                timeToFirstToken: 0.2,
                tokenCount: 30
            )
            var msg2 = ChatMessage.assistant("Second")
            msg2.benchmarkInfo = ChatMessage.BenchmarkSnapshot(
                decodeTokensPerSecond: 60.0,
                timeToFirstToken: 0.1,
                tokenCount: 70
            )
            let summary = ExperimentSummary.compute(from: [.user("Q"), msg1, .user("Q2"), msg2])

            // Average of 20.0 and 60.0 = 40.0
            #expect(summary.averageDecodeSpeed == 40.0)
            #expect(summary.totalTokens == 100) // 30 + 70
            #expect(summary.messageCount == 4)
        }

        @Test("Tool calls are counted across all messages")
        func toolCallCounting() {
            var msg = ChatMessage.assistant("Result")
            msg.toolCalls = [
                ToolCallEvent(toolName: "calc", arguments: "{}", result: "4", durationMs: 1, timestamp: Date(), succeeded: true),
                ToolCallEvent(toolName: "fetch", arguments: "{}", result: "{}", durationMs: 2, timestamp: Date(), succeeded: true),
            ]
            let summary = ExperimentSummary.compute(from: [.user("Do stuff"), msg])
            #expect(summary.totalToolCalls == 2)
        }

        @Test("Experiment duration is nil when all messages share the same timestamp")
        func sameTimestampDuration() {
            let now = Date()
            let msg1 = ChatMessage(
                id: UUID(), role: .user, content: "A", thinkingContent: nil,
                toolCalls: [], attachments: [], timestamp: now,
                benchmarkInfo: nil, isStreaming: false, thinkingWordCount: 0, specialResults: [:]
            )
            let msg2 = ChatMessage(
                id: UUID(), role: .assistant, content: "B", thinkingContent: nil,
                toolCalls: [], attachments: [], timestamp: now,
                benchmarkInfo: nil, isStreaming: false, thinkingWordCount: 0, specialResults: [:]
            )
            let summary = ExperimentSummary.compute(from: [msg1, msg2])
            #expect(summary.experimentDuration == nil)
        }

        @Test("Experiment duration computed from first to last message timestamp")
        func durationComputed() {
            let start = Date(timeIntervalSince1970: 1000)
            let end = Date(timeIntervalSince1970: 1060)
            let msg1 = ChatMessage(
                id: UUID(), role: .user, content: "A", thinkingContent: nil,
                toolCalls: [], attachments: [], timestamp: start,
                benchmarkInfo: nil, isStreaming: false, thinkingWordCount: 0, specialResults: [:]
            )
            let msg2 = ChatMessage(
                id: UUID(), role: .assistant, content: "B", thinkingContent: nil,
                toolCalls: [], attachments: [], timestamp: end,
                benchmarkInfo: nil, isStreaming: false, thinkingWordCount: 0, specialResults: [:]
            )
            let summary = ExperimentSummary.compute(from: [msg1, msg2])
            #expect(summary.experimentDuration == 60.0)
        }
    }

    // MARK: - ExperimentSummary Codable

    @Suite("ExperimentSummary Codable")
    struct ExperimentSummaryCodableTests {

        @Test("Round-trip preserves all fields")
        func roundTrip() throws {
            let summary = ExperimentSummary(
                averageDecodeSpeed: 45.5,
                totalTokens: 300,
                messageCount: 6,
                lastActivityDate: Date(timeIntervalSince1970: 1000),
                totalToolCalls: 3,
                experimentDuration: 120.0
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let data = try encoder.encode(summary)
            let decoded = try decoder.decode(ExperimentSummary.self, from: data)

            #expect(decoded.averageDecodeSpeed == 45.5)
            #expect(decoded.totalTokens == 300)
            #expect(decoded.messageCount == 6)
            #expect(decoded.totalToolCalls == 3)
            #expect(decoded.experimentDuration == 120.0)
        }

        @Test("Nil averageDecodeSpeed round-trips as nil")
        func nilSpeedRoundTrip() throws {
            let summary = ExperimentSummary(
                averageDecodeSpeed: nil,
                totalTokens: 0,
                messageCount: 0,
                lastActivityDate: Date(),
                totalToolCalls: 0,
                experimentDuration: nil
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let data = try encoder.encode(summary)
            let decoded = try decoder.decode(ExperimentSummary.self, from: data)

            #expect(decoded.averageDecodeSpeed == nil)
            #expect(decoded.experimentDuration == nil)
        }
    }

    // MARK: - ConversationIndexEntry

    @Suite("ConversationIndexEntry")
    struct ConversationIndexEntryTests {

        @Test("Init from SavedConversation extracts all fields")
        func initFromConversation() {
            let config = makeConfig(
                modelName: "Gemma 4 E2B · Desktop GPU+CPU",
                thinkingEnabled: true,
                toolCallingEnabled: true
            )
            let messages: [ChatMessage] = [.user("Hello"), .assistant("Hi")]
            let convo = SavedConversation(
                id: UUID(),
                title: "E2B · Hello",
                config: config,
                messages: messages,
                summary: ExperimentSummary.compute(from: messages),
                createdAt: Date(timeIntervalSince1970: 1000),
                lastModifiedAt: Date(timeIntervalSince1970: 2000),
                forkedFrom: nil
            )

            let entry = ConversationIndexEntry(from: convo)

            #expect(entry.id == convo.id)
            #expect(entry.title == "E2B · Hello")
            #expect(entry.modelShortName == "E2B")
            #expect(entry.messageCount == 2)
            #expect(entry.createdAt == convo.createdAt)
            #expect(entry.lastModifiedAt == convo.lastModifiedAt)
            #expect(entry.forkedFrom == nil)
        }

        @Test("activeFeatureBadges reflects config flags")
        func featureBadges() {
            let config = makeConfig(thinkingEnabled: true, toolCallingEnabled: true)
            let convo = SavedConversation(
                id: UUID(),
                title: "Test",
                config: config,
                messages: [],
                summary: makeSummary(),
                createdAt: Date(),
                lastModifiedAt: Date(),
                forkedFrom: nil
            )
            let entry = ConversationIndexEntry(from: convo)

            #expect(entry.activeFeatureBadges.contains("Thinking"))
            #expect(entry.activeFeatureBadges.contains("Tools"))
        }

        @Test("configLightSummary includes model and backend")
        func lightSummary() {
            let config = makeConfig(modelName: "Gemma 4 E2B · Desktop", backend: "GPU")
            let convo = SavedConversation(
                id: UUID(),
                title: "Test",
                config: config,
                messages: [],
                summary: makeSummary(),
                createdAt: Date(),
                lastModifiedAt: Date(),
                forkedFrom: nil
            )
            let entry = ConversationIndexEntry(from: convo)

            #expect(entry.configLightSummary.contains("E2B"))
            #expect(entry.configLightSummary.contains("GPU"))
        }

        @Test("Codable round-trip preserves all fields")
        func codableRoundTrip() throws {
            let config = makeConfig(thinkingEnabled: true)
            let convo = makeConversation(config: config)
            let original = ConversationIndexEntry(from: convo)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let data = try encoder.encode(original)
            let decoded = try decoder.decode(ConversationIndexEntry.self, from: data)

            #expect(decoded.id == original.id)
            #expect(decoded.title == original.title)
            #expect(decoded.modelShortName == original.modelShortName)
            #expect(decoded.messageCount == original.messageCount)
            #expect(decoded.totalTokens == original.totalTokens)
            #expect(decoded.activeFeatureBadges == original.activeFeatureBadges)
        }

        @Test("forkedFrom round-trips through Codable")
        func forkedFromCodable() throws {
            let parentId = UUID()
            let convo = makeConversation(forkedFrom: parentId)
            let original = ConversationIndexEntry(from: convo)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let data = try encoder.encode(original)
            let decoded = try decoder.decode(ConversationIndexEntry.self, from: data)

            #expect(decoded.forkedFrom == parentId)
        }
    }

    // MARK: - SavedConversation.generateTitle

    @Suite("Smart Title Generation")
    struct TitleGenerationTests {

        @Test("Title with no user message produces 'New Experiment'")
        func noUserMessage() {
            let config = makeConfig(modelName: "Gemma 4 E2B · Desktop")
            let title = SavedConversation.generateTitle(config: config, messages: [])
            #expect(title.contains("New Experiment"))
            #expect(title.contains("E2B"))
        }

        @Test("Title with short prompt includes full prompt")
        func shortPrompt() {
            let config = makeConfig(modelName: "Gemma 4 E2B · Desktop")
            let messages = [ChatMessage.user("Explain gravity")]
            let title = SavedConversation.generateTitle(config: config, messages: messages)
            #expect(title.contains("Explain gravity"))
            #expect(title.contains("E2B"))
        }

        @Test("Title truncates long prompt on word boundary with ellipsis")
        func longPromptTruncation() {
            let config = makeConfig(modelName: "Gemma 4 E2B · Desktop")
            let longPrompt = "Explain quantum entanglement in simple terms that a five year old could understand"
            let messages = [ChatMessage.user(longPrompt)]
            let title = SavedConversation.generateTitle(config: config, messages: messages)

            // Should be truncated with "…"
            #expect(title.contains("…"))
            // Original 80+ chars should be truncated
            #expect(title.count < longPrompt.count + 10)
        }

        @Test("Title with empty user content produces 'New Experiment'")
        func emptyUserContent() {
            let config = makeConfig(modelName: "Gemma 4 E2B · Desktop")
            let messages = [ChatMessage.user("")]
            let title = SavedConversation.generateTitle(config: config, messages: messages)
            #expect(title.contains("New Experiment"))
        }

        @Test("Title removes newlines from prompt")
        func newlinesRemoved() {
            let config = makeConfig(modelName: "Gemma 4 E2B · Desktop")
            let messages = [ChatMessage.user("Hello\nWorld")]
            let title = SavedConversation.generateTitle(config: config, messages: messages)
            #expect(!title.contains("\n"))
            #expect(title.contains("Hello World"))
        }

        @Test("Title uses first user message, not system or assistant")
        func usesFirstUserMessage() {
            let config = makeConfig(modelName: "Gemma 4 E2B · Desktop")
            let messages: [ChatMessage] = [
                .system("You are helpful"),
                .user("What is Swift?"),
                .assistant("Swift is a programming language"),
            ]
            let title = SavedConversation.generateTitle(config: config, messages: messages)
            #expect(title.contains("What is Swift?"))
            #expect(!title.contains("You are helpful"))
        }
    }

    // MARK: - ConversationStoreError

    @Suite("ConversationStoreError")
    struct ConversationStoreErrorTests {

        @Test("Each error case produces a non-empty localized description")
        func errorDescriptions() {
            let underlying = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "disk full"])
            let testId = UUID()

            let errors: [ConversationStoreError] = [
                .saveFailed(underlying),
                .loadFailed(underlying),
                .deleteFailed(underlying),
                .notFound(testId),
            ]

            for error in errors {
                let description = error.errorDescription ?? ""
                #expect(!description.isEmpty, "Error description should not be empty for \(error)")
            }
        }

        @Test("notFound includes the UUID in description")
        func notFoundIncludesId() {
            let id = UUID()
            let error = ConversationStoreError.notFound(id)
            let description = error.errorDescription ?? ""
            #expect(description.contains(id.uuidString))
        }

        @Test("saveFailed includes underlying error message")
        func saveFailedIncludesUnderlying() {
            let underlying = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "no space left"])
            let error = ConversationStoreError.saveFailed(underlying)
            let description = error.errorDescription ?? ""
            #expect(description.contains("no space left"))
        }
    }
}
