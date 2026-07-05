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
import LiteRTLM

// MARK: - ToolToAppToolAdapter

/// Wraps a `LiteRTLM.Tool` as an `AppTool` for use with runtime-agnostic engine paths.
///
/// During the Phase 2 migration, existing tools still conform to `LiteRTLM.Tool` directly.
/// The generic `ModelLoadConfig.tools` expects `[any AppTool]?`, so this adapter bridges
/// the gap by wrapping each `Tool` instance.
///
/// ## How It Works
///
/// The adapter uses `LiteRTLM.Tool`'s reflection-based `getSchema()` method to extract
/// the tool's name, description, and parameter schema, then re-packages them as
/// `AppToolSchema` properties. Execution creates a fresh `Tool` instance via JSON
/// round-trip through the tool's `Decodable` conformance, populating `@ToolParam` fields.
///
/// ## Usage
///
/// ```swift
/// let liteRTTools: [Tool] = ToolRegistry.defaultTools
/// let appTools: [any AppTool] = ToolToAppToolAdapter.adaptAll(liteRTTools)
/// let loadConfig = ModelLoadConfig(tools: appTools, ...)
/// ```
struct ToolToAppToolAdapter: AppTool {

    let name: String
    let toolDescription: String
    let parameterSchema: AppToolSchema
    /// Type-erased closure that creates a fresh Tool instance from arguments and runs it.
    private let executeClosure: @Sendable ([String: Any]) async throws -> String

    /// Adapt an array of `LiteRTLM.Tool` instances to `[any AppTool]`.
    ///
    /// Uses `adaptGeneric(_:)` to preserve each tool's concrete type for `Decodable` conformance.
    ///
    /// - Parameter tools: Array of concrete `Tool` instances.
    /// - Returns: Array of `AppTool` wrappers.
    static func adaptAll(_ tools: [any Tool]) -> [any AppTool] {
        tools.map { tool in
            // Use _openExistential to capture the concrete type for Decodable round-trip.
            // `any Tool` erases the concrete type; we need it back for JSONDecoder.decode(_:from:).
            func open<T: Tool>(_ tool: T) -> any AppTool {
                adaptGeneric(tool)
            }
            return open(tool)
        }
    }

    /// Adapt a single `LiteRTLM.Tool` to `AppTool`, preserving the concrete type.
    ///
    /// This generic method captures `T` (the concrete Tool type) so that
    /// `JSONDecoder.decode(T.self, from:)` works correctly — unlike `any Tool`,
    /// which erases the type and prevents Decodable conformance.
    private static func adaptGeneric<T: Tool>(_ tool: T) -> any AppTool {
        let schema = tool.getSchema()

        // Extract name and description from the LiteRT schema
        let function = schema["function"] as? [String: Any] ?? [:]
        let toolName = function["name"] as? String ?? String(describing: T.self)
        let toolDesc = function["description"] as? String ?? ""

        // Extract parameters
        let parameters = function["parameters"] as? [String: Any] ?? [:]
        let properties = parameters["properties"] as? [String: Any] ?? [:]
        let required = parameters["required"] as? [String] ?? []

        var appParams: [String: AppToolParameter] = [:]
        for (key, value) in properties {
            if let paramDict = value as? [String: Any] {
                let type = paramDict["type"] as? String ?? "string"
                let description = paramDict["description"] as? String ?? ""
                let enumValues = paramDict["enum"] as? [String]
                appParams[key] = AppToolParameter(
                    type: type,
                    description: description,
                    enumValues: enumValues
                )
            }
        }

        let appSchema = AppToolSchema(properties: appParams, required: required)

        return ToolToAppToolAdapter(
            name: toolName,
            toolDescription: toolDesc,
            parameterSchema: appSchema,
            executeClosure: { arguments in
                // JSON round-trip: encode arguments → JSON → decode as T (concrete Tool type).
                // This populates @ToolParam properties via Tool's Decodable conformance.
                let jsonData = try JSONSerialization.data(
                    withJSONObject: arguments,
                    options: []
                )
                let instance = try JSONDecoder().decode(T.self, from: jsonData)
                let result = try await instance.run()
                if let str = result as? String {
                    return str
                }
                // Convert non-string results to JSON string
                if let data = try? JSONSerialization.data(
                    withJSONObject: result,
                    options: [.fragmentsAllowed]
                ) {
                    return String(data: data, encoding: .utf8) ?? String(describing: result)
                }
                return String(describing: result)
            }
        )
    }

    func execute(arguments: [String: Any]) async throws -> String {
        try await executeClosure(arguments)
    }
}
