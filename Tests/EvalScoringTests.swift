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
@testable import GemmaEdgeGallery_iOS
#elseif os(macOS)
@testable import GemmaEdgeGallery_macOS
#endif

/// Tests for `EvalRunner.score()` — validates all `ExpectedBehavior` scoring paths.
final class EvalScoringTests: XCTestCase {

    private var mockEngine: MockInstrumentedEngine!
    private var evalStore: EvalStore!
    private var tempDir: URL!
    private var evalRunner: EvalRunner!

    @MainActor
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EvalScoringTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        mockEngine = MockInstrumentedEngine()
        evalStore = EvalStore(storageDirectory: tempDir)
        evalRunner = EvalRunner(engine: mockEngine, store: evalStore)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - containsText

    @MainActor
    func testContainsText_pass() {
        let result = evalRunner.score(
            response: "The answer is 42",
            toolCallEvents: [],
            against: .containsText("42")
        )
        XCTAssertTrue(result.isPass)
    }

    @MainActor
    func testContainsText_caseInsensitive() {
        let result = evalRunner.score(
            response: "HELLO WORLD",
            toolCallEvents: [],
            against: .containsText("hello")
        )
        XCTAssertTrue(result.isPass)
    }

    @MainActor
    func testContainsText_fail() {
        let result = evalRunner.score(
            response: "No match here",
            toolCallEvents: [],
            against: .containsText("xyz")
        )
        XCTAssertTrue(result.isFailure)
    }

    // MARK: - toolCall

    @MainActor
    func testToolCall_pass() {
        let events = [makeToolCallEvent(toolName: "calculate")]
        let result = evalRunner.score(
            response: "The result is 42",
            toolCallEvents: events,
            against: .toolCall(toolName: "calculate")
        )
        XCTAssertTrue(result.isPass)
    }

    @MainActor
    func testToolCall_wrongTool() {
        let events = [makeToolCallEvent(toolName: "other_tool")]
        let result = evalRunner.score(
            response: "Done",
            toolCallEvents: events,
            against: .toolCall(toolName: "calculate")
        )
        XCTAssertTrue(result.isFailure)
    }

    @MainActor
    func testToolCall_noToolsCalled() {
        let result = evalRunner.score(
            response: "No tools used",
            toolCallEvents: [],
            against: .toolCall(toolName: "calculate")
        )
        XCTAssertTrue(result.isFailure)
        if case .fail(let reason) = result {
            XCTAssertTrue(reason.contains("no tools were called"), "Expected 'no tools were called' in reason: \(reason)")
        }
    }

    @MainActor
    func testToolCall_failedToolIgnored() {
        let events = [makeToolCallEvent(toolName: "calculate", succeeded: false)]
        let result = evalRunner.score(
            response: "Error occurred",
            toolCallEvents: events,
            against: .toolCall(toolName: "calculate")
        )
        XCTAssertTrue(result.isFailure)
    }

    // MARK: - toolCallWithArgs

    @MainActor
    func testToolCallWithArgs_pass() {
        let events = [makeToolCallEvent(toolName: "calculate", arguments: "{\"expression\": \"2+2\"}")]
        let result = evalRunner.score(
            response: "4",
            toolCallEvents: events,
            against: .toolCallWithArgs(toolName: "calculate", key: "expression", expectedValue: "2+2")
        )
        XCTAssertTrue(result.isPass)
    }

    @MainActor
    func testToolCallWithArgs_wrongValue() {
        let events = [makeToolCallEvent(toolName: "calculate", arguments: "{\"expression\": \"3+3\"}")]
        let result = evalRunner.score(
            response: "6",
            toolCallEvents: events,
            against: .toolCallWithArgs(toolName: "calculate", key: "expression", expectedValue: "2+2")
        )
        XCTAssertTrue(result.isFailure)
    }

    @MainActor
    func testToolCallWithArgs_missingKey() {
        let events = [makeToolCallEvent(toolName: "calculate", arguments: "{\"other_key\": \"value\"}")]
        let result = evalRunner.score(
            response: "Result",
            toolCallEvents: events,
            against: .toolCallWithArgs(toolName: "calculate", key: "expression", expectedValue: "2+2")
        )
        XCTAssertTrue(result.isFailure)
    }

    // MARK: - toolCallChain

    @MainActor
    func testToolCallChain_pass() {
        let events = [
            makeToolCallEvent(toolName: "get_date_time"),
            makeToolCallEvent(toolName: "calculate"),
        ]
        let result = evalRunner.score(
            response: "Done",
            toolCallEvents: events,
            against: .toolCallChain(["get_date_time", "calculate"])
        )
        XCTAssertTrue(result.isPass)
    }

    @MainActor
    func testToolCallChain_wrongOrder() {
        let events = [
            makeToolCallEvent(toolName: "calculate"),
            makeToolCallEvent(toolName: "get_date_time"),
        ]
        let result = evalRunner.score(
            response: "Done",
            toolCallEvents: events,
            against: .toolCallChain(["get_date_time", "calculate"])
        )
        XCTAssertTrue(result.isFailure)
    }

    @MainActor
    func testToolCallChain_partial() {
        let events = [makeToolCallEvent(toolName: "get_date_time")]
        let result = evalRunner.score(
            response: "Done",
            toolCallEvents: events,
            against: .toolCallChain(["get_date_time", "calculate"])
        )
        XCTAssertTrue(result.isFailure)
    }

    // MARK: - nonEmpty

    @MainActor
    func testNonEmpty_pass() {
        let result = evalRunner.score(
            response: "Hello",
            toolCallEvents: [],
            against: .nonEmpty
        )
        XCTAssertTrue(result.isPass)
    }

    @MainActor
    func testNonEmpty_fail_empty() {
        let result = evalRunner.score(
            response: "",
            toolCallEvents: [],
            against: .nonEmpty
        )
        XCTAssertTrue(result.isFailure)
    }

    @MainActor
    func testNonEmpty_fail_whitespace() {
        let result = evalRunner.score(
            response: "   \n  ",
            toolCallEvents: [],
            against: .nonEmpty
        )
        XCTAssertTrue(result.isFailure)
    }

    // MARK: - matchesRegex

    @MainActor
    func testMatchesRegex_pass() {
        let result = evalRunner.score(
            response: "The answer is 42",
            toolCallEvents: [],
            against: .matchesRegex("\\d+")
        )
        XCTAssertTrue(result.isPass)
    }

    @MainActor
    func testMatchesRegex_fail() {
        let result = evalRunner.score(
            response: "No numbers here",
            toolCallEvents: [],
            against: .matchesRegex("\\d+")
        )
        XCTAssertTrue(result.isFailure)
    }

    @MainActor
    func testMatchesRegex_invalidPattern() {
        let result = evalRunner.score(
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

    @MainActor
    func testCustom_returnsManualReviewNeeded() {
        let result = evalRunner.score(
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
