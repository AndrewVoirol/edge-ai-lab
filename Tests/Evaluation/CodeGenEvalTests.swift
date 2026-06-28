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

    // MARK: - Scorer Edge Cases

    @Test("Bare code without fenced block passes when elements present")
    func bareCodeWithoutFencePasses() {
        // Model outputs raw code with no ``` markers and no language mention
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
        #expect(result.isPass, "Bare code with all required elements should pass even without fences")
    }

    @Test("Wrong language response: Python when Swift expected — fails when Swift-only elements missing")
    func wrongLanguageButElementsPresent() {
        // Python code when we expect Swift-specific elements like 'var' and 'struct'
        // that don't appear in Python code at all.
        let response = """
        ```python
        def reverse_string(s: str) -> str:
            return s[::-1]
        ```
        """
        // No ```swift fence, no "swift" mention, and elements not all present
        // → scorer rejects with "does not appear to contain swift code"
        let result = EvalScorer.score(
            response: response,
            toolCallEvents: [],
            against: .codeContains(language: "swift", requiredElements: ["var", "struct", "return"])
        )
        #expect(result.isFailure, "Python code missing Swift-only keywords should fail")
        if case .fail(let reason) = result {
            #expect(
                reason.contains("swift"),
                "Failure reason should mention the expected language: got '\(reason)'"
            )
        }
    }

    @Test("Wrong language response: Python when Swift expected — elements match by coincidence")
    func wrongLanguageElementsMatchByCoincidence() {
        // Edge case: a Python response that coincidentally contains all the Swift keywords
        // The scorer does NOT do language-level parsing — it only checks string presence.
        let response = """
        ```python
        # This func-tion demonstrates String handling
        def hello():
            func = "test"  # variable named func
            String = "hello"  # variable named String
            return String
        ```
        """
        let result = EvalScorer.score(
            response: response,
            toolCallEvents: [],
            against: .codeContains(language: "swift", requiredElements: ["func", "String", "return"])
        )
        // This WILL pass because the scorer is intentionally simple — it checks
        // string presence, not AST parsing. This is a known limitation.
        #expect(result.isPass, "Scorer checks string presence, not language semantics — coincidental matches pass")
    }

    @Test("Multiple code blocks — passes if any block has required elements")
    func multipleCodeBlocks() {
        let response = """
        Here's the solution:

        ```swift
        func reverseString(_ input: String) -> String {
            return String(input.reversed())
        }
        ```

        And here's how you'd use it:

        ```swift
        let result = reverseString("Hello")
        print(result)  // "olleH"
        ```

        The function takes a String parameter and returns the reversed version.
        """
        let result = EvalScorer.score(
            response: response,
            toolCallEvents: [],
            against: .codeContains(language: "swift", requiredElements: ["func", "String", "return"])
        )
        #expect(result.isPass, "Multiple code blocks with all elements present should pass")
    }

    @Test("Empty response fails with descriptive message mentioning expected language")
    func emptyResponseDescriptiveMessage() {
        let result = EvalScorer.score(
            response: "",
            toolCallEvents: [],
            against: .codeContains(language: "swift", requiredElements: ["func", "return"])
        )
        #expect(result.isFailure)
        if case .fail(let reason) = result {
            #expect(reason.contains("empty"), "Failure reason should mention response is empty")
            #expect(reason.contains("swift"), "Failure reason should mention expected language")
        } else {
            Issue.record("Expected .fail, got: \(result)")
        }
    }

    @Test("Whitespace-only response fails with descriptive message")
    func whitespaceOnlyResponseFails() {
        let result = EvalScorer.score(
            response: "   \n\n   \t  ",
            toolCallEvents: [],
            against: .codeContains(language: "python", requiredElements: ["def", "return"])
        )
        #expect(result.isFailure)
        if case .fail(let reason) = result {
            #expect(reason.contains("empty"), "Whitespace-only should be treated as empty")
        } else {
            Issue.record("Expected .fail, got: \(result)")
        }
    }

    @Test("Fenced block marker with no code inside fails")
    func fencedBlockMarkerOnlyFails() {
        let response = """
        Here's the code:

        ```swift
        ```
        """
        let result = EvalScorer.score(
            response: response,
            toolCallEvents: [],
            against: .codeContains(language: "swift", requiredElements: ["func", "String", "return"])
        )
        #expect(result.isFailure, "Fenced block with no actual code should fail")
        if case .fail(let reason) = result {
            #expect(reason.contains("func"), "Should report missing elements")
        }
    }

    // MARK: - Integration: Scoring Pipeline End-to-End

    /// Runs EvalScorer.score() against each CodeGenEvalSuite prompt with a realistic
    /// mock response. Validates that the full scoring pipeline (not just construction)
    /// works end-to-end for every prompt in the suite.
    @Test("All 15 prompts score as pass with realistic mock responses")
    func scoringPipelineEndToEnd() {
        let suite = BuiltInEvalSuites.codeGeneration

        // Mock responses that a model might realistically produce for each prompt.
        // Keyed by prompt index to match the suite's prompt order.
        let mockResponses: [String] = [
            // 1. Swift: Reverse a string
            """
            Here's a Swift function to reverse a string:

            ```swift
            func reverseString(_ input: String) -> String {
                return String(input.reversed())
            }
            ```
            """,
            // 2. Swift: Fibonacci
            """
            ```swift
            func fibonacci(_ n: Int) -> Int {
                if n <= 1 { return n }
                return fibonacci(n - 1) + fibonacci(n - 2)
            }
            ```
            """,
            // 3. Swift: Rectangle struct
            """
            ```swift
            struct Rectangle {
                var width: Double
                var height: Double

                var area: Double {
                    width * height
                }
            }
            ```
            """,
            // 4. Swift: Array filter
            """
            In Swift, you can filter even numbers:

            ```swift
            let numbers: [Int] = [1, 2, 3, 4, 5, 6]
            let evens = numbers.filter { $0 % 2 == 0 }
            ```
            """,
            // 5. Swift: NetworkError enum
            """
            ```swift
            enum NetworkError: Error {
                case timeout
                case unauthorized
                case notFound
            }
            ```
            """,
            // 6. Python: List comprehension squares
            """
            ```python
            def square_list(numbers):
                return [x ** 2 for x in numbers]
            ```
            """,
            // 7. Python: BankAccount class
            """
            ```python
            class BankAccount:
                def __init__(self):
                    self.balance = 0

                def deposit(self, amount):
                    self.balance += amount

                def withdraw(self, amount):
                    self.balance -= amount

                def get_balance(self):
                    return self.balance
            ```
            """,
            // 8. Python: File reading
            """
            ```python
            def count_lines(filepath):
                with open(filepath, 'r') as f:
                    lines = f.readlines()
                return len(lines)
            ```
            """,
            // 9. Python: Word frequency
            """
            ```python
            def word_frequency(text):
                words = text.split()
                freq = {}
                for word in words:
                    freq[word] = freq.get(word, 0) + 1
                return freq
            ```
            """,
            // 10. Python: Timer decorator
            """
            ```python
            import time

            def timer(func):
                def wrapper(*args, **kwargs):
                    start = time.time()
                    result = func(*args, **kwargs)
                    end = time.time()
                    print(f"{func.__name__} took {end - start:.4f} seconds")
                    return result
                return wrapper
            ```
            """,
            // 11. JavaScript: Async fetch
            """
            ```javascript
            async function fetchData(url) {
                const response = await fetch(url);
                return response.json();
            }
            ```
            """,
            // 12. JavaScript: Array reduce sum
            """
            ```javascript
            function sum(numbers) {
                return numbers.reduce((acc, num) => acc + num, 0);
            }
            ```
            """,
            // 13. JavaScript: DOM manipulation
            """
            ```javascript
            const paragraph = document.createElement('p');
            paragraph.textContent = 'Hello, World!';
            document.body.appendChild(paragraph);
            ```
            """,
            // 14. Binary search (any language)
            """
            Here's a binary search implementation:

            ```python
            def binary_search(arr, target):
                low, high = 0, len(arr) - 1
                while low <= high:
                    mid = (low + high) // 2
                    if arr[mid] == target:
                        return mid
                    elif arr[mid] < target:
                        low = mid + 1
                    else:
                        high = mid - 1
                return -1
            ```
            """,
            // 15. FizzBuzz
            """
            Here's a FizzBuzz implementation:

            ```python
            for i in range(1, 101):
                if i % 15 == 0:
                    print("FizzBuzz")
                elif i % 3 == 0:
                    print("Fizz")
                elif i % 5 == 0:
                    print("Buzz")
                else:
                    print(i)
            ```
            """,
        ]

        #expect(
            suite.prompts.count == mockResponses.count,
            "Mock response count (\(mockResponses.count)) must match prompt count (\(suite.prompts.count))"
        )

        for (index, prompt) in suite.prompts.enumerated() {
            let response = mockResponses[index]
            let score = EvalScorer.score(
                response: response,
                toolCallEvents: [],
                against: prompt.expectedBehavior
            )
            #expect(
                score.isPass,
                "Prompt \(index + 1) '\(prompt.truncatedPrompt)' should pass with mock response, got: \(score)"
            )
        }
    }
}

