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

/// Tests for `FileSearchTool`, which searches for files by name using
/// Spotlight (macOS) or FileManager (iOS).
@Suite struct FileSearchToolTests {

    // MARK: - Tool Identity

    @Test("Tool name is search_files")
    func toolName() {
        #expect(FileSearchTool.name == "search_files")
    }

    @Test("Tool description is non-empty")
    func toolDescription() {
        #expect(!FileSearchTool.description.isEmpty)
    }

    @Test("Tool is registered in ToolRegistry")
    func registeredInRegistry() {
        let toolNames = ToolRegistry.defaultTools.map { type(of: $0).name }
        #expect(toolNames.contains("search_files"))
    }

    // MARK: - Empty Query

    @Test("Empty query returns error JSON")
    func emptyQueryReturnsError() async throws {
        var tool = FileSearchTool()
        tool.query = ""
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("error"))
        #expect(json.contains("Search query is required"))
    }

    @Test("Whitespace-only query returns error JSON")
    func whitespaceQueryReturnsError() async throws {
        var tool = FileSearchTool()
        tool.query = "   "
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("error"))
    }

    // MARK: - Valid Query

    @Test("Valid query returns JSON with expected keys")
    func validQueryReturnsExpectedKeys() async throws {
        var tool = FileSearchTool()
        tool.query = "test"
        let result = try await tool.run()
        let json = try #require(result as? String)
        // Should contain structural keys regardless of results
        #expect(json.contains("results"))
        #expect(json.contains("count"))
        #expect(json.contains("query"))
    }

    @Test("Query is echoed back in response")
    func queryEchoedInResponse() async throws {
        var tool = FileSearchTool()
        tool.query = "uniqueSearchTerm12345"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("uniqueSearchTerm12345"))
    }

    @Test("Result JSON is parseable")
    func resultIsParseable() async throws {
        var tool = FileSearchTool()
        tool.query = "test"
        let result = try await tool.run()
        let json = try #require(result as? String)
        let data = json.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(parsed != nil)
    }

    @Test("Source field indicates search method")
    func sourceFieldPresent() async throws {
        var tool = FileSearchTool()
        tool.query = "test"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("source"))
        #if os(macOS)
        #expect(json.contains("spotlight"))
        #elseif os(iOS)
        #expect(json.contains("documents"))
        #endif
    }
}
