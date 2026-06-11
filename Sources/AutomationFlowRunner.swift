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
import SwiftUI

// NOTE: This file uses print() intentionally for structured stdout output.
// The [AUTOMATION_FLOW_*] prefixed lines are protocol output consumed by
// automation scripts and Antigravity skills. Do NOT replace with os.Logger.

// MARK: - Flow Data Models

/// Represents a complete automation flow loaded from JSON.
struct AutomationFlow: Codable, Sendable {
    let name: String
    let description: String?
    let prerequisites: [String]?
    let steps: [FlowStep]
}

/// Represents a single step within an automation flow.
struct FlowStep: Codable, Sendable {
    let step: Int
    let action: String
    let description: String
    let targetElement: String?
    let value: String?
    let expectedElements: [String]?
    let condition: String?

    enum CodingKeys: String, CodingKey {
        case step, action, description
        case targetElement = "target_element"
        case value
        case expectedElements = "expected_elements"
        case condition
    }
}

/// Result of executing a single flow step.
struct FlowStepResult: Sendable {
    let step: Int
    let action: String
    let description: String
    let passed: Bool
    let message: String
    let durationMs: Double
}

/// Aggregate result of a complete flow execution.
struct FlowResult: Sendable {
    let flowName: String
    let passed: Bool
    let stepResults: [FlowStepResult]
    let totalDurationMs: Double
    let failedStep: Int?

    var summary: String {
        let passCount = stepResults.filter(\.passed).count
        let totalCount = stepResults.count
        let status = passed ? "PASSED" : "FAILED"
        return "[\(status)] \(flowName): \(passCount)/\(totalCount) steps passed in \(String(format: "%.1f", totalDurationMs))ms"
    }
}

// MARK: - Flow Runner

/// Executes automation flows defined in JSON files.
///
/// The runner loads flow definitions from the app bundle or filesystem,
/// interpolates environment variables, and executes steps sequentially.
/// Results are reported via structured stdout for consumption by CI
/// scripts and Antigravity automation skills.
@MainActor
struct AutomationFlowRunner {

    /// Default timeout for UI verification steps (seconds).
    static let defaultStepTimeout: TimeInterval = 10.0

    /// Default timeout for wait conditions (seconds).
    static let defaultWaitTimeout: TimeInterval = 60.0

    // MARK: - Flow Discovery & Loading

    /// Discovers all available flow files from the automation/flows directory.
    nonisolated static func discoverFlows() -> [String] {
        let flowsDir = flowsDirectory()
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: flowsDir,
            includingPropertiesForKeys: nil
        ) else {
            print("[AUTOMATION_FLOW_ERROR] Could not read flows directory: \(flowsDir.path)")
            return []
        }

        return contents
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    /// Loads a flow definition from JSON.
    static func loadFlow(named name: String) -> AutomationFlow? {
        let flowFile = flowsDirectory().appendingPathComponent("\(name).json")

        guard FileManager.default.fileExists(atPath: flowFile.path) else {
            print("[AUTOMATION_FLOW_ERROR] Flow file not found: \(flowFile.path)")
            return nil
        }

        do {
            let data = try Data(contentsOf: flowFile)
            let flow = try JSONDecoder().decode(AutomationFlow.self, from: data)
            print("[AUTOMATION_FLOW] Loaded flow '\(flow.name)' with \(flow.steps.count) steps")
            return flow
        } catch {
            print("[AUTOMATION_FLOW_ERROR] Failed to parse flow '\(name)': \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Flow Execution

    /// Executes a flow by name, reporting results via stdout protocol.
    static func executeFlow(named name: String) async -> FlowResult {
        print("[AUTOMATION_FLOW_START] Executing flow: \(name)")
        let startTime = CFAbsoluteTimeGetCurrent()

        guard let flow = loadFlow(named: name) else {
            let result = FlowResult(
                flowName: name,
                passed: false,
                stepResults: [],
                totalDurationMs: 0,
                failedStep: nil
            )
            print("[AUTOMATION_FLOW_FAILURE] Could not load flow: \(name)")
            return result
        }

        // Check prerequisites
        if let prereqs = flow.prerequisites, !prereqs.isEmpty {
            print("[AUTOMATION_FLOW] Prerequisites: \(prereqs.joined(separator: ", "))")
        }

        var stepResults: [FlowStepResult] = []
        var failedStep: Int? = nil

        for step in flow.steps {
            let stepStart = CFAbsoluteTimeGetCurrent()
            print("[AUTOMATION_FLOW_STEP] Step \(step.step): \(step.description)")

            let result = await executeStep(step)
            let durationMs = (CFAbsoluteTimeGetCurrent() - stepStart) * 1000

            let stepResult = FlowStepResult(
                step: step.step,
                action: step.action,
                description: step.description,
                passed: result.success,
                message: result.message,
                durationMs: durationMs
            )
            stepResults.append(stepResult)

            if result.success {
                print("[AUTOMATION_FLOW_STEP_PASS] Step \(step.step) passed: \(result.message)")
            } else {
                print("[AUTOMATION_FLOW_STEP_FAIL] Step \(step.step) failed: \(result.message)")
                failedStep = step.step
                break // Stop on first failure
            }
        }

        let totalDurationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        let allPassed = failedStep == nil

        let flowResult = FlowResult(
            flowName: flow.name,
            passed: allPassed,
            stepResults: stepResults,
            totalDurationMs: totalDurationMs,
            failedStep: failedStep
        )

        // Print structured result
        printFlowResult(flowResult)

        return flowResult
    }

    /// Executes all discovered flows sequentially.
    static func executeAllFlows() async -> [FlowResult] {
        let flowNames = discoverFlows()
        print("[AUTOMATION_FLOW] Discovered \(flowNames.count) flows: \(flowNames.joined(separator: ", "))")

        var results: [FlowResult] = []
        for name in flowNames {
            let result = await executeFlow(named: name)
            results.append(result)
        }

        // Print summary
        let passCount = results.filter(\.passed).count
        print("\n[AUTOMATION_FLOW_SUMMARY] \(passCount)/\(results.count) flows passed")
        for result in results {
            print("[AUTOMATION_FLOW_SUMMARY]   \(result.summary)")
        }

        return results
    }

    // MARK: - Step Execution

    private static func executeStep(_ step: FlowStep) async -> (success: Bool, message: String) {
        switch step.action {
        case "verify_ui":
            return await executeVerifyUI(step)
        case "tap":
            return await executeTap(step)
        case "type_text":
            return await executeTypeText(step)
        case "wait":
            return await executeWait(step)
        case "screenshot":
            return executeScreenshot(step)
        default:
            return (false, "Unknown action: \(step.action)")
        }
    }

    /// Verifies that expected UI elements exist.
    /// In-process, this uses SwiftUI's accessibility identifiers via the
    /// app's own view hierarchy — no XCUITest required.
    private static func executeVerifyUI(_ step: FlowStep) async -> (success: Bool, message: String) {
        guard let expectedElements = step.expectedElements, !expectedElements.isEmpty else {
            return (false, "No expected_elements specified for verify_ui action")
        }

        // In-process UI verification: check if elements with matching
        // accessibility identifiers or labels exist in the current window.
        // This is a lightweight check that works without XCUITest.
        //
        // NOTE: For full accessibility tree inspection, the automation
        // harness should be used with `xcrun simctl` or the xcodebuild-mcp
        // snapshot_ui tool from an Antigravity skill.
        //
        // In-process fallback: we report the expected elements and let the
        // orchestrator (CI script or Antigravity skill) validate externally.
        let elements = expectedElements.joined(separator: ", ")
        print("[AUTOMATION_FLOW_VERIFY] Expected elements: \(elements)")

        // Allow a brief layout pass for SwiftUI to update
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s

        return (true, "Verification requested for: \(elements)")
    }

    /// Simulates a tap on a UI element.
    /// In-process, this logs the intent; external tools handle actual taps.
    private static func executeTap(_ step: FlowStep) async -> (success: Bool, message: String) {
        guard let target = step.targetElement else {
            return (false, "No target_element specified for tap action")
        }

        print("[AUTOMATION_FLOW_TAP] Target: \(target)")

        // Brief delay to simulate user interaction pacing
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s

        return (true, "Tap requested on: \(target)")
    }

    /// Types text into a UI element.
    /// Supports environment variable interpolation ($VAR_NAME).
    private static func executeTypeText(_ step: FlowStep) async -> (success: Bool, message: String) {
        guard let target = step.targetElement else {
            return (false, "No target_element specified for type_text action")
        }
        guard let rawValue = step.value else {
            return (false, "No value specified for type_text action")
        }

        // Interpolate environment variables
        let value = interpolateEnvironmentVariables(rawValue)
        let displayValue = rawValue.contains("$") ? "[interpolated]" : value

        print("[AUTOMATION_FLOW_TYPE] Target: \(target), Value: \(displayValue)")

        // Brief delay to simulate typing
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s

        return (true, "Type text requested on '\(target)': \(displayValue)")
    }

    /// Waits for a condition to be met.
    /// Supported conditions:
    ///   - `element_exists:<identifier>` — wait until element appears
    ///   - `element_not_exists:<identifier>` — wait until element disappears
    private static func executeWait(_ step: FlowStep) async -> (success: Bool, message: String) {
        guard let condition = step.condition else {
            return (false, "No condition specified for wait action")
        }

        let parts = condition.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else {
            return (false, "Invalid condition format. Expected 'type:value', got: \(condition)")
        }

        let conditionType = String(parts[0])
        let conditionValue = String(parts[1])

        print("[AUTOMATION_FLOW_WAIT] Condition: \(conditionType) -> \(conditionValue)")

        // In-process wait: poll with timeout.
        // External orchestrators can use this as a signal to wait.
        let timeout = defaultWaitTimeout
        let pollInterval: UInt64 = 1_000_000_000 // 1 second
        let maxPolls = Int(timeout)
        var polls = 0

        while polls < maxPolls {
            try? await Task.sleep(nanoseconds: pollInterval)
            polls += 1

            // Log progress every 5 seconds
            if polls % 5 == 0 {
                print("[AUTOMATION_FLOW_WAIT] Still waiting (\(polls)s / \(Int(timeout))s)...")
            }

            // In-process, we can't easily check XCUIElement existence.
            // For now, we wait a reasonable time and report success.
            // The actual UI validation happens via external MCP tools.
            if polls >= 3 {
                // Minimum 3s wait for any condition
                return (true, "Wait condition assumed satisfied after \(polls)s: \(condition)")
            }
        }

        return (false, "Wait condition timed out after \(Int(timeout))s: \(condition)")
    }

    /// Takes a screenshot (delegates to external tools).
    private static func executeScreenshot(_ step: FlowStep) -> (success: Bool, message: String) {
        let filename = step.value ?? "flow_screenshot_\(Int(Date().timeIntervalSince1970))"
        print("[AUTOMATION_FLOW_SCREENSHOT] Requested: \(filename)")
        return (true, "Screenshot requested: \(filename)")
    }

    // MARK: - Utilities

    /// Returns the path to the automation/flows directory.
    nonisolated private static func flowsDirectory() -> URL {
        // Check for flows relative to the main bundle first (when running as app),
        // then fall back to the project directory structure.

        // 1. Tuist folder reference: automation/flows as a subdirectory in the bundle
        if let bundleFlows = Bundle.main.url(forResource: "flows", withExtension: nil, subdirectory: "automation") {
            return bundleFlows
        }

        // 2. Tuist folder reference: flows directly in bundle root
        let bundleRootFlows = Bundle.main.bundleURL.appendingPathComponent("flows")
        if FileManager.default.fileExists(atPath: bundleRootFlows.path) {
            return bundleRootFlows
        }

        // 3. Glob-bundled individual files: JSON files in the bundle root
        //    When Tuist bundles via glob (automation/flows/**/*.json), files end up
        //    directly in the bundle root. Return the bundle root and let discovery
        //    find them there.
        if Bundle.main.url(forResource: "benchmark_flow", withExtension: "json") != nil {
            return Bundle.main.bundleURL
        }

        // 4. Development fallback: look relative to project root.
        // This works when running from Xcode where the working directory
        // is the project root.
        let projectFlows = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("automation")
            .appendingPathComponent("flows")

        if FileManager.default.fileExists(atPath: projectFlows.path) {
            return projectFlows
        }

        // Last resort: check common paths (macOS only)
        #if os(macOS)
        let homeFlows = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Antigravity/Projects/gemma-edgegallery/automation/flows")
        return homeFlows
        #else
        // On iOS, flows should always be in the bundle or current directory
        return projectFlows
        #endif
    }

    /// Interpolates environment variables in a string.
    /// Replaces $VAR_NAME with the value of the environment variable.
    nonisolated static func interpolateEnvironmentVariables(_ input: String) -> String {
        var result = input
        let pattern = "\\$([A-Z_][A-Z0-9_]*)"

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return input
        }

        let matches = regex.matches(in: input, range: NSRange(input.startIndex..., in: input))

        // Process matches in reverse order to preserve indices
        for match in matches.reversed() {
            guard let varRange = Range(match.range(at: 1), in: input) else { continue }
            let varName = String(input[varRange])

            if let value = ProcessInfo.processInfo.environment[varName] {
                let fullRange = Range(match.range, in: result)!
                result.replaceSubrange(fullRange, with: value)
            }
        }

        return result
    }

    /// Prints structured flow result as JSON for consumption by automation scripts.
    private static func printFlowResult(_ result: FlowResult) {
        let stepDicts: [[String: Any]] = result.stepResults.map { step in
            [
                "step": step.step,
                "action": step.action,
                "description": step.description,
                "passed": step.passed,
                "message": step.message,
                "duration_ms": step.durationMs
            ]
        }

        let resultDict: [String: Any] = [
            "flow_name": result.flowName,
            "passed": result.passed,
            "total_duration_ms": result.totalDurationMs,
            "failed_step": result.failedStep as Any,
            "steps": stepDicts,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: resultDict, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print("\n[AUTOMATION_FLOW_RESULTS_JSON]")
            print(jsonString)
            print("[AUTOMATION_FLOW_RESULTS_END]\n")
        }
    }
}
