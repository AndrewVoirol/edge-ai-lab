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

import Testing
import Foundation

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - HTML Detector Tests

/// Tests for `HTMLDetector` — code block language detection, HTML extraction,
/// and full document detection.
@Suite("HTMLDetector Tests")
struct HTMLDetectorTests {

    // MARK: - isHTMLCodeBlock

    @Suite("isHTMLCodeBlock")
    struct IsHTMLCodeBlockTests {
        @Test("Detects 'html' as HTML code block")
        func detectsHtml() {
            #expect(HTMLDetector.isHTMLCodeBlock(language: "html") == true)
        }

        @Test("Detects 'HTML' (uppercase) as HTML code block")
        func detectsHtmlUppercase() {
            #expect(HTMLDetector.isHTMLCodeBlock(language: "HTML") == true)
        }

        @Test("Detects 'htm' as HTML code block")
        func detectsHtm() {
            #expect(HTMLDetector.isHTMLCodeBlock(language: "htm") == true)
        }

        @Test("Detects 'svg' as HTML code block")
        func detectsSvg() {
            #expect(HTMLDetector.isHTMLCodeBlock(language: "svg") == true)
        }

        @Test("Detects 'canvas' as HTML code block")
        func detectsCanvas() {
            #expect(HTMLDetector.isHTMLCodeBlock(language: "canvas") == true)
        }

        @Test("Detects 'Html' (mixed case) as HTML code block")
        func detectsMixedCase() {
            #expect(HTMLDetector.isHTMLCodeBlock(language: "Html") == true)
        }

        @Test("Returns false for nil language")
        func nilLanguage() {
            #expect(HTMLDetector.isHTMLCodeBlock(language: nil) == false)
        }

        @Test("Returns false for 'python'")
        func rejectsPython() {
            #expect(HTMLDetector.isHTMLCodeBlock(language: "python") == false)
        }

        @Test("Returns false for 'swift'")
        func rejectsSwift() {
            #expect(HTMLDetector.isHTMLCodeBlock(language: "swift") == false)
        }

        @Test("Returns false for 'javascript'")
        func rejectsJavascript() {
            #expect(HTMLDetector.isHTMLCodeBlock(language: "javascript") == false)
        }

        @Test("Returns false for empty string")
        func rejectsEmptyString() {
            #expect(HTMLDetector.isHTMLCodeBlock(language: "") == false)
        }

        @Test("Handles whitespace in language")
        func handlesWhitespace() {
            #expect(HTMLDetector.isHTMLCodeBlock(language: " html ") == true)
        }
    }

    // MARK: - extractHTML

    @Suite("extractHTML")
    struct ExtractHTMLTests {
        @Test("Extracts HTML from backtick-fenced code block")
        func extractsFromBackticks() {
            let block = """
            ```html
            <div>Hello, World!</div>
            ```
            """
            let result = HTMLDetector.extractHTML(from: block)
            #expect(result == "<div>Hello, World!</div>")
        }

        @Test("Extracts HTML from tilde-fenced code block")
        func extractsFromTildes() {
            let block = """
            ~~~html
            <p>Test</p>
            ~~~
            """
            let result = HTMLDetector.extractHTML(from: block)
            #expect(result == "<p>Test</p>")
        }

        @Test("Extracts multi-line HTML")
        func extractsMultiLine() {
            let block = """
            ```html
            <!DOCTYPE html>
            <html>
            <body><h1>Title</h1></body>
            </html>
            ```
            """
            let result = HTMLDetector.extractHTML(from: block)
            #expect(result != nil)
            #expect(result!.contains("<!DOCTYPE html>"))
            #expect(result!.contains("<h1>Title</h1>"))
        }

        @Test("Extracts SVG from code block")
        func extractsSvg() {
            let block = """
            ```svg
            <svg width="100" height="100"><circle cx="50" cy="50" r="40"/></svg>
            ```
            """
            let result = HTMLDetector.extractHTML(from: block)
            #expect(result != nil)
            #expect(result!.contains("<svg"))
        }

        @Test("Returns nil for non-HTML language")
        func nilForNonHtml() {
            let block = """
            ```python
            print("hello")
            ```
            """
            let result = HTMLDetector.extractHTML(from: block)
            #expect(result == nil)
        }

        @Test("Returns nil for too-short input")
        func nilForShortInput() {
            let result = HTMLDetector.extractHTML(from: "```html\n```")
            #expect(result == nil)
        }

        @Test("Returns nil for non-fenced input")
        func nilForNonFenced() {
            let result = HTMLDetector.extractHTML(from: "<div>Not fenced</div>")
            #expect(result == nil)
        }

        @Test("Returns nil for fenced block with no closing fence")
        func nilForNoClosingFence() {
            let result = HTMLDetector.extractHTML(from: "```html\n<div>Unclosed</div>")
            #expect(result == nil)
        }
    }

    // MARK: - containsHTMLDocument

    @Suite("containsHTMLDocument")
    struct ContainsHTMLDocumentTests {
        @Test("Detects DOCTYPE html")
        func detectsDoctype() {
            #expect(HTMLDetector.containsHTMLDocument("<!DOCTYPE html><html><body></body></html>") == true)
        }

        @Test("Detects DOCTYPE HTML (uppercase)")
        func detectsDoctypeUppercase() {
            #expect(HTMLDetector.containsHTMLDocument("<!DOCTYPE HTML>") == true)
        }

        @Test("Detects <html> tag")
        func detectsHtmlTag() {
            #expect(HTMLDetector.containsHTMLDocument("<html><body>Content</body></html>") == true)
        }

        @Test("Detects <html lang='en'> with attributes")
        func detectsHtmlWithAttributes() {
            #expect(HTMLDetector.containsHTMLDocument("<html lang=\"en\"><body></body></html>") == true)
        }

        @Test("Detects standalone <svg>")
        func detectsSvg() {
            #expect(HTMLDetector.containsHTMLDocument("<svg width=\"100\" height=\"100\"><circle/></svg>") == true)
        }

        @Test("Returns false for plain text")
        func rejectsPlainText() {
            #expect(HTMLDetector.containsHTMLDocument("Hello, World!") == false)
        }

        @Test("Returns false for HTML fragments (no document structure)")
        func rejectsFragments() {
            #expect(HTMLDetector.containsHTMLDocument("<div><p>A paragraph</p></div>") == false)
        }

        @Test("Returns false for markdown with angle brackets")
        func rejectsMarkdown() {
            #expect(HTMLDetector.containsHTMLDocument("Use `<div>` for containers") == false)
        }

        @Test("Returns false for empty string")
        func rejectsEmpty() {
            #expect(HTMLDetector.containsHTMLDocument("") == false)
        }

        @Test("Handles whitespace-padded input")
        func handlesWhitespace() {
            #expect(HTMLDetector.containsHTMLDocument("  \n  <!DOCTYPE html>\n  <html>\n  </html>  ") == true)
        }
    }
}
