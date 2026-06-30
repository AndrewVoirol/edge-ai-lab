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

// MARK: - AppTool Protocol

/// Runtime-agnostic tool protocol for on-device function calling.
///
/// ## Design
///
/// Tools conform to `AppTool` instead of `LiteRTLM.Tool` directly. Runtime-specific
/// bridges (`LiteRTToolBridge`, `MLXToolBridge`) adapt `AppTool` to each SDK's
/// native tool format at the engine boundary.
///
/// This eliminates `import LiteRTLM` from every tool file and allows the same tool
/// implementation to work with both LiteRT-LM and MLX backends.
///
/// ## Migration from LiteRTLM.Tool
///
/// | Old (LiteRTLM)                        | New (AppTool)                          |
/// |---------------------------------------|----------------------------------------|
/// | `struct MyTool: Tool`                 | `struct MyTool: AppTool`               |
/// | `@ToolParam(description:) var x: T`   | Manual `parameterSchema` property      |
/// | `func run() async throws -> Any`      | `func execute(arguments:) async throws -> String` |
/// | `static let name`                     | `var name: String { get }`             |
/// | `static let description`              | `var toolDescription: String { get }`  |
///
/// ## Thread Safety
///
/// All `AppTool` implementations must be `Sendable`. The `execute(arguments:)` method
/// is called from async contexts and may be invoked concurrently for independent tool calls.
protocol AppTool: Sendable {
    /// The tool name, matching the function_call name in model output (e.g. "calculate").
    var name: String { get }

    /// Human-readable description of what the tool does. Used in the system prompt
    /// to help the model decide when to call this tool.
    var toolDescription: String { get }

    /// JSON Schema describing the tool's parameters. Each property's name, type,
    /// and description are included so the model can generate valid arguments.
    var parameterSchema: AppToolSchema { get }

    /// Execute the tool with the given arguments.
    ///
    /// - Parameter arguments: Dictionary of parameter name → value pairs decoded
    ///   from the model's tool call output. Values are `Any` (typically `String`,
    ///   `Double`, `Int`, `Bool`, or nested `[String: Any]`).
    /// - Returns: A string result to feed back to the model as tool output.
    /// - Throws: If the tool execution fails (e.g., invalid arguments, runtime error).
    func execute(arguments: [String: Any]) async throws -> String
}

// MARK: - AppToolSchema

/// JSON Schema representation for tool parameters.
///
/// Maps directly to the `parameters` object in an OpenAI-compatible function calling schema:
/// ```json
/// {
///   "type": "object",
///   "properties": { ... },
///   "required": ["param1", "param2"]
/// }
/// ```
struct AppToolSchema: Sendable {
    /// Parameter definitions keyed by parameter name.
    let properties: [String: AppToolParameter]

    /// Names of required parameters.
    let required: [String]

    /// Convert to a JSON-compatible dictionary for tool calling schemas.
    func toJSONDict() -> [String: Any] {
        var props: [String: Any] = [:]
        for (key, param) in properties {
            var paramDict: [String: Any] = [
                "type": param.type,
                "description": param.description,
            ]
            if let enumValues = param.enumValues {
                paramDict["enum"] = enumValues
            }
            props[key] = paramDict
        }
        return [
            "type": "object",
            "properties": props,
            "required": required,
        ]
    }
}

// MARK: - AppToolParameter

/// A single parameter in a tool's schema.
struct AppToolParameter: Sendable {
    /// JSON Schema type: "string", "number", "integer", "boolean", "array", "object".
    let type: String

    /// Human-readable description for the model.
    let description: String

    /// Optional enum constraint — restricts valid values.
    let enumValues: [String]?

    /// Convenience initializer without enum constraint.
    init(type: String, description: String) {
        self.type = type
        self.description = description
        self.enumValues = nil
    }

    /// Full initializer with optional enum constraint.
    init(type: String, description: String, enumValues: [String]?) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
    }
}

// MARK: - AppTool Schema Convenience

extension AppTool {
    /// Generate the full tool definition as a JSON-compatible dictionary.
    ///
    /// Format matches OpenAI function calling schema:
    /// ```json
    /// {
    ///   "type": "function",
    ///   "function": {
    ///     "name": "tool_name",
    ///     "description": "what it does",
    ///     "parameters": { ... }
    ///   }
    /// }
    /// ```
    func toFunctionDefinition() -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": toolDescription,
                "parameters": parameterSchema.toJSONDict(),
            ],
        ]
    }
}

// MARK: - AppToolError

/// Errors that can occur during tool execution.
enum AppToolError: LocalizedError {
    /// A required argument was missing from the tool call.
    case missingArgument(String)

    /// An argument had an unexpected type.
    case invalidArgument(name: String, expected: String, got: String)

    /// The tool encountered a runtime error.
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingArgument(let name):
            return "Missing required argument: '\(name)'"
        case .invalidArgument(let name, let expected, let got):
            return "Invalid argument '\(name)': expected \(expected), got \(got)"
        case .executionFailed(let reason):
            return "Tool execution failed: \(reason)"
        }
    }
}

// MARK: - Argument Extraction Helpers

extension AppTool {
    /// Extract a required string argument, throwing if missing.
    func requireString(_ key: String, from arguments: [String: Any]) throws -> String {
        if let value = arguments[key] as? String {
            return value
        }
        if let value = arguments[key] {
            return String(describing: value)
        }
        throw AppToolError.missingArgument(key)
    }

    /// Extract an optional string argument.
    func optionalString(_ key: String, from arguments: [String: Any]) -> String? {
        if let value = arguments[key] as? String {
            return value
        }
        if let value = arguments[key] {
            return String(describing: value)
        }
        return nil
    }

    /// Extract a required numeric argument, throwing if missing or not convertible.
    func requireDouble(_ key: String, from arguments: [String: Any]) throws -> Double {
        if let value = arguments[key] as? Double {
            return value
        }
        if let value = arguments[key] as? Int {
            return Double(value)
        }
        if let str = arguments[key] as? String, let value = Double(str) {
            return value
        }
        if arguments[key] == nil {
            throw AppToolError.missingArgument(key)
        }
        throw AppToolError.invalidArgument(
            name: key, expected: "number",
            got: String(describing: type(of: arguments[key]!)))
    }

    /// Extract an optional boolean argument.
    func optionalBool(_ key: String, from arguments: [String: Any]) -> Bool? {
        if let value = arguments[key] as? Bool {
            return value
        }
        if let str = arguments[key] as? String {
            return str.lowercased() == "true"
        }
        return nil
    }
}
