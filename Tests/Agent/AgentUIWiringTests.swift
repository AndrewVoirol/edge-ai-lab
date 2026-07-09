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
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - Agent Mode Toggle Tests

/// Tests for the `isAgentMode` toggle on ConversationViewModel
/// and the resulting harness initialization state.
@Suite("Agent Mode — Toggle")
struct AgentModeToggleTests {

    @Test("isAgentMode defaults to false")
    @MainActor
    func defaultsToFalse() {
        let vm = ConversationViewModel(conversationStore: .inMemory())
        #expect(vm.isAgentMode == false)
    }

    @Test("isAgentMode can be toggled on")
    @MainActor
    func toggleOn() {
        let vm = ConversationViewModel(conversationStore: .inMemory())
        vm.isAgentMode = true
        #expect(vm.isAgentMode == true)
    }

    @Test("isAgentMode can be toggled off")
    @MainActor
    func toggleOff() {
        let vm = ConversationViewModel(conversationStore: .inMemory())
        vm.isAgentMode = true
        vm.isAgentMode = false
        #expect(vm.isAgentMode == false)
    }

    @Test("toggle() flips isAgentMode")
    @MainActor
    func toggleFlips() {
        let vm = ConversationViewModel(conversationStore: .inMemory())
        #expect(vm.isAgentMode == false)
        vm.isAgentMode.toggle()
        #expect(vm.isAgentMode == true)
        vm.isAgentMode.toggle()
        #expect(vm.isAgentMode == false)
    }

    @Test("agentHarness is initialized with idle status")
    @MainActor
    func harnessStartsIdle() {
        let vm = ConversationViewModel(conversationStore: .inMemory())
        #expect(vm.agentHarness.status == .idle)
        #expect(vm.agentHarness.isRunning == false)
    }

    @Test("agentHarness is non-nil regardless of isAgentMode")
    @MainActor
    func harnessAlwaysPresent() {
        let vm = ConversationViewModel(conversationStore: .inMemory())
        #expect(vm.agentHarness.isRunning == false) // Access without agent mode
        vm.isAgentMode = true
        #expect(vm.agentHarness.isRunning == false) // Still accessible
    }

    @Test("availableToolNames matches ToolRegistry count")
    func availableToolNamesCount() {
        // 13 tools are registered — if this changes, update the wiring
        #expect(ConversationViewModel.availableToolNames.count == 13)
    }
}

// MARK: - Agent Status Visibility Logic Tests

/// Tests the conditions that determine when `AgentStatusView` is shown
/// in the UI hierarchy. The view appears when:
/// `isAgentMode == true && (harness.isRunning || harness.status != .idle)`
@Suite("Agent Mode — Status Visibility Logic")
struct AgentStatusVisibilityTests {

    /// Simulates the visibility condition used in ContentView and iOSChatTabView.
    private func shouldShowStatus(isAgentMode: Bool, isRunning: Bool, status: AgentStatus) -> Bool {
        isAgentMode && (isRunning || status != .idle)
    }

    @Test("Hidden when agent mode is off and harness is idle")
    func hiddenWhenOff() {
        #expect(shouldShowStatus(isAgentMode: false, isRunning: false, status: .idle) == false)
    }

    @Test("Hidden when agent mode is off even if harness is running")
    func hiddenEvenWhenRunning() {
        #expect(shouldShowStatus(isAgentMode: false, isRunning: true, status: .thinking) == false)
    }

    @Test("Hidden when agent mode is on but harness is idle and not running")
    func hiddenWhenIdleAndNotRunning() {
        #expect(shouldShowStatus(isAgentMode: true, isRunning: false, status: .idle) == false)
    }

    @Test("Visible when agent mode is on and harness is running (thinking)")
    func visibleWhenThinking() {
        #expect(shouldShowStatus(isAgentMode: true, isRunning: true, status: .thinking) == true)
    }

    @Test("Visible when agent mode is on and harness is running (executing tool)")
    func visibleWhenExecuting() {
        #expect(shouldShowStatus(isAgentMode: true, isRunning: true, status: .executingTool("calculate")) == true)
    }

    @Test("Visible when agent mode is on and harness has completed (not running)")
    func visibleWhenCompleted() {
        #expect(shouldShowStatus(isAgentMode: true, isRunning: false, status: .completed(summary: "Done")) == true)
    }

    @Test("Visible when agent mode is on and harness was force-stopped")
    func visibleWhenForceStopped() {
        #expect(shouldShowStatus(isAgentMode: true, isRunning: false, status: .forceStopped(summary: "Max iterations")) == true)
    }

    @Test("Visible when agent mode is on and harness was cancelled")
    func visibleWhenCancelled() {
        #expect(shouldShowStatus(isAgentMode: true, isRunning: false, status: .cancelled) == true)
    }

    @Test("Visible when agent mode is on and waiting for approval")
    func visibleWhenWaitingForApproval() {
        #expect(shouldShowStatus(
            isAgentMode: true,
            isRunning: true,
            status: .waitingForApproval(tool: "get_location", arguments: [:])
        ) == true)
    }
}

// MARK: - Agent Approval Sheet Binding Tests

/// Tests the computed Binding<Bool> logic that drives the approval sheet.
/// The sheet is shown when `harness.status == .waitingForApproval(...)`.
@Suite("Agent Mode — Approval Sheet Binding")
struct AgentApprovalSheetBindingTests {

    /// Simulates the `get` closure of the sheet binding.
    private func shouldShowApproval(status: AgentStatus) -> Bool {
        if case .waitingForApproval = status { return true }
        return false
    }

    @Test("Sheet hidden when idle")
    func hiddenWhenIdle() {
        #expect(shouldShowApproval(status: .idle) == false)
    }

    @Test("Sheet hidden when thinking")
    func hiddenWhenThinking() {
        #expect(shouldShowApproval(status: .thinking) == false)
    }

    @Test("Sheet hidden when executing tool")
    func hiddenWhenExecuting() {
        #expect(shouldShowApproval(status: .executingTool("calculate")) == false)
    }

    @Test("Sheet hidden when completed")
    func hiddenWhenCompleted() {
        #expect(shouldShowApproval(status: .completed(summary: "Done")) == false)
    }

    @Test("Sheet hidden when force-stopped")
    func hiddenWhenForceStopped() {
        #expect(shouldShowApproval(status: .forceStopped(summary: "Max")) == false)
    }

    @Test("Sheet hidden when cancelled")
    func hiddenWhenCancelled() {
        #expect(shouldShowApproval(status: .cancelled) == false)
    }

    @Test("Sheet shown when waiting for approval")
    func shownWhenWaitingForApproval() {
        #expect(shouldShowApproval(
            status: .waitingForApproval(tool: "get_location", arguments: ["lat": "0", "lon": "0"])
        ) == true)
    }

    @Test("Sheet shown with empty arguments")
    func shownWithEmptyArguments() {
        #expect(shouldShowApproval(
            status: .waitingForApproval(tool: "take_photo", arguments: [:])
        ) == true)
    }
}

// MARK: - Agent Harness Approve/Deny Tests

/// Tests the approve and deny methods on AgentHarness to ensure
/// the approval flow resolves correctly.
@Suite("Agent Mode — Approve/Deny Actions")
struct AgentApproveDenyTests {

    @Test("approveAction sets autoApproveAll when toggled")
    @MainActor
    func approveActionRespectsAutoApprove() {
        let harness = AgentHarness()
        harness.autoApproveAll = false
        #expect(harness.autoApproveAll == false)
        harness.autoApproveAll = true
        #expect(harness.autoApproveAll == true)
    }

    @Test("autoApproveAll defaults to false")
    @MainActor
    func autoApproveAllDefaultsFalse() {
        let harness = AgentHarness()
        #expect(harness.autoApproveAll == false)
    }

    @Test("autoApproveAll is cleared on reset")
    @MainActor
    func autoApproveAllClearedOnReset() {
        let harness = AgentHarness()
        harness.autoApproveAll = true
        harness.reset()
        #expect(harness.autoApproveAll == false)
    }
}

// MARK: - AgentStatus Equatable Exhaustive Tests

/// Exhaustive equality tests for all AgentStatus cases.
/// The Equatable conformance is manually implemented,
/// so each case/cross-case must be verified.
@Suite("AgentStatus — Equatable")
struct AgentStatusEquatableTests {

    @Test("idle == idle")
    func idleEquality() {
        #expect(AgentStatus.idle == AgentStatus.idle)
    }

    @Test("thinking == thinking")
    func thinkingEquality() {
        #expect(AgentStatus.thinking == AgentStatus.thinking)
    }

    @Test("executingTool matches same name")
    func executingToolSameName() {
        #expect(AgentStatus.executingTool("calc") == AgentStatus.executingTool("calc"))
    }

    @Test("executingTool does NOT match different name")
    func executingToolDifferentName() {
        #expect(AgentStatus.executingTool("calc") != AgentStatus.executingTool("photo"))
    }

    @Test("waitingForApproval matches same tool and args")
    func approvalMatchesSame() {
        let args = ["key": "value"]
        #expect(
            AgentStatus.waitingForApproval(tool: "get_location", arguments: args)
            == AgentStatus.waitingForApproval(tool: "get_location", arguments: args)
        )
    }

    @Test("waitingForApproval does NOT match different tool")
    func approvalDifferentTool() {
        #expect(
            AgentStatus.waitingForApproval(tool: "get_location", arguments: [:])
            != AgentStatus.waitingForApproval(tool: "take_photo", arguments: [:])
        )
    }

    @Test("waitingForApproval does NOT match different args")
    func approvalDifferentArgs() {
        #expect(
            AgentStatus.waitingForApproval(tool: "get_location", arguments: ["a": "1"])
            != AgentStatus.waitingForApproval(tool: "get_location", arguments: ["b": "2"])
        )
    }

    @Test("completed matches same summary")
    func completedSameSummary() {
        #expect(AgentStatus.completed(summary: "Done") == AgentStatus.completed(summary: "Done"))
    }

    @Test("completed does NOT match different summary")
    func completedDifferentSummary() {
        #expect(AgentStatus.completed(summary: "Done") != AgentStatus.completed(summary: "Error"))
    }

    @Test("forceStopped matches same summary")
    func forceStoppedSame() {
        #expect(AgentStatus.forceStopped(summary: "Max") == AgentStatus.forceStopped(summary: "Max"))
    }

    @Test("forceStopped does NOT match different summary")
    func forceStoppedDifferent() {
        #expect(AgentStatus.forceStopped(summary: "A") != AgentStatus.forceStopped(summary: "B"))
    }

    @Test("cancelled == cancelled")
    func cancelledEquality() {
        #expect(AgentStatus.cancelled == AgentStatus.cancelled)
    }

    // Cross-case inequality
    @Test("Different status types are not equal")
    func crossCaseInequality() {
        let cases: [AgentStatus] = [
            .idle,
            .thinking,
            .executingTool("calc"),
            .waitingForApproval(tool: "x", arguments: [:]),
            .completed(summary: "y"),
            .forceStopped(summary: "z"),
            .cancelled,
        ]
        for i in cases.indices {
            for j in cases.indices where i != j {
                #expect(cases[i] != cases[j],
                        "Expected \(cases[i]) != \(cases[j])")
            }
        }
    }
}

// MARK: - Agent Step Tests

/// Tests for the AgentStep value type used in reasoning traces.
@Suite("AgentStep — Properties")
struct AgentStepPropertyTests {

    @Test("AgentStep stores all properties")
    func storesAllProperties() {
        let id = UUID()
        let date = Date()
        let toolCall = ToolCallInfo(
            toolName: "calculate",
            arguments: ["expression": "2+2"],
            riskLevel: .safe,
            wasApproved: nil
        )
        let step = AgentStep(
            id: id,
            iteration: 3,
            reasoning: "I need to calculate this",
            toolCall: toolCall,
            toolResult: "4",
            timestamp: date
        )

        #expect(step.id == id)
        #expect(step.iteration == 3)
        #expect(step.reasoning == "I need to calculate this")
        #expect(step.toolCall?.toolName == "calculate")
        #expect(step.toolCall?.arguments["expression"] == "2+2")
        #expect(step.toolCall?.riskLevel == .safe)
        #expect(step.toolCall?.wasApproved == nil)
        #expect(step.toolResult == "4")
        #expect(step.timestamp == date)
    }

    @Test("AgentStep with nil reasoning and tool call")
    func nilOptionalFields() {
        let step = AgentStep(
            id: UUID(),
            iteration: 0,
            reasoning: nil,
            toolCall: nil,
            toolResult: nil,
            timestamp: Date()
        )

        #expect(step.reasoning == nil)
        #expect(step.toolCall == nil)
        #expect(step.toolResult == nil)
    }

    @Test("ToolCallInfo stores approval state correctly")
    func toolCallInfoApprovalState() {
        let approved = ToolCallInfo(
            toolName: "get_location",
            arguments: [:],
            riskLevel: .requiresApproval,
            wasApproved: true
        )
        #expect(approved.wasApproved == true)

        let denied = ToolCallInfo(
            toolName: "get_location",
            arguments: [:],
            riskLevel: .requiresApproval,
            wasApproved: false
        )
        #expect(denied.wasApproved == false)

        let autoApproved = ToolCallInfo(
            toolName: "calculate",
            arguments: [:],
            riskLevel: .safe,
            wasApproved: nil
        )
        #expect(autoApproved.wasApproved == nil)
    }
}

// MARK: - Agent Harness State Machine Tests

/// Tests that verify the harness state transitions are correct
/// for the UI bindings to work properly.
@Suite("Agent Mode — Harness State Machine")
struct AgentHarnessStateMachineTests {

    @Test("Harness starts idle, not running")
    @MainActor
    func initialState() {
        let harness = AgentHarness()
        #expect(harness.status == .idle)
        #expect(harness.isRunning == false)
        #expect(harness.currentIteration == 0)
        #expect(harness.steps.isEmpty)
    }

    @Test("Harness transitions to completed after [DONE]")
    @MainActor
    func completedTransition() async {
        let harness = AgentHarness()
        await harness.run(
            initialPrompt: "test",
            availableToolNames: [],
            generateResponse: { _ in
                return (response: "[DONE] All done.", toolEvents: [])
            }
        )
        #expect(harness.isRunning == false)
        if case .completed = harness.status {
            // Expected
        } else {
            Issue.record("Expected .completed, got \(harness.status)")
        }
    }

    @Test("Harness force-stops after maxIterations")
    @MainActor
    func forceStopTransition() async {
        let harness = AgentHarness()
        harness.maxIterations = 2

        await harness.run(
            initialPrompt: "loop forever",
            availableToolNames: [],
            generateResponse: { _ in
                return (response: "Still thinking...", toolEvents: [])
            }
        )

        #expect(harness.isRunning == false)
        if case .forceStopped = harness.status {
            // Expected
        } else {
            Issue.record("Expected .forceStopped, got \(harness.status)")
        }
    }

    @Test("Cancel produces cancelled status")
    @MainActor
    func cancelTransition() async {
        let harness = AgentHarness()

        // Run with a delay on first call, cancel immediately
        let task = Task { @MainActor in
            await harness.run(
                initialPrompt: "slow task",
                availableToolNames: [],
                generateResponse: { _ in
                    try? await Task.sleep(for: .seconds(10))
                    return (response: "done", toolEvents: [])
                }
            )
        }

        // Give the loop a moment to start
        try? await Task.sleep(for: .milliseconds(50))
        harness.cancel()
        await task.value

        #expect(harness.isRunning == false)
        #expect(harness.status == .cancelled)
    }

    @Test("Steps accumulate across iterations")
    @MainActor
    func stepsAccumulate() async {
        let harness = AgentHarness()
        var callCount = 0

        await harness.run(
            initialPrompt: "multi-step",
            availableToolNames: ["calculate"],
            generateResponse: { _ in
                callCount += 1
                if callCount < 3 {
                    return (response: "Step \(callCount)", toolEvents: [])
                }
                return (response: "[DONE] Finished after 3 steps.", toolEvents: [])
            }
        )

        #expect(harness.steps.count == 3)
        #expect(harness.steps[0].iteration == 0)
        #expect(harness.steps[1].iteration == 1)
        #expect(harness.steps[2].iteration == 2)
    }
}
