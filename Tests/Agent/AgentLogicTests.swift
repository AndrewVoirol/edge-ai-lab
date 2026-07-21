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

// MARK: - Risk Classification Tests

@Suite("AgentLogic — Risk Classification")
struct AgentLogicRiskClassificationTests {

    @Test("Safe tools are classified as safe")
    func safeToolsClassifiedCorrectly() {
        let safeTools = [
            "calculate",
            "get_current_datetime",
            "get_device_info",
            "convert_units",
            "analyze_text",
            "get_system_health"
        ]
        for tool in safeTools {
            #expect(AgentLogic.classifyRisk(toolName: tool) == .safe,
                    "Expected \(tool) to be classified as safe")
        }
    }

    @Test("Risky tools require approval")
    func riskyToolsRequireApproval() {
        let riskyTools = [
            "get_location",
            "take_photo",
            "get_device_motion",
            "search_files",
            "get_sensors",
            "get_network_info",
            "create_shortcut"
        ]
        for tool in riskyTools {
            #expect(AgentLogic.classifyRisk(toolName: tool) == .requiresApproval,
                    "Expected \(tool) to require approval")
        }
    }

    @Test("Unknown tools require approval")
    func unknownToolsRequireApproval() {
        #expect(AgentLogic.classifyRisk(toolName: "unknown_tool") == .requiresApproval)
        #expect(AgentLogic.classifyRisk(toolName: "") == .requiresApproval)
    }

    @Test("Safe tools set contains exactly 6 tools")
    func safeToolsCount() {
        #expect(AgentLogic.safeTools.count == 6)
    }
}

// MARK: - Termination Detection Tests

@Suite("AgentLogic — Termination Detection")
struct AgentLogicTerminationTests {

    @Test("Detects [DONE] marker")
    func detectsDoneMarker() {
        let response = "I have analyzed the data. The answer is 42. [DONE]"
        let result = AgentLogic.detectTermination(response: response, currentIteration: 1, maxIterations: 10)
        #expect(result == .done)
    }

    @Test("Detects [DONE] marker at start")
    func detectsDoneMarkerAtStart() {
        let response = "[DONE] All finished."
        let result = AgentLogic.detectTermination(response: response, currentIteration: 0, maxIterations: 10)
        #expect(result == .done)
    }

    @Test("Detects [NEED_APPROVAL:tool_name] marker")
    func detectsNeedApprovalWithTool() {
        let response = "I need to access your location. [NEED_APPROVAL:get_location]"
        let result = AgentLogic.detectTermination(response: response, currentIteration: 1, maxIterations: 10)
        #expect(result == .needsApproval(tool: "get_location"))
    }

    @Test("Detects [NEED_APPROVAL] without tool name")
    func detectsNeedApprovalWithoutTool() {
        let response = "I need approval. [NEED_APPROVAL]"
        let result = AgentLogic.detectTermination(response: response, currentIteration: 1, maxIterations: 10)
        #expect(result == .needsApproval(tool: "unknown"))
    }

    @Test("Detects max iterations")
    func detectsMaxIterations() {
        let response = "Continuing to work..."
        let result = AgentLogic.detectTermination(response: response, currentIteration: 10, maxIterations: 10)
        #expect(result == .maxIterations)
    }

    @Test("Returns nil when no markers and not at max")
    func returnsNilWhenNoTermination() {
        let response = "I need to calculate something first."
        let result = AgentLogic.detectTermination(response: response, currentIteration: 3, maxIterations: 10)
        #expect(result == nil)
    }

    @Test("[DONE] takes priority over max iterations")
    func doneOverMaxIterations() {
        let response = "Final answer: 42 [DONE]"
        let result = AgentLogic.detectTermination(response: response, currentIteration: 10, maxIterations: 10)
        #expect(result == .done)
    }
}

// MARK: - System Prompt Tests

@Suite("AgentLogic — System Prompt")
struct AgentLogicSystemPromptTests {

    @Test("System prompt includes tool names")
    func systemPromptIncludesToolNames() {
        let tools = ["calculate", "get_location", "analyze_text"]
        let prompt = AgentLogic.buildAgentSystemPrompt(availableTools: tools)
        for tool in tools {
            #expect(prompt.contains(tool))
        }
    }

    @Test("System prompt includes instructions")
    func systemPromptIncludesInstructions() {
        let prompt = AgentLogic.buildAgentSystemPrompt(availableTools: ["calculate"])
        #expect(prompt.contains("step by step"))
        #expect(prompt.contains("[DONE]"))
        #expect(prompt.contains("[NEED_APPROVAL"))
    }

    @Test("System prompt with empty tools")
    func systemPromptWithEmptyTools() {
        let prompt = AgentLogic.buildAgentSystemPrompt(availableTools: [])
        #expect(prompt.contains("Available tools:"))
    }
}

// MARK: - Reasoning Extraction Tests

@Suite("AgentLogic — Reasoning Extraction")
struct AgentLogicReasoningTests {

    @Test("Extracts reasoning before [DONE]")
    func extractsReasoningBeforeDone() {
        let response = "I analyzed the data and found the answer is 42. [DONE]"
        let reasoning = AgentLogic.extractReasoningTrace(from: response)
        #expect(reasoning == "I analyzed the data and found the answer is 42.")
    }

    @Test("Extracts reasoning before [NEED_APPROVAL]")
    func extractsReasoningBeforeApproval() {
        let response = "I need your location to continue. [NEED_APPROVAL:get_location]"
        let reasoning = AgentLogic.extractReasoningTrace(from: response)
        #expect(reasoning == "I need your location to continue.")
    }

    @Test("Returns full response when no markers")
    func returnsFullResponseWhenNoMarkers() {
        let response = "Let me think about this problem."
        let reasoning = AgentLogic.extractReasoningTrace(from: response)
        #expect(reasoning == "Let me think about this problem.")
    }

    @Test("Returns nil for empty response")
    func returnsNilForEmptyResponse() {
        let reasoning = AgentLogic.extractReasoningTrace(from: "")
        #expect(reasoning == nil)
    }

    @Test("Returns nil when only markers")
    func returnsNilWhenOnlyMarkers() {
        let reasoning = AgentLogic.extractReasoningTrace(from: "[DONE]")
        #expect(reasoning == nil)
    }
}

// MARK: - Force Stop Summary Tests

@Suite("AgentLogic — Force Stop Summary")
struct AgentLogicForceStopTests {

    @Test("Summary includes step count")
    func summaryIncludesStepCount() {
        let steps = [
            AgentStep(id: UUID(), iteration: 0, reasoning: "Analyzing", toolCall: nil, toolResult: nil, timestamp: Date()),
            AgentStep(id: UUID(), iteration: 1, reasoning: "Computing", toolCall: nil, toolResult: nil, timestamp: Date())
        ]
        let summary = AgentLogic.generateForceStopSummary(completedSteps: steps)
        #expect(summary.contains("2 step(s)"))
    }

    @Test("Summary includes tool names")
    func summaryIncludesToolNames() {
        let steps = [
            AgentStep(
                id: UUID(),
                iteration: 0,
                reasoning: "Calculating",
                toolCall: ToolCallInfo(
                    toolName: "calculate",
                    arguments: ["expression": "2+2"],
                    riskLevel: .safe,
                    wasApproved: nil
                ),
                toolResult: "4",
                timestamp: Date()
            )
        ]
        let summary = AgentLogic.generateForceStopSummary(completedSteps: steps)
        #expect(summary.contains("calculate"))
    }

    @Test("Summary includes last reasoning")
    func summaryIncludesLastReasoning() {
        let steps = [
            AgentStep(id: UUID(), iteration: 0, reasoning: "Final thought here", toolCall: nil, toolResult: nil, timestamp: Date())
        ]
        let summary = AgentLogic.generateForceStopSummary(completedSteps: steps)
        #expect(summary.contains("Final thought here"))
    }

    @Test("Summary handles empty steps")
    func summaryHandlesEmptySteps() {
        let summary = AgentLogic.generateForceStopSummary(completedSteps: [])
        #expect(summary.contains("0 step(s)"))
    }

    @Test("Summary truncates long reasoning")
    func summaryTruncatesLongReasoning() {
        let longText = String(repeating: "a", count: 300)
        let steps = [
            AgentStep(id: UUID(), iteration: 0, reasoning: longText, toolCall: nil, toolResult: nil, timestamp: Date())
        ]
        let summary = AgentLogic.generateForceStopSummary(completedSteps: steps)
        #expect(summary.contains("..."))
    }

    @Test("Summary includes elapsed time")
    func summaryIncludesElapsedTime() {
        let t1 = Date()
        let t2 = t1.addingTimeInterval(5.3)
        let steps = [
            AgentStep(id: UUID(), iteration: 0, reasoning: "Start", toolCall: nil, toolResult: nil, timestamp: t1),
            AgentStep(id: UUID(), iteration: 1, reasoning: "End", toolCall: nil, toolResult: nil, timestamp: t2)
        ]
        let summary = AgentLogic.generateForceStopSummary(completedSteps: steps)
        #expect(summary.contains("Elapsed: 5.3s"))
    }

    @Test("Summary includes iteration limit note")
    func summaryIncludesIterationNote() {
        let steps = [
            AgentStep(id: UUID(), iteration: 0, reasoning: "Working", toolCall: nil, toolResult: nil, timestamp: Date())
        ]
        let summary = AgentLogic.generateForceStopSummary(completedSteps: steps)
        #expect(summary.contains("maximum iteration limit"))
    }
}

// MARK: - Fuzzy Termination Tests

@Suite("AgentLogic — Fuzzy Termination Detection")
struct AgentLogicFuzzyTerminationTests {

    @Test("Detects 'task complete' at end of response")
    func detectsTaskComplete() {
        let response = "I've calculated all the values. The result is 42.\n\nTask complete."
        let result = AgentLogic.detectTermination(response: response, currentIteration: 1, maxIterations: 10)
        #expect(result == .done)
    }

    @Test("Detects 'I'm done' at end of response")
    func detectsImDone() {
        let response = "Everything has been analyzed and the answer is clear. I'm done."
        let result = AgentLogic.detectTermination(response: response, currentIteration: 1, maxIterations: 10)
        #expect(result == .done)
    }

    @Test("Detects 'here is the final answer'")
    func detectsFinalAnswer() {
        let response = "After thorough analysis, here is the final answer: The temperature is 25°C."
        let result = AgentLogic.detectTermination(response: response, currentIteration: 1, maxIterations: 10)
        #expect(result == .done)
    }

    @Test("Does NOT trigger fuzzy detection in mid-reasoning")
    func doesNotTriggerMidReasoning() {
        let response = "I need to continue working. Let me use the calculator next."
        let result = AgentLogic.detectTermination(response: response, currentIteration: 1, maxIterations: 10)
        #expect(result == nil)
    }

    @Test("Does NOT trigger fuzzy when NEED_APPROVAL is present")
    func doesNotTriggerWithApprovalMarker() {
        let response = "I have completed the analysis but need permission. [NEED_APPROVAL:get_location] Task complete."
        let result = AgentLogic.detectTermination(response: response, currentIteration: 1, maxIterations: 10)
        #expect(result == .needsApproval(tool: "get_location"))
    }

    @Test("[DONE] still takes priority over fuzzy detection")
    func doneStillTakesPriority() {
        let response = "Task complete. [DONE]"
        let result = AgentLogic.detectTermination(response: response, currentIteration: 1, maxIterations: 10)
        #expect(result == .done)
    }
}

// MARK: - Tool Call Validation Tests

@Suite("AgentLogic — Tool Call Validation")
struct AgentLogicToolValidationTests {

    @Test("Valid tool call passes validation")
    func validToolCallPasses() {
        let result = AgentLogic.validateToolCall(
            toolName: "calculate",
            arguments: ["expression": "2+2"],
            availableToolNames: ["calculate", "get_device_info"]
        )
        #expect(result == nil)
    }

    @Test("Unknown tool name fails validation")
    func unknownToolFails() {
        let result = AgentLogic.validateToolCall(
            toolName: "hack_system",
            arguments: ["target": "everything"],
            availableToolNames: ["calculate", "get_device_info"]
        )
        #expect(result != nil)
        #expect(result!.contains("Unknown tool"))
        #expect(result!.contains("hack_system"))
    }

    @Test("Empty arguments fail validation")
    func emptyArgumentsFail() {
        let result = AgentLogic.validateToolCall(
            toolName: "calculate",
            arguments: [:],
            availableToolNames: ["calculate"]
        )
        #expect(result != nil)
        #expect(result!.contains("no arguments"))
    }
}
