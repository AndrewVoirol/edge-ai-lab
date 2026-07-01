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

/// Tests for ConversationViewModel's MCP server management methods:
/// add, update, delete configs and query client state/tools.
/// Focuses on the cross-platform methods (no macOS-only MCP client start/stop).
@Suite("ConversationViewModel MCP")
@MainActor
struct ConversationViewModelMCPTests {

    // MARK: - Helpers

    /// Creates a ConversationViewModel with a mock engine and temp metrics store.
    private static func makeViewModel() -> ConversationViewModel {
        let engine = MockInferenceEngine.happyPath()
        let metricsFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_mcp_metrics_\(UUID().uuidString).json")
        let metricsStore = MetricsStore(fileURL: metricsFileURL)
        return ConversationViewModel(engine: engine, metricsStore: metricsStore)
    }

    private static func makeConfig(
        name: String = "Test Server",
        enabled: Bool = false,
        command: String = "/usr/bin/echo"
    ) -> MCPServerConfig {
        MCPServerConfig(
            name: name,
            enabled: enabled,
            command: command,
            args: [],
            env: [:]
        )
    }

    // MARK: - Add

    @Test("addMCPServerConfig adds the config to mcpServers")
    func testAddMCPServerConfig() {
        let vm = Self.makeViewModel()
        let initialCount = vm.mcpServers.count
        let config = Self.makeConfig(name: "New Server")

        vm.addMCPServerConfig(config)

        #expect(vm.mcpServers.count == initialCount + 1)
        #expect(vm.mcpServers.contains(where: { $0.id == config.id }))
        #expect(vm.mcpServers.last?.name == "New Server")
    }

    // MARK: - Update

    @Test("updateMCPServerConfig updates an existing config in place")
    func testUpdateMCPServerConfig() {
        let vm = Self.makeViewModel()
        var config = Self.makeConfig(name: "Original")
        vm.addMCPServerConfig(config)

        // Mutate the config
        config.name = "Updated"
        config.enabled = false
        vm.updateMCPServerConfig(config)

        let found = vm.mcpServers.first(where: { $0.id == config.id })
        #expect(found != nil, "Config should still exist after update")
        #expect(found?.name == "Updated", "Name should be updated")
    }

    // MARK: - Delete

    @Test("deleteMCPServerConfig removes the config from mcpServers")
    func testDeleteMCPServerConfig() {
        let vm = Self.makeViewModel()
        let config = Self.makeConfig(name: "ToDelete")
        vm.addMCPServerConfig(config)

        // Verify it was added
        #expect(vm.mcpServers.contains(where: { $0.id == config.id }))

        vm.deleteMCPServerConfig(id: config.id)

        #expect(!vm.mcpServers.contains(where: { $0.id == config.id }), "Config should be removed")
    }

    // MARK: - Client State

    @Test("getMCPClientState returns .stopped when no client exists")
    func testGetMCPClientStateStopped() {
        let vm = Self.makeViewModel()
        let randomId = UUID()

        let state = vm.getMCPClientState(for: randomId)

        #expect(state == .stopped, "State should be .stopped when no client is active")
    }

    // MARK: - Tools

    @Test("getMCPTools returns empty array when state is .stopped")
    func testGetMCPToolsEmpty() {
        let vm = Self.makeViewModel()
        let randomId = UUID()

        let tools = vm.getMCPTools(for: randomId)

        #expect(tools.isEmpty, "Tools should be empty when no client is connected")
    }
}
