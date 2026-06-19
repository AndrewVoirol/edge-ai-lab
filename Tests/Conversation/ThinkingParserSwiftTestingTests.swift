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

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - Thinking Parser Swift Testing Tests

@Suite("ThinkingParser")
struct ThinkingParserSwiftTestingTests {

    // MARK: - Basic Parsing (Static API) — Parameterized

    /// Each case: (label, input, expectedThinking, expectedResponse)
    @Test(
        "Static parse extracts thinking and response correctly",
        arguments: [
            ("no think tags", "Just a normal response", "", "Just a normal response"),
            ("simple think block", "<think>Let me reason</think>The answer is 42", "Let me reason", "The answer is 42"),
            ("alternate think tag", "<|think|>Reasoning here</think>Answer", "Reasoning here", "Answer"),
            ("think at start", "<think>First think</think>Response", "First think", "Response"),
            ("multiple think blocks", "<think>Block1</think>Middle<think>Block2</think>End", "Block1Block2", "MiddleEnd"),
            ("empty input", "", "", ""),
            ("only thinking", "<think>Just thinking</think>", "Just thinking", ""),
            ("HTML tags not confused", "Use <div> and <span> tags", "", "Use <div> and <span> tags"),
        ] as [(String, String, String, String)]
    )
    func staticParse(label: String, input: String, expectedThinking: String, expectedResponse: String) {
        let (thinking, response) = ThinkingParser.parse(input)
        #expect(thinking == expectedThinking, "Thinking mismatch for '\(label)'")
        #expect(response == expectedResponse, "Response mismatch for '\(label)'")
    }

    // MARK: - Streaming Tests

    /// Helper: feeds chunks into a parser and collects thinking/response strings.
    private static func feedChunks(_ chunks: [String]) -> (thinking: String, response: String) {
        var parser = ThinkingParser()
        var thinking = ""
        var response = ""
        for chunk in chunks {
            for segment in parser.feed(chunk) {
                switch segment {
                case .thinking(let t): thinking += t
                case .response(let t): response += t
                }
            }
        }
        for segment in parser.finalize() {
            switch segment {
            case .thinking(let t): thinking += t
            case .response(let t): response += t
            }
        }
        return (thinking, response)
    }

    @Test("Streaming handles tag split across chunks")
    func streamingSplitTag() {
        var parser = ThinkingParser()
        let s1 = parser.feed("Hello <thi")
        let s2 = parser.feed("nk>reasoning")
        let s3 = parser.feed("</think>done")
        let s4 = parser.finalize()

        let allSegments = s1 + s2 + s3 + s4
        let thinking = allSegments.filter { $0.isThinking }.map { $0.text }.joined()
        let response = allSegments.filter { !$0.isThinking }.map { $0.text }.joined()

        #expect(thinking == "reasoning")
        #expect(response == "Hello done")
    }

    @Test("Streaming handles multiple chunks correctly")
    func streamingMultipleChunks() {
        let (thinking, response) = Self.feedChunks(["<think>", "step ", "1", "</think>", "answer"])
        #expect(thinking == "step 1")
        #expect(response == "answer")
    }

    @Test("Reset parser clears state for clean start")
    func resetParser() {
        var parser = ThinkingParser()
        _ = parser.feed("<think>partial")
        parser.reset()
        let segments = parser.feed("clean start") + parser.finalize()
        #expect(segments.count == 1)
        #expect(segments.first?.text == "clean start")
        #expect(!(segments.first?.isThinking ?? true))
    }

    // MARK: - Gemma 4 Thought Channel Wrapping Tests (Parameterized)

    @Test(
        "Thought channel wrapping patterns parse correctly",
        arguments: [
            (
                "basic pattern",
                ["<think>", "Let me reason about this.", "</think>", "The answer is 42."],
                "Let me reason about this.",
                "The answer is 42."
            ),
            (
                "multi-chunk thought",
                ["<think>", "Step 1: ", "Analyze. ", "Step 2: ", "Compute.", "</think>", "Result: 7"],
                "Step 1: Analyze. Step 2: Compute.",
                "Result: 7"
            ),
            (
                "think only, no response",
                ["<think>", "Reasoning...", "</think>"],
                "Reasoning...",
                ""
            ),
        ] as [(String, [String], String, String)]
    )
    func thoughtChannelWrapping(
        label: String,
        chunks: [String],
        expectedThinking: String,
        expectedResponse: String
    ) {
        let (thinking, response) = Self.feedChunks(chunks)
        #expect(thinking == expectedThinking, "Thinking mismatch for '\(label)'")
        #expect(response == expectedResponse, "Response mismatch for '\(label)'")
    }

    // MARK: - System Message Composition Tests

    @Test("Thinking system message is just the trigger when user message is empty")
    func thinkingSystemMessageComposition() {
        let thinkingTrigger = "<|think|>"
        let userSystemMessage = ""

        let parts = [
            thinkingTrigger,
            userSystemMessage.isEmpty ? nil : userSystemMessage,
        ].compactMap { $0 }
        let composed = parts.joined(separator: "\n")

        #expect(composed == "<|think|>")
    }

    @Test("Thinking system message combines trigger and user message")
    func thinkingSystemMessageWithUserMessage() {
        let thinkingTrigger = "<|think|>"
        let userSystemMessage = "You are a helpful coding assistant."

        let parts: [String?] = [
            thinkingTrigger,
            userSystemMessage.isEmpty ? nil : userSystemMessage,
        ]
        let composed = parts.compactMap { $0 }.joined(separator: "\n")

        #expect(composed == "<|think|>\nYou are a helpful coding assistant.")
    }

    @Test("No system message when thinking is disabled and user message is empty")
    func noThinkingSystemMessageWhenDisabled() {
        let enableThinking = false
        let userSystemMessage = ""

        var parts: [String] = []
        if enableThinking {
            parts.append("<|think|>")
        }
        if !userSystemMessage.isEmpty {
            parts.append(userSystemMessage)
        }
        let composed: String? = parts.isEmpty ? nil : parts.joined(separator: "\n")

        #expect(composed == nil)
    }
}
