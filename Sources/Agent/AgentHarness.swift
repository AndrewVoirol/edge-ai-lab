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
import Observation
import os

/// The core ReAct (Reason → Act → Observe) loop harness.
///
/// Drives multi-step autonomous reasoning with tool execution and user oversight.
/// The harness wraps the inference engine's built-in tool-calling loop with
/// a higher-level reasoning cycle: each iteration sends a message to the model,
/// observes tool calls via `ToolExecutionTracker`, and decides whether to
/// continue, pause for approval, or terminate.
@Observable
@MainActor
final class AgentHarness {

    private static let logger = Logger(
        subsystem: "com.andrewvoirol.EdgeAILab.agent",
        category: "harness"
    )

    // MARK: - State

    /// Current iteration in the reasoning loop (0-indexed).
    var currentIteration: Int = 0

    /// Maximum iterations before force-stopping.
    var maxIterations: Int = 10

    /// Current agent status.
    var status: AgentStatus = .idle

    /// Full trace of reasoning steps and actions.
    var steps: [AgentStep] = []

    /// Whether the agent loop is currently running.
    var isRunning: Bool = false

    /// Whether the user has opted to auto-approve all remaining tool calls.
    var autoApproveAll: Bool = false

    // MARK: - Internal State

    /// Continuation for the approval flow. When the agent encounters a risky tool,
    /// it suspends here and waits for the user to approve or deny.
    private var approvalContinuation: CheckedContinuation<Bool, Never>?

    /// Flag to signal cancellation from outside the loop.
    private var isCancelled: Bool = false

    /// Tracks which tools have already been retried once after an error.
    /// Key: tool name, Value: true if already retried.
    /// Prevents infinite retry loops while allowing one chance to recover.
    private var retriedTools: Set<String> = []

    // MARK: - Core Loop

    /// Run the agent ReAct loop.
    ///
    /// - Parameters:
    ///   - initialPrompt: The user's task description.
    ///   - availableToolNames: Names of available tools (for the system prompt).
    ///   - generateResponse: A closure that sends a prompt to the engine and returns
    ///     the full response text along with any tool call events that occurred.
    ///     The caller (ConversationViewModel) handles streaming UI updates internally.
    func run(
        initialPrompt: String,
        availableToolNames: [String],
        generateResponse: @escaping (String) async throws -> (response: String, toolEvents: [ToolCallEvent])
    ) async {
        guard !isRunning else { return }

        Self.logger.info("🤖 Agent starting: \(initialPrompt.prefix(80), privacy: .public)")

        // Reset state
        currentIteration = 0
        steps = []
        isRunning = true
        isCancelled = false
        autoApproveAll = false
        retriedTools = []
        status = .thinking

        defer {
            isRunning = false
            if case .thinking = status { status = .idle }
            if case .executingTool = status { status = .idle }
        }

        // Build the agent system prompt
        let systemPrompt = AgentLogic.buildAgentSystemPrompt(availableTools: availableToolNames)
        var currentPrompt = "\(systemPrompt)\n\nUser task: \(initialPrompt)"
        let availableToolNameSet = Set(availableToolNames)

        // ReAct Loop
        while currentIteration < maxIterations && !isCancelled {
            Self.logger.info("🔄 Iteration \(self.currentIteration + 1)/\(self.maxIterations)")
            status = .thinking

            // Reason: Send prompt to model
            let response: String
            let toolEvents: [ToolCallEvent]
            do {
                let result = try await generateResponse(currentPrompt)
                response = result.response
                toolEvents = result.toolEvents
            } catch {
                Self.logger.error("❌ Agent inference failed: \(error.localizedDescription, privacy: .public)")
                let step = AgentStep(
                    id: UUID(),
                    iteration: currentIteration,
                    reasoning: "Error: \(error.localizedDescription)",
                    toolCall: nil,
                    toolResult: nil,
                    timestamp: Date()
                )
                steps.append(step)
                status = .forceStopped(
                    summary: "Agent stopped due to inference error: \(error.localizedDescription)"
                )
                return
            }

            guard !isCancelled else {
                status = .cancelled
                return
            }

            // Extract reasoning trace
            let reasoning = AgentLogic.extractReasoningTrace(from: response)

            // Observe: Check for tool calls that happened during inference
            var stepToolCall: ToolCallInfo?
            var stepToolResult: String?

            if let lastEvent = toolEvents.last {
                let parsedArgs = AgentHarnessHelpers.parseArguments(lastEvent.arguments)

                // Pre-dispatch validation: catch invalid tool calls before execution
                if let validationError = AgentLogic.validateToolCall(
                    toolName: lastEvent.toolName,
                    arguments: parsedArgs,
                    availableToolNames: availableToolNameSet
                ) {
                    Self.logger.warning("⚠️ Tool validation failed for \(lastEvent.toolName, privacy: .public): \(validationError, privacy: .public)")
                    stepToolCall = ToolCallInfo(
                        toolName: lastEvent.toolName,
                        arguments: parsedArgs,
                        riskLevel: .requiresApproval,
                        wasApproved: false
                    )
                    stepToolResult = "Validation error: \(validationError)"
                    currentPrompt = "Your tool call to '\(lastEvent.toolName)' was rejected: \(validationError)" +
                        "\n\nPlease correct the tool name or arguments and try again."
                } else {
                    let risk = AgentLogic.classifyRisk(toolName: lastEvent.toolName)

                // If risky and not auto-approved, pause for user approval
                if risk == .requiresApproval && !autoApproveAll {
                    status = .waitingForApproval(tool: lastEvent.toolName, arguments: parsedArgs)

                    Self.logger.info("⏸️ Waiting for approval: \(lastEvent.toolName, privacy: .public)")

                    // Suspend until user responds
                    let approved = await withCheckedContinuation { continuation in
                        self.approvalContinuation = continuation
                    }
                    self.approvalContinuation = nil

                    stepToolCall = ToolCallInfo(
                        toolName: lastEvent.toolName,
                        arguments: parsedArgs,
                        riskLevel: risk,
                        wasApproved: approved
                    )

                    if !approved {
                        stepToolResult = "User denied this action."
                        currentPrompt = "The user denied the \(lastEvent.toolName) tool call. " +
                            "Please continue without it or find an alternative approach."
                    } else {
                        stepToolResult = lastEvent.result
                        currentPrompt = "Tool \(lastEvent.toolName) returned: \(lastEvent.result)" +
                            "\n\nAnalyze this result and decide your next step."
                    }
                } else {
                    stepToolCall = ToolCallInfo(
                        toolName: lastEvent.toolName,
                        arguments: parsedArgs,
                        riskLevel: risk,
                        wasApproved: risk == .safe ? nil : true
                    )
                    stepToolResult = lastEvent.result
                    status = .executingTool(lastEvent.toolName)

                    // Structured error classification replaces string-matching heuristics
                    let executionResult = ToolExecutionResult.from(event: lastEvent)

                    switch executionResult {
                    case .failure(let message, let isRetryable):
                        if isRetryable && !retriedTools.contains(lastEvent.toolName) {
                            retriedTools.insert(lastEvent.toolName)
                            currentPrompt = "Tool \(lastEvent.toolName) returned an error: \(message)" +
                                "\n\nThe tool encountered an issue. Try a different approach, " +
                                "adjust the parameters, or use an alternative tool to accomplish the task."
                        } else {
                            currentPrompt = "Tool \(lastEvent.toolName) failed: \(message)" +
                                "\n\nThis error is not retryable. Use a different approach or tool."
                        }
                    case .success:
                        currentPrompt = "Tool \(lastEvent.toolName) returned: \(lastEvent.result)" +
                            "\n\nAnalyze this result and decide your next step."
                    }
                }
                } // end else (validation passed)
            } else {
                // No tool calls — model is reasoning or done
                currentPrompt = response
            }

            // Record step
            let step = AgentStep(
                id: UUID(),
                iteration: currentIteration,
                reasoning: reasoning,
                toolCall: stepToolCall,
                toolResult: stepToolResult,
                timestamp: Date()
            )
            steps.append(step)
            currentIteration += 1

            // Check termination
            if let termination = AgentLogic.detectTermination(
                response: response,
                currentIteration: currentIteration,
                maxIterations: maxIterations
            ) {
                switch termination {
                case .done:
                    let finalAnswer = reasoning ?? response
                    status = .completed(summary: finalAnswer)
                    Self.logger.info("✅ Agent completed after \(self.currentIteration) iteration(s)")
                    return
                case .fuzzyDone:
                    let finalAnswer = reasoning ?? response
                    status = .completed(summary: "⚡ Agent appears to have finished (no explicit [DONE] marker):\n\n\(finalAnswer)")
                    Self.logger.info("✅ Agent fuzzy-completed after \(self.currentIteration) iteration(s)")
                    return
                case .maxIterations:
                    let summary = AgentLogic.generateForceStopSummary(completedSteps: steps)
                    status = .forceStopped(summary: summary)
                    Self.logger.info("⏹️ Agent force-stopped at max iterations")
                    return
                case .needsApproval, .cancelled:
                    break
                }
            }
        }

        // If we exit the while loop naturally (max iterations)
        if !isCancelled {
            let summary = AgentLogic.generateForceStopSummary(completedSteps: steps)
            status = .forceStopped(summary: summary)
            Self.logger.info("⏹️ Agent force-stopped at max iterations")
        } else {
            status = .cancelled
        }
    }

    // MARK: - User Actions

    /// Approve the pending risky tool call.
    func approveAction() {
        approvalContinuation?.resume(returning: true)
    }

    /// Deny the pending risky tool call.
    func denyAction() {
        approvalContinuation?.resume(returning: false)
    }

    /// Cancel the agent loop gracefully.
    func cancel() {
        Self.logger.info("🛑 Agent cancelled by user")
        isCancelled = true
        // If waiting for approval, deny it to unblock
        approvalContinuation?.resume(returning: false)
        approvalContinuation = nil
    }

    /// Reset the harness to idle state.
    func reset() {
        currentIteration = 0
        steps = []
        status = .idle
        isRunning = false
        isCancelled = false
        autoApproveAll = false
        retriedTools = []
        approvalContinuation = nil
    }
}

// MARK: - Helpers

/// Pure helper functions for AgentHarness, extracted for testability.
enum AgentHarnessHelpers {
    /// Parse JSON argument string into a dictionary.
    static func parseArguments(_ jsonString: String) -> [String: String] {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ["raw": jsonString]
        }
        return json.mapValues { String(describing: $0) }
    }
}
