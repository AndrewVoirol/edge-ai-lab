// Copyright 2026 Andrew Voirol. Apache-2.0

import Foundation

// MARK: - Instruction Following Eval Suite

extension BuiltInEvalSuites {

    /// Tests the model's ability to follow precise formatting and structural instructions.
    ///
    /// Covers bullet-point counts, case constraints, JSON formatting, numbered lists,
    /// sentence structure, word avoidance, paragraph separation, markdown headers,
    /// response boundaries, comma-separated output, recipe format, word counts,
    /// keyword inclusion, and alphabetical sentence starts.
    static let instructionFollowing = EvalSuite(
        name: "Instruction Following",
        description: "Tests the model's ability to follow precise formatting and structural instructions.",
        category: .instructionFollowing,
        prompts: [
            // 1. Exactly 3 bullet points
            EvalPrompt(
                prompt: "Respond in exactly 3 bullet points about the benefits of exercise",
                expectedBehavior: .matchesRegex("(?s)^[\\s]*[-•*]\\s+.+\\n[\\s]*[-•*]\\s+.+\\n[\\s]*[-•*]\\s+.+\\s*$")
            ),

            // 2. Only lowercase letters
            EvalPrompt(
                prompt: "Answer using only lowercase letters: What is the capital of France?",
                expectedBehavior: .matchesRegex("^[^A-Z]*$")
            ),

            // 3. Valid JSON with 'name' and 'age' keys
            EvalPrompt(
                prompt: "Respond in valid JSON format with keys 'name' and 'age' for a fictional person",
                expectedBehavior: .containsAll(["\"name\"", "\"age\""])
            ),

            // 4. Exactly 5 numbered programming languages
            EvalPrompt(
                prompt: "List exactly 5 programming languages, numbered 1 through 5",
                expectedBehavior: .matchesRegex("(?s)1[.)].*2[.)].*3[.)].*4[.)].*5[.)]")
            ),

            // 5. Single sentence explaining gravity
            EvalPrompt(
                prompt: "Write a single sentence explaining gravity",
                expectedBehavior: .matchesRegex("^[^.!?]*[.!?]\\s*$")
            ),

            // 6. Explain photosynthesis without using the word 'sun'
            EvalPrompt(
                prompt: "Explain photosynthesis but do NOT use the word 'sun'",
                expectedBehavior: .matchesRegex("(?s)^(?!.*(?i)\\bsun\\b).*$")
            ),

            // 7. Exactly two paragraphs separated by a blank line
            EvalPrompt(
                prompt: "Respond with exactly two paragraphs separated by a blank line",
                expectedBehavior: .matchesRegex("(?s).+\\n\\n.+")
            ),

            // 8. Markdown headers (##) for each of 3 main points
            EvalPrompt(
                prompt: "Use markdown headers (##) for each of your 3 main points about climate change",
                expectedBehavior: .containsAll(["##"])
            ),

            // 9. Start response with 'Absolutely'
            EvalPrompt(
                prompt: "Start your response with the word 'Absolutely'. Then explain why reading is important.",
                expectedBehavior: .matchesRegex("^Absolutely")
            ),

            // 10. End response with 'Thank you for reading.'
            EvalPrompt(
                prompt: "Write a brief summary of renewable energy. End your response with the phrase 'Thank you for reading.'",
                expectedBehavior: .matchesRegex("Thank you for reading\\.\\s*$")
            ),

            // 11. Comma-separated list with no other text
            EvalPrompt(
                prompt: "Provide your answer as a comma-separated list with no other text: name 5 colors",
                expectedBehavior: .matchesRegex("^[^\\n]*,[^\\n]*$")
            ),

            // 12. Recipe format with Ingredients and Instructions sections
            EvalPrompt(
                prompt: "Respond in the style of a recipe with 'Ingredients:' and 'Instructions:' sections for making a sandwich",
                expectedBehavior: .containsAll(["Ingredients", "Instructions"])
            ),

            // 13. Exactly 3 words
            EvalPrompt(
                prompt: "Give me exactly 3 words that describe the ocean",
                expectedBehavior: .matchesRegex("^\\s*\\S+\\s+\\S+\\s+\\S+\\s*$")
            ),

            // 14. Must include the word 'analogy'
            EvalPrompt(
                prompt: "Explain quantum computing using an analogy. Your response must include the word 'analogy'",
                expectedBehavior: .containsText("analogy")
            ),

            // 15. Alphabetical sentence starts — verify A through E
            EvalPrompt(
                prompt: "Write a response where every sentence starts with a different letter of the alphabet, in order from A to E",
                expectedBehavior: .matchesRegex("(?i)\\bA\\w.*\\..*\\bB\\w.*\\..*\\bC\\w.*\\..*\\bD\\w.*\\..*\\bE\\w")
            ),
        ],
        isBuiltIn: true
    )
}
