import Foundation

/// Configuration for a local Model Context Protocol (MCP) server.
/// Exposes stdio transport configuration for macOS background processes.
public struct MCPServerConfig: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var enabled: Bool
    public var command: String
    public var args: [String]
    public var env: [String: String]

    public init(id: UUID = UUID(), name: String, enabled: Bool = false, command: String, args: [String] = [], env: [String: String] = [:]) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.command = command
        self.args = args
        self.env = env
    }
}

/// Persistence helper for managing MCP server configurations via UserDefaults.
public enum MCPServerStorage {
    private static let key = "com.andrewvoirol.GemmaEdgeGallery.mcpServers"

    /// Save the list of MCP server configurations.
    public static func save(_ configs: [MCPServerConfig]) {
        do {
            let data = try JSONEncoder().encode(configs)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            print("Failed to save MCP server configs: \(error)")
        }
    }

    /// Load the list of MCP server configurations, with fallback to default templates if empty.
    public static func load() -> [MCPServerConfig] {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            let defaults = createDefaultTemplates()
            save(defaults)
            return defaults
        }
        do {
            return try JSONDecoder().decode([MCPServerConfig].self, from: data)
        } catch {
            print("Failed to decode MCP server configs: \(error)")
            return createDefaultTemplates()
        }
    }

    /// Pre-populates default MCP templates (disabled by default) to assist the user.
    private static func createDefaultTemplates() -> [MCPServerConfig] {
        return [
            MCPServerConfig(
                name: "Filesystem Tool (Example)",
                enabled: false,
                command: "/usr/local/bin/node",
                args: ["/opt/homebrew/lib/node_modules/@modelcontextprotocol/server-filesystem/dist/index.js", "/Users/shared"],
                env: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"]
            ),
            MCPServerConfig(
                name: "Git Inspector (Example)",
                enabled: false,
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-git", "--repository", "/Users/shared/project"],
                env: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin"]
            )
        ]
    }
}
