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

// MARK: - EvalSuiteEditorLogic Tests

@Suite("EvalSuiteEditorLogic")
struct EvalSuiteEditorLogicTests {

    // MARK: - isValid Tests

    @Test("Valid suite: non-empty name and non-empty prompts")
    func validSuite() {
        #expect(EvalSuiteEditorLogic.isValid(
            name: "My Suite",
            promptTexts: ["What is 2+2?", "Explain gravity"]
        ))
    }

    @Test("Invalid: empty name")
    func emptyNameInvalid() {
        #expect(!EvalSuiteEditorLogic.isValid(
            name: "",
            promptTexts: ["What is 2+2?"]
        ))
    }

    @Test("Invalid: whitespace-only name")
    func whitespaceOnlyNameInvalid() {
        #expect(!EvalSuiteEditorLogic.isValid(
            name: "   ",
            promptTexts: ["What is 2+2?"]
        ))
    }

    @Test("Invalid: no prompts")
    func noPromptsInvalid() {
        #expect(!EvalSuiteEditorLogic.isValid(
            name: "My Suite",
            promptTexts: []
        ))
    }

    @Test("Invalid: one prompt has empty text")
    func emptyPromptTextInvalid() {
        #expect(!EvalSuiteEditorLogic.isValid(
            name: "My Suite",
            promptTexts: ["Valid prompt", ""]
        ))
    }

    @Test("Invalid: prompt with whitespace-only text")
    func whitespaceOnlyPromptInvalid() {
        #expect(!EvalSuiteEditorLogic.isValid(
            name: "My Suite",
            promptTexts: ["Valid prompt", "   "]
        ))
    }

    @Test("Valid: name with leading/trailing spaces is accepted")
    func nameWithSpacesValid() {
        #expect(EvalSuiteEditorLogic.isValid(
            name: "  My Suite  ",
            promptTexts: ["A prompt"]
        ))
    }

    @Test("Valid: single prompt")
    func singlePromptValid() {
        #expect(EvalSuiteEditorLogic.isValid(
            name: "Suite",
            promptTexts: ["One prompt"]
        ))
    }

    // MARK: - isSameBehaviorType Tests

    @Test("Same type: nonEmpty")
    func sameTypeNonEmpty() {
        #expect(EvalSuiteEditorLogic.isSameBehaviorType(.nonEmpty, .nonEmpty))
    }

    @Test("Same type: containsText with different values")
    func sameTypeContainsText() {
        #expect(EvalSuiteEditorLogic.isSameBehaviorType(
            .containsText("hello"),
            .containsText("world")
        ))
    }

    @Test("Same type: containsAny with different values")
    func sameTypeContainsAny() {
        #expect(EvalSuiteEditorLogic.isSameBehaviorType(
            .containsAny(["a"]),
            .containsAny(["b", "c"])
        ))
    }

    @Test("Same type: containsAll with different values")
    func sameTypeContainsAll() {
        #expect(EvalSuiteEditorLogic.isSameBehaviorType(
            .containsAll(["x"]),
            .containsAll(["y", "z"])
        ))
    }

    @Test("Same type: toolCall with different names")
    func sameTypeToolCall() {
        #expect(EvalSuiteEditorLogic.isSameBehaviorType(
            .toolCall(toolName: "calculate"),
            .toolCall(toolName: "convert_units")
        ))
    }

    @Test("Same type: toolCallWithArgs with different values")
    func sameTypeToolCallWithArgs() {
        #expect(EvalSuiteEditorLogic.isSameBehaviorType(
            .toolCallWithArgs(toolName: "calc", key: "expr", expectedValue: "2+2"),
            .toolCallWithArgs(toolName: "other", key: "k", expectedValue: "v")
        ))
    }

    @Test("Same type: toolCallChain with different chains")
    func sameTypeToolCallChain() {
        #expect(EvalSuiteEditorLogic.isSameBehaviorType(
            .toolCallChain(["a", "b"]),
            .toolCallChain(["c"])
        ))
    }

    @Test("Same type: matchesRegex with different patterns")
    func sameTypeMatchesRegex() {
        #expect(EvalSuiteEditorLogic.isSameBehaviorType(
            .matchesRegex("\\d+"),
            .matchesRegex("[a-z]+")
        ))
    }

    @Test("Same type: custom with different descriptions")
    func sameTypeCustom() {
        #expect(EvalSuiteEditorLogic.isSameBehaviorType(
            .custom(description: "Check A"),
            .custom(description: "Check B")
        ))
    }

    @Test("Different types: nonEmpty vs containsText")
    func differentTypeNonEmptyVsContains() {
        #expect(!EvalSuiteEditorLogic.isSameBehaviorType(
            .nonEmpty,
            .containsText("hello")
        ))
    }

    @Test("Different types: toolCall vs toolCallWithArgs")
    func differentTypeToolCallVsToolCallWithArgs() {
        #expect(!EvalSuiteEditorLogic.isSameBehaviorType(
            .toolCall(toolName: "calc"),
            .toolCallWithArgs(toolName: "calc", key: "x", expectedValue: "1")
        ))
    }

    @Test("Different types: matchesRegex vs custom")
    func differentTypeRegexVsCustom() {
        #expect(!EvalSuiteEditorLogic.isSameBehaviorType(
            .matchesRegex("\\d+"),
            .custom(description: "manual check")
        ))
    }

    @Test("Different types: containsAny vs containsAll")
    func differentTypeContainsAnyVsAll() {
        #expect(!EvalSuiteEditorLogic.isSameBehaviorType(
            .containsAny(["a"]),
            .containsAll(["a"])
        ))
    }

    // MARK: - buildSuite Tests

    @Test("buildSuite creates new suite with generated ID")
    func buildNewSuite() {
        let prompts = [
            EvalPrompt(prompt: "Test prompt", expectedBehavior: .nonEmpty)
        ]
        let suite = EvalSuiteEditorLogic.buildSuite(
            existingSuiteId: nil,
            name: "  New Suite  ",
            description: "  A description  ",
            category: .math,
            prompts: prompts,
            existingCreatedAt: nil
        )

        #expect(suite.name == "New Suite")
        #expect(suite.description == "A description")
        #expect(suite.category == .math)
        #expect(suite.prompts.count == 1)
        #expect(suite.isBuiltIn == false)
    }

    @Test("buildSuite preserves existing ID and creation date when editing")
    func buildExistingSuite() {
        let existingId = UUID()
        let existingDate = Date(timeIntervalSince1970: 1000)
        let prompts = [
            EvalPrompt(prompt: "Updated prompt", expectedBehavior: .nonEmpty)
        ]
        let suite = EvalSuiteEditorLogic.buildSuite(
            existingSuiteId: existingId,
            name: "Edited Suite",
            description: "Updated desc",
            category: .reasoning,
            prompts: prompts,
            existingCreatedAt: existingDate
        )

        #expect(suite.id == existingId)
        #expect(suite.createdAt == existingDate)
        #expect(suite.name == "Edited Suite")
        #expect(suite.isBuiltIn == false)
    }

    @Test("buildSuite trims whitespace from name and description")
    func buildSuiteTrimsWhitespace() {
        let suite = EvalSuiteEditorLogic.buildSuite(
            existingSuiteId: nil,
            name: "   Spaces   ",
            description: "  Leading and trailing  ",
            category: .general,
            prompts: [EvalPrompt(prompt: "p", expectedBehavior: .nonEmpty)],
            existingCreatedAt: nil
        )

        #expect(suite.name == "Spaces")
        #expect(suite.description == "Leading and trailing")
    }
}
