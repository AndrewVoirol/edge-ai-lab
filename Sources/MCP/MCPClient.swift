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
import os

/// State of an MCP Client connection.
public enum MCPClientState: Sendable, Equatable {
    case stopped
    case starting
    case connected(tools: [MCPToolInfo])
    case failed(error: String)
}

/// Metadata about a tool fetched from an MCP server.
public struct MCPToolInfo: Codable, Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let description: String
    public let inputSchema: [String: AnyCodable]

    public init(name: String, description: String, inputSchema: [String: AnyCodable]) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

/// A client implementation of the Model Context Protocol (MCP) using stdio transport.
/// Spawns and manages a local subprocess on macOS; compiles as a silent stub on iOS.
public final class MCPClient: @unchecked Sendable {
    private static let logger = Logger(
        subsystem: "com.andrewvoirol.EdgeAILab.mcp",
        category: "client"
    )

    public let config: MCPServerConfig
    
    #if os(macOS)
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    #endif

    private let stateLock = NSLock()
    private var _state: MCPClientState = .stopped
    public var state: MCPClientState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _state
    }

    public var onStateChange: ((MCPClientState) -> Void)?

    private let requestLock = NSLock()
    private var messageId = 1
    private var pendingRequests: [Int: (Result<[String: Any], Error>) -> Void] = [:]
    
    private let lineBuffer = LineBuffer()

    public init(config: MCPServerConfig) {
        self.config = config
    }

    private func updateState(_ newState: MCPClientState) {
        stateLock.lock()
        _state = newState
        stateLock.unlock()
        Self.logger.info("Server '\(self.config.name)' state changed: \(String(describing: newState))")
        onStateChange?(newState)
    }

    // MARK: - Lifecycle

    /// Starts the MCP server subprocess and performs the initialize handshake.
    public func start() async {
        #if os(iOS)
        updateState(.failed(error: "MCP subprocesses are not supported on iOS sandboxes."))
        #else
        let shouldStart = stateLock.withLock {
            let canStart: Bool
            switch _state {
            case .stopped:
                canStart = true
            case .failed:
                canStart = true
            default:
                canStart = false
            }
            if canStart {
                _state = .starting
            }
            return canStart
        }
        guard shouldStart else { return }

        Self.logger.info("Starting MCP server '\(self.config.name)'...")

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Set path to executable
        process.executableURL = URL(fileURLWithPath: config.command)
        process.arguments = config.args

        process.terminationHandler = { [weak self] proc in
            Self.logger.warning("MCP server '\(self?.config.name ?? "")' exited with status \(proc.terminationStatus)")
            guard let self = self else { return }

            self.requestLock.lock()
            let callbacks = Array(self.pendingRequests.values)
            self.pendingRequests.removeAll()
            self.requestLock.unlock()

            for callback in callbacks {
                callback(.failure(NSError(domain: "MCPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Server terminated unexpectedly (exit code \(proc.terminationStatus))"])))
            }

            self.stateLock.lock()
            let currentState = self._state
            self.stateLock.unlock()

            if case .connected = currentState {
                self.updateState(.failed(error: "Server exited unexpectedly (status \(proc.terminationStatus))"))
            } else if case .starting = currentState {
                self.updateState(.failed(error: "Server exited during initialization (status \(proc.terminationStatus))"))
            } else {
                self.updateState(.stopped)
            }
        }

        // Set environment variables
        var env = ProcessInfo.processInfo.environment
        for (key, val) in config.env {
            env[key] = val
        }
        process.environment = env

        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe

        // Monitor stderr for logging/debugging
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let log = String(data: data, encoding: .utf8) {
                Self.logger.warning("[\(self?.config.name ?? "MCP Server") Stderr]: \(log.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }

        // Monitor stdout for JSON-RPC messages
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let lines = self.lineBuffer.append(data)
            for line in lines {
                self.handleIncomingMessage(line)
            }
        }

        do {
            try process.run()
            
            // Perform initialize handshake
            let initResponse = try await sendRequest(
                method: "initialize",
                params: [
                    "protocolVersion": "2024-11-05",
                    "capabilities": [String: Any](),
                    "clientInfo": [
                        "name": "EdgeAILab",
                        "version": "1.0.0"
                    ]
                ]
            )

            Self.logger.info("Handshake initialized with: \(initResponse)")

            // Send initialized notification
            sendNotification(method: "notifications/initialized")

            // Fetch tools
            let toolsResponse = try await sendRequest(method: "tools/list", params: [:])
            let mcpTools: [MCPToolInfo]
            if let toolsList = toolsResponse["tools"] as? [[String: Any]] {
                let data = try JSONSerialization.data(withJSONObject: toolsList)
                mcpTools = try JSONDecoder().decode([MCPToolInfo].self, from: data)
            } else {
                mcpTools = []
            }

            updateState(.connected(tools: mcpTools))

        } catch {
            Self.logger.error("Failed to launch MCP server '\(self.config.name)': \(error.localizedDescription)")
            updateState(.failed(error: error.localizedDescription))
            stop()
        }
        #endif
    }

    /// Stops the subprocess and clears all pending requests.
    public func stop() {
        #if os(macOS)
        stdinPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        if let process = process {
            process.terminationHandler = nil
            if process.isRunning {
                process.terminate()
            }
        }

        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        #endif

        requestLock.lock()
        for callback in pendingRequests.values {
            callback(.failure(NSError(domain: "MCPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Client stopped"])))
        }
        pendingRequests.removeAll()
        requestLock.unlock()

        updateState(.stopped)
    }

    // MARK: - JSON-RPC Communication

    /// Sends a JSON-RPC request and awaits the response matching the ID.
    public func callTool(name: String, arguments: [String: Any]) async throws -> [String: Any] {
        return try await sendRequest(
            method: "tools/call",
            params: [
                "name": name,
                "arguments": arguments
            ]
        )
    }

    private func sendRequest(method: String, params: [String: Any]) async throws -> [String: Any] {
        #if os(iOS)
        throw NSError(domain: "MCPClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "MCP subprocesses not supported on iOS"])
        #else
        let id: Int = requestLock.withLock {
            let currentId = messageId
            messageId += 1
            return currentId
        }

        let requestObj: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ]

        return try await withCheckedThrowingContinuation { continuation in
            requestLock.lock()
            pendingRequests[id] = { result in
                switch result {
                case .success(let obj):
                    continuation.resume(returning: obj)
                case .failure(let err):
                    continuation.resume(throwing: err)
                }
            }
            requestLock.unlock()

            do {
                let data = try JSONSerialization.data(withJSONObject: requestObj)
                guard var str = String(data: data, encoding: .utf8) else {
                    throw NSError(domain: "MCPClient", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to serialize request"])
                }
                str.append("\n")
                
                guard let stdinHandle = stdinPipe?.fileHandleForWriting else {
                    throw NSError(domain: "MCPClient", code: -4, userInfo: [NSLocalizedDescriptionKey: "Stdin unavailable"])
                }

                if let writeData = str.data(using: .utf8) {
                    try stdinHandle.write(contentsOf: writeData)
                }
            } catch {
                requestLock.lock()
                pendingRequests.removeValue(forKey: id)
                requestLock.unlock()
                continuation.resume(throwing: error)
            }
        }
        #endif
    }

    private func sendNotification(method: String) {
        #if os(macOS)
        let notifObj: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method
        ]
        if let data = try? JSONSerialization.data(withJSONObject: notifObj),
           let str = String(data: data, encoding: .utf8),
           let stdinHandle = stdinPipe?.fileHandleForWriting,
           let writeData = "\(str)\n".data(using: .utf8) {
            try? stdinHandle.write(contentsOf: writeData)
        }
        #endif
    }

    private func handleIncomingMessage(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // We only handle responses to our requests (which have "id" and "result" or "error")
        if let id = json["id"] as? Int {
            requestLock.lock()
            let callback = pendingRequests.removeValue(forKey: id)
            requestLock.unlock()

            if let callback = callback {
                if let errorObj = json["error"] as? [String: Any] {
                    let errMsg = errorObj["message"] as? String ?? "Unknown MCP error"
                    let errCode = errorObj["code"] as? Int ?? -1
                    callback(.failure(NSError(domain: "MCPClient", code: errCode, userInfo: [NSLocalizedDescriptionKey: errMsg])))
                } else if let result = json["result"] as? [String: Any] {
                    callback(.success(result))
                } else {
                    callback(.failure(NSError(domain: "MCPClient", code: -5, userInfo: [NSLocalizedDescriptionKey: "Malformed response"])))
                }
            }
        }
    }
}

// MARK: - LineBuffer Helper

private final class LineBuffer {
    private var data = Data()
    private let lock = NSLock()

    func append(_ newData: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        data.append(newData)

        var lines: [String] = []
        // ASCII 10 is '\n'
        while let newlineIndex = data.firstIndex(of: UInt8(10)) {
            let lineData = data.prefix(upTo: newlineIndex)
            if let lineString = String(data: lineData, encoding: .utf8) {
                let trimmed = lineString.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    lines.append(trimmed)
                }
            }
            data.removeSubrange(...newlineIndex)
        }
        return lines
    }
}

// MARK: - AnyCodable Helper for Schema Persistence

/// Helper struct to serialize and deserialize arbitrary JSON-like dictionaries in Codable types.
public struct AnyCodable: Codable, Hashable, Sendable {
    public let value: AnySendable

    public init(_ value: Any) {
        self.value = AnySendable(value)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = AnySendable(NSNull())
        } else if let bool = try? container.decode(Bool.self) {
            self.value = AnySendable(bool)
        } else if let int = try? container.decode(Int.self) {
            self.value = AnySendable(int)
        } else if let double = try? container.decode(Double.self) {
            self.value = AnySendable(double)
        } else if let string = try? container.decode(String.self) {
            self.value = AnySendable(string)
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = AnySendable(array.map { $0.value.value })
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            var rawDict: [String: Any] = [:]
            for (k, v) in dict {
                rawDict[k] = v.value.value
            }
            self.value = AnySendable(rawDict)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode AnyCodable")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try encodeValue(value.value, to: &container)
    }

    private func encodeValue(_ val: Any, to container: inout SingleValueEncodingContainer) throws {
        if val is NSNull {
            try container.encodeNil()
        } else if let bool = val as? Bool {
            try container.encode(bool)
        } else if let int = val as? Int {
            try container.encode(int)
        } else if let double = val as? Double {
            try container.encode(double)
        } else if let string = val as? String {
            try container.encode(string)
        } else if let array = val as? [Any] {
            try container.encode(array.map { AnyCodable($0) })
        } else if let dict = val as? [String: Any] {
            var codableDict: [String: AnyCodable] = [:]
            for (k, v) in dict {
                codableDict[k] = AnyCodable(v)
            }
            try container.encode(codableDict)
        } else {
            try container.encode(String(describing: val))
        }
    }
}

/// Sendable wrapper for Any
public struct AnySendable: @unchecked Sendable, Hashable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public static func == (lhs: AnySendable, rhs: AnySendable) -> Bool {
        return String(describing: lhs.value) == String(describing: rhs.value)
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(String(describing: value))
    }
}
