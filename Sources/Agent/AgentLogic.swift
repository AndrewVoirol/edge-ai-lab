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
        /// Model explicitly marked completion with [DONE].
        case done
        /// Model semantically indicated completion (fuzzy phrase match).
        /// Less confident than `.done` — the model didn't use the exact marker.
        case fuzzyDone
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
    /// - Semantic completion phrases (fuzzy detection for smaller models)
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

        // Fuzzy termination detection — smaller models may not produce exact [DONE] markers.
        // Check for common semantic completion phrases at the end of the response.
        let trimmedSuffix = String(response.suffix(200)).lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let completionPhrases = [
            "task complete",
            "i'm done",
            "i am done",
            "here is the final answer",
            "here's the final answer",
            "that completes the task",
            "the task is complete",
            "i have completed",
        ]
        // Only trigger fuzzy detection if no tool call markers are present
        // AND the response looks like a final answer (not mid-reasoning)
        if !response.contains("[NEED_APPROVAL") {
            for phrase in completionPhrases {
                if trimmedSuffix.contains(phrase) {
                    return .fuzzyDone
                }
            }
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

        // Include elapsed time for context
        if let firstStep = completedSteps.first, let lastStep = completedSteps.last {
            let elapsed = lastStep.timestamp.timeIntervalSince(firstStep.timestamp)
            let elapsedFormatted = String(format: "%.1f", elapsed)
            summary += "\nElapsed: \(elapsedFormatted)s"
        }

        if let lastReasoning = completedSteps.last?.reasoning {
            let truncated = String(lastReasoning.prefix(200))
            summary += "\nLast reasoning: \(truncated)"
            if lastReasoning.count > 200 {
                summary += "..."
            }
        }

        summary += "\n\nNote: The agent reached its maximum iteration limit. " +
            "The above represents the progress made before stopping."

        return summary
    }

    // MARK: - Tool Call Validation

    /// Validate that a tool call has all required parameters before dispatching.
    ///
    /// Returns `nil` if validation passes, or an error message describing what's missing.
    /// This saves an inference round-trip by catching obviously invalid tool calls
    /// before they reach the tool implementation.
    static func validateToolCall(
        toolName: String,
        arguments: [String: String],
        availableToolNames: Set<String>
    ) -> String? {
        // Check tool exists
        guard availableToolNames.contains(toolName) else {
            return "Unknown tool '\(toolName)'. Available tools: \(availableToolNames.sorted().joined(separator: ", "))"
        }

        // Check arguments are non-empty (tool-specific validation happens in the tool itself)
        if arguments.isEmpty {
            return "Tool '\(toolName)' was called with no arguments. Most tools require at least one parameter."
        }

        return nil
    }
}
