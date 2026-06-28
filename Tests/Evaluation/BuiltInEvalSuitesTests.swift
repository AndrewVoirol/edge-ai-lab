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

/// Tests for `BuiltInEvalSuites` — validates the default evaluation suites
/// that ship with the app.
final class BuiltInEvalSuitesTests: XCTestCase {

    // MARK: - Suite Count & Built-In Flag

    func testAllBuiltInCount() {
        XCTAssertEqual(BuiltInEvalSuites.allBuiltIn.count, 8)
    }

    func testAllSuitesAreBuiltIn() {
        for suite in BuiltInEvalSuites.allBuiltIn {
            XCTAssertTrue(suite.isBuiltIn, "\(suite.name) should be marked as built-in")
        }
    }

    // MARK: - Individual Suite Validation

    func testMathAccuracySuite() {
        let suite = BuiltInEvalSuites.mathAccuracy
        XCTAssertEqual(suite.name, "Math Accuracy")
        XCTAssertEqual(suite.category, .math)
        XCTAssertEqual(suite.promptCount, 30)
    }

    func testToolCallingSuite() {
        let suite = BuiltInEvalSuites.toolCallingReliability
        XCTAssertEqual(suite.name, "Tool Calling Reliability")
        XCTAssertEqual(suite.category, .toolCalling)
        XCTAssertEqual(suite.promptCount, 20)
    }

    func testReasoningSuite() {
        let suite = BuiltInEvalSuites.reasoning
        XCTAssertEqual(suite.name, "Reasoning")
        XCTAssertEqual(suite.category, .reasoning)
        XCTAssertEqual(suite.promptCount, 25)
    }

    func testMultimodalSuite() {
        let suite = BuiltInEvalSuites.multimodal
        XCTAssertEqual(suite.name, "Multimodal")
        XCTAssertEqual(suite.category, .multimodal)
        XCTAssertEqual(suite.promptCount, 25)
    }

    // MARK: - Uniqueness & Completeness

    func testAllSuitesHaveUniqueIds() {
        let ids = Set(BuiltInEvalSuites.allBuiltIn.map(\.id))
        XCTAssertEqual(ids.count, BuiltInEvalSuites.allBuiltIn.count)
    }

    func testAllSuitesHaveNonEmptyDescriptions() {
        for suite in BuiltInEvalSuites.allBuiltIn {
            XCTAssertFalse(suite.description.isEmpty, "\(suite.name) should have a non-empty description")
        }
    }

    func testAllPromptsHaveNonEmptyText() {
        for suite in BuiltInEvalSuites.allBuiltIn {
            for prompt in suite.prompts {
                XCTAssertFalse(
                    prompt.prompt.isEmpty,
                    "Prompt in \(suite.name) should have non-empty text"
                )
            }
        }
    }

    // MARK: - Expected Behavior Patterns

    func testMathSuiteHasOnlyToolCallExpectations() {
        let suite = BuiltInEvalSuites.mathAccuracy
        for prompt in suite.prompts {
            if case .toolCall = prompt.expectedBehavior {
                // Expected — all math prompts should call a tool
            } else {
                XCTFail("Math suite prompt should have .toolCall expected behavior, got: \(prompt.expectedBehavior.displayDescription)")
            }
        }
    }

    func testReasoningSuiteCategories() {
        let suite = BuiltInEvalSuites.reasoning
        let behaviors = suite.prompts.map(\.expectedBehavior)

        let hasContainsText = behaviors.contains {
            if case .containsText = $0 { return true }
            return false
        }
        let hasMatchesRegex = behaviors.contains {
            if case .matchesRegex = $0 { return true }
            return false
        }
        let hasNonEmpty = behaviors.contains {
            if case .nonEmpty = $0 { return true }
            return false
        }

        XCTAssertTrue(hasContainsText, "Reasoning suite should have .containsText expectations")
        XCTAssertTrue(hasMatchesRegex, "Reasoning suite should have .matchesRegex expectations")
        XCTAssertTrue(hasNonEmpty, "Reasoning suite should have .nonEmpty expectations")
    }
}
