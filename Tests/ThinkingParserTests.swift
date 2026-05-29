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
@testable import GemmaEdgeGallery_iOS
#elseif os(macOS)
@testable import GemmaEdgeGallery_macOS
#endif

// MARK: - Thinking Parser Tests

final class ThinkingParserTests: XCTestCase {

    // MARK: - Basic Parsing (Static API)

    func testNoThinkTags() {
        let (thinking, response) = ThinkingParser.parse("Just a normal response")
        XCTAssertEqual(thinking, "")
        XCTAssertEqual(response, "Just a normal response")
    }

    func testSimpleThinkBlock() {
        let (thinking, response) = ThinkingParser.parse("<think>Let me reason</think>The answer is 42")
        XCTAssertEqual(thinking, "Let me reason")
        XCTAssertEqual(response, "The answer is 42")
    }

    func testAlternateThinkTag() {
        let (thinking, response) = ThinkingParser.parse("<|think|>Reasoning here</think>Answer")
        XCTAssertEqual(thinking, "Reasoning here")
        XCTAssertEqual(response, "Answer")
    }

    func testThinkAtStart() {
        let (thinking, response) = ThinkingParser.parse("<think>First think</think>Response")
        XCTAssertEqual(thinking, "First think")
        XCTAssertEqual(response, "Response")
    }

    func testMultipleThinkBlocks() {
        let text = "<think>Block1</think>Middle<think>Block2</think>End"
        let (thinking, response) = ThinkingParser.parse(text)
        XCTAssertEqual(thinking, "Block1Block2")
        XCTAssertEqual(response, "MiddleEnd")
    }

    func testEmptyInput() {
        let (thinking, response) = ThinkingParser.parse("")
        XCTAssertEqual(thinking, "")
        XCTAssertEqual(response, "")
    }

    func testOnlyThinking() {
        let (thinking, response) = ThinkingParser.parse("<think>Just thinking</think>")
        XCTAssertEqual(thinking, "Just thinking")
        XCTAssertEqual(response, "")
    }

    // MARK: - Streaming Tests

    func testStreamingSplitTag() {
        var parser = ThinkingParser()
        // Tag split across chunks: "<thi" + "nk>"
        let s1 = parser.feed("Hello <thi")
        let s2 = parser.feed("nk>reasoning")
        let s3 = parser.feed("</think>done")
        let s4 = parser.finalize()

        let allSegments = s1 + s2 + s3 + s4
        let thinking = allSegments.filter { $0.isThinking }.map { $0.text }.joined()
        let response = allSegments.filter { !$0.isThinking }.map { $0.text }.joined()

        XCTAssertEqual(thinking, "reasoning")
        XCTAssertEqual(response, "Hello done")
    }

    func testStreamingMultipleChunks() {
        var parser = ThinkingParser()
        let chunks = ["<think>", "step ", "1", "</think>", "answer"]
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
        XCTAssertEqual(thinking, "step 1")
        XCTAssertEqual(response, "answer")
    }

    // Test that non-think angle brackets pass through as response text
    func testHtmlTagsNotConfused() {
        let (thinking, response) = ThinkingParser.parse("Use <div> and <span> tags")
        XCTAssertEqual(thinking, "")
        XCTAssertEqual(response, "Use <div> and <span> tags")
    }

    func testResetParser() {
        var parser = ThinkingParser()
        _ = parser.feed("<think>partial")
        parser.reset()
        let segments = parser.feed("clean start") + parser.finalize()
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.text, "clean start")
        XCTAssertFalse(segments.first?.isThinking ?? true)
    }

    // MARK: - Gemma 4 Thought Channel Wrapping Tests
    // These simulate the pattern InstrumentedEngine produces when the SDK
    // returns thinking via channels["thought"] — we wrap it in <think></think>
    // and the parser should handle it correctly.

    func testThoughtChannelWrapping_BasicPattern() {
        // Simulates: engine yields "<think>", then thought text, then "</think>", then response
        var parser = ThinkingParser()
        var thinking = ""
        var response = ""

        let chunks = ["<think>", "Let me reason about this.", "</think>", "The answer is 42."]
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

        XCTAssertEqual(thinking, "Let me reason about this.")
        XCTAssertEqual(response, "The answer is 42.")
    }

    func testThoughtChannelWrapping_MultiChunkThought() {
        // Simulates: thought channel sends many small chunks before response
        var parser = ThinkingParser()
        var thinking = ""
        var response = ""

        let chunks = ["<think>", "Step 1: ", "Analyze. ", "Step 2: ", "Compute.", "</think>", "Result: 7"]
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

        XCTAssertEqual(thinking, "Step 1: Analyze. Step 2: Compute.")
        XCTAssertEqual(response, "Result: 7")
    }

    func testThoughtChannelWrapping_ThinkOnlyNoResponse() {
        // Edge case: model thinks but never produces a response
        var parser = ThinkingParser()
        var thinking = ""
        var response = ""

        for chunk in ["<think>", "Reasoning...", "</think>"] {
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

        XCTAssertEqual(thinking, "Reasoning...")
        XCTAssertEqual(response, "")
    }

    // MARK: - System Message Composition Tests

    func testThinkingSystemMessageComposition() {
        // When thinking is enabled, system message should contain <|think|>
        let thinkingTrigger = "<|think|>"
        let userSystemMessage = ""

        let parts = [
            thinkingTrigger,
            userSystemMessage.isEmpty ? nil : userSystemMessage
        ].compactMap { $0 }
        let composed = parts.joined(separator: "\n")

        XCTAssertEqual(composed, "<|think|>")
    }

    func testThinkingSystemMessageWithUserMessage() {
        // When thinking is enabled AND user has a custom system message
        let thinkingTrigger = "<|think|>"
        let userSystemMessage = "You are a helpful coding assistant."

        let parts: [String?] = [
            thinkingTrigger,
            userSystemMessage.isEmpty ? nil : userSystemMessage
        ]
        let composed = parts.compactMap { $0 }.joined(separator: "\n")

        XCTAssertEqual(composed, "<|think|>\nYou are a helpful coding assistant.")
    }

    func testNoThinkingSystemMessageWhenDisabled() {
        // When thinking is disabled, system message should be nil or just user's
        let enableThinking = false
        let userSystemMessage = ""

        let parts: [String?] = [
            enableThinking ? "<|think|>" : nil,
            userSystemMessage.isEmpty ? nil : userSystemMessage
        ]
        let filtered = parts.compactMap { $0 }
        let composed: String? = filtered.isEmpty ? nil : filtered.joined(separator: "\n")

        XCTAssertNil(composed)
    }
}
