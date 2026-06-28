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

/// Tests for `WiFiTool`, which reports network connectivity information
/// via NWPathMonitor and CoreWLAN (macOS).
@Suite struct WiFiToolTests {

    // MARK: - Tool Identity

    @Test("Tool name is get_network_info")
    func toolName() {
        #expect(WiFiTool.name == "get_network_info")
    }

    @Test("Tool description is non-empty")
    func toolDescription() {
        #expect(!WiFiTool.description.isEmpty)
    }

    @Test("Tool is registered in ToolRegistry")
    func registeredInRegistry() {
        let toolNames = ToolRegistry.defaultTools.map { type(of: $0).name }
        #expect(toolNames.contains("get_network_info"))
    }

    // MARK: - JSON Structure

    @Test("Result contains status key")
    func resultContainsStatus() async throws {
        let tool = WiFiTool()
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("status"))
    }

    @Test("Result contains interface_type key")
    func resultContainsInterfaceType() async throws {
        let tool = WiFiTool()
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("interface_type"))
    }

    @Test("Result contains platform key")
    func resultContainsPlatform() async throws {
        let tool = WiFiTool()
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("platform"))
    }

    @Test("Result contains timestamp")
    func resultContainsTimestamp() async throws {
        let tool = WiFiTool()
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("timestamp"))
    }

    @Test("Result JSON is parseable")
    func resultIsParseable() async throws {
        let tool = WiFiTool()
        let result = try await tool.run()
        let json = try #require(result as? String)
        let data = json.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(parsed != nil)
    }

    @Test("Result contains is_expensive field")
    func resultContainsIsExpensive() async throws {
        let tool = WiFiTool()
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("is_expensive"))
    }

    @Test("Result contains is_constrained field")
    func resultContainsIsConstrained() async throws {
        let tool = WiFiTool()
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("is_constrained"))
    }
}
