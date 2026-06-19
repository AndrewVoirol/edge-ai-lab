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

// MARK: - Tool Call Observability

/// Thread-safe tracker to intercept tool executions at runtime.
public final class ToolExecutionTracker: @unchecked Sendable {
    public static let shared = ToolExecutionTracker()
    
    private let lock = NSRecursiveLock()
    private var callback: ((ToolCallEvent) -> Void)?
    
    private init() {}
    
    /// Register a callback to be notified when a tool executes.
    public func registerCallback(_ callback: @escaping (ToolCallEvent) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        self.callback = callback
    }
    
    /// Remove the active callback.
    public func clearCallback() {
        lock.lock()
        defer { lock.unlock() }
        self.callback = nil
    }
    
    /// Notify the tracker that a tool was executed.
    public func notify(_ event: ToolCallEvent) {
        lock.lock()
        let activeCallback = self.callback
        lock.unlock()
        activeCallback?(event)
    }
}

public struct ToolCallEvent: Identifiable, Sendable, Codable {
    /// Unique identifier for this tool call event.
    public let id: UUID

    /// The name of the tool that was invoked (e.g., "calculate", "get_device_info").
    public let toolName: String

    /// JSON-serialized string of the arguments passed to the tool.
    public let arguments: String

    /// JSON-serialized string of the tool's return value.
    public let result: String

    /// Wall-clock duration of the tool execution in milliseconds.
    public let durationMs: Double

    /// When this tool call occurred.
    public let timestamp: Date

    /// Whether the tool completed without throwing an error.
    public let succeeded: Bool

    public init(toolName: String, arguments: String, result: String, durationMs: Double, timestamp: Date, succeeded: Bool) {
        self.id = UUID()
        self.toolName = toolName
        self.arguments = arguments
        self.result = result
        self.durationMs = durationMs
        self.timestamp = timestamp
        self.succeeded = succeeded
    }
}

// MARK: - JSON Serialization Helper

/// Converts a dictionary to a pretty-printed JSON string.
/// Falls back to a debug description if serialization fails.
/// Sanitizes non-finite Double values (Infinity/NaN) to prevent
/// uncatchable NSInvalidArgumentException from JSONSerialization.
func jsonString(from dictionary: [String: Any]) -> String {
    // Sanitize non-finite floats that would crash JSONSerialization
    let sanitized = dictionary.mapValues { value -> Any in
        if let d = value as? Double, !d.isFinite {
            return d.isInfinite ? (d > 0 ? "Infinity" : "-Infinity") : "NaN"
        }
        if let f = value as? Float, !f.isFinite {
            return f.isInfinite ? (f > 0 ? "Infinity" : "-Infinity") : "NaN"
        }
        return value
    }
    guard let data = try? JSONSerialization.data(
        withJSONObject: sanitized,
        options: [.prettyPrinted, .sortedKeys]
    ) else {
        return "{\"error\": \"Failed to serialize result\"}"
    }
    return String(data: data, encoding: .utf8) ?? "{\"error\": \"Failed to encode result\"}"
}

// MARK: - Tool Registry

/// Central registry for all built-in tools available for on-device function calling.
///
/// Usage:
/// ```swift
/// // Get all tools for ConversationConfig
/// let config = ConversationConfig(tools: ToolRegistry.defaultTools)
///
/// // Or use the convenience ToolManager
/// let manager = ToolRegistry.createToolManager()
/// ```
enum ToolRegistry {

    /// All built-in tools for on-device function calling.
    ///
    /// Every tool in this list is:
    /// - **Side-effect-free**: No network calls, no file writes, no state mutations
    /// - **Offline-capable**: Works without any internet connection
    /// - **Safe**: No arbitrary code execution, sandboxed to read-only operations
    static let defaultTools: [Tool] = [
        CalculatorTool(),
        DateTimeTool(),
        DeviceInfoTool(),
        UnitConverterTool(),
        TextAnalyzerTool(),
        SystemHealthTool()
    ]

    /// Creates a `ToolManager` pre-configured with all built-in tools.
    ///
    /// The `ToolManager` handles the tool call loop automatically (up to 25 iterations)
    /// and generates OpenAPI-compliant JSON schemas from the `@ToolParam` declarations.
    ///
    /// - Returns: A configured `ToolManager` ready for use with a conversation.
    static func createToolManager() -> ToolManager {
        ToolManager(tools: defaultTools)
    }
}

