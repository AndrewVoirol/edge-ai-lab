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
import LiteRTLM
import NaturalLanguage

// MARK: - TextAnalyzerTool

/// Analyzes text properties including word count, character count, sentence count,
/// paragraph count, average word length, reading time estimate, and detected language.
///
/// Uses `NLLanguageRecognizer` for language detection and word-per-minute estimates
/// for reading time (250 WPM average adult reading speed).
///
/// Example: `analyze_text(text: "Hello world. This is a test.")` → word count, stats, etc.
struct TextAnalyzerTool: Tool {
    static let name = "analyze_text"
    static let description = "Analyze text properties including word count, character count, sentence count, reading time, and detected language"

    @ToolParam(description: "The text to analyze")
    var text: String

    func run() async throws -> Any {
        let startTime = CFAbsoluteTimeGetCurrent()
        let argumentsDict = ["text": text]
        var resultString = ""
        defer {
            let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            let succeeded = !resultString.isEmpty && !resultString.contains("\"error\"")
            let event = ToolCallEvent(
                toolName: Self.name,
                arguments: jsonString(from: argumentsDict),
                result: resultString,
                durationMs: duration,
                timestamp: Date(),
                succeeded: succeeded
            )
            ToolExecutionTracker.shared.notify(event)
        }
        // Word count — split on whitespace and newlines, filter empties
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        let wordCount = words.count

        // Character counts
        let characterCount = text.count
        let characterCountNoSpaces = text.filter { !$0.isWhitespace }.count

        // Sentence count — use linguistic tagger for accuracy
        var sentenceCount = 0
        text.enumerateSubstrings(
            in: text.startIndex...,
            options: [.bySentences, .localized]
        ) { _, _, _, _ in
            sentenceCount += 1
        }
        // Fallback: at least 1 sentence if there's text
        if sentenceCount == 0 && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sentenceCount = 1
        }

        // Paragraph count — split by double newlines or single newlines
        let paragraphs = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let paragraphCount = max(paragraphs.count, text.isEmpty ? 0 : 1)

        // Average word length
        let totalCharacters = words.reduce(0) { $0 + $1.count }
        let averageWordLength = wordCount > 0
            ? Double(totalCharacters) / Double(wordCount)
            : 0.0

        // Reading time estimate (250 words per minute average)
        let readingTimeMinutes = Double(wordCount) / 250.0
        let readingTimeFormatted: String
        if readingTimeMinutes < 1.0 {
            let seconds = Int(readingTimeMinutes * 60)
            readingTimeFormatted = "\(max(seconds, 1)) seconds"
        } else {
            readingTimeFormatted = String(format: "%.1f minutes", readingTimeMinutes)
        }

        // Language detection using NLLanguageRecognizer
        let detectedLanguage: String
        if #available(iOS 12.0, macOS 10.14, *) {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(text)
            if let language = recognizer.dominantLanguage {
                detectedLanguage = Locale.current.localizedString(
                    forLanguageCode: language.rawValue
                ) ?? language.rawValue
            } else {
                detectedLanguage = "undetermined"
            }
        } else {
            detectedLanguage = "unavailable"
        }

        resultString = jsonString(from: [
            "word_count": wordCount,
            "character_count": characterCount,
            "character_count_no_spaces": characterCountNoSpaces,
            "sentence_count": sentenceCount,
            "paragraph_count": paragraphCount,
            "average_word_length": String(format: "%.1f", averageWordLength),
            "estimated_reading_time": readingTimeFormatted,
            "detected_language": detectedLanguage
        ])
        return resultString
    }
}
