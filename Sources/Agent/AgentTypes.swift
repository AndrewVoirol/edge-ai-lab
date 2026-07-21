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

// MARK: - Agent Step

/// Represents a single step in the agent's ReAct loop.
/// Each step captures the model's reasoning, any tool call made,
/// the tool's result, and a timestamp.
struct AgentStep: Identifiable, Sendable {
    let id: UUID
    let iteration: Int
    let reasoning: String?
    let toolCall: ToolCallInfo?
    let toolResult: String?
    let timestamp: Date
}

// MARK: - Tool Call Info

/// Information about a tool call made during an agent step.
/// Uses `[String: String]` for arguments because `Any` is not `Sendable`.
struct ToolCallInfo: Sendable {
    let toolName: String
    let arguments: [String: String]
    let riskLevel: AgentLogic.RiskLevel
    /// `nil` if the tool was safe (auto-approved), `true` if user approved, `false` if denied.
    let wasApproved: Bool?
}

// MARK: - Tool Execution Result

/// Structured result from tool execution, replacing string-matching error detection.
///
/// The harness uses this to decide whether to retry (`isRetryable`),
/// inject recovery instructions, or pass the result through normally.
enum ToolExecutionResult: Sendable, Equatable {
    /// Tool completed successfully with a result string.
    case success(String)
    /// Tool failed with an error message.
    /// - `isRetryable`: Whether the harness should attempt the tool again with adjusted parameters.
    ///   `true` for transient errors (timeout, parse failure). `false` for permanent errors (unsupported operation).
    case failure(message: String, isRetryable: Bool)

    /// Convenience: classify a raw ToolCallEvent into a structured result.
    ///
    /// Uses the `succeeded` flag from ToolCallEvent as the primary signal,
    /// with string-content analysis as a fallback for tools that report errors
    /// in the result body while still returning `succeeded = true`.
    static func from(event: ToolCallEvent) -> ToolExecutionResult {
        // Primary signal: the tool's own success flag
        if !event.succeeded {
            return .failure(message: event.result, isRetryable: true)
        }

        // Secondary signal: detect error-shaped content in successful results
        // Some tools return succeeded=true but include error details in the result body
        let resultLower = event.result.lowercased()
        if event.result.contains("\"error\"") ||
           resultLower.hasPrefix("error:") ||
           resultLower.contains("\"error_message\"") {
            return .failure(message: event.result, isRetryable: true)
        }

        return .success(event.result)
    }
}

// MARK: - Agent Status

/// The current status of the agent harness.
enum AgentStatus: Sendable {
    case idle
    case thinking
    case executingTool(String)
    case waitingForApproval(tool: String, arguments: [String: String])
    case completed(summary: String)
    case forceStopped(summary: String)
    case cancelled
}

// MARK: - AgentStatus Equatable

extension AgentStatus: Equatable {
    static func == (lhs: AgentStatus, rhs: AgentStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.thinking, .thinking): return true
        case (.executingTool(let a), .executingTool(let b)): return a == b
        case (.waitingForApproval(let t1, let a1), .waitingForApproval(let t2, let a2)):
            return t1 == t2 && a1 == a2
        case (.completed(let a), .completed(let b)): return a == b
        case (.forceStopped(let a), .forceStopped(let b)): return a == b
        case (.cancelled, .cancelled): return true
        default: return false
        }
    }
}
