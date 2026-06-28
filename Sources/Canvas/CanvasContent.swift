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

// MARK: - Canvas Content

/// Represents HTML content extracted from model output for rendering in the Canvas panel.
///
/// Each `CanvasContent` instance captures a snapshot of HTML at the time the user
/// clicks "Open in Canvas" — it's not live-updated as the model streams.
struct CanvasContent: Identifiable, Sendable {
    /// Unique identifier for this canvas content instance.
    let id: UUID

    /// The raw HTML string to render in the WKWebView.
    let htmlContent: String

    /// The language tag from the source code block (e.g., "html", "svg").
    let language: String?

    /// The UUID of the ChatMessage that produced this content.
    let sourceMessageId: UUID

    /// When this content was created.
    let createdAt: Date

    /// Memberwise initializer with defaults for convenience.
    init(
        id: UUID = UUID(),
        htmlContent: String,
        language: String? = nil,
        sourceMessageId: UUID,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.htmlContent = htmlContent
        self.language = language
        self.sourceMessageId = sourceMessageId
        self.createdAt = createdAt
    }
}

// MARK: - Dark Mode CSS Injection

/// Helper for generating dark-mode CSS to inject into Canvas HTML content.
///
/// Follows the project pattern of `enum` namespaces with `static` methods
/// for testable logic.
enum CanvasDarkModeCSS {
    /// Dark Forest theme colors matching the app's design system.
    /// - Background: #0D1117 (deep dark matching backgroundPrimary feel)
    /// - Text: #C9D1D9 (soft cream matching textPrimary)
    static let darkModeStylesheet = """
    <style id="canvas-dark-mode">
        :root {
            color-scheme: dark;
        }
        body {
            background-color: #0D1117;
            color: #C9D1D9;
        }
        /* Ensure links are visible on dark background */
        a { color: #58A6FF; }
        a:visited { color: #8B949E; }
    </style>
    """

    /// Wraps raw HTML content with dark mode CSS injection.
    ///
    /// If the content already contains a `<head>` tag, the stylesheet is injected
    /// inside it. Otherwise, a `<head>` section is prepended.
    ///
    /// - Parameter html: The raw HTML content to wrap.
    /// - Returns: The HTML content with dark mode CSS injected.
    static func inject(into html: String) -> String {
        let lowered = html.lowercased()

        // If there's a <head> tag, inject after it
        if let headRange = lowered.range(of: "<head>") {
            let insertionIndex = html.index(headRange.upperBound, offsetBy: 0)
            var modified = html
            modified.insert(contentsOf: "\n\(darkModeStylesheet)\n", at: insertionIndex)
            return modified
        }

        // If there's an <html> tag but no <head>, add one
        if let htmlRange = lowered.range(of: "<html") {
            // Find the end of the <html> tag
            if let closeAngle = html[htmlRange.upperBound...].firstIndex(of: ">") {
                let insertionIndex = html.index(after: closeAngle)
                var modified = html
                modified.insert(contentsOf: "\n<head>\(darkModeStylesheet)</head>\n", at: insertionIndex)
                return modified
            }
        }

        // No <html> or <head> — prepend the stylesheet
        return "\(darkModeStylesheet)\n\(html)"
    }
}
