// Copyright 2026 Andrew Voirol. Apache-2.0

import Foundation
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Tests for `BuiltInEvalSuites.instructionFollowing` — validates suite construction,
/// regex compilation, and scoring for key prompts.
@Suite("Instruction Following Eval Suite")
struct InstructionFollowingEvalTests {

    // MARK: - Suite Construction

    @Test("Suite has 15 prompts")
    func suitePromptCount() {
        let suite = BuiltInEvalSuites.instructionFollowing
        #expect(suite.prompts.count == 15)
    }

    @Test("Suite has correct metadata")
    func suiteMetadata() {
        let suite = BuiltInEvalSuites.instructionFollowing
        #expect(suite.name == "Instruction Following")
        #expect(suite.category == .instructionFollowing)
        #expect(suite.isBuiltIn == true)
        #expect(!suite.description.isEmpty)
    }

    // MARK: - Regex Compilation

    @Test("All regex patterns compile without error")
    func allRegexPatternsCompile() throws {
        let suite = BuiltInEvalSuites.instructionFollowing
        for prompt in suite.prompts {
            if case .matchesRegex(let pattern) = prompt.expectedBehavior {
                // Should not throw — pattern must be valid
                let _ = try NSRegularExpression(pattern: pattern)
            }
        }
    }

    // MARK: - Scoring Validation

    @Test("Lowercase regex passes for all-lowercase response")
    func lowercaseRegexPassesForLowercaseResponse() throws {
        // Prompt 2: "Answer using only lowercase letters"
        let pattern = "^[^A-Z]*$"
        let regex = try NSRegularExpression(pattern: pattern)
        let response = "paris"
        let range = NSRange(response.startIndex..., in: response)
        let match = regex.firstMatch(in: response, range: range)
        #expect(match != nil, "All-lowercase response should match")
    }

    @Test("Lowercase regex fails for response with uppercase")
    func lowercaseRegexFailsForUppercase() throws {
        let pattern = "^[^A-Z]*$"
        let regex = try NSRegularExpression(pattern: pattern)
        let response = "Paris"
        let range = NSRange(response.startIndex..., in: response)
        let match = regex.firstMatch(in: response, range: range)
        #expect(match == nil, "Response with uppercase should not match")
    }

    @Test("Numbered list regex matches valid 5-item list")
    func numberedListRegexMatches() throws {
        let pattern = "(?s)1[.)].*2[.)].*3[.)].*4[.)].*5[.)]"
        let regex = try NSRegularExpression(pattern: pattern)
        let response = """
        1. Python
        2. JavaScript
        3. Swift
        4. Rust
        5. Go
        """
        let range = NSRange(response.startIndex..., in: response)
        let match = regex.firstMatch(in: response, range: range)
        #expect(match != nil, "Valid 5-item numbered list should match")
    }

    @Test("Start-with-Absolutely regex matches correct response")
    func startWithAbsolutelyMatches() throws {
        let pattern = "^Absolutely"
        let regex = try NSRegularExpression(pattern: pattern)
        let response = "Absolutely, reading is important because..."
        let range = NSRange(response.startIndex..., in: response)
        let match = regex.firstMatch(in: response, range: range)
        #expect(match != nil, "Response starting with 'Absolutely' should match")
    }

    @Test("Start-with-Absolutely regex rejects wrong start")
    func startWithAbsolutelyRejectsWrongStart() throws {
        let pattern = "^Absolutely"
        let regex = try NSRegularExpression(pattern: pattern)
        let response = "Sure, reading is important because..."
        let range = NSRange(response.startIndex..., in: response)
        let match = regex.firstMatch(in: response, range: range)
        #expect(match == nil, "Response not starting with 'Absolutely' should not match")
    }

    @Test("Two-paragraph regex matches paragraphs separated by blank line")
    func twoParagraphRegexMatches() throws {
        let pattern = "(?s).+\\n\\n.+"
        let regex = try NSRegularExpression(pattern: pattern)
        let response = "First paragraph content here.\n\nSecond paragraph content here."
        let range = NSRange(response.startIndex..., in: response)
        let match = regex.firstMatch(in: response, range: range)
        #expect(match != nil, "Two paragraphs separated by blank line should match")
    }

    @Test("Three-word regex matches exactly three words")
    func threeWordRegexMatches() throws {
        let pattern = "^\\s*\\S+\\s+\\S+\\s+\\S+\\s*$"
        let regex = try NSRegularExpression(pattern: pattern)
        let response = "vast deep blue"
        let range = NSRange(response.startIndex..., in: response)
        let match = regex.firstMatch(in: response, range: range)
        #expect(match != nil, "Exactly three words should match")
    }

    @Test("Three-word regex rejects four words")
    func threeWordRegexRejectsFourWords() throws {
        let pattern = "^\\s*\\S+\\s+\\S+\\s+\\S+\\s*$"
        let regex = try NSRegularExpression(pattern: pattern)
        let response = "vast deep blue ocean"
        let range = NSRange(response.startIndex..., in: response)
        let match = regex.firstMatch(in: response, range: range)
        #expect(match == nil, "Four words should not match three-word pattern")
    }
}
