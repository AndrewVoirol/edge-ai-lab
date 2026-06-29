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

// MARK: - AgentHarness Tests

@Suite("AgentHarness — Core Loop")
struct AgentHarnessTests {

    @Test("Initial state is idle")
    @MainActor
    func initialStateIsIdle() {
        let harness = AgentHarness()
        #expect(harness.status == .idle)
        #expect(harness.isRunning == false)
        #expect(harness.currentIteration == 0)
        #expect(harness.steps.isEmpty)
    }

    @Test("Completes on [DONE] response")
    @MainActor
    func completesOnDone() async {
        let harness = AgentHarness()
        var callCount = 0

        await harness.run(
            initialPrompt: "What is 2+2?",
            availableToolNames: ["calculate"],
            generateResponse: { _ in
                callCount += 1
                return (response: "The answer is 4. [DONE]", toolEvents: [])
            }
        )

        #expect(callCount == 1)
        #expect(harness.steps.count == 1)
        #expect(harness.isRunning == false)
        if case .completed = harness.status {
            // Success
        } else {
            Issue.record("Expected .completed status, got \(harness.status)")
        }
    }

    @Test("Force stops at max iterations")
    @MainActor
    func forceStopsAtMaxIterations() async {
        let harness = AgentHarness()
        harness.maxIterations = 3

        await harness.run(
            initialPrompt: "Keep going",
            availableToolNames: [],
            generateResponse: { _ in
                return (response: "Still thinking...", toolEvents: [])
            }
        )

        #expect(harness.currentIteration == 3)
        #expect(harness.steps.count == 3)
        if case .forceStopped = harness.status {
            // Success
        } else {
            Issue.record("Expected .forceStopped status, got \(harness.status)")
        }
    }

    @Test("Tracks iterations correctly")
    @MainActor
    func tracksIterations() async {
        let harness = AgentHarness()
        harness.maxIterations = 5
        var callCount = 0

        await harness.run(
            initialPrompt: "Count to 3",
            availableToolNames: [],
            generateResponse: { _ in
                callCount += 1
                if callCount >= 3 {
                    return (response: "Done counting [DONE]", toolEvents: [])
                }
                return (response: "Counting... \(callCount)", toolEvents: [])
            }
        )

        #expect(callCount == 3)
        #expect(harness.steps.count == 3)
    }

    @Test("Handles inference error gracefully")
    @MainActor
    func handlesInferenceError() async {
        let harness = AgentHarness()

        await harness.run(
            initialPrompt: "Will fail",
            availableToolNames: [],
            generateResponse: { _ in
                throw NSError(domain: "Test", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Simulated inference error"
                ])
            }
        )

        #expect(harness.steps.count == 1)
        #expect(harness.isRunning == false)
        if case .forceStopped(let summary) = harness.status {
            #expect(summary.contains("inference error"))
        } else {
            Issue.record("Expected .forceStopped status")
        }
    }

    @Test("Cancel stops the loop")
    @MainActor
    func cancelStopsLoop() async {
        let harness = AgentHarness()
        harness.maxIterations = 100

        // Start agent in a separate task, cancel it after first iteration
        let agentTask = Task { @MainActor in
            await harness.run(
                initialPrompt: "Long task",
                availableToolNames: [],
                generateResponse: { _ in
                    // Yield to let the cancellation happen
                    try? await Task.sleep(for: .milliseconds(10))
                    return (response: "Still working...", toolEvents: [])
                }
            )
        }

        // Give the agent a moment to start
        try? await Task.sleep(for: .milliseconds(50))
        harness.cancel()

        await agentTask.value

        #expect(harness.isRunning == false)
        #expect(harness.status == .cancelled)
    }

    @Test("Reset clears all state")
    @MainActor
    func resetClearsState() {
        let harness = AgentHarness()
        // Manually set some state
        harness.currentIteration = 5
        harness.steps = [
            AgentStep(id: UUID(), iteration: 0, reasoning: "test", toolCall: nil, toolResult: nil, timestamp: Date())
        ]
        harness.status = .completed(summary: "Done")
        harness.isRunning = true
        harness.autoApproveAll = true

        harness.reset()

        #expect(harness.currentIteration == 0)
        #expect(harness.steps.isEmpty)
        #expect(harness.status == .idle)
        #expect(harness.isRunning == false)
        #expect(harness.autoApproveAll == false)
    }

    @Test("Records tool call events in steps")
    @MainActor
    func recordsToolCallEvents() async {
        let harness = AgentHarness()
        var callCount = 0

        await harness.run(
            initialPrompt: "Calculate 2+2",
            availableToolNames: ["calculate"],
            generateResponse: { _ in
                callCount += 1
                if callCount == 1 {
                    let event = ToolCallEvent(
                        toolName: "calculate",
                        arguments: "{\"expression\": \"2+2\"}",
                        result: "4",
                        durationMs: 1.0,
                        timestamp: Date(),
                        succeeded: true
                    )
                    return (response: "Using calculator...", toolEvents: [event])
                }
                return (response: "The answer is 4. [DONE]", toolEvents: [])
            }
        )

        #expect(harness.steps.count == 2)
        let firstStep = harness.steps[0]
        #expect(firstStep.toolCall != nil)
        #expect(firstStep.toolCall?.toolName == "calculate")
        #expect(firstStep.toolCall?.riskLevel == .safe)
        #expect(firstStep.toolCall?.wasApproved == nil) // safe = auto-approved
        #expect(firstStep.toolResult == "4")
    }
}

// MARK: - AgentHarness Helpers Tests

@Suite("AgentHarnessHelpers — Argument Parsing")
struct AgentHarnessHelpersTests {

    @Test("Parses valid JSON arguments")
    func parsesValidJSON() {
        let json = "{\"expression\": \"2+2\", \"mode\": \"basic\"}"
        let result = AgentHarnessHelpers.parseArguments(json)
        #expect(result["expression"] == "2+2")
        #expect(result["mode"] == "basic")
    }

    @Test("Falls back for invalid JSON")
    func fallsBackForInvalidJSON() {
        let result = AgentHarnessHelpers.parseArguments("not json")
        #expect(result["raw"] == "not json")
    }

    @Test("Handles empty string")
    func handlesEmptyString() {
        let result = AgentHarnessHelpers.parseArguments("")
        #expect(result["raw"] == "")
    }
}
