import Foundation

// MARK: - MCP Server Management

/// Extension extracting MCP server lifecycle management from ConversationViewModel.
/// Manages client connections, configuration CRUD, and state queries.
extension ConversationViewModel {

    #if os(macOS)
    func startEnabledMCPServers() async {
        for config in mcpServers where config.enabled {
            await startMCPServer(config)
        }
    }

    func startMCPServer(_ config: MCPServerConfig) async {
        if let existing = activeClients[config.id] {
            existing.stop()
        }

        let client = MCPClient(config: config)
        activeClients[config.id] = client

        client.onStateChange = { [weak self] _ in
            Task { @MainActor in
                if let idx = self?.mcpServers.firstIndex(where: { $0.id == config.id }) {
                    // Mutate to trigger UI update
                    self?.mcpServers[idx] = config
                }
            }
        }

        await client.start()
    }

    func stopMCPServer(id: UUID) {
        if let client = activeClients.removeValue(forKey: id) {
            client.stop()
        }
    }
    #endif

    func updateMCPServerConfig(_ config: MCPServerConfig) {
        if let idx = mcpServers.firstIndex(where: { $0.id == config.id }) {
            mcpServers[idx] = config
            MCPServerStorage.save(mcpServers)

            #if os(macOS)
            if config.enabled {
                Task {
                    await startMCPServer(config)
                }
            } else {
                stopMCPServer(id: config.id)
            }
            #endif
        }
    }

    func addMCPServerConfig(_ config: MCPServerConfig) {
        mcpServers.append(config)
        MCPServerStorage.save(mcpServers)
        #if os(macOS)
        if config.enabled {
            Task {
                await startMCPServer(config)
            }
        }
        #endif
    }

    func deleteMCPServerConfig(id: UUID) {
        #if os(macOS)
        stopMCPServer(id: id)
        #endif
        mcpServers.removeAll(where: { $0.id == id })
        MCPServerStorage.save(mcpServers)
    }

    func getMCPClientState(for id: UUID) -> MCPClientState {
        #if os(macOS)
        return activeClients[id]?.state ?? .stopped
        #else
        return .stopped
        #endif
    }

    func getMCPTools(for id: UUID) -> [MCPToolInfo] {
        if case .connected(let tools) = getMCPClientState(for: id) {
            return tools
        }
        return []
    }
}
