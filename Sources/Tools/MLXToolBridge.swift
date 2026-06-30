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

#if canImport(MLX)
import MLXLMCommon

// MARK: - MLXToolBridge

/// Converts `AppTool` definitions to MLX-compatible tool calling format.
///
/// MLX uses the OpenAI-compatible function calling schema via `UserInput.tools`.
/// This bridge converts `AppTool`'s schema to the `[[String: any Sendable]]`
/// format expected by `ChatSession`.
///
/// ## Usage
///
/// ```swift
/// let tools: [AppTool] = ToolRegistry.defaultTools
/// let mlxTools = MLXToolBridge.convertToMLXFormat(tools)
/// // Pass mlxTools as the `tools` parameter to UserInput
/// ```
enum MLXToolBridge {

    /// Convert an array of `AppTool`s to MLX's tool calling format.
    ///
    /// Returns `[[String: any Sendable]]` — each element is a function definition
    /// dictionary matching the OpenAI function calling schema.
    static func convertToMLXFormat(_ tools: [AppTool]) -> [[String: any Sendable]] {
        tools.map { tool in
            convertToolToSendableDict(tool)
        }
    }

    /// Convert a single `AppTool` to an MLX-compatible tool definition.
    private static func convertToolToSendableDict(
        _ tool: AppTool
    ) -> [String: any Sendable] {
        let schema = tool.parameterSchema
        var properties: [String: [String: any Sendable]] = [:]

        for (key, param) in schema.properties {
            var paramDict: [String: any Sendable] = [
                "type": param.type,
                "description": param.description,
            ]
            if let enumValues = param.enumValues {
                paramDict["enum"] = enumValues
            }
            properties[key] = paramDict
        }

        let parameters: [String: any Sendable] = [
            "type": "object",
            "properties": properties,
            "required": schema.required,
        ]

        let function: [String: any Sendable] = [
            "name": tool.name,
            "description": tool.toolDescription,
            "parameters": parameters,
        ]

        return [
            "type": "function",
            "function": function,
        ]
    }

    /// Parse a tool call from the model's JSON output and execute the matching tool.
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool to execute.
    ///   - arguments: The arguments dictionary from the model's tool call.
    ///   - tools: The available tools to search.
    /// - Returns: The tool's string result.
    /// - Throws: If no matching tool is found or execution fails.
    static func executeToolCall(
        toolName: String,
        arguments: [String: Any],
        tools: [AppTool]
    ) async throws -> String {
        guard let tool = tools.first(where: { $0.name == toolName }) else {
            throw AppToolError.executionFailed(
                "No tool found with name '\(toolName)'")
        }
        return try await tool.execute(arguments: arguments)
    }
}

#else

// MARK: - Simulator Stub

/// Stub for iOS Simulator and platforms without MLX.
enum MLXToolBridge {
    static func convertToMLXFormat(_ tools: [AppTool]) -> [[String: Any]] {
        tools.map { $0.toFunctionDefinition() }
    }

    static func executeToolCall(
        toolName: String,
        arguments: [String: Any],
        tools: [AppTool]
    ) async throws -> String {
        guard let tool = tools.first(where: { $0.name == toolName }) else {
            throw AppToolError.executionFailed(
                "No tool found with name '\(toolName)'")
        }
        return try await tool.execute(arguments: arguments)
    }
}

#endif
