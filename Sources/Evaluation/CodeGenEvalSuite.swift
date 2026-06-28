// Copyright 2026 Andrew Voirol. Apache-2.0

import Foundation

// MARK: - Code Generation Eval Suite

extension BuiltInEvalSuites {

    /// Tests the model's ability to generate syntactically plausible code across
    /// multiple languages and problem types.
    ///
    /// Uses `.codeContains(language:requiredElements:)` to verify that responses
    /// include language-appropriate syntax keywords. Each prompt targets a specific
    /// coding task (function definition, class design, algorithm implementation)
    /// and checks for structural markers rather than exact output.
    ///
    /// 15 prompts covering Swift, Python, JavaScript, and general-purpose tasks.
    static let codeGeneration = EvalSuite(
        name: "Code Generation",
        description: "Tests code generation across Swift, Python, and JavaScript with structural validation of syntax keywords and required elements.",
        category: .codeGeneration,
        prompts: [
            // --- Swift (5 prompts) ---

            // 1. String reversal function
            EvalPrompt(
                prompt: "Write a Swift function to reverse a string",
                expectedBehavior: .codeContains(
                    language: "swift",
                    requiredElements: ["func", "String", "return"]
                ),
                timeoutSeconds: 60
            ),

            // 2. Fibonacci sequence
            EvalPrompt(
                prompt: "Write a Swift function that returns the nth Fibonacci number",
                expectedBehavior: .codeContains(
                    language: "swift",
                    requiredElements: ["func", "Int", "return"]
                ),
                timeoutSeconds: 60
            ),

            // 3. Struct with computed property
            EvalPrompt(
                prompt: "Write a Swift struct called Rectangle with width and height properties and a computed property for area",
                expectedBehavior: .codeContains(
                    language: "swift",
                    requiredElements: ["struct", "Rectangle", "var", "area"]
                ),
                timeoutSeconds: 60
            ),

            // 4. Array filtering with closures
            EvalPrompt(
                prompt: "Write Swift code that filters an array of integers to keep only even numbers using a closure",
                expectedBehavior: .codeContains(
                    language: "swift",
                    requiredElements: ["filter", "Int"]
                ),
                timeoutSeconds: 60
            ),

            // 5. Error handling with enum
            EvalPrompt(
                prompt: "Write a Swift enum called NetworkError that conforms to Error with cases for timeout, unauthorized, and notFound",
                expectedBehavior: .codeContains(
                    language: "swift",
                    requiredElements: ["enum", "NetworkError", "Error", "case"]
                ),
                timeoutSeconds: 60
            ),

            // --- Python (5 prompts) ---

            // 6. List comprehension
            EvalPrompt(
                prompt: "Write a Python function that takes a list of numbers and returns a list of their squares using a list comprehension",
                expectedBehavior: .codeContains(
                    language: "python",
                    requiredElements: ["def", "return"]
                ),
                timeoutSeconds: 60
            ),

            // 7. Class with methods
            EvalPrompt(
                prompt: "Write a Python class called BankAccount with deposit, withdraw, and get_balance methods",
                expectedBehavior: .codeContains(
                    language: "python",
                    requiredElements: ["class", "BankAccount", "def", "self"]
                ),
                timeoutSeconds: 60
            ),

            // 8. File reading
            EvalPrompt(
                prompt: "Write a Python function to read a text file and return the number of lines",
                expectedBehavior: .codeContains(
                    language: "python",
                    requiredElements: ["def", "open", "return"]
                ),
                timeoutSeconds: 60
            ),

            // 9. Dictionary manipulation
            EvalPrompt(
                prompt: "Write a Python function that counts the frequency of each word in a string and returns a dictionary",
                expectedBehavior: .codeContains(
                    language: "python",
                    requiredElements: ["def", "return"]
                ),
                timeoutSeconds: 60
            ),

            // 10. Decorator
            EvalPrompt(
                prompt: "Write a Python decorator called timer that prints how long a function takes to execute",
                expectedBehavior: .codeContains(
                    language: "python",
                    requiredElements: ["def", "timer", "import"]
                ),
                timeoutSeconds: 60
            ),

            // --- JavaScript (3 prompts) ---

            // 11. Async fetch function
            EvalPrompt(
                prompt: "Write a JavaScript async function that fetches data from a URL and returns the JSON response",
                expectedBehavior: .codeContains(
                    language: "javascript",
                    requiredElements: ["async", "fetch", "return"]
                ),
                timeoutSeconds: 60
            ),

            // 12. Array reduce
            EvalPrompt(
                prompt: "Write a JavaScript function using reduce to calculate the sum of an array of numbers",
                expectedBehavior: .codeContains(
                    language: "javascript",
                    requiredElements: ["reduce", "return"]
                ),
                timeoutSeconds: 60
            ),

            // 13. DOM manipulation
            EvalPrompt(
                prompt: "Write JavaScript code that creates a new paragraph element, sets its text content, and appends it to the document body",
                expectedBehavior: .codeContains(
                    language: "javascript",
                    requiredElements: ["document", "createElement"]
                ),
                timeoutSeconds: 60
            ),

            // --- General / Algorithm (2 prompts) ---

            // 14. Binary search (language-agnostic with code check)
            EvalPrompt(
                prompt: "Write a function in any language that implements binary search on a sorted array",
                expectedBehavior: .codeContains(
                    language: "binary search",
                    requiredElements: ["return"]
                ),
                timeoutSeconds: 60
            ),

            // 15. FizzBuzz
            EvalPrompt(
                prompt: "Write a FizzBuzz implementation in any programming language for numbers 1 to 100",
                expectedBehavior: .codeContains(
                    language: "fizzbuzz",
                    requiredElements: ["Fizz", "Buzz"]
                ),
                timeoutSeconds: 60
            ),
        ],
        isBuiltIn: true
    )
}
