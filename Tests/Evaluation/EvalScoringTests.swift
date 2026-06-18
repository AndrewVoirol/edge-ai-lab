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
import XCTest

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Tests for `EvalScorer.score()` — validates all `ExpectedBehavior` scoring paths.
final class EvalScoringTests: XCTestCase {

    // MARK: - containsText

    func testContainsText_pass() {
        let result = EvalScorer.score(
            response: "The answer is 42",
            toolCallEvents: [],
            against: .containsText("42")
        )
        XCTAssertTrue(result.isPass)
    }

    func testContainsText_caseInsensitive() {
        let result = EvalScorer.score(
            response: "HELLO WORLD",
            toolCallEvents: [],
            against: .containsText("hello")
        )
        XCTAssertTrue(result.isPass)
    }

    func testContainsText_fail() {
        let result = EvalScorer.score(
            response: "No match here",
            toolCallEvents: [],
            against: .containsText("xyz")
        )
        XCTAssertTrue(result.isFailure)
    }

    // MARK: - toolCall

    func testToolCall_pass() {
        let events = [makeToolCallEvent(toolName: "calculate")]
        let result = EvalScorer.score(
            response: "The result is 42",
            toolCallEvents: events,
            against: .toolCall(toolName: "calculate")
        )
        XCTAssertTrue(result.isPass)
    }

    func testToolCall_wrongTool() {
        let events = [makeToolCallEvent(toolName: "other_tool")]
        let result = EvalScorer.score(
            response: "Done",
            toolCallEvents: events,
            against: .toolCall(toolName: "calculate")
        )
        XCTAssertTrue(result.isFailure)
    }

    func testToolCall_noToolsCalled() {
        let result = EvalScorer.score(
            response: "No tools used",
            toolCallEvents: [],
            against: .toolCall(toolName: "calculate")
        )
        XCTAssertTrue(result.isFailure)
        if case .fail(let reason) = result {
            XCTAssertTrue(reason.contains("no tools were called"), "Expected 'no tools were called' in reason: \(reason)")
        }
    }

    func testToolCall_failedToolIgnored() {
        let events = [makeToolCallEvent(toolName: "calculate", succeeded: false)]
        let result = EvalScorer.score(
            response: "Error occurred",
            toolCallEvents: events,
            against: .toolCall(toolName: "calculate")
        )
        XCTAssertTrue(result.isFailure)
    }

    // MARK: - toolCallWithArgs

    func testToolCallWithArgs_pass() {
        let events = [makeToolCallEvent(toolName: "calculate", arguments: "{\"expression\": \"2+2\"}")]
        let result = EvalScorer.score(
            response: "4",
            toolCallEvents: events,
            against: .toolCallWithArgs(toolName: "calculate", key: "expression", expectedValue: "2+2")
        )
        XCTAssertTrue(result.isPass)
    }

    func testToolCallWithArgs_wrongValue() {
        let events = [makeToolCallEvent(toolName: "calculate", arguments: "{\"expression\": \"3+3\"}")]
        let result = EvalScorer.score(
            response: "6",
            toolCallEvents: events,
            against: .toolCallWithArgs(toolName: "calculate", key: "expression", expectedValue: "2+2")
        )
        XCTAssertTrue(result.isFailure)
    }

    func testToolCallWithArgs_missingKey() {
        let events = [makeToolCallEvent(toolName: "calculate", arguments: "{\"other_key\": \"value\"}")]
        let result = EvalScorer.score(
            response: "Result",
            toolCallEvents: events,
            against: .toolCallWithArgs(toolName: "calculate", key: "expression", expectedValue: "2+2")
        )
        XCTAssertTrue(result.isFailure)
    }

    // MARK: - toolCallChain

    func testToolCallChain_pass() {
        let events = [
            makeToolCallEvent(toolName: "get_date_time"),
            makeToolCallEvent(toolName: "calculate"),
        ]
        let result = EvalScorer.score(
            response: "Done",
            toolCallEvents: events,
            against: .toolCallChain(["get_date_time", "calculate"])
        )
        XCTAssertTrue(result.isPass)
    }

    func testToolCallChain_wrongOrder() {
        let events = [
            makeToolCallEvent(toolName: "calculate"),
            makeToolCallEvent(toolName: "get_date_time"),
        ]
        let result = EvalScorer.score(
            response: "Done",
            toolCallEvents: events,
            against: .toolCallChain(["get_date_time", "calculate"])
        )
        XCTAssertTrue(result.isFailure)
    }

    func testToolCallChain_partial() {
        let events = [makeToolCallEvent(toolName: "get_date_time")]
        let result = EvalScorer.score(
            response: "Done",
            toolCallEvents: events,
            against: .toolCallChain(["get_date_time", "calculate"])
        )
        XCTAssertTrue(result.isFailure)
    }

    // MARK: - nonEmpty

    func testNonEmpty_pass() {
        let result = EvalScorer.score(
            response: "Hello",
            toolCallEvents: [],
            against: .nonEmpty
        )
        XCTAssertTrue(result.isPass)
    }

    func testNonEmpty_fail_empty() {
        let result = EvalScorer.score(
            response: "",
            toolCallEvents: [],
            against: .nonEmpty
        )
        XCTAssertTrue(result.isFailure)
    }

    func testNonEmpty_fail_whitespace() {
        let result = EvalScorer.score(
            response: "   \n  ",
            toolCallEvents: [],
            against: .nonEmpty
        )
        XCTAssertTrue(result.isFailure)
    }

    // MARK: - matchesRegex

    func testMatchesRegex_pass() {
        let result = EvalScorer.score(
            response: "The answer is 42",
            toolCallEvents: [],
            against: .matchesRegex("\\d+")
        )
        XCTAssertTrue(result.isPass)
    }

    func testMatchesRegex_fail() {
        let result = EvalScorer.score(
            response: "No numbers here",
            toolCallEvents: [],
            against: .matchesRegex("\\d+")
        )
        XCTAssertTrue(result.isFailure)
    }

    func testMatchesRegex_invalidPattern() {
        let result = EvalScorer.score(
            response: "Some text",
            toolCallEvents: [],
            against: .matchesRegex("[")
        )
        if case .error = result {
            // Expected
        } else {
            XCTFail("Expected .error for invalid regex, got: \(result)")
        }
    }

    // MARK: - custom

    func testCustom_returnsManualReviewNeeded() {
        let result = EvalScorer.score(
            response: "Some response",
            toolCallEvents: [],
            against: .custom(description: "Check quality")
        )
        if case .manualReviewNeeded = result {
            // Expected
        } else {
            XCTFail("Expected .manualReviewNeeded for custom behavior, got: \(result)")
        }
    }

    // MARK: - Helpers

    private func makeToolCallEvent(
        toolName: String,
        arguments: String = "{}",
        result: String = "",
        succeeded: Bool = true
    ) -> ToolCallEvent {
        ToolCallEvent(
            toolName: toolName,
            arguments: arguments,
            result: result,
            durationMs: 10,
            timestamp: Date(),
            succeeded: succeeded
        )
    }
}
