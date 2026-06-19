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
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Tests for `TextAnalyzerTool`, which produces word count, character count,
/// sentence/paragraph counts, reading time estimates, and language detection.
@Suite struct TextAnalyzerToolTests {

    // MARK: - Helpers

    /// Parse the JSON result string into a dictionary for structured assertions.
    private func parseJSON(_ jsonString: String) throws -> [String: Any] {
        let data = try #require(jsonString.data(using: .utf8))
        let obj = try JSONSerialization.jsonObject(with: data)
        return try #require(obj as? [String: Any])
    }

    // MARK: - Empty Text

    @Test("Empty text has word_count of 0")
    func emptyTextWordCount() async throws {
        var tool = TextAnalyzerTool()
        tool.text = ""
        let result = try await tool.run()
        let json = try #require(result as? String)
        let dict = try parseJSON(json)
        let wordCount = try #require(dict["word_count"] as? Int)
        #expect(wordCount == 0)
    }

    @Test("Empty text has character_count of 0")
    func emptyTextCharacterCount() async throws {
        var tool = TextAnalyzerTool()
        tool.text = ""
        let result = try await tool.run()
        let json = try #require(result as? String)
        let dict = try parseJSON(json)
        let charCount = try #require(dict["character_count"] as? Int)
        #expect(charCount == 0)
    }

    // MARK: - Single Word

    @Test("Single word 'Hello' has word_count 1")
    func singleWordCount() async throws {
        var tool = TextAnalyzerTool()
        tool.text = "Hello"
        let result = try await tool.run()
        let json = try #require(result as? String)
        let dict = try parseJSON(json)
        let wordCount = try #require(dict["word_count"] as? Int)
        #expect(wordCount == 1)
    }

    @Test("Single word 'Hello' has correct character_count")
    func singleWordCharacterCount() async throws {
        var tool = TextAnalyzerTool()
        tool.text = "Hello"
        let result = try await tool.run()
        let json = try #require(result as? String)
        let dict = try parseJSON(json)
        let charCount = try #require(dict["character_count"] as? Int)
        #expect(charCount == 5)
    }

    // MARK: - Multi-Word Sentence

    @Test("Multi-word sentence has correct word count")
    func multiWordSentenceCount() async throws {
        var tool = TextAnalyzerTool()
        tool.text = "The quick brown fox jumps over the lazy dog."
        let result = try await tool.run()
        let json = try #require(result as? String)
        let dict = try parseJSON(json)
        let wordCount = try #require(dict["word_count"] as? Int)
        #expect(wordCount == 9)
    }

    @Test("Multi-word sentence has sentence_count of 1")
    func multiWordSentenceSentenceCount() async throws {
        var tool = TextAnalyzerTool()
        tool.text = "The quick brown fox jumps over the lazy dog."
        let result = try await tool.run()
        let json = try #require(result as? String)
        let dict = try parseJSON(json)
        let sentenceCount = try #require(dict["sentence_count"] as? Int)
        #expect(sentenceCount == 1)
    }

    @Test("Two sentences produce sentence_count of 2")
    func twoSentences() async throws {
        var tool = TextAnalyzerTool()
        tool.text = "Hello world. This is a test."
        let result = try await tool.run()
        let json = try #require(result as? String)
        let dict = try parseJSON(json)
        let sentenceCount = try #require(dict["sentence_count"] as? Int)
        #expect(sentenceCount == 2)
    }

    // MARK: - Multi-Paragraph

    @Test("Multi-paragraph text has correct paragraph count")
    func multiParagraphCount() async throws {
        var tool = TextAnalyzerTool()
        tool.text = "First paragraph.\n\nSecond paragraph.\n\nThird paragraph."
        let result = try await tool.run()
        let json = try #require(result as? String)
        let dict = try parseJSON(json)
        let paragraphCount = try #require(dict["paragraph_count"] as? Int)
        #expect(paragraphCount == 3)
    }

    // MARK: - Reading Time

    @Test("Short text reading time contains 'seconds'")
    func shortTextReadingTimeInSeconds() async throws {
        var tool = TextAnalyzerTool()
        tool.text = "Hello world"
        let result = try await tool.run()
        let json = try #require(result as? String)
        let dict = try parseJSON(json)
        let readingTime = try #require(dict["estimated_reading_time"] as? String)
        #expect(readingTime.contains("seconds"))
    }

    // MARK: - Character Count With/Without Spaces

    @Test("Character count includes spaces, no-spaces count excludes them")
    func characterCountWithAndWithoutSpaces() async throws {
        var tool = TextAnalyzerTool()
        tool.text = "a b c"
        let result = try await tool.run()
        let json = try #require(result as? String)
        let dict = try parseJSON(json)
        let charCount = try #require(dict["character_count"] as? Int)
        let charCountNoSpaces = try #require(dict["character_count_no_spaces"] as? Int)
        #expect(charCount == 5)       // 'a', ' ', 'b', ' ', 'c'
        #expect(charCountNoSpaces == 3) // 'a', 'b', 'c'
    }

    // MARK: - JSON Structure

    @Test("Result contains all expected keys")
    func resultContainsAllExpectedKeys() async throws {
        var tool = TextAnalyzerTool()
        tool.text = "Testing all keys."
        let result = try await tool.run()
        let json = try #require(result as? String)
        let dict = try parseJSON(json)
        #expect(dict["word_count"] != nil)
        #expect(dict["character_count"] != nil)
        #expect(dict["character_count_no_spaces"] != nil)
        #expect(dict["sentence_count"] != nil)
        #expect(dict["paragraph_count"] != nil)
        #expect(dict["average_word_length"] != nil)
        #expect(dict["estimated_reading_time"] != nil)
        #expect(dict["detected_language"] != nil)
    }
}
