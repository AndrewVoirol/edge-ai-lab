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

import XCTest

/// XCUITest suite that auto-invokes the automation harness in dry-run mode.
///
/// These tests validate that the automation plumbing works end-to-end without
/// requiring a running model or real UI interaction. The app is launched with
/// automation launch arguments and is expected to process them and signal
/// completion via a marker file on disk.
///
/// We use filesystem-based signaling because:
/// 1. `exit()` causes XCUITest to relaunch the app without the original args
/// 2. Accessibility elements require SwiftUI view rendering, which doesn't
///    fire reliably under XCUITest's launch sandbox
///
/// The harness writes `/tmp/automation_complete.txt` when it finishes.
///
/// This suite is designed for CI — it runs fast (no model loading) and catches
/// regressions in the automation harness argument parsing and flow dispatch.
final class AutomationHarnessXCTests: XCTestCase {

    /// Timeout for the app to finish automation and signal completion.
    private let automationTimeout: TimeInterval = 30

    /// Path to the marker file written by the automation harness on completion.
    private let markerPath = "/tmp/automation_complete.txt"

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Remove any stale marker file from previous test runs
        try? FileManager.default.removeItem(atPath: markerPath)
    }

    override func tearDownWithError() throws {
        // Clean up the marker file
        try? FileManager.default.removeItem(atPath: markerPath)
        // Ensure the app is fully terminated between tests
        let app = XCUIApplication()
        if app.state != .notRunning {
            app.terminate()
            usleep(500_000)
        }
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    /// Launches the app with the given automation arguments and waits for
    /// the completion marker file to appear on disk.
    ///
    /// Returns `true` if automation completed within the timeout.
    @discardableResult
    private func launchAndWaitForCompletion(arguments: [String]) -> Bool {
        let app = XCUIApplication()

        // Terminate any existing instance to ensure clean launch state.
        if app.state != .notRunning {
            app.terminate()
            usleep(1_000_000)
        }

        app.launchArguments = arguments
        app.launch()

        // Poll for the marker file — the harness writes it when automation
        // completes. We poll rather than using inotify because XCUITest
        // doesn't have access to FSEvents.
        let deadline = Date().addingTimeInterval(automationTimeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: markerPath) {
                return true
            }
            usleep(250_000) // 250ms polling interval
        }
        return false
    }

    /// Reads the exit code from the marker file (first line).
    private func readExitCode() -> Int32? {
        guard let content = try? String(contentsOfFile: markerPath, encoding: .utf8) else {
            return nil
        }
        let firstLine = content.components(separatedBy: "\n").first ?? ""
        return Int32(firstLine.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    /// Reads the diagnostic message from the marker file (second line onward).
    private func readDiagnosticMessage() -> String {
        guard let content = try? String(contentsOfFile: markerPath, encoding: .utf8) else {
            return "No marker file"
        }
        let lines = content.components(separatedBy: "\n")
        return lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Tests

    /// Verifies that `-ListFlows` causes the app to enumerate all registered
    /// automation flows and signal completion.
    func testAllFlowsDiscoverable() throws {
        let completed = launchAndWaitForCompletion(arguments: [
            "-RunAutomationHarness",
            "-ListFlows"
        ])

        XCTAssertTrue(
            completed,
            "App should write completion marker after listing flows"
        )
        XCTAssertEqual(readExitCode(), 0, "ListFlows should complete with exit code 0")
    }

    /// Verifies that the `e2e_regression_flow` can be invoked in dry-run mode.
    func testE2ERegressionFlowDryRun() throws {
        let completed = launchAndWaitForCompletion(arguments: [
            "-RunAutomationHarness",
            "-RunFlow", "e2e_regression_flow",
            "-DryRun"
        ])

        XCTAssertTrue(
            completed,
            "e2e_regression_flow dry-run should write completion marker"
        )
        XCTAssertEqual(readExitCode(), 0, "e2e_regression_flow dry-run should pass. Diagnostic: \(readDiagnosticMessage())")
    }

    /// Verifies that the `benchmark_flow` can be invoked in dry-run mode.
    func testBenchmarkFlowDryRun() throws {
        let completed = launchAndWaitForCompletion(arguments: [
            "-RunAutomationHarness",
            "-RunFlow", "benchmark_flow",
            "-DryRun"
        ])

        XCTAssertTrue(
            completed,
            "benchmark_flow dry-run should write completion marker"
        )
        XCTAssertEqual(readExitCode(), 0, "benchmark_flow dry-run should pass. Diagnostic: \(readDiagnosticMessage())")
    }

    /// Verifies that `-RunAllFlows -DryRun` is accepted and all flows pass.
    func testDryRunModifierAccepted() throws {
        let completed = launchAndWaitForCompletion(arguments: [
            "-RunAutomationHarness",
            "-RunAllFlows",
            "-DryRun"
        ])

        XCTAssertTrue(
            completed,
            "All flows in dry-run mode should write completion marker"
        )
        XCTAssertEqual(readExitCode(), 0, "All flows dry-run should pass")
    }
}
