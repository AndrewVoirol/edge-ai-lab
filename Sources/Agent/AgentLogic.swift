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

/// Pure-function namespace for agent reasoning logic.
/// All methods are static and side-effect free for testability.
enum AgentLogic {

    // MARK: - Risk Classification

    enum RiskLevel: String, Sendable, Equatable {
        case safe
        case requiresApproval
    }

    // MARK: - Termination Reasons

    enum TerminationReason: Equatable {
        case done
        case needsApproval(tool: String)
        case maxIterations
        case cancelled
    }

    /// The set of tool names that are safe to auto-execute without user approval.
    /// These tools are read-only or purely computational with no side effects.
    nonisolated static let safeTools: Set<String> = [
        "calculate",
        "get_current_datetime",
        "get_device_info",
        "convert_units",
        "analyze_text",
        "get_system_health"
    ]

    /// Classify tool risk. Safe tools auto-execute; risky tools pause for user approval.
    ///
    /// - Safe tools: calculator, date_time, device_info, unit_converter, text_analyzer, system_health
    /// - Requires approval: get_location, take_photo, get_device_motion, search_files, get_sensors,
    ///   get_network_info, create_shortcut
    static func classifyRisk(toolName: String) -> RiskLevel {
        safeTools.contains(toolName) ? .safe : .requiresApproval
    }

    /// Detect termination markers in model response.
    ///
    /// Checks for:
    /// - `[DONE]` — model has finished its task
    /// - `[NEED_APPROVAL:tool_name]` — model requests permission for a risky tool
    /// - Max iteration limit reached
    static func detectTermination(
        response: String,
        currentIteration: Int,
        maxIterations: Int
    ) -> TerminationReason? {
        if response.contains("[DONE]") {
            return .done
        }

        // Extract tool name from [NEED_APPROVAL:tool_name] pattern
        if let range = response.range(of: "[NEED_APPROVAL", options: .literal) {
            let afterMarker = response[range.upperBound...]
            if afterMarker.hasPrefix(":") {
                let toolPart = afterMarker.dropFirst()
                if let endBracket = toolPart.firstIndex(of: "]") {
                    let toolName = String(toolPart[toolPart.startIndex..<endBracket])
                        .trimmingCharacters(in: .whitespaces)
                    return .needsApproval(tool: toolName)
                }
            }
            return .needsApproval(tool: "unknown")
        }

        if currentIteration >= maxIterations {
            return .maxIterations
        }

        return nil
    }

    /// Build the agent-mode system prompt that instructs the model to reason step-by-step.
    static func buildAgentSystemPrompt(availableTools: [String]) -> String {
        let toolList = availableTools.joined(separator: ", ")
        return """
        You are an autonomous AI agent running on-device. You solve tasks step by step.

        Available tools: \(toolList)

        Instructions:
        1. Think step by step. Explain your reasoning before each action.
        2. Use tools when needed to gather information or perform calculations.
        3. After each tool result, analyze the output and decide your next step.
        4. When you have enough information to answer the user's question, respond with \
        your final answer and include [DONE] at the end.
        5. If you need to use a tool that could access sensitive data (location, camera, \
        files, network, sensors, shortcuts, motion), include [NEED_APPROVAL:tool_name] \
        in your response.
        6. Do NOT use [DONE] until you have a complete answer.
        7. Keep your reasoning concise but clear.
        """
    }

    /// Extract the reasoning/thinking portion from model response.
    /// Returns text before the first termination marker, or the full response if none.
    static func extractReasoningTrace(from response: String) -> String? {
        let markers = ["[DONE]", "[NEED_APPROVAL"]
        var endIndex = response.endIndex

        for marker in markers {
            if let range = response.range(of: marker) {
                if range.lowerBound < endIndex {
                    endIndex = range.lowerBound
                }
            }
        }

        let reasoning = String(response[response.startIndex..<endIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return reasoning.isEmpty ? nil : reasoning
    }

    /// Generate a summary when force-stopped at max iterations.
    static func generateForceStopSummary(completedSteps: [AgentStep]) -> String {
        let toolCalls = completedSteps.compactMap { $0.toolCall?.toolName }
        let uniqueTools = Set(toolCalls)

        var summary = "Agent stopped after \(completedSteps.count) step(s)."

        if !uniqueTools.isEmpty {
            summary += "\nTools used: \(uniqueTools.sorted().joined(separator: ", "))"
        }

        if let lastReasoning = completedSteps.last?.reasoning {
            let truncated = String(lastReasoning.prefix(200))
            summary += "\nLast reasoning: \(truncated)"
            if lastReasoning.count > 200 {
                summary += "..."
            }
        }

        return summary
    }
}
