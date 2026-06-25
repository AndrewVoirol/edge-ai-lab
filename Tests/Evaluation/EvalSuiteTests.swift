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
import XCTest

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Tests for `EvalSuite`, `EvalCategory`, `EvalPrompt`, and `ExpectedBehavior` types.
final class EvalSuiteTests: XCTestCase {

    // MARK: - EvalSuite Creation

    func testSuiteCreation() {
        let before = Date()
        let suite = EvalSuite(
            name: "Test Suite",
            description: "A test suite",
            category: .general,
            prompts: []
        )
        let after = Date()

        XCTAssertFalse(suite.id.uuidString.isEmpty)
        XCTAssertEqual(suite.name, "Test Suite")
        XCTAssertEqual(suite.description, "A test suite")
        XCTAssertEqual(suite.category, .general)
        XCTAssertTrue(suite.prompts.isEmpty)
        XCTAssertFalse(suite.isBuiltIn)
        XCTAssertGreaterThanOrEqual(suite.createdAt, before)
        XCTAssertLessThanOrEqual(suite.createdAt, after)
    }

    // MARK: - Computed Properties

    func testPromptCount() {
        let suite = EvalSuite(
            name: "Count Suite",
            description: "",
            category: .general,
            prompts: [
                EvalPrompt(prompt: "P1", expectedBehavior: .nonEmpty),
                EvalPrompt(prompt: "P2", expectedBehavior: .nonEmpty),
                EvalPrompt(prompt: "P3", expectedBehavior: .nonEmpty),
            ]
        )
        XCTAssertEqual(suite.promptCount, 3)
    }

    func testHasMultimodalPrompts_withImageData() {
        let suite = EvalSuite(
            name: "MM Suite",
            description: "",
            category: .multimodal,
            prompts: [
                EvalPrompt(prompt: "Describe image", expectedBehavior: .nonEmpty, imageData: Data([0xFF])),
            ]
        )
        XCTAssertTrue(suite.hasMultimodalPrompts)
    }

    func testHasMultimodalPrompts_noMultimodal() {
        let suite = EvalSuite(
            name: "Text Suite",
            description: "",
            category: .general,
            prompts: [
                EvalPrompt(prompt: "Hello", expectedBehavior: .nonEmpty),
            ]
        )
        XCTAssertFalse(suite.hasMultimodalPrompts)
    }

    func testDisplaySummary() {
        let suite = EvalSuite(
            name: "Summary Suite",
            description: "",
            category: .math,
            prompts: [
                EvalPrompt(prompt: "P1", expectedBehavior: .nonEmpty),
                EvalPrompt(prompt: "P2", expectedBehavior: .nonEmpty),
                EvalPrompt(prompt: "P3", expectedBehavior: .nonEmpty),
            ]
        )
        XCTAssertEqual(suite.displaySummary, "3 prompts · Math")
    }

    func testDisplaySummary_singlePrompt() {
        let suite = EvalSuite(
            name: "Single Suite",
            description: "",
            category: .general,
            prompts: [
                EvalPrompt(prompt: "P1", expectedBehavior: .nonEmpty),
            ]
        )
        XCTAssertEqual(suite.displaySummary, "1 prompt · General")
    }

    func testEstimatedDurationSeconds() {
        let suite = EvalSuite(
            name: "Duration Suite",
            description: "",
            category: .general,
            prompts: [
                EvalPrompt(prompt: "P1", expectedBehavior: .nonEmpty, timeoutSeconds: 60),
                EvalPrompt(prompt: "P2", expectedBehavior: .nonEmpty, timeoutSeconds: 45),
                EvalPrompt(prompt: "P3", expectedBehavior: .nonEmpty, timeoutSeconds: 90),
            ]
        )
        XCTAssertEqual(suite.estimatedDurationSeconds, 195)
    }

    // MARK: - EvalCategory Tests

    func testAllCategoriesHaveDisplayName() {
        for category in EvalCategory.allCases {
            XCTAssertFalse(category.displayName.isEmpty, "\(category) should have a non-empty displayName")
        }
    }

    func testAllCategoriesHaveSymbolName() {
        for category in EvalCategory.allCases {
            XCTAssertFalse(category.symbolName.isEmpty, "\(category) should have a non-empty symbolName")
        }
    }

    func testCategoryRawValues() {
        XCTAssertEqual(EvalCategory.math.rawValue, "math")
        XCTAssertEqual(EvalCategory.toolCalling.rawValue, "toolCalling")
        XCTAssertEqual(EvalCategory.reasoning.rawValue, "reasoning")
        XCTAssertEqual(EvalCategory.multimodal.rawValue, "multimodal")
        XCTAssertEqual(EvalCategory.general.rawValue, "general")
        XCTAssertEqual(EvalCategory.custom.rawValue, "custom")
    }

    // MARK: - EvalPrompt Tests

    func testPromptCreation() {
        let prompt = EvalPrompt(prompt: "Test prompt", expectedBehavior: .nonEmpty)
        XCTAssertEqual(prompt.prompt, "Test prompt")
        XCTAssertNil(prompt.imageData)
        XCTAssertNil(prompt.audioData)
        XCTAssertEqual(prompt.timeoutSeconds, 60)
    }

    func testIsImagePrompt() {
        let prompt = EvalPrompt(
            prompt: "Describe image",
            expectedBehavior: .nonEmpty,
            imageData: Data([0xFF, 0xD8])
        )
        XCTAssertTrue(prompt.isImagePrompt)
        XCTAssertTrue(prompt.isMultimodal)
    }

    func testIsAudioPrompt() {
        let prompt = EvalPrompt(
            prompt: "Transcribe audio",
            expectedBehavior: .nonEmpty,
            audioData: Data([0x00, 0x01])
        )
        XCTAssertTrue(prompt.isAudioPrompt)
        XCTAssertTrue(prompt.isMultimodal)
    }

    func testTruncatedPrompt_short() {
        let shortText = "Short prompt"
        let prompt = EvalPrompt(prompt: shortText, expectedBehavior: .nonEmpty)
        XCTAssertEqual(prompt.truncatedPrompt, shortText)
    }

    func testTruncatedPrompt_long() {
        let longText = String(repeating: "a", count: 100)
        let prompt = EvalPrompt(prompt: longText, expectedBehavior: .nonEmpty)
        XCTAssertTrue(prompt.truncatedPrompt.hasSuffix("..."))
        XCTAssertEqual(prompt.truncatedPrompt.count, 80)
    }

    // MARK: - ExpectedBehavior Tests

    func testContainsTextDisplay() {
        let behavior = ExpectedBehavior.containsText("hello")
        XCTAssertEqual(behavior.displayDescription, "Contains: \"hello\"")
    }

    func testToolCallDisplay() {
        let behavior = ExpectedBehavior.toolCall(toolName: "calculate")
        XCTAssertEqual(behavior.displayDescription, "Calls tool: calculate")
    }

    func testNonEmptyIsAutoScorable() {
        XCTAssertTrue(ExpectedBehavior.nonEmpty.isAutoScorable)
    }

    func testCustomIsNotAutoScorable() {
        let behavior = ExpectedBehavior.custom(description: "Check quality manually")
        XCTAssertFalse(behavior.isAutoScorable)
    }

    func testToolCallInvolvesToolCalling() {
        let behavior = ExpectedBehavior.toolCall(toolName: "calculate")
        XCTAssertTrue(behavior.involvesToolCalling)
    }

    func testContainsTextNotInvolvesToolCalling() {
        let behavior = ExpectedBehavior.containsText("answer")
        XCTAssertFalse(behavior.involvesToolCalling)
    }

    // MARK: - Codable Round-Trip

    func testSuiteCodableRoundTrip() throws {
        let original = EvalSuite(
            name: "Codable Suite",
            description: "Tests Codable conformance",
            category: .math,
            prompts: [
                EvalPrompt(prompt: "What is 2+2?", expectedBehavior: .containsText("4")),
                EvalPrompt(prompt: "Calculate sqrt(16)", expectedBehavior: .toolCall(toolName: "calculate")),
            ],
            isBuiltIn: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(EvalSuite.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.prompts.count, original.prompts.count)
        XCTAssertEqual(decoded.category, original.category)
        XCTAssertEqual(decoded.isBuiltIn, original.isBuiltIn)
    }
}
