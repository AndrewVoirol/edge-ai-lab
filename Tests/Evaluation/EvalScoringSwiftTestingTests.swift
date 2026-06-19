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

/// Swift Testing version of `EvalScoringTests` — validates all `ExpectedBehavior` scoring paths.
@Suite("EvalScorer Scoring Paths")
struct EvalScoringSwiftTestingTests {

    // MARK: - Helpers

    private static func makeToolCallEvent(
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

    // MARK: - containsText (Parameterized)

    /// Cases: (response, searchText, shouldPass)
    struct ContainsTextCase: CustomStringConvertible, Sendable {
        let response: String
        let searchText: String
        let shouldPass: Bool
        let label: String
        var description: String { label }
    }

    @Test(
        "containsText scoring",
        arguments: [
            ("The answer is 42", "42", true, "exact match"),
            ("HELLO WORLD", "hello", true, "case insensitive"),
            ("No match here", "xyz", false, "no match"),
        ] as [(String, String, Bool, String)]
    )
    func containsText(response: String, searchText: String, shouldPass: Bool, label: String) {
        let result = EvalScorer.score(
            response: response,
            toolCallEvents: [],
            against: .containsText(searchText)
        )
        if shouldPass {
            #expect(result.isPass, "Expected pass for '\(label)'")
        } else {
            #expect(result.isFailure, "Expected failure for '\(label)'")
        }
    }

    // MARK: - toolCall

    @Test("toolCall passes when correct tool is called")
    func toolCallPass() {
        let events = [Self.makeToolCallEvent(toolName: "calculate")]
        let result = EvalScorer.score(
            response: "The result is 42",
            toolCallEvents: events,
            against: .toolCall(toolName: "calculate")
        )
        #expect(result.isPass)
    }

    @Test("toolCall fails when wrong tool is called")
    func toolCallWrongTool() {
        let events = [Self.makeToolCallEvent(toolName: "other_tool")]
        let result = EvalScorer.score(
            response: "Done",
            toolCallEvents: events,
            against: .toolCall(toolName: "calculate")
        )
        #expect(result.isFailure)
    }

    @Test("toolCall fails when no tools are called")
    func toolCallNoToolsCalled() {
        let result = EvalScorer.score(
            response: "No tools used",
            toolCallEvents: [],
            against: .toolCall(toolName: "calculate")
        )
        #expect(result.isFailure)
        if case .fail(let reason) = result {
            #expect(reason.contains("no tools were called"))
        }
    }

    @Test("toolCall ignores failed tool executions")
    func toolCallFailedToolIgnored() {
        let events = [Self.makeToolCallEvent(toolName: "calculate", succeeded: false)]
        let result = EvalScorer.score(
            response: "Error occurred",
            toolCallEvents: events,
            against: .toolCall(toolName: "calculate")
        )
        #expect(result.isFailure)
    }

    // MARK: - toolCallWithArgs (Parameterized)

    @Test(
        "toolCallWithArgs scoring",
        arguments: [
            ("{\"expression\": \"2+2\"}", "expression", "2+2", true, "matching args"),
            ("{\"expression\": \"3+3\"}", "expression", "2+2", false, "wrong value"),
            ("{\"other_key\": \"value\"}", "expression", "2+2", false, "missing key"),
        ] as [(String, String, String, Bool, String)]
    )
    func toolCallWithArgs(
        arguments: String,
        key: String,
        expectedValue: String,
        shouldPass: Bool,
        label: String
    ) {
        let events = [Self.makeToolCallEvent(toolName: "calculate", arguments: arguments)]
        let result = EvalScorer.score(
            response: "Result",
            toolCallEvents: events,
            against: .toolCallWithArgs(toolName: "calculate", key: key, expectedValue: expectedValue)
        )
        if shouldPass {
            #expect(result.isPass, "Expected pass for '\(label)'")
        } else {
            #expect(result.isFailure, "Expected failure for '\(label)'")
        }
    }

    // MARK: - toolCallChain (Parameterized)

    @Test(
        "toolCallChain scoring",
        arguments: [
            (["get_date_time", "calculate"], ["get_date_time", "calculate"], true, "correct order"),
            (["calculate", "get_date_time"], ["get_date_time", "calculate"], false, "wrong order"),
            (["get_date_time"], ["get_date_time", "calculate"], false, "partial chain"),
        ] as [([String], [String], Bool, String)]
    )
    func toolCallChain(
        calledTools: [String],
        expectedChain: [String],
        shouldPass: Bool,
        label: String
    ) {
        let events = calledTools.map { Self.makeToolCallEvent(toolName: $0) }
        let result = EvalScorer.score(
            response: "Done",
            toolCallEvents: events,
            against: .toolCallChain(expectedChain)
        )
        if shouldPass {
            #expect(result.isPass, "Expected pass for '\(label)'")
        } else {
            #expect(result.isFailure, "Expected failure for '\(label)'")
        }
    }

    // MARK: - nonEmpty (Parameterized)

    @Test(
        "nonEmpty scoring",
        arguments: [
            ("Hello", true, "non-empty string"),
            ("", false, "empty string"),
            ("   \n  ", false, "whitespace only"),
        ] as [(String, Bool, String)]
    )
    func nonEmpty(response: String, shouldPass: Bool, label: String) {
        let result = EvalScorer.score(
            response: response,
            toolCallEvents: [],
            against: .nonEmpty
        )
        if shouldPass {
            #expect(result.isPass, "Expected pass for '\(label)'")
        } else {
            #expect(result.isFailure, "Expected failure for '\(label)'")
        }
    }

    // MARK: - matchesRegex

    @Test(
        "matchesRegex scoring",
        arguments: [
            ("The answer is 42", "\\d+", true, "digits found"),
            ("No numbers here", "\\d+", false, "no digits"),
        ] as [(String, String, Bool, String)]
    )
    func matchesRegex(response: String, pattern: String, shouldPass: Bool, label: String) {
        let result = EvalScorer.score(
            response: response,
            toolCallEvents: [],
            against: .matchesRegex(pattern)
        )
        if shouldPass {
            #expect(result.isPass, "Expected pass for '\(label)'")
        } else {
            #expect(result.isFailure, "Expected failure for '\(label)'")
        }
    }

    @Test("matchesRegex returns error for invalid pattern")
    func matchesRegexInvalidPattern() {
        let result = EvalScorer.score(
            response: "Some text",
            toolCallEvents: [],
            against: .matchesRegex("[")
        )
        if case .error = result {
            // Expected
        } else {
            Issue.record("Expected .error for invalid regex, got: \(result)")
        }
    }

    // MARK: - custom

    @Test("custom behavior returns manualReviewNeeded")
    func customReturnsManualReviewNeeded() {
        let result = EvalScorer.score(
            response: "Some response",
            toolCallEvents: [],
            against: .custom(description: "Check quality")
        )
        if case .manualReviewNeeded = result {
            // Expected
        } else {
            Issue.record("Expected .manualReviewNeeded for custom behavior, got: \(result)")
        }
    }
}
