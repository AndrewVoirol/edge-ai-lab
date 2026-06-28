// Copyright 2026 Andrew Voirol. Apache-2.0

import Foundation
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Tests for `BuiltInEvalSuites.longContext` — validates suite construction,
/// timeout configuration, and prompt quality for long-passage retrieval tasks.
@Suite("Long Context Eval Suite")
struct LongContextEvalTests {

    // MARK: - Suite Construction

    @Test("Suite has 8 prompts")
    func suitePromptCount() {
        let suite = BuiltInEvalSuites.longContext
        #expect(suite.prompts.count == 8)
    }

    @Test("Suite has correct metadata")
    func suiteMetadata() {
        let suite = BuiltInEvalSuites.longContext
        #expect(suite.name == "Long Context")
        #expect(suite.category == .reasoning)
        #expect(suite.isBuiltIn == true)
        #expect(!suite.description.isEmpty)
    }

    @Test("All prompts have non-empty text")
    func allPromptsNonEmpty() {
        let suite = BuiltInEvalSuites.longContext
        for prompt in suite.prompts {
            #expect(!prompt.prompt.isEmpty, "Prompt should have non-empty text")
        }
    }

    // MARK: - Timeout Configuration

    @Test("All prompts have 120 second timeout")
    func allPromptsHave120SecondTimeout() {
        let suite = BuiltInEvalSuites.longContext
        for prompt in suite.prompts {
            #expect(
                prompt.timeoutSeconds == 120,
                "Long context prompt should have 120s timeout, got \(prompt.timeoutSeconds)s for: \(prompt.truncatedPrompt)"
            )
        }
    }

    @Test("Suite estimated duration reflects extended timeouts")
    func suiteEstimatedDuration() {
        let suite = BuiltInEvalSuites.longContext
        // 8 prompts × 120s = 960s
        #expect(suite.estimatedDurationSeconds == 960)
    }

    // MARK: - Prompt Length Validation

    @Test("All prompts contain substantial context passages")
    func allPromptsHaveLongContext() {
        let suite = BuiltInEvalSuites.longContext
        for prompt in suite.prompts {
            // Each prompt should be significantly longer than typical eval prompts.
            // 500+ word passages should result in at least 2000 characters.
            #expect(
                prompt.prompt.count >= 2000,
                "Long context prompt should have at least 2000 characters, got \(prompt.prompt.count) for: \(prompt.truncatedPrompt)"
            )
        }
    }

    @Test("All prompts contain a question section")
    func allPromptsContainQuestion() {
        let suite = BuiltInEvalSuites.longContext
        for prompt in suite.prompts {
            #expect(
                prompt.prompt.contains("Question:"),
                "Long context prompt should contain 'Question:' marker for: \(prompt.truncatedPrompt)"
            )
        }
    }

    // MARK: - Expected Behavior Validation

    @Test("All prompts are auto-scorable")
    func allPromptsAutoScorable() {
        let suite = BuiltInEvalSuites.longContext
        for prompt in suite.prompts {
            #expect(
                prompt.expectedBehavior.isAutoScorable,
                "All long context prompts should be auto-scorable"
            )
        }
    }

    @Test("Suite does not involve tool calling")
    func suiteDoesNotInvolveToolCalling() {
        let suite = BuiltInEvalSuites.longContext
        for prompt in suite.prompts {
            #expect(
                !prompt.expectedBehavior.involvesToolCalling,
                "Long context prompts should not involve tool calling"
            )
        }
    }

    @Test("Suite uses containsText and containsAll behaviors")
    func suiteUsesTextAndAllBehaviors() {
        let suite = BuiltInEvalSuites.longContext
        let behaviors = suite.prompts.map(\.expectedBehavior)

        let hasContainsText = behaviors.contains {
            if case .containsText = $0 { return true }
            return false
        }
        let hasContainsAll = behaviors.contains {
            if case .containsAll = $0 { return true }
            return false
        }

        #expect(hasContainsText, "Long context suite should have .containsText expectations")
        #expect(hasContainsAll, "Long context suite should have .containsAll expectations")
    }

    // MARK: - No Multimodal Content

    @Test("Suite has no multimodal prompts")
    func noMultimodalPrompts() {
        let suite = BuiltInEvalSuites.longContext
        #expect(
            !suite.hasMultimodalPrompts,
            "Long context suite should be text-only, no image or audio data"
        )
    }

    // MARK: - Stress Tests: Word Count Validation

    @Test("Every passage contains 500+ words")
    func everyPassageHas500PlusWords() {
        let suite = BuiltInEvalSuites.longContext
        for (index, prompt) in suite.prompts.enumerated() {
            // Extract the passage (everything before "Question:")
            let parts = prompt.prompt.components(separatedBy: "Question:")
            let passage = parts.first ?? prompt.prompt

            // Count words by splitting on whitespace
            let words = passage.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
            #expect(
                words.count >= 500,
                "Passage \(index + 1) should have 500+ words, got \(words.count)"
            )
        }
    }

    // MARK: - Stress Tests: Uniqueness

    @Test("No two passages are identical")
    func allPassagesAreUnique() {
        let suite = BuiltInEvalSuites.longContext
        var seenPassages = Set<String>()

        for (index, prompt) in suite.prompts.enumerated() {
            // Normalize: extract passage before "Question:" and trim
            let parts = prompt.prompt.components(separatedBy: "Question:")
            let passage = (parts.first ?? prompt.prompt)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let inserted = seenPassages.insert(passage).inserted
            #expect(
                inserted,
                "Passage \(index + 1) is a duplicate of a previous passage"
            )
        }
        #expect(
            seenPassages.count == suite.prompts.count,
            "All \(suite.prompts.count) passages should be unique"
        )
    }

    @Test("No two questions are identical")
    func allQuestionsAreUnique() {
        let suite = BuiltInEvalSuites.longContext
        var seenQuestions = Set<String>()

        for (index, prompt) in suite.prompts.enumerated() {
            let parts = prompt.prompt.components(separatedBy: "Question:")
            guard parts.count >= 2 else {
                Issue.record("Prompt \(index + 1) missing 'Question:' marker")
                continue
            }
            let question = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let inserted = seenQuestions.insert(question).inserted
            #expect(
                inserted,
                "Question \(index + 1) is a duplicate of a previous question"
            )
        }
    }

    // MARK: - Stress Tests: Answer-in-Passage Verification

    @Test("Expected answers are present in their corresponding passages")
    func expectedAnswersAreInPassage() {
        let suite = BuiltInEvalSuites.longContext
        for (index, prompt) in suite.prompts.enumerated() {
            // Extract the passage (before "Question:")
            let parts = prompt.prompt.components(separatedBy: "Question:")
            let passage = parts.first ?? prompt.prompt

            // Extract expected answer texts from the behavior
            let expectedTexts: [String]
            switch prompt.expectedBehavior {
            case .containsText(let text):
                expectedTexts = [text]
            case .containsAll(let texts):
                expectedTexts = texts
            case .containsAny(let texts):
                expectedTexts = texts
            default:
                // Other behavior types don't have extractable answer strings
                continue
            }

            // Verify each expected answer string appears in the passage.
            // This ensures we're testing retrieval, not hallucination.
            for expected in expectedTexts {
                let msg = "Passage \(index + 1) should contain expected answer '\(expected)' — if the answer isn't in the passage, the prompt tests hallucination rather than retrieval"
                #expect(
                    passage.contains(expected),
                    Comment(rawValue: msg)
                )
            }
        }
    }
}

