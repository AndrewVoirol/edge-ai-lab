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

// MARK: - Canvas Content Tests

/// Tests for `CanvasContent` and `CanvasDarkModeCSS`.
@Suite("CanvasContent Tests")
struct CanvasContentTests {

    // MARK: - CanvasContent Model

    @Suite("CanvasContent Model")
    struct ModelTests {
        @Test("Creates CanvasContent with all fields")
        func createWithAllFields() {
            let id = UUID()
            let messageId = UUID()
            let date = Date()
            let content = CanvasContent(
                id: id,
                htmlContent: "<h1>Hello</h1>",
                language: "html",
                sourceMessageId: messageId,
                createdAt: date
            )

            #expect(content.id == id)
            #expect(content.htmlContent == "<h1>Hello</h1>")
            #expect(content.language == "html")
            #expect(content.sourceMessageId == messageId)
            #expect(content.createdAt == date)
        }

        @Test("Creates CanvasContent with default values")
        func createWithDefaults() {
            let messageId = UUID()
            let before = Date()
            let content = CanvasContent(
                htmlContent: "<p>Test</p>",
                sourceMessageId: messageId
            )
            let after = Date()

            #expect(content.htmlContent == "<p>Test</p>")
            #expect(content.language == nil)
            #expect(content.sourceMessageId == messageId)
            #expect(content.createdAt >= before)
            #expect(content.createdAt <= after)
        }

        @Test("Each instance has unique ID by default")
        func uniqueIds() {
            let messageId = UUID()
            let a = CanvasContent(htmlContent: "<div>A</div>", sourceMessageId: messageId)
            let b = CanvasContent(htmlContent: "<div>B</div>", sourceMessageId: messageId)
            #expect(a.id != b.id)
        }

        @Test("Conforms to Identifiable")
        func identifiable() {
            let content = CanvasContent(
                htmlContent: "<p>ID test</p>",
                sourceMessageId: UUID()
            )
            // Identifiable conformance is compile-time — this test verifies
            // the id property is accessible.
            let _ = content.id
        }

        @Test("Conforms to Sendable")
        func sendable() {
            // Sendable conformance is compile-time — this test verifies
            // CanvasContent can be passed across actor boundaries.
            let content = CanvasContent(
                htmlContent: "<p>Sendable test</p>",
                sourceMessageId: UUID()
            )
            Task {
                let _ = content.htmlContent
            }
        }
    }

    // MARK: - Dark Mode CSS Injection

    @Suite("CanvasDarkModeCSS")
    struct DarkModeCSSTests {
        @Test("Dark mode stylesheet contains expected background color")
        func stylesheetContainsBackground() {
            #expect(CanvasDarkModeCSS.darkModeStylesheet.contains("#0D1117"))
        }

        @Test("Dark mode stylesheet contains expected text color")
        func stylesheetContainsTextColor() {
            #expect(CanvasDarkModeCSS.darkModeStylesheet.contains("#C9D1D9"))
        }

        @Test("Dark mode stylesheet includes link colors")
        func stylesheetContainsLinkColor() {
            #expect(CanvasDarkModeCSS.darkModeStylesheet.contains("#58A6FF"))
        }

        @Test("Injects into HTML with <head> tag")
        func injectsIntoHead() {
            let html = "<html><head><title>Test</title></head><body><p>Hi</p></body></html>"
            let result = CanvasDarkModeCSS.inject(into: html)
            #expect(result.contains("#0D1117"))
            #expect(result.contains("<head>"))
            // Stylesheet should be after <head>
            let headIndex = result.range(of: "<head>")!.upperBound
            let styleIndex = result.range(of: "#0D1117")!.lowerBound
            #expect(styleIndex > headIndex)
        }

        @Test("Injects into HTML with <html> but no <head>")
        func injectsIntoHtmlNoHead() {
            let html = "<html><body><p>No head</p></body></html>"
            let result = CanvasDarkModeCSS.inject(into: html)
            #expect(result.contains("#0D1117"))
            #expect(result.contains("<head>"))
        }

        @Test("Injects into HTML with <html> attributes but no <head>")
        func injectsIntoHtmlWithAttributes() {
            let html = "<html lang=\"en\"><body><p>Attributes</p></body></html>"
            let result = CanvasDarkModeCSS.inject(into: html)
            #expect(result.contains("#0D1117"))
        }

        @Test("Prepends to HTML without <html> or <head>")
        func prependsToRawHtml() {
            let html = "<div><p>Raw content</p></div>"
            let result = CanvasDarkModeCSS.inject(into: html)
            #expect(result.contains("#0D1117"))
            // Stylesheet should come before the content
            let styleIndex = result.range(of: "#0D1117")!.lowerBound
            let contentIndex = result.range(of: "<div>")!.lowerBound
            #expect(styleIndex < contentIndex)
        }

        @Test("Preserves original content after injection")
        func preservesOriginalContent() {
            let html = "<html><head></head><body><h1>Keep Me</h1></body></html>"
            let result = CanvasDarkModeCSS.inject(into: html)
            #expect(result.contains("<h1>Keep Me</h1>"))
            #expect(result.contains("</body>"))
            #expect(result.contains("</html>"))
        }

        @Test("Handles empty HTML string")
        func handlesEmptyHtml() {
            let result = CanvasDarkModeCSS.inject(into: "")
            #expect(result.contains("#0D1117"))
        }

        @Test("Handles SVG content (no head/html)")
        func handlesSvgContent() {
            let svg = "<svg width=\"100\" height=\"100\"><circle cx=\"50\" cy=\"50\" r=\"40\"/></svg>"
            let result = CanvasDarkModeCSS.inject(into: svg)
            #expect(result.contains("#0D1117"))
            #expect(result.contains("<svg"))
        }
    }
}
