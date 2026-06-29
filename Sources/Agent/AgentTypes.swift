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
