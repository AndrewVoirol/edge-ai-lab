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

import Testing
import Foundation

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
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

    // MARK: - Bundled Flows Parsing

    @Test("All bundled flow JSON files parse as valid AutomationFlow")
    func bundledFlowsAllParse() throws {
        let flowsDir = AutomationFlowRunner.flowsDirectory()
        let fm = FileManager.default

        guard fm.fileExists(atPath: flowsDir.path) else {
            // Flows directory not found in test bundle — skip on CI or device
            Issue.record(
                "Flows directory not found at \(flowsDir.path). Flow files are bundled via app resources in Project.swift and may not be available in the unit test bundle."
            )
            return
        }

        // Recursively collect all .json files (including ui/ subdirectory)
        guard let enumerator = fm.enumerator(
            at: flowsDir,
            includingPropertiesForKeys: nil
        ) else {
            Issue.record("Could not enumerate flows directory: \(flowsDir.path)")
            return
        }

        var jsonURLs: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "json" {
            jsonURLs.append(url)
        }

        #expect(!jsonURLs.isEmpty, "Expected at least one flow JSON file")

        let decoder = JSONDecoder()
        var failedFiles: [String] = []
        for url in jsonURLs {
            do {
                let data = try Data(contentsOf: url)
                // Pre-check: skip files that aren't flow definitions
                // (e.g., test fixtures or config files that may end up in the same directory)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   json["name"] == nil {
                    continue // Not a flow file — skip silently
                }
                let flow = try decoder.decode(AutomationFlow.self, from: data)
                #expect(!flow.name.isEmpty, "Flow in \(url.lastPathComponent) should have a name")
                #expect(!flow.steps.isEmpty, "Flow '\(flow.name)' should have at least one step")
            } catch {
                failedFiles.append("\(url.lastPathComponent): \(error)")
            }
        }
        #expect(failedFiles.isEmpty, "Failed to parse flow files: \(failedFiles.joined(separator: "; "))")
    }

    // MARK: - Empty Steps

    @Test("Flow with empty steps array decodes correctly")
    func flowWithEmptySteps() throws {
        let json = """
        {
            "name": "Empty Flow",
            "steps": []
        }
        """

        let data = json.data(using: .utf8)!
        let flow = try JSONDecoder().decode(AutomationFlow.self, from: data)

        #expect(flow.name == "Empty Flow")
        #expect(flow.steps.isEmpty)
    }

    // MARK: - All Known Actions

    @Test(
        "All known action strings are valid in flow steps",
        arguments: ["verify_ui", "tap", "type_text", "wait", "screenshot"]
    )
    func flowStepAllActions(action: String) throws {
        let json = """
        {
            "name": "Action Test",
            "steps": [
                {
                    "step": 1,
                    "action": "\(action)",
                    "description": "Test \(action)"
                }
            ]
        }
        """

        let data = json.data(using: .utf8)!
        let flow = try JSONDecoder().decode(AutomationFlow.self, from: data)

        #expect(flow.steps[0].action == action)
    }

    // MARK: - Multiple Variable Interpolation

    @Test("Interpolate multiple environment variables in one string")
    func interpolateMultipleVars() throws {
        let input = "$HOME/path/$USER"
        let result = AutomationFlowRunner.interpolateEnvironmentVariables(input)

        // Both $HOME and $USER should be replaced (they exist on macOS/iOS)
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            #expect(result.contains(home), "Should interpolate $HOME")
            #expect(!result.contains("$HOME"), "$HOME should be replaced")
        }
        if let user = ProcessInfo.processInfo.environment["USER"] {
            #expect(result.contains(user), "Should interpolate $USER")
            #expect(!result.contains("$USER"), "$USER should be replaced")
        }

        // The "/path/" separator should be preserved
        #expect(result.contains("/path/"), "Literal path segments should be preserved")
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

    // MARK: - Serialization Round-Trip

    @Test("FlowResult round-trips through manual JSON dictionary encoding")
    func flowResultSerialization() throws {
        // FlowResult is Sendable but not Codable, so we test the manual
        // dictionary-based JSON encoding path used by printFlowResult().
        let stepResults = [
            FlowStepResult(step: 1, action: "tap", description: "Tap button", passed: true, message: "OK", durationMs: 15.5),
            FlowStepResult(step: 2, action: "verify_ui", description: "Verify", passed: false, message: "Missing", durationMs: 22.3),
        ]

        let original = FlowResult(
            flowName: "Serialize Flow",
            passed: false,
            stepResults: stepResults,
            totalDurationMs: 37.8,
            failedStep: 2
        )

        // Encode to JSON using the same dictionary structure as printFlowResult()
        let stepDicts: [[String: Any]] = original.stepResults.map { step in
            [
                "step": step.step,
                "action": step.action,
                "description": step.description,
                "passed": step.passed,
                "message": step.message,
                "duration_ms": step.durationMs,
            ]
        }

        let resultDict: [String: Any] = [
            "flow_name": original.flowName,
            "passed": original.passed,
            "total_duration_ms": original.totalDurationMs,
            "failed_step": original.failedStep as Any,
            "steps": stepDicts,
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: resultDict, options: [.sortedKeys])
        #expect(!jsonData.isEmpty, "JSON data should not be empty")

        // Decode back and verify key fields
        let decoded = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]
        #expect(decoded["flow_name"] as? String == "Serialize Flow")
        #expect(decoded["passed"] as? Bool == false)
        #expect(decoded["failed_step"] as? Int == 2)

        let decodedSteps = decoded["steps"] as! [[String: Any]]
        #expect(decodedSteps.count == 2)
        #expect(decodedSteps[0]["action"] as? String == "tap")
        #expect(decodedSteps[1]["passed"] as? Bool == false)

        // Verify the total_duration_ms round-trips accurately
        let decodedDuration = decoded["total_duration_ms"] as? Double ?? 0
        #expect(abs(decodedDuration - 37.8) < 0.001, "Duration should round-trip accurately")
    }
}
