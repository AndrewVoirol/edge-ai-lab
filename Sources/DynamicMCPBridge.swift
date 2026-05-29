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
import LiteRTLM
import os

// MARK: - AnyDecodable Helper

/// Decodable wrapper to decode arbitrary JSON-like dictionaries in dynamic tools.
struct AnyDecodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyDecodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyDecodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode AnyDecodable")
        }
    }
}

struct DynamicKey: CodingKey {
    var stringValue: String
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int?
    init?(intValue: Int) { nil }
}

// MARK: - Dynamic MCP Tool Type Pool

/// Shared manager that assigns dynamic tools to the static Type Pool.
public final class MCPBridgeManager: @unchecked Sendable {
    public static let shared = MCPBridgeManager()

    private let lock = NSRecursiveLock()
    private var currentIndex = 0
    private var clients: [String: MCPClient] = [:]

    private init() {}

    /// Registers active MCP clients to locate their handlers during execution.
    public func register(client: MCPClient) {
        lock.lock()
        defer { lock.unlock() }
        clients[client.config.name] = client
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        currentIndex = 0
        clients.removeAll()
    }

    /// Map a list of dynamic MCP tools to our static pool.
    /// - Returns: A list of configured Tool instances ready for registration.
    public func bridge(tools: [MCPToolInfo], client: MCPClient) -> [Tool] {
        lock.lock()
        defer { lock.unlock() }

        clients[client.config.name] = client

        var bridged: [Tool] = []

        for tool in tools {
            guard currentIndex < pool.count else {
                Logger(subsystem: "com.andrewvoirol.GemmaEdgeGallery", category: "mcp").warning("⚠️ MCP Tool pool exhausted! Cannot register tool: \(tool.name, privacy: .public)")
                break
            }

            let mcpToolType = pool[currentIndex]
            currentIndex += 1

            // Configure the static Type parameters
            mcpToolType.configure(
                name: tool.name,
                description: tool.description,
                schema: serializeSchema(tool: tool),
                handler: { [weak client] args in
                    guard let client = client else {
                        throw NSError(domain: "MCPBridgeManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Client deallocated"])
                    }
                    return try await client.callTool(name: tool.name, arguments: args)
                }
            )

            // Instantiate a new copy to pass to LiteRT-LM config
            bridged.append(mcpToolType.init())
        }

        return bridged
    }

    private func serializeSchema(tool: MCPToolInfo) -> [String: Any] {
        // Convert [String: AnyCodable] inputSchema back to [String: Any]
        var schemaDict: [String: Any] = [:]
        for (k, v) in tool.inputSchema {
            schemaDict[k] = v.value.value
        }
        return [
            "type": "function",
            "function": [
                "name": tool.name,
                "description": tool.description,
                "parameters": schemaDict
            ]
        ]
    }

    // List of static types in the pool
    private let pool: [DynamicMCPToolType.Type] = [
        DynamicMCPTool1.self,
        DynamicMCPTool2.self,
        DynamicMCPTool3.self,
        DynamicMCPTool4.self,
        DynamicMCPTool5.self,
        DynamicMCPTool6.self,
        DynamicMCPTool7.self,
        DynamicMCPTool8.self,
        DynamicMCPTool9.self,
        DynamicMCPTool10.self
    ]
}

// MARK: - Dynamic MCP Tool Type Protocols & Types

protocol DynamicMCPToolType: Tool {
    static func configure(
        name: String,
        description: String,
        schema: [String: Any],
        handler: @escaping ([String: Any]) async throws -> Any
    )
}

// Macro-like pre-baked types conforming to dynamic setup
public struct DynamicMCPTool1: DynamicMCPToolType {
    public static var name: String { _name }
    public static var description: String { _description }

    private static var _name = "dynamic_mcp_1"
    private static var _description = ""
    private static var _schema: [String: Any] = [:]
    private static var _handler: (([String: Any]) async throws -> Any)?

    public var arguments: [String: Any] = [:]

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var args: [String: Any] = [:]
        for key in container.allKeys {
            if let val = try? container.decode(AnyDecodable.self, forKey: key) {
                args[key.stringValue] = val.value
            }
        }
        self.arguments = args
    }

    public static func configure(name: String, description: String, schema: [String: Any], handler: @escaping ([String: Any]) async throws -> Any) {
        _name = name
        _description = description
        _schema = schema
        _handler = handler
    }

    public func getSchema() -> [String: Any] {
        return Self._schema
    }

    public func run() async throws -> Any {
        guard let handler = Self._handler else {
            return ["error": "Handler not configured"]
        }
        return try await handler(arguments)
    }
}

public struct DynamicMCPTool2: DynamicMCPToolType {
    public static var name: String { _name }
    public static var description: String { _description }
    private static var _name = "dynamic_mcp_2"
    private static var _description = ""
    private static var _schema: [String: Any] = [:]
    private static var _handler: (([String: Any]) async throws -> Any)?
    public var arguments: [String: Any] = [:]
    public init() {}
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var args: [String: Any] = [:]
        for key in container.allKeys {
            if let val = try? container.decode(AnyDecodable.self, forKey: key) {
                args[key.stringValue] = val.value
            }
        }
        self.arguments = args
    }
    public static func configure(name: String, description: String, schema: [String: Any], handler: @escaping ([String: Any]) async throws -> Any) {
        _name = name
        _description = description
        _schema = schema
        _handler = handler
    }
    public func getSchema() -> [String: Any] { return Self._schema }
    public func run() async throws -> Any {
        guard let handler = Self._handler else { return ["error": "Handler not configured"] }
        return try await handler(arguments)
    }
}

public struct DynamicMCPTool3: DynamicMCPToolType {
    public static var name: String { _name }
    public static var description: String { _description }
    private static var _name = "dynamic_mcp_3"
    private static var _description = ""
    private static var _schema: [String: Any] = [:]
    private static var _handler: (([String: Any]) async throws -> Any)?
    public var arguments: [String: Any] = [:]
    public init() {}
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var args: [String: Any] = [:]
        for key in container.allKeys {
            if let val = try? container.decode(AnyDecodable.self, forKey: key) {
                args[key.stringValue] = val.value
            }
        }
        self.arguments = args
    }
    public static func configure(name: String, description: String, schema: [String: Any], handler: @escaping ([String: Any]) async throws -> Any) {
        _name = name
        _description = description
        _schema = schema
        _handler = handler
    }
    public func getSchema() -> [String: Any] { return Self._schema }
    public func run() async throws -> Any {
        guard let handler = Self._handler else { return ["error": "Handler not configured"] }
        return try await handler(arguments)
    }
}

public struct DynamicMCPTool4: DynamicMCPToolType {
    public static var name: String { _name }
    public static var description: String { _description }
    private static var _name = "dynamic_mcp_4"
    private static var _description = ""
    private static var _schema: [String: Any] = [:]
    private static var _handler: (([String: Any]) async throws -> Any)?
    public var arguments: [String: Any] = [:]
    public init() {}
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var args: [String: Any] = [:]
        for key in container.allKeys {
            if let val = try? container.decode(AnyDecodable.self, forKey: key) {
                args[key.stringValue] = val.value
            }
        }
        self.arguments = args
    }
    public static func configure(name: String, description: String, schema: [String: Any], handler: @escaping ([String: Any]) async throws -> Any) {
        _name = name
        _description = description
        _schema = schema
        _handler = handler
    }
    public func getSchema() -> [String: Any] { return Self._schema }
    public func run() async throws -> Any {
        guard let handler = Self._handler else { return ["error": "Handler not configured"] }
        return try await handler(arguments)
    }
}

public struct DynamicMCPTool5: DynamicMCPToolType {
    public static var name: String { _name }
    public static var description: String { _description }
    private static var _name = "dynamic_mcp_5"
    private static var _description = ""
    private static var _schema: [String: Any] = [:]
    private static var _handler: (([String: Any]) async throws -> Any)?
    public var arguments: [String: Any] = [:]
    public init() {}
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var args: [String: Any] = [:]
        for key in container.allKeys {
            if let val = try? container.decode(AnyDecodable.self, forKey: key) {
                args[key.stringValue] = val.value
            }
        }
        self.arguments = args
    }
    public static func configure(name: String, description: String, schema: [String: Any], handler: @escaping ([String: Any]) async throws -> Any) {
        _name = name
        _description = description
        _schema = schema
        _handler = handler
    }
    public func getSchema() -> [String: Any] { return Self._schema }
    public func run() async throws -> Any {
        guard let handler = Self._handler else { return ["error": "Handler not configured"] }
        return try await handler(arguments)
    }
}

public struct DynamicMCPTool6: DynamicMCPToolType {
    public static var name: String { _name }
    public static var description: String { _description }
    private static var _name = "dynamic_mcp_6"
    private static var _description = ""
    private static var _schema: [String: Any] = [:]
    private static var _handler: (([String: Any]) async throws -> Any)?
    public var arguments: [String: Any] = [:]
    public init() {}
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var args: [String: Any] = [:]
        for key in container.allKeys {
            if let val = try? container.decode(AnyDecodable.self, forKey: key) {
                args[key.stringValue] = val.value
            }
        }
        self.arguments = args
    }
    public static func configure(name: String, description: String, schema: [String: Any], handler: @escaping ([String: Any]) async throws -> Any) {
        _name = name
        _description = description
        _schema = schema
        _handler = handler
    }
    public func getSchema() -> [String: Any] { return Self._schema }
    public func run() async throws -> Any {
        guard let handler = Self._handler else { return ["error": "Handler not configured"] }
        return try await handler(arguments)
    }
}

public struct DynamicMCPTool7: DynamicMCPToolType {
    public static var name: String { _name }
    public static var description: String { _description }
    private static var _name = "dynamic_mcp_7"
    private static var _description = ""
    private static var _schema: [String: Any] = [:]
    private static var _handler: (([String: Any]) async throws -> Any)?
    public var arguments: [String: Any] = [:]
    public init() {}
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var args: [String: Any] = [:]
        for key in container.allKeys {
            if let val = try? container.decode(AnyDecodable.self, forKey: key) {
                args[key.stringValue] = val.value
            }
        }
        self.arguments = args
    }
    public static func configure(name: String, description: String, schema: [String: Any], handler: @escaping ([String: Any]) async throws -> Any) {
        _name = name
        _description = description
        _schema = schema
        _handler = handler
    }
    public func getSchema() -> [String: Any] { return Self._schema }
    public func run() async throws -> Any {
        guard let handler = Self._handler else { return ["error": "Handler not configured"] }
        return try await handler(arguments)
    }
}

public struct DynamicMCPTool8: DynamicMCPToolType {
    public static var name: String { _name }
    public static var description: String { _description }
    private static var _name = "dynamic_mcp_8"
    private static var _description = ""
    private static var _schema: [String: Any] = [:]
    private static var _handler: (([String: Any]) async throws -> Any)?
    public var arguments: [String: Any] = [:]
    public init() {}
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var args: [String: Any] = [:]
        for key in container.allKeys {
            if let val = try? container.decode(AnyDecodable.self, forKey: key) {
                args[key.stringValue] = val.value
            }
        }
        self.arguments = args
    }
    public static func configure(name: String, description: String, schema: [String: Any], handler: @escaping ([String: Any]) async throws -> Any) {
        _name = name
        _description = description
        _schema = schema
        _handler = handler
    }
    public func getSchema() -> [String: Any] { return Self._schema }
    public func run() async throws -> Any {
        guard let handler = Self._handler else { return ["error": "Handler not configured"] }
        return try await handler(arguments)
    }
}

public struct DynamicMCPTool9: DynamicMCPToolType {
    public static var name: String { _name }
    public static var description: String { _description }
    private static var _name = "dynamic_mcp_9"
    private static var _description = ""
    private static var _schema: [String: Any] = [:]
    private static var _handler: (([String: Any]) async throws -> Any)?
    public var arguments: [String: Any] = [:]
    public init() {}
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var args: [String: Any] = [:]
        for key in container.allKeys {
            if let val = try? container.decode(AnyDecodable.self, forKey: key) {
                args[key.stringValue] = val.value
            }
        }
        self.arguments = args
    }
    public static func configure(name: String, description: String, schema: [String: Any], handler: @escaping ([String: Any]) async throws -> Any) {
        _name = name
        _description = description
        _schema = schema
        _handler = handler
    }
    public func getSchema() -> [String: Any] { return Self._schema }
    public func run() async throws -> Any {
        guard let handler = Self._handler else { return ["error": "Handler not configured"] }
        return try await handler(arguments)
    }
}

public struct DynamicMCPTool10: DynamicMCPToolType {
    public static var name: String { _name }
    public static var description: String { _description }
    private static var _name = "dynamic_mcp_10"
    private static var _description = ""
    private static var _schema: [String: Any] = [:]
    private static var _handler: (([String: Any]) async throws -> Any)?
    public var arguments: [String: Any] = [:]
    public init() {}
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var args: [String: Any] = [:]
        for key in container.allKeys {
            if let val = try? container.decode(AnyDecodable.self, forKey: key) {
                args[key.stringValue] = val.value
            }
        }
        self.arguments = args
    }
    public static func configure(name: String, description: String, schema: [String: Any], handler: @escaping ([String: Any]) async throws -> Any) {
        _name = name
        _description = description
        _schema = schema
        _handler = handler
    }
    public func getSchema() -> [String: Any] { return Self._schema }
    public func run() async throws -> Any {
        guard let handler = Self._handler else { return ["error": "Handler not configured"] }
        return try await handler(arguments)
    }
}
