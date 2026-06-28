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

    // MARK: - Edge Cases: Nested & Extended Fencing

    @Suite("Edge Cases: Fencing")
    struct FencingEdgeCaseTests {
        @Test("Nested code fences — inner ``` inside outer ```html")
        func nestedCodeFences() {
            // Model output may include nested fences when explaining code
            let block = """
            ```html
            <div>
            <pre>```
            some code
            ```</pre>
            </div>
            ```
            """
            let result = HTMLDetector.extractHTML(from: block)
            // Should extract content — inner ``` is treated as part of the HTML
            #expect(result != nil)
            #expect(result!.contains("<div>"))
        }

        @Test("Extra backticks (````) — four-backtick fence with html tag")
        func extraBackticks() {
            // Some markdown renderers use 4+ backticks for nested code
            let block = """
            ````html
            <p>Four backticks</p>
            ````
            """
            let result = HTMLDetector.extractHTML(from: block)
            // Our detector uses hasPrefix("```") so ```` also matches
            #expect(result != nil)
            #expect(result!.contains("<p>Four backticks</p>"))
        }

        @Test("Five backticks — also handled by hasPrefix")
        func fiveBackticks() {
            let block = """
            `````html
            <h2>Five</h2>
            `````
            """
            let result = HTMLDetector.extractHTML(from: block)
            #expect(result != nil)
            #expect(result!.contains("<h2>Five</h2>"))
        }

        @Test("Mixed fence types — opens with ``` but closes with ~~~")
        func mixedFenceTypes() {
            let block = """
            ```html
            <div>Mixed</div>
            ~~~
            """
            // lastIndex(where: hasPrefix("```")) won't find "~~~",
            // so this should return nil — no matching close fence
            let result = HTMLDetector.extractHTML(from: block)
            #expect(result == nil)
        }

        @Test("Indented fence lines")
        func indentedFenceLines() {
            let block = """
              ```html
              <p>Indented</p>
              ```
            """
            let result = HTMLDetector.extractHTML(from: block)
            // trimmingCharacters handles leading whitespace on fence lines
            #expect(result != nil)
        }
    }

    // MARK: - Edge Cases: Security & XSS

    @Suite("Edge Cases: Security")
    struct SecurityEdgeCaseTests {
        @Test("XSS script tag — detected as HTML and extractable")
        func xssScriptTag() {
            // <script> content IS valid HTML — Canvas should render it
            // (network is blocked by WKContentRuleList, not by detection)
            let block = """
            ```html
            <html><body><script>alert(1)</script></body></html>
            ```
            """
            let result = HTMLDetector.extractHTML(from: block)
            #expect(result != nil)
            #expect(result!.contains("<script>alert(1)</script>"))
        }

        @Test("XSS with event handler — detected as HTML")
        func xssEventHandler() {
            let block = """
            ```html
            <img src=x onerror="alert('xss')">
            ```
            """
            let result = HTMLDetector.extractHTML(from: block)
            #expect(result != nil)
            #expect(result!.contains("onerror"))
        }

        @Test("Script language tag is NOT HTML-renderable")
        func scriptLanguageNotRenderable() {
            // Language "javascript" or "js" blocks should not show Canvas button
            #expect(HTMLDetector.isHTMLCodeBlock(language: "javascript") == false)
            #expect(HTMLDetector.isHTMLCodeBlock(language: "js") == false)
        }

        @Test("containsHTMLDocument detects script-laden document")
        func detectsDocumentWithScript() {
            let xss = """
            <!DOCTYPE html>
            <html>
            <body><script>document.cookie</script></body>
            </html>
            """
            // Still a valid HTML document — detection should return true
            #expect(HTMLDetector.containsHTMLDocument(xss) == true)
        }
    }

    // MARK: - Edge Cases: Large & Empty Content

    @Suite("Edge Cases: Large & Empty Content")
    struct LargeContentEdgeCaseTests {
        @Test("Very large HTML (100KB+) — no crash")
        func largeHtmlNoCrash() {
            // Generate 100KB+ of HTML content
            let repeatedDiv = "<div><p>Row of content with enough text to pad the file.</p></div>\n"
            let count = (100_000 / repeatedDiv.utf8.count) + 1
            let largeBody = String(repeating: repeatedDiv, count: count)
            let largeHTML = "<html><head></head><body>\(largeBody)</body></html>"

            // Verify it's actually > 100KB
            #expect(largeHTML.utf8.count > 100_000)

            // Detection should still work
            #expect(HTMLDetector.containsHTMLDocument(largeHTML) == true)
        }

        @Test("Large HTML in fenced block — extractable without crash")
        func largeHtmlFencedBlock() {
            let repeatedP = "<p>Test paragraph content.</p>\n"
            let count = (100_000 / repeatedP.utf8.count) + 1
            let largeBody = String(repeating: repeatedP, count: count)
            let block = "```html\n\(largeBody)```"

            let result = HTMLDetector.extractHTML(from: block)
            #expect(result != nil)
            #expect(result!.utf8.count > 100_000)
        }

        @Test("Empty HTML body — fenced block with only whitespace between fences")
        func emptyHtmlBody() {
            // Use explicit construction to avoid multiline string indentation issues
            let block = "```html\n\n```"
            let result = HTMLDetector.extractHTML(from: block)
            // An empty line between fences is non-empty content (the newline itself)
            // But the joined content is "" which IS empty → returns nil
            // This is correct: truly empty code blocks have no renderable content
            #expect(result == nil)
        }

        @Test("HTML with only a single space as body")
        func singleSpaceBody() {
            let block = "```html\n \n```"
            let result = HTMLDetector.extractHTML(from: block)
            // A single space is technically non-empty content
            #expect(result != nil)
        }

        @Test("containsHTMLDocument with very long non-HTML text")
        func longNonHtmlText() {
            let longText = String(repeating: "This is not HTML at all. ", count: 5000)
            #expect(HTMLDetector.containsHTMLDocument(longText) == false)
        }

        @Test("containsHTMLDocument with empty body tags")
        func emptyBodyTags() {
            #expect(HTMLDetector.containsHTMLDocument("<html></html>") == true)
        }
    }
}
