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
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Tests for `ShortcutsTool`, which configures Siri Shortcut metadata.
/// This is an experimental tool — tests verify input validation and JSON structure.
@Suite struct ShortcutsToolTests {

    // MARK: - Tool Identity

    @Test("Tool name is create_shortcut")
    func toolName() {
        #expect(ShortcutsTool.name == "create_shortcut")
    }

    @Test("Tool description is non-empty")
    func toolDescription() {
        #expect(!ShortcutsTool.description.isEmpty)
    }

    @Test("Tool is registered in ToolRegistry")
    func registeredInRegistry() {
        let toolNames = ToolRegistry.defaultTools.map { type(of: $0).name }
        #expect(toolNames.contains("create_shortcut"))
    }

    // MARK: - Input Validation

    @Test("Empty name returns error JSON")
    func emptyNameReturnsError() async throws {
        var tool = ShortcutsTool()
        tool.name = ""
        tool.prompt = "Test prompt"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("error"))
        #expect(json.contains("Shortcut name is required"))
    }

    @Test("Whitespace-only name returns error JSON")
    func whitespaceNameReturnsError() async throws {
        var tool = ShortcutsTool()
        tool.name = "   "
        tool.prompt = "Test prompt"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("error"))
    }

    @Test("Empty prompt returns error JSON")
    func emptyPromptReturnsError() async throws {
        var tool = ShortcutsTool()
        tool.name = "Test Shortcut"
        tool.prompt = ""
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("error"))
        #expect(json.contains("Prompt is required"))
    }

    // MARK: - Success Case

    @Test("Valid inputs return shortcut_configured status")
    func validInputsReturnSuccess() async throws {
        var tool = ShortcutsTool()
        tool.name = "Morning Briefing"
        tool.prompt = "Give me a morning briefing"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("shortcut_configured"))
        #expect(json.contains("Morning Briefing"))
        #expect(json.contains("Give me a morning briefing"))
    }

    @Test("Response includes name and prompt echoed back")
    func responseEchosInputs() async throws {
        var tool = ShortcutsTool()
        tool.name = "Daily Summary"
        tool.prompt = "Summarize my day"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("Daily Summary"))
        #expect(json.contains("Summarize my day"))
    }

    @Test("Success response is parseable JSON")
    func successResponseIsParseable() async throws {
        var tool = ShortcutsTool()
        tool.name = "Test"
        tool.prompt = "Test prompt"
        let result = try await tool.run()
        let json = try #require(result as? String)
        let data = json.data(using: .utf8)!
        let rawParsed = try? JSONSerialization.jsonObject(with: data)
        let parsed = rawParsed as? [String: Any]
        #expect(parsed != nil)
        let status = parsed?["status"] as? String
        #expect(status == "shortcut_configured")
    }

    @Test("Success response includes note about AppIntents")
    func successResponseIncludesNote() async throws {
        var tool = ShortcutsTool()
        tool.name = "Test"
        tool.prompt = "Test prompt"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("note"))
        #expect(json.contains("AppIntents"))
    }
}
