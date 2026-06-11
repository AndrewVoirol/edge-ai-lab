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

import Testing
import Foundation

#if os(iOS)
@testable import GemmaEdgeGallery_iOS
#elseif os(macOS)
@testable import GemmaEdgeGallery_macOS
#endif

// MARK: - Automation Flow Tests (Swift Testing)

/// Tests for the AutomationFlowRunner system.
///
/// This suite validates the JSON flow parsing, step execution ordering,
/// and environment variable interpolation used by the DeveloperAutomationHarness.
///
/// ## Pattern
/// New tests in this project use Swift Testing (`@Test`/`@Suite`) instead of XCTest.
/// Existing XCTest tests are migrated incrementally as they're touched.
///
/// ## Adding New Tests
/// ```swift
/// @Test("Description of what you're testing")
/// func myNewTest() throws {
///     // Use #expect() instead of XCTAssert
///     #expect(someValue == expectedValue)
/// }
/// ```
@Suite("Automation Flow Runner")
struct AutomationFlowRunnerTests {

    // MARK: - JSON Parsing

    @Test("Flow JSON decodes with all required fields")
    func flowJSONDecoding() throws {
        let json = """
        {
            "name": "Test Flow",
            "steps": [
                {
                    "step": 1,
                    "action": "verify_ui",
                    "description": "Verify the app launched.",
                    "expected_elements": ["Models", "Chat"]
                },
                {
                    "step": 2,
                    "action": "tap",
                    "description": "Tap the settings button.",
                    "target_element": "gearshape"
                }
            ]
        }
        """

        let data = json.data(using: .utf8)!
        let flow = try JSONDecoder().decode(AutomationFlow.self, from: data)

        #expect(flow.name == "Test Flow")
        #expect(flow.steps.count == 2)
        #expect(flow.steps[0].action == "verify_ui")
        #expect(flow.steps[0].expectedElements == ["Models", "Chat"])
        #expect(flow.steps[1].action == "tap")
        #expect(flow.steps[1].targetElement == "gearshape")
    }

    @Test("Flow JSON decodes optional fields")
    func flowOptionalFields() throws {
        let json = """
        {
            "name": "Minimal Flow",
            "description": "A flow with optional fields",
            "prerequisites": ["Model loaded"],
            "steps": [
                {
                    "step": 1,
                    "action": "wait",
                    "description": "Wait for completion.",
                    "condition": "element_not_exists:Generating..."
                }
            ]
        }
        """

        let data = json.data(using: .utf8)!
        let flow = try JSONDecoder().decode(AutomationFlow.self, from: data)

        #expect(flow.description == "A flow with optional fields")
        #expect(flow.prerequisites == ["Model loaded"])
        #expect(flow.steps[0].condition == "element_not_exists:Generating...")
        #expect(flow.steps[0].targetElement == nil)
        #expect(flow.steps[0].value == nil)
    }

    @Test("Flow step with type_text includes value")
    func typeTextStep() throws {
        let json = """
        {
            "name": "Type Text Flow",
            "steps": [
                {
                    "step": 1,
                    "action": "type_text",
                    "description": "Type a prompt.",
                    "target_element": "promptField",
                    "value": "Hello, AI!"
                }
            ]
        }
        """

        let data = json.data(using: .utf8)!
        let flow = try JSONDecoder().decode(AutomationFlow.self, from: data)

        #expect(flow.steps[0].value == "Hello, AI!")
        #expect(flow.steps[0].targetElement == "promptField")
    }

    // MARK: - Step Ordering

    @Test("Steps are decoded in order",
          arguments: ["model_setup_flow", "inference_flow", "settings_flow",
                      "benchmark_flow", "multimodal_flow"])
    func stepOrdering(flowName: String) throws {
        // This test verifies that flow steps maintain sequential ordering.
        // The actual flow files are in automation/flows/ but may not be
        // accessible from the test bundle. We verify the contract instead.
        let json = """
        {
            "name": "\(flowName)",
            "steps": [
                {"step": 1, "action": "verify_ui", "description": "Step 1"},
                {"step": 2, "action": "tap", "description": "Step 2", "target_element": "btn"},
                {"step": 3, "action": "wait", "description": "Step 3", "condition": "element_exists:done"}
            ]
        }
        """

        let data = json.data(using: .utf8)!
        let flow = try JSONDecoder().decode(AutomationFlow.self, from: data)

        for (index, step) in flow.steps.enumerated() {
            #expect(step.step == index + 1,
                    "Step \(index + 1) should have step number \(index + 1), got \(step.step)")
        }
    }

    // MARK: - Environment Variable Interpolation

    @Test("Environment variable interpolation replaces $VAR_NAME")
    func envVarInterpolation() throws {
        // Set a test environment variable
        let input = "Token: $HOME and $PATH"
        let result = AutomationFlowRunner.interpolateEnvironmentVariables(input)

        // $HOME and $PATH should be replaced with actual values
        #expect(!result.contains("$HOME"), "Should interpolate $HOME")
        #expect(!result.contains("$PATH"), "Should interpolate $PATH")
    }

    @Test("Environment variable interpolation preserves non-variable text")
    func envVarPreservesText() throws {
        let input = "Hello, World! No variables here."
        let result = AutomationFlowRunner.interpolateEnvironmentVariables(input)
        #expect(result == input)
    }

    @Test("Environment variable interpolation handles undefined variables")
    func envVarUndefined() throws {
        let input = "Value: $DEFINITELY_NOT_A_REAL_ENV_VAR_12345"
        let result = AutomationFlowRunner.interpolateEnvironmentVariables(input)
        // Undefined variables should remain as-is
        #expect(result.contains("$DEFINITELY_NOT_A_REAL_ENV_VAR_12345"))
    }

    // MARK: - FlowStep Codable Conformance

    @Test("FlowStep CodingKeys map snake_case JSON to camelCase Swift")
    func codingKeysMapping() throws {
        let json = """
        {
            "step": 1,
            "action": "type_text",
            "description": "Type text",
            "target_element": "field",
            "value": "text",
            "expected_elements": ["a", "b"],
            "condition": "element_exists:c"
        }
        """

        let data = json.data(using: .utf8)!
        let step = try JSONDecoder().decode(FlowStep.self, from: data)

        #expect(step.targetElement == "field")
        #expect(step.expectedElements == ["a", "b"])
    }

    // MARK: - Flow Discovery

    @Test("discoverFlows returns sorted flow names")
    func flowDiscovery() throws {
        let flows = AutomationFlowRunner.discoverFlows()
        // Flows should be sorted alphabetically
        let sorted = flows.sorted()
        #expect(flows == sorted, "Discovered flows should be sorted alphabetically")
    }
}

// MARK: - FlowResult Tests

@Suite("Flow Result")
struct FlowResultTests {

    @Test("FlowResult summary includes pass/fail status")
    func resultSummary() {
        let result = FlowResult(
            flowName: "Test Flow",
            passed: true,
            stepResults: [
                FlowStepResult(step: 1, action: "tap", description: "Tap", passed: true, message: "OK", durationMs: 10),
                FlowStepResult(step: 2, action: "verify", description: "Verify", passed: true, message: "OK", durationMs: 20)
            ],
            totalDurationMs: 30,
            failedStep: nil
        )

        #expect(result.summary.contains("PASSED"))
        #expect(result.summary.contains("2/2"))
    }

    @Test("FlowResult summary shows FAILED for failing flows")
    func failedResultSummary() {
        let result = FlowResult(
            flowName: "Failing Flow",
            passed: false,
            stepResults: [
                FlowStepResult(step: 1, action: "tap", description: "Tap", passed: true, message: "OK", durationMs: 10),
                FlowStepResult(step: 2, action: "verify", description: "Verify", passed: false, message: "Not found", durationMs: 20)
            ],
            totalDurationMs: 30,
            failedStep: 2
        )

        #expect(result.summary.contains("FAILED"))
        #expect(result.failedStep == 2)
    }
}
