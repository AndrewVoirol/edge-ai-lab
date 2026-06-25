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

// MARK: - Helpers

/// Creates a minimal `ExperimentConfig` for testing purposes.
/// Uses the memberwise init with sensible defaults.
private func makeConfig(modelName: String = "Gemma 4 E2B · Desktop GPU+CPU") -> ExperimentConfig {
    ExperimentConfig(
        modelName: modelName,
        modelFile: "gemma-4-E2B-it.litertlm",
        modelId: nil,
        architectureType: nil,
        modelVariant: nil,
        backend: "GPU",
        didFallback: false,
        temperature: 1.0,
        topK: 40,
        topP: 0.95,
        seed: 0,
        thinkingEnabled: false,
        toolCallingEnabled: false,
        agentSkillsEnabled: false,
        mtpEnabled: false,
        benchmarkEnabled: false,
        systemMessage: nil,
        createdAt: Date()
    )
}

/// Creates a `ChatMessage` with a specific role, content, and timestamp.
private func makeMessage(
    role: ChatMessage.Role,
    content: String,
    timestamp: Date = Date(),
    toolCalls: [ToolCallEvent] = [],
    benchmarkInfo: ChatMessage.BenchmarkSnapshot? = nil
) -> ChatMessage {
    ChatMessage(
        id: UUID(),
        role: role,
        content: content,
        thinkingContent: nil,
        toolCalls: toolCalls,
        attachments: [],
        timestamp: timestamp,
        benchmarkInfo: benchmarkInfo,
        isStreaming: false,
        thinkingWordCount: 0,
        specialResults: [:]
    )
}

/// Creates a `ToolCallEvent` for testing tool call counting.
private func makeToolCall(name: String = "test_tool") -> ToolCallEvent {
    ToolCallEvent(
        toolName: name,
        arguments: "{}",
        result: "{}",
        durationMs: 10.0,
        timestamp: Date(),
        succeeded: true
    )
}

// MARK: - ExperimentSummary Tests

@Suite("ExperimentSummary")
struct ExperimentSummaryTests {

    @Suite("Codable")
    struct CodableTests {

        @Test("Round-trip encodes and decodes all fields")
        func roundTrip() throws {
            let now = Date()
            let original = ExperimentSummary(
                averageDecodeSpeed: 42.5,
                totalTokens: 1000,
                messageCount: 6,
                lastActivityDate: now,
                totalToolCalls: 3,
                experimentDuration: 120.0
            )

            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(ExperimentSummary.self, from: data)

            #expect(decoded.averageDecodeSpeed == 42.5)
            #expect(decoded.totalTokens == 1000)
            #expect(decoded.messageCount == 6)
            #expect(decoded.totalToolCalls == 3)
            #expect(decoded.experimentDuration == 120.0)
            // Date comparison: allow sub-millisecond rounding from JSON
            #expect(abs(decoded.lastActivityDate.timeIntervalSince(now)) < 0.001)
        }

        @Test("Round-trip preserves nil optional fields")
        func roundTripWithNils() throws {
            let original = ExperimentSummary(
                averageDecodeSpeed: nil,
                totalTokens: 0,
                messageCount: 0,
                lastActivityDate: Date(),
                totalToolCalls: 0,
                experimentDuration: nil
            )

            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(ExperimentSummary.self, from: data)

            #expect(decoded.averageDecodeSpeed == nil)
            #expect(decoded.experimentDuration == nil)
        }
    }

    @Suite("compute(from:)")
    struct ComputeTests {

        @Test("Empty messages returns zeroed summary")
        func emptyMessages() {
            let summary = ExperimentSummary.compute(from: [])

            #expect(summary.messageCount == 0)
            #expect(summary.totalTokens == 0)
            #expect(summary.totalToolCalls == 0)
            #expect(summary.averageDecodeSpeed == nil)
            #expect(summary.experimentDuration == nil)
        }

        @Test("messageCount equals total number of messages")
        func messageCountAccuracy() {
            let messages = [
                makeMessage(role: .user, content: "Hello"),
                makeMessage(role: .assistant, content: "Hi"),
                makeMessage(role: .system, content: "System prompt"),
                makeMessage(role: .user, content: "Follow-up"),
                makeMessage(role: .assistant, content: "Response"),
            ]

            let summary = ExperimentSummary.compute(from: messages)
            #expect(summary.messageCount == 5)
        }

        @Test("totalToolCalls counts tool calls across all messages")
        func toolCallCounting() {
            let messages = [
                makeMessage(role: .user, content: "Do something", toolCalls: [makeToolCall()]),
                makeMessage(role: .assistant, content: "Done",
                           toolCalls: [makeToolCall(name: "tool_a"), makeToolCall(name: "tool_b")]),
                makeMessage(role: .user, content: "More"),
            ]

            let summary = ExperimentSummary.compute(from: messages)
            #expect(summary.totalToolCalls == 3)
        }

        @Test("experimentDuration computed from first to last message timestamp")
        func experimentDurationMultipleMessages() {
            let start = Date(timeIntervalSince1970: 1000)
            let mid = Date(timeIntervalSince1970: 1030)
            let end = Date(timeIntervalSince1970: 1060)

            let messages = [
                makeMessage(role: .user, content: "First", timestamp: start),
                makeMessage(role: .assistant, content: "Middle", timestamp: mid),
                makeMessage(role: .user, content: "Last", timestamp: end),
            ]

            let summary = ExperimentSummary.compute(from: messages)
            #expect(summary.experimentDuration == 60.0)
        }

        @Test("experimentDuration is nil with a single message")
        func experimentDurationSingleMessage() {
            let messages = [
                makeMessage(role: .user, content: "Only one"),
            ]

            let summary = ExperimentSummary.compute(from: messages)
            #expect(summary.experimentDuration == nil)
        }

        @Test("averageDecodeSpeed computed from assistant benchmarkInfo")
        func averageDecodeSpeed() {
            let bench1 = ChatMessage.BenchmarkSnapshot(
                decodeTokensPerSecond: 30.0, timeToFirstToken: 0.1, tokenCount: 100
            )
            let bench2 = ChatMessage.BenchmarkSnapshot(
                decodeTokensPerSecond: 50.0, timeToFirstToken: 0.2, tokenCount: 200
            )

            let messages = [
                makeMessage(role: .user, content: "Q1"),
                makeMessage(role: .assistant, content: "A1", benchmarkInfo: bench1),
                makeMessage(role: .user, content: "Q2"),
                makeMessage(role: .assistant, content: "A2", benchmarkInfo: bench2),
            ]

            let summary = ExperimentSummary.compute(from: messages)

            // Average: (30 + 50) / 2 = 40
            #expect(summary.averageDecodeSpeed == 40.0)
            // Total tokens: 100 + 200 = 300
            #expect(summary.totalTokens == 300)
        }

        @Test("averageDecodeSpeed is nil when no assistant has benchmarkInfo")
        func averageDecodeSpeedNilWithoutBenchmarks() {
            let messages = [
                makeMessage(role: .user, content: "Hello"),
                makeMessage(role: .assistant, content: "Hi"),
            ]

            let summary = ExperimentSummary.compute(from: messages)
            #expect(summary.averageDecodeSpeed == nil)
            #expect(summary.totalTokens == 0)
        }
    }
}

// MARK: - SavedConversation Tests

@Suite("SavedConversation")
struct SavedConversationTests {

    @Suite("generateTitle")
    struct GenerateTitleTests {

        @Test("Returns model name with 'New Experiment' when no user messages")
        func noUserMessages() {
            let config = makeConfig(modelName: "Gemma 4 E2B · Desktop")
            let messages = [
                makeMessage(role: .system, content: "System prompt"),
                makeMessage(role: .assistant, content: "Ready"),
            ]

            let title = SavedConversation.generateTitle(config: config, messages: messages)
            #expect(title == "E2B · New Experiment")
        }

        @Test("Returns model name with 'New Experiment' when user prompt is empty")
        func emptyPrompt() {
            let config = makeConfig(modelName: "Gemma 4 E2B · Desktop")
            let messages = [
                makeMessage(role: .user, content: "   "),
            ]

            let title = SavedConversation.generateTitle(config: config, messages: messages)
            #expect(title == "E2B · New Experiment")
        }

        @Test("Short prompt (under 40 chars) is not truncated")
        func shortPrompt() {
            let config = makeConfig(modelName: "Gemma 4 E2B · Desktop")
            let messages = [
                makeMessage(role: .user, content: "Explain quantum entanglement"),
            ]

            let title = SavedConversation.generateTitle(config: config, messages: messages)
            #expect(title == "E2B · Explain quantum entanglement")
        }

        @Test("Long prompt is truncated on word boundary with ellipsis")
        func longPromptTruncated() {
            let config = makeConfig(modelName: "Gemma 4 E2B · Desktop")
            let longPrompt = "Explain the differences between classical and quantum computing in simple terms please"
            let messages = [
                makeMessage(role: .user, content: longPrompt),
            ]

            let title = SavedConversation.generateTitle(config: config, messages: messages)

            // Title should start with model short name
            #expect(title.hasPrefix("E2B · "))

            // Should end with ellipsis (truncated)
            #expect(title.hasSuffix("…"))

            // The prompt portion (after "E2B · ") should be <= 41 chars (40 + ellipsis)
            let promptPart = String(title.dropFirst("E2B · ".count))
            // Truncated on word boundary: can't exceed 40 chars before the "…"
            let withoutEllipsis = String(promptPart.dropLast())
            #expect(withoutEllipsis.count <= 40)
        }

        @Test("Newlines in prompt are replaced with spaces")
        func newlinesReplaced() {
            let config = makeConfig(modelName: "Gemma 4 E2B · Desktop")
            let messages = [
                makeMessage(role: .user, content: "Line one\nLine two"),
            ]

            let title = SavedConversation.generateTitle(config: config, messages: messages)
            #expect(!title.contains("\n"))
            #expect(title.contains("Line one Line two"))
        }

        @Test("Uses first user message even when preceded by system/assistant")
        func firstUserMessageUsed() {
            let config = makeConfig(modelName: "Gemma 4 12B · Desktop")
            let messages = [
                makeMessage(role: .system, content: "You are helpful"),
                makeMessage(role: .assistant, content: "Hello!"),
                makeMessage(role: .user, content: "What is AI?"),
                makeMessage(role: .user, content: "Tell me more"),
            ]

            let title = SavedConversation.generateTitle(config: config, messages: messages)
            #expect(title == "12B · What is AI?")
        }
    }

    @Suite("Codable")
    struct CodableTests {

        @Test("Round-trip encodes and decodes a SavedConversation")
        func roundTrip() throws {
            let config = makeConfig()
            let now = Date()
            let forkedId = UUID()
            let messages = [
                makeMessage(role: .user, content: "Hello", timestamp: now),
            ]
            let summary = ExperimentSummary.compute(from: messages)

            let original = SavedConversation(
                id: UUID(),
                title: "E2B · Hello",
                config: config,
                messages: messages,
                summary: summary,
                createdAt: now,
                lastModifiedAt: now,
                forkedFrom: forkedId
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let data = try encoder.encode(original)
            let decoded = try decoder.decode(SavedConversation.self, from: data)

            #expect(decoded.id == original.id)
            #expect(decoded.title == "E2B · Hello")
            #expect(decoded.messages.count == 1)
            #expect(decoded.messages.first?.content == "Hello")
            #expect(decoded.summary.messageCount == 1)
            #expect(decoded.forkedFrom == forkedId)
            #expect(decoded.config.modelName == config.modelName)
            #expect(decoded.config.backend == "GPU")
        }

        @Test("Round-trip with forkedFrom nil")
        func roundTripForkedFromNil() throws {
            let config = makeConfig()
            let now = Date()
            let summary = ExperimentSummary.compute(from: [])

            let original = SavedConversation(
                id: UUID(),
                title: "Test",
                config: config,
                messages: [],
                summary: summary,
                createdAt: now,
                lastModifiedAt: now,
                forkedFrom: nil
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let data = try encoder.encode(original)
            let decoded = try decoder.decode(SavedConversation.self, from: data)

            #expect(decoded.forkedFrom == nil)
        }
    }
}
