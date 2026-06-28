// Copyright 2026 Andrew Voirol. Apache-2.0

import Foundation
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Tests for `BuiltInEvalSuites.codeGeneration` — validates suite construction,
/// the new `.codeContains` scoring variant, and false positive resistance.
@Suite("Code Generation Eval Suite")
struct CodeGenEvalTests {

    // MARK: - Suite Construction

    @Test("Suite has 15 prompts")
    func suitePromptCount() {
        let suite = BuiltInEvalSuites.codeGeneration
        #expect(suite.prompts.count == 15)
    }

    @Test("Suite has correct metadata")
    func suiteMetadata() {
        let suite = BuiltInEvalSuites.codeGeneration
        #expect(suite.name == "Code Generation")
        #expect(suite.category == .codeGeneration)
        #expect(suite.isBuiltIn == true)
        #expect(!suite.description.isEmpty)
    }

    @Test("All prompts have non-empty text")
    func allPromptsNonEmpty() {
        let suite = BuiltInEvalSuites.codeGeneration
        for prompt in suite.prompts {
            #expect(!prompt.prompt.isEmpty, "Prompt should have non-empty text")
        }
    }

    @Test("All prompts use codeContains behavior")
    func allPromptsUseCodeContains() {
        let suite = BuiltInEvalSuites.codeGeneration
        for prompt in suite.prompts {
            if case .codeContains = prompt.expectedBehavior {
                // Expected — all code gen prompts should use codeContains
            } else {
                Issue.record("Code gen prompt should use .codeContains, got: \(prompt.expectedBehavior.displayDescription)")
            }
        }
    }

    @Test("All prompts are auto-scorable")
    func allPromptsAutoScorable() {
        let suite = BuiltInEvalSuites.codeGeneration
        for prompt in suite.prompts {
            #expect(
                prompt.expectedBehavior.isAutoScorable,
                "All code gen prompts should be auto-scorable"
            )
        }
    }

    // MARK: - codeContains Scoring — Passing Cases

    @Test("codeContains passes for Swift function with fenced code block")
    func codeContainsPassesSwiftFenced() {
        let response = """
        Here's a Swift function to reverse a string:

        ```swift
        func reverseString(_ input: String) -> String {
            return String(input.reversed())
        }
        ```
        """
        let result = EvalScorer.score(
            response: response,
            toolCallEvents: [],
            against: .codeContains(language: "swift", requiredElements: ["func", "String", "return"])
        )
        #expect(result.isPass, "Should pass for valid Swift code with all required elements")
    }

    @Test("codeContains passes for Python code with fenced block")
    func codeContainsPassesPythonFenced() {
        let response = """
        Here's a Python function:

        ```python
        def square_list(numbers):
            return [x ** 2 for x in numbers]
        ```
        """
        let result = EvalScorer.score(
            response: response,
            toolCallEvents: [],
            against: .codeContains(language: "python", requiredElements: ["def", "return"])
        )
        #expect(result.isPass, "Should pass for valid Python code")
    }

    @Test("codeContains passes for code without fence but with language mention")
    func codeContainsPassesWithoutFence() {
        let response = """
        In Swift, you can write:

        func hello() -> String {
            return "Hello"
        }
        """
        let result = EvalScorer.score(
            response: response,
            toolCallEvents: [],
            against: .codeContains(language: "swift", requiredElements: ["func", "String", "return"])
        )
        #expect(result.isPass, "Should pass when language is mentioned and elements are present")
    }

    @Test("codeContains passes when all elements present without fence or language mention")
    func codeContainsPassesAllElementsNoFence() {
        // If all required elements are present, we pass even without a language fence
        let response = """
        func reverseString(_ input: String) -> String {
            return String(input.reversed())
        }
        """
        let result = EvalScorer.score(
            response: response,
            toolCallEvents: [],
            against: .codeContains(language: "swift", requiredElements: ["func", "String", "return"])
        )
        #expect(result.isPass, "Should pass when all code elements are present even without fence")
    }

    // MARK: - codeContains Scoring — Failing Cases

    @Test("codeContains fails for empty response")
    func codeContainsFailsEmpty() {
        let result = EvalScorer.score(
            response: "",
            toolCallEvents: [],
            against: .codeContains(language: "swift", requiredElements: ["func", "return"])
        )
        #expect(result.isFailure, "Should fail for empty response")
    }

    @Test("codeContains fails when required elements are missing")
    func codeContainsFailsMissingElements() {
        let response = """
        ```swift
        let greeting = "Hello, World!"
        print(greeting)
        ```
        """
        let result = EvalScorer.score(
            response: response,
            toolCallEvents: [],
            against: .codeContains(language: "swift", requiredElements: ["func", "return"])
        )
        #expect(result.isFailure, "Should fail when code is missing required elements")
        if case .fail(let reason) = result {
            #expect(reason.contains("func"), "Failure reason should mention missing element 'func'")
            #expect(reason.contains("return"), "Failure reason should mention missing element 'return'")
        }
    }

    @Test("codeContains fails for wrong language without required elements")
    func codeContainsFailsWrongLanguage() {
        // Python code when we expect Swift-specific elements
        let response = """
        ```python
        def hello():
            return "Hello"
        ```
        """
        let result = EvalScorer.score(
            response: response,
            toolCallEvents: [],
            against: .codeContains(language: "swift", requiredElements: ["func", "String"])
        )
        #expect(result.isFailure, "Should fail when code is in wrong language and missing Swift keywords")
    }

    @Test("codeContains fails for prose response with no code")
    func codeContainsFailsProseOnly() {
        let response = "To reverse a string in Swift, you would typically use the built-in reversed() method on the characters collection."
        let result = EvalScorer.score(
            response: response,
            toolCallEvents: [],
            against: .codeContains(language: "swift", requiredElements: ["func", "String", "return"])
        )
        #expect(result.isFailure, "Should fail for prose-only response missing code elements")
    }

    // MARK: - codeContains Case Sensitivity

    @Test("codeContains checks elements case-sensitively")
    func codeContainsCaseSensitive() {
        let response = """
        ```swift
        FUNC myFunction() -> string {
            RETURN "hello"
        }
        ```
        """
        let result = EvalScorer.score(
            response: response,
            toolCallEvents: [],
            against: .codeContains(language: "swift", requiredElements: ["func", "String", "return"])
        )
        #expect(result.isFailure, "Should fail because 'func' != 'FUNC' and 'String' != 'string'")
    }

    // MARK: - Display Description

    @Test("codeContains display description shows language and elements")
    func codeContainsDisplayDescription() {
        let behavior = ExpectedBehavior.codeContains(
            language: "swift",
            requiredElements: ["func", "return"]
        )
        let desc = behavior.displayDescription
        #expect(desc.contains("swift"), "Display should mention language")
        #expect(desc.contains("func"), "Display should list required elements")
        #expect(desc.contains("return"), "Display should list required elements")
    }

    @Test("codeContains is auto-scorable")
    func codeContainsIsAutoScorable() {
        let behavior = ExpectedBehavior.codeContains(
            language: "swift",
            requiredElements: ["func"]
        )
        #expect(behavior.isAutoScorable)
    }

    @Test("codeContains does not involve tool calling")
    func codeContainsDoesNotInvolveToolCalling() {
        let behavior = ExpectedBehavior.codeContains(
            language: "swift",
            requiredElements: ["func"]
        )
        #expect(!behavior.involvesToolCalling)
    }
}
