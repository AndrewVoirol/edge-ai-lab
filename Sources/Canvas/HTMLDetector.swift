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

// MARK: - HTML Detector

/// Detects and extracts HTML content from model output for Canvas rendering.
///
/// Used by `CodeBlockView` to decide whether to show the "Open in Canvas" button,
/// and by `CanvasPanelView` to extract renderable HTML from code blocks.
///
/// Follows the project pattern of `enum` namespaces with `static` methods
/// for testable logic that doesn't belong in SwiftUI views.
enum HTMLDetector {

    /// Languages that indicate an HTML code block suitable for Canvas rendering.
    private static let htmlLanguages: Set<String> = ["html", "htm", "svg", "canvas"]

    /// Checks whether a code block's language tag indicates HTML content.
    ///
    /// - Parameter language: The language identifier from a fenced code block (e.g., "html", "svg").
    /// - Returns: `true` if the language is recognized as HTML-renderable.
    static func isHTMLCodeBlock(language: String?) -> Bool {
        guard let lang = language?.lowercased().trimmingCharacters(in: .whitespaces) else {
            return false
        }
        return htmlLanguages.contains(lang)
    }

    /// Extracts HTML content from a fenced code block string.
    ///
    /// Handles both triple-backtick (```) and triple-tilde (~~~) fencing.
    /// Returns the inner content if the block starts with a recognized HTML language tag.
    ///
    /// - Parameter codeBlock: The raw fenced code block text, including the fence lines.
    /// - Returns: The extracted HTML string, or `nil` if the block isn't a recognized HTML block.
    static func extractHTML(from codeBlock: String) -> String? {
        let lines = codeBlock.components(separatedBy: "\n")
        guard lines.count >= 3 else { return nil }

        let firstLine = lines[0].trimmingCharacters(in: .whitespaces)

        // Check for ``` or ~~~ fencing
        let fenceChar: Character
        if firstLine.hasPrefix("```") {
            fenceChar = "`"
        } else if firstLine.hasPrefix("~~~") {
            fenceChar = "~"
        } else {
            return nil
        }

        // Extract language from the opening fence
        let fencePrefix = String(repeating: String(fenceChar), count: 3)
        let langTag = firstLine.dropFirst(fencePrefix.count)
            .trimmingCharacters(in: .whitespaces)
            .lowercased()

        guard htmlLanguages.contains(langTag) else { return nil }

        // Find the closing fence
        let closingFence = fencePrefix
        guard let lastFenceIndex = lines.lastIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix(closingFence)
        }), lastFenceIndex > 0 else {
            return nil
        }

        // Extract content between fences
        let contentLines = lines[1..<lastFenceIndex]
        let content = contentLines.joined(separator: "\n")
        return content.isEmpty ? nil : content
    }

    /// Checks whether raw text contains an HTML document or standalone SVG.
    ///
    /// Detects `<!DOCTYPE html>`, `<html>`, and standalone `<svg>` elements.
    /// Does NOT match partial HTML fragments like lone `<div>` tags to avoid
    /// false positives in markdown content.
    ///
    /// - Parameter text: The raw text to check.
    /// - Returns: `true` if the text appears to contain a renderable HTML document.
    static func containsHTMLDocument(_ text: String) -> Bool {
        let lowered = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for DOCTYPE declaration
        if lowered.contains("<!doctype html") {
            return true
        }
        
        // Check for <html> tag (with optional attributes)
        if lowered.range(of: #"<html[\s>]"#, options: .regularExpression) != nil {
            return true
        }

        // Check for standalone <svg> (with optional attributes)
        if lowered.range(of: #"<svg[\s>]"#, options: .regularExpression) != nil {
            return true
        }

        return false
    }
}
