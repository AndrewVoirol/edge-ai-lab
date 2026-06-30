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

// MARK: - LiteRTToolBridge

/// Bridges `AppTool` to `LiteRTLM.Tool` for use with the LiteRT-LM SDK.
///
/// LiteRT-LM's `Tool` protocol is `Decodable` with a required `init()` — the SDK creates
/// tool instances from the model's JSON output. This bridge pattern uses a pool of 
/// pre-registered concrete `Tool` types (similar to `DynamicMCPBridge`'s approach)
/// to avoid creating tool types at runtime.
///
/// ## Phase 2 Migration Path
///
/// During Phase 2 Core, existing tools still conform to `LiteRTLM.Tool` directly.
/// When tools are migrated to `AppTool` in Phase 2 Consumers, the bridge's
/// `createLiteRTTools()` method converts `[AppTool]` → `[Tool]` for backward
/// compatibility with `InstrumentedEngine`.
///
/// ## Usage (Phase 2 Consumers — Future)
///
/// ```swift
/// let appTools: [AppTool] = ToolRegistry.defaultTools
/// let registry = LiteRTToolBridgeRegistry.shared
/// registry.registerAll(appTools)
/// let liteRTTools = registry.createLiteRTTools()
/// ```
enum LiteRTToolBridge {
    /// Execute a tool call by looking up the `AppTool` by name.
    ///
    /// This is used by `LiteRTEngineAdapter` when it receives a tool call event
    /// from the generation stream and needs to execute the matching tool.
    static func executeToolCall(
        toolName: String,
        arguments: [String: Any],
        tools: [any AppTool]
    ) async throws -> String {
        guard let tool = tools.first(where: { $0.name == toolName }) else {
            throw AppToolError.executionFailed(
                "No tool found with name '\(toolName)'")
        }
        return try await tool.execute(arguments: arguments)
    }
}

// MARK: - LiteRTToolBridgeRegistry

/// Registry that maps tool names to `AppTool` instances for bridge lookup.
///
/// When the engine receives a tool call, it looks up the matching `AppTool`
/// by name in this registry and delegates execution.
final class LiteRTToolBridgeRegistry: @unchecked Sendable {
    static let shared = LiteRTToolBridgeRegistry()

    private var tools: [String: any AppTool] = [:]

    /// Register an AppTool for lookup by name.
    func register(_ tool: any AppTool) {
        tools[tool.name] = tool
    }

    /// Look up a registered AppTool by name.
    func tool(named name: String) -> (any AppTool)? {
        tools[name]
    }

    /// Register all tools for name-based lookup.
    func registerAll(_ appTools: [any AppTool]) {
        for tool in appTools {
            register(tool)
        }
    }

    /// Clear all registrations.
    func clear() {
        tools.removeAll()
    }
}
