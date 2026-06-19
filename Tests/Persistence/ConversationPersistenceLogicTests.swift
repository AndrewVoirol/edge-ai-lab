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

// MARK: - Test Helpers

/// Builds a minimal `ExperimentConfig` for title-generation tests.
/// Only `modelName` matters for `generateTitle` (via `modelShortName`).
private func makeConfig(modelName: String = "Gemma 4 E2B · Desktop GPU+CPU") -> ExperimentConfig {
    ExperimentConfig(
        modelName: modelName,
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
        thinkingEnabled: false,
        toolCallingEnabled: false,
        agentSkillsEnabled: false,
        mtpEnabled: false,
        benchmarkEnabled: true,
        systemMessage: nil,
        createdAt: Date()
    )
}

/// Builds a `ChatMessage` with explicit role, content, timestamp,
/// optional benchmark info, and optional tool calls.
private func makeMessage(
    role: ChatMessage.Role,
    content: String = "",
    timestamp: Date = Date(),
    benchmark: ChatMessage.BenchmarkSnapshot? = nil,
    toolCalls: [ToolCallEvent] = []
) -> ChatMessage {
    ChatMessage(
        id: UUID(),
        role: role,
        content: content,
        thinkingContent: nil,
        toolCalls: toolCalls,
        attachments: [],
        timestamp: timestamp,
        benchmarkInfo: benchmark,
        isStreaming: false,
        thinkingWordCount: 0,
        specialResults: [:]
    )
}

/// Builds a `ToolCallEvent` stub.
private func makeToolCall() -> ToolCallEvent {
    ToolCallEvent(
        toolName: "test_tool",
        arguments: "{}",
        result: "{}",
        durationMs: 10.0,
        timestamp: Date(),
        succeeded: true
    )
}

// MARK: - Suite

@Suite("Conversation Persistence Logic")
struct ConversationPersistenceLogicSwiftTests {

    // =========================================================================
    // MARK: - SavedConversation.generateTitle
    // =========================================================================

    @Suite("generateTitle")
    struct GenerateTitle {

        private let config = makeConfig()

        // MARK: Fallback to "New Experiment"

        @Test("No user messages returns model · New Experiment")
        func noUserMessages() {
            let title = SavedConversation.generateTitle(
                config: config,
                messages: []
            )
            #expect(title == "E2B · New Experiment")
        }

        @Test("System-only messages returns model · New Experiment")
        func systemOnlyMessages() {
            let messages = [makeMessage(role: .system, content: "You are a helpful assistant.")]
            let title = SavedConversation.generateTitle(config: config, messages: messages)
            #expect(title == "E2B · New Experiment")
        }

        @Test("Empty user message content returns model · New Experiment")
        func emptyUserMessage() {
            let messages = [makeMessage(role: .user, content: "")]
            let title = SavedConversation.generateTitle(config: config, messages: messages)
            #expect(title == "E2B · New Experiment")
        }

        @Test("Whitespace-only user message returns model · New Experiment")
        func whitespaceOnlyUserMessage() {
            let messages = [makeMessage(role: .user, content: "   \n\t  ")]
            let title = SavedConversation.generateTitle(config: config, messages: messages)
            #expect(title == "E2B · New Experiment")
        }

        // MARK: Short prompts (≤ 40 chars)

        @Test("Short prompt is included verbatim")
        func shortPrompt() {
            let messages = [makeMessage(role: .user, content: "What is quantum computing?")]
            let title = SavedConversation.generateTitle(config: config, messages: messages)
            #expect(title == "E2B · What is quantum computing?")
        }

        @Test("Exactly 40-char prompt is not truncated")
        func exactly40Chars() {
            // Exactly 40 characters
            let prompt = String(repeating: "a", count: 35) + " word"
            #expect(prompt.count == 40)
            let messages = [makeMessage(role: .user, content: prompt)]
            let title = SavedConversation.generateTitle(config: config, messages: messages)
            #expect(title == "E2B · \(prompt)")
        }

        // MARK: Long prompts (> 40 chars)

        @Test("Long prompt truncated at word boundary with ellipsis")
        func longPromptWordBoundary() {
            let prompt = "Explain the theory of general relativity in simple terms please"
            #expect(prompt.count > 40)
            let messages = [makeMessage(role: .user, content: prompt)]
            let title = SavedConversation.generateTitle(config: config, messages: messages)
            // The 40-char prefix is "Explain the theory of general relativity"
            // Last space is before "relativity", so it truncates there
            #expect(title.hasPrefix("E2B · "))
            #expect(title.hasSuffix("…"))
            #expect(!title.contains("simple"))
        }

        @Test("Long prompt with no spaces truncates at 40 chars with ellipsis")
        func longPromptNoSpaces() {
            let prompt = String(repeating: "x", count: 50)
            let messages = [makeMessage(role: .user, content: prompt)]
            let title = SavedConversation.generateTitle(config: config, messages: messages)
            // Should be "E2B · " + 40 x's + "…"
            let expected = "E2B · " + String(repeating: "x", count: 40) + "…"
            #expect(title == expected)
        }

        // MARK: Newline handling

        @Test("Newlines in prompt replaced with spaces")
        func newlinesReplacedWithSpaces() {
            let prompt = "Line one\nLine two"
            let messages = [makeMessage(role: .user, content: prompt)]
            let title = SavedConversation.generateTitle(config: config, messages: messages)
            #expect(title == "E2B · Line one Line two")
            #expect(!title.contains("\n"))
        }

        // MARK: Multiple messages

        @Test("Uses first user message, not subsequent ones")
        func usesFirstUserMessage() {
            let messages = [
                makeMessage(role: .system, content: "System prompt"),
                makeMessage(role: .user, content: "First question"),
                makeMessage(role: .assistant, content: "Answer"),
                makeMessage(role: .user, content: "Second question"),
            ]
            let title = SavedConversation.generateTitle(config: config, messages: messages)
            #expect(title == "E2B · First question")
        }

        // MARK: Model short name variants

        @Test("12B model name renders correctly")
        func model12B() {
            let cfg = makeConfig(modelName: "Gemma 4 12B · Desktop GPU")
            let messages = [makeMessage(role: .user, content: "Hello")]
            let title = SavedConversation.generateTitle(config: cfg, messages: messages)
            #expect(title == "12B · Hello")
        }

        @Test("E4B model name renders correctly")
        func modelE4B() {
            let cfg = makeConfig(modelName: "Gemma 4 E4B · Desktop GPU+CPU")
            let messages = [makeMessage(role: .user, content: "Hello")]
            let title = SavedConversation.generateTitle(config: cfg, messages: messages)
            #expect(title == "E4B · Hello")
        }

        @Test("Fallback model name uses first word")
        func modelFallback() {
            let cfg = makeConfig(modelName: "CustomModel v2")
            let messages = [makeMessage(role: .user, content: "Hello")]
            let title = SavedConversation.generateTitle(config: cfg, messages: messages)
            #expect(title == "CustomModel · Hello")
        }
    }

    // =========================================================================
    // MARK: - ExperimentSummary.compute
    // =========================================================================

    @Suite("ExperimentSummary.compute")
    struct ComputeSummary {

        // MARK: Empty messages

        @Test("Empty message array yields zeroed summary with nil optionals")
        func emptyMessages() {
            let summary = ExperimentSummary.compute(from: [])
            #expect(summary.messageCount == 0)
            #expect(summary.averageDecodeSpeed == nil)
            #expect(summary.totalTokens == 0)
            #expect(summary.totalToolCalls == 0)
            #expect(summary.experimentDuration == nil)
        }

        // MARK: Single user message

        @Test("Single user message: count 1, nil speed, nil duration")
        func singleUserMessage() {
            let msg = makeMessage(role: .user, content: "Hello")
            let summary = ExperimentSummary.compute(from: [msg])
            #expect(summary.messageCount == 1)
            #expect(summary.averageDecodeSpeed == nil)
            #expect(summary.totalTokens == 0)
            #expect(summary.experimentDuration == nil)
        }

        // MARK: Single assistant with benchmark

        @Test("Single assistant with benchmark returns its speed and token count")
        func singleAssistantWithBenchmark() {
            let benchmark = ChatMessage.BenchmarkSnapshot(
                decodeTokensPerSecond: 42.0,
                timeToFirstToken: 0.1,
                tokenCount: 100
            )
            let msg = makeMessage(role: .assistant, content: "Response", benchmark: benchmark)
            let summary = ExperimentSummary.compute(from: [msg])
            #expect(summary.messageCount == 1)
            #expect(summary.averageDecodeSpeed == 42.0)
            #expect(summary.totalTokens == 100)
        }

        // MARK: Assistant without benchmark

        @Test("Assistant without benchmark: nil speed, 0 tokens")
        func assistantWithoutBenchmark() {
            let msg = makeMessage(role: .assistant, content: "Response")
            let summary = ExperimentSummary.compute(from: [msg])
            #expect(summary.messageCount == 1)
            #expect(summary.averageDecodeSpeed == nil)
            #expect(summary.totalTokens == 0)
        }

        // MARK: Multiple assistants — averaged speed

        @Test("Multiple assistants: decode speed is averaged, tokens are summed")
        func multipleAssistantsAveraged() {
            let b1 = ChatMessage.BenchmarkSnapshot(
                decodeTokensPerSecond: 30.0,
                timeToFirstToken: 0.1,
                tokenCount: 80
            )
            let b2 = ChatMessage.BenchmarkSnapshot(
                decodeTokensPerSecond: 50.0,
                timeToFirstToken: 0.2,
                tokenCount: 120
            )
            let messages = [
                makeMessage(role: .assistant, content: "R1", benchmark: b1),
                makeMessage(role: .assistant, content: "R2", benchmark: b2),
            ]
            let summary = ExperimentSummary.compute(from: messages)
            #expect(summary.averageDecodeSpeed == 40.0) // (30+50)/2
            #expect(summary.totalTokens == 200)          // 80+120
        }

        // MARK: Tool calls

        @Test("Tool calls counted across all messages")
        func toolCallsCounted() {
            let tc1 = makeToolCall()
            let tc2 = makeToolCall()
            let tc3 = makeToolCall()
            let messages = [
                makeMessage(role: .user, content: "Q1", toolCalls: [tc1]),
                makeMessage(role: .assistant, content: "A1", toolCalls: [tc2, tc3]),
            ]
            let summary = ExperimentSummary.compute(from: messages)
            #expect(summary.totalToolCalls == 3)
        }

        @Test("No tool calls yields zero")
        func noToolCalls() {
            let messages = [makeMessage(role: .user, content: "Hello")]
            let summary = ExperimentSummary.compute(from: messages)
            #expect(summary.totalToolCalls == 0)
        }

        // MARK: Duration

        @Test("Two messages with different timestamps yield correct duration")
        func durationFromTwoMessages() {
            let t1 = Date(timeIntervalSince1970: 1000)
            let t2 = Date(timeIntervalSince1970: 1060)
            let messages = [
                makeMessage(role: .user, content: "Q", timestamp: t1),
                makeMessage(role: .assistant, content: "A", timestamp: t2),
            ]
            let summary = ExperimentSummary.compute(from: messages)
            #expect(summary.experimentDuration == 60.0)
        }

        @Test("Single message yields nil duration (first == last)")
        func singleMessageNilDuration() {
            let t = Date(timeIntervalSince1970: 1000)
            let messages = [makeMessage(role: .user, content: "Q", timestamp: t)]
            let summary = ExperimentSummary.compute(from: messages)
            #expect(summary.experimentDuration == nil)
        }

        @Test("Two messages with identical timestamps yield nil duration")
        func identicalTimestampsNilDuration() {
            let t = Date(timeIntervalSince1970: 1000)
            let messages = [
                makeMessage(role: .user, content: "Q", timestamp: t),
                makeMessage(role: .assistant, content: "A", timestamp: t),
            ]
            let summary = ExperimentSummary.compute(from: messages)
            #expect(summary.experimentDuration == nil)
        }

        // MARK: Last activity date

        @Test("lastActivityDate is the timestamp of the last message")
        func lastActivityDate() {
            let t1 = Date(timeIntervalSince1970: 1000)
            let t2 = Date(timeIntervalSince1970: 2000)
            let messages = [
                makeMessage(role: .user, content: "Q", timestamp: t1),
                makeMessage(role: .assistant, content: "A", timestamp: t2),
            ]
            let summary = ExperimentSummary.compute(from: messages)
            #expect(summary.lastActivityDate == t2)
        }

        // MARK: Mixed scenario

        @Test("Mixed user/assistant/system messages compute all fields correctly")
        func mixedScenario() {
            let t1 = Date(timeIntervalSince1970: 0)
            let t2 = Date(timeIntervalSince1970: 5)
            let t3 = Date(timeIntervalSince1970: 10)
            let t4 = Date(timeIntervalSince1970: 15)

            let bench = ChatMessage.BenchmarkSnapshot(
                decodeTokensPerSecond: 25.0,
                timeToFirstToken: 0.3,
                tokenCount: 50
            )
            let tc = makeToolCall()

            let messages = [
                makeMessage(role: .system, content: "System", timestamp: t1),
                makeMessage(role: .user, content: "Question", timestamp: t2),
                makeMessage(role: .assistant, content: "Answer", timestamp: t3,
                            benchmark: bench, toolCalls: [tc]),
                makeMessage(role: .user, content: "Follow-up", timestamp: t4),
            ]
            let summary = ExperimentSummary.compute(from: messages)
            #expect(summary.messageCount == 4)
            #expect(summary.averageDecodeSpeed == 25.0)
            #expect(summary.totalTokens == 50)
            #expect(summary.totalToolCalls == 1)
            #expect(summary.experimentDuration == 15.0)
            #expect(summary.lastActivityDate == t4)
        }
    }
}
