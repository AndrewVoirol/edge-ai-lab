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

/// Bridge that loads automation flow JSONs and executes them via XCUIElement queries.
///
/// This is **Path 2** of the dual-path automation strategy:
/// - Path 1 (in-app): `AutomationFlowRunner` + `AccessibilityTreeInspector`
/// - Path 2 (XCUITest): `FlowDrivenUITestRunner` + `XCUIElement` queries
///
/// Both paths consume the same flow JSON files from `automation/flows/`.
///
/// ## Usage
/// ```swift
/// func testSettingsFlow() throws {
///     let app = launchApp()
///     let runner = FlowDrivenUITestRunner(app: app, flowName: "settings_flow")
///     try runner.execute()
/// }
/// ```
class FlowDrivenUITestRunner {

    // MARK: - Inline Flow Models
    // Duplicated from Sources/Utilities/AutomationFlowRunner.swift because
    // the UITest target cannot import the main app module's internal types.

    /// Represents a complete automation flow loaded from JSON.
    struct AutomationFlow: Codable {
        let name: String
        let description: String?
        let prerequisites: [String]?
        let platform: String?
        let steps: [FlowStep]
    }

    /// Represents a single step within an automation flow.
    struct FlowStep: Codable {
        let step: Int
        let action: String
        let description: String
        let targetElement: String?
        let targetElements: [String]?
        let value: String?
        let expectedElements: [String]?
        let expectedElementsAny: [String]?
        let condition: String?
        let assertion: FlowStepAssertion?
        let timeoutSeconds: TimeInterval?
        let key: String?
        let modifiers: [String]?
        let buttonId: String?
        let label: String?
        let expected: String?
        let maxAttempts: Int?

        enum CodingKeys: String, CodingKey {
            case step, action, description
            case targetElement = "target_element"
            case targetElements = "target_elements"
            case value
            case expectedElements = "expected_elements"
            case expectedElementsAny = "expected_elements_any"
            case condition
            case assertion
            case timeoutSeconds = "timeout_seconds"
            case key, modifiers
            case buttonId = "button_id"
            case label, expected
            case maxAttempts = "max_attempts"
        }
    }

    /// Optional post-step assertion that validates element values.
    struct FlowStepAssertion: Codable {
        let type: String
        let element: String?
        let expected: String?
    }

    // MARK: - Properties

    let app: XCUIApplication
    let flowName: String
    let stepTimeout: TimeInterval
    let flowDirectory: String

    /// Loaded flow definition. Populated by `loadFlow()`.
    private var flow: AutomationFlow?

    // MARK: - Initialization

    /// Creates a new flow-driven test runner.
    ///
    /// - Parameters:
    ///   - app: The `XCUIApplication` under test.
    ///   - flowName: Name of the flow JSON file (without `.json` extension).
    ///   - stepTimeout: Default timeout for element resolution (seconds).
    ///   - flowDirectory: Subdirectory under `automation/flows/` to search.
    ///     Defaults to `"ui"` for XCUITest-specific flows.
    init(
        app: XCUIApplication,
        flowName: String,
        stepTimeout: TimeInterval = 5.0,
        flowDirectory: String = "ui"
    ) {
        self.app = app
        self.flowName = flowName
        self.stepTimeout = stepTimeout
        self.flowDirectory = flowDirectory
    }

    // MARK: - Flow Loading

    /// Load the flow JSON from the test bundle.
    ///
    /// Searches for the flow file in the test bundle's resources:
    /// 1. `automation/flows/<flowDirectory>/<flowName>.json`
    /// 2. `automation/flows/<flowName>.json` (fallback)
    /// 3. Direct bundle resource lookup by name
    private func loadFlow() throws -> AutomationFlow {
        let testBundle = Bundle(for: type(of: self))

        // Strategy 1: Look in the flow subdirectory
        if let url = testBundle.url(
            forResource: flowName,
            withExtension: "json",
            subdirectory: "automation/flows/\(flowDirectory)"
        ) {
            return try decodeFlow(from: url)
        }

        // Strategy 2: Look in the flows root
        if let url = testBundle.url(
            forResource: flowName,
            withExtension: "json",
            subdirectory: "automation/flows"
        ) {
            return try decodeFlow(from: url)
        }

        // Strategy 3: Direct resource lookup (Tuist may flatten paths)
        if let url = testBundle.url(forResource: flowName, withExtension: "json") {
            return try decodeFlow(from: url)
        }

        // Strategy 4: Search the project directory (development fallback)
        let projectPaths = [
            "automation/flows/\(flowDirectory)/\(flowName).json",
            "automation/flows/\(flowName).json"
        ]
        for relativePath in projectPaths {
            let projectURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: projectURL.path) {
                return try decodeFlow(from: projectURL)
            }
        }

        throw FlowRunnerError.flowNotFound(flowName)
    }

    private func decodeFlow(from url: URL) throws -> AutomationFlow {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AutomationFlow.self, from: data)
    }

    // MARK: - Flow Execution

    /// Execute the flow, asserting each step via XCUIElement queries.
    ///
    /// Loads the flow JSON, iterates through each step, performs the
    /// corresponding XCUIElement action, and reports pass/fail via XCTAssert.
    /// Stops on the first failure (consistent with `continueAfterFailure = false`).
    func execute() throws {
        let flow = try loadFlow()
        self.flow = flow

        print("[FLOW_RUNNER] Executing flow: \(flow.name) (\(flow.steps.count) steps)")

        for step in flow.steps {
            let stepStart = CFAbsoluteTimeGetCurrent()
            print("[FLOW_RUNNER] Step \(step.step): \(step.description)")

            try executeStep(step)

            // Evaluate post-step assertion if present
            if let assertion = step.assertion {
                try evaluateAssertion(assertion, stepNumber: step.step)
            }

            let durationMs = (CFAbsoluteTimeGetCurrent() - stepStart) * 1000
            print("[FLOW_RUNNER] Step \(step.step) passed (\(String(format: "%.1f", durationMs))ms)")
        }

        print("[FLOW_RUNNER] Flow '\(flow.name)' completed: all \(flow.steps.count) steps passed")
    }

    /// Dispatch a single step to the appropriate action handler.
    private func executeStep(_ step: FlowStep) throws {
        let timeout = step.timeoutSeconds ?? stepTimeout

        switch step.action {
        case "verify_ui":
            if let anyElements = step.expectedElementsAny, !anyElements.isEmpty {
                // "Any-of" mode: at least one element from the set must exist
                try performVerifyUIAny(
                    candidates: anyElements,
                    timeout: timeout
                )
            }
            if let allElements = step.expectedElements, !allElements.isEmpty {
                // "All" mode: every element must exist
                try performVerifyUI(
                    expectedElements: allElements,
                    timeout: timeout
                )
            }

        case "tap":
            guard let target = step.targetElement else {
                throw FlowRunnerError.missingField("target_element", step: step.step)
            }
            try performTap(target: target, timeout: timeout)

        case "type_text":
            guard let target = step.targetElement else {
                throw FlowRunnerError.missingField("target_element", step: step.step)
            }
            guard let value = step.value else {
                throw FlowRunnerError.missingField("value", step: step.step)
            }
            try performTypeText(target: target, value: value, timeout: timeout)

        case "wait":
            if let condition = step.condition {
                try performWait(condition: condition, timeout: timeout)
            } else {
                // Simple delay — no condition, just wait for UI to stabilize
                let delayMs = UInt32(timeout * 1_000_000)
                usleep(delayMs)
            }

        case "screenshot":
            performScreenshot(filename: step.value)

        case "keyboard_shortcut":
            guard let key = step.key else {
                throw FlowRunnerError.missingField("key", step: step.step)
            }
            try performKeyboardShortcut(key: key, modifiers: step.modifiers ?? [])

        case "scroll_to":
            guard let target = step.targetElement else {
                throw FlowRunnerError.missingField("target_element", step: step.step)
            }
            try performScrollTo(
                identifier: target,
                maxAttempts: step.maxAttempts ?? 6
            )

        case "navigate_tab":
            guard let label = step.label ?? step.targetElement else {
                throw FlowRunnerError.missingField("label", step: step.step)
            }
            try performNavigateTab(label: label)

        case "open_sheet":
            guard let target = step.targetElement else {
                throw FlowRunnerError.missingField("target_element", step: step.step)
            }
            try performTap(target: target, timeout: timeout)

        case "dismiss_sheet":
            try performDismissSheet(buttonId: step.buttonId ?? step.targetElement)

        case "verify_not_exists":
            guard let target = step.targetElement else {
                throw FlowRunnerError.missingField("target_element", step: step.step)
            }
            try performVerifyNotExists(target: target)

        case "verify_enabled":
            guard let target = step.targetElement else {
                throw FlowRunnerError.missingField("target_element", step: step.step)
            }
            try performVerifyEnabled(target: target, timeout: timeout)

        case "verify_value":
            guard let target = step.targetElement else {
                throw FlowRunnerError.missingField("target_element", step: step.step)
            }
            guard let expected = step.expected ?? step.value else {
                throw FlowRunnerError.missingField("expected", step: step.step)
            }
            try performVerifyValue(target: target, expected: expected, timeout: timeout)

        case "tap_first_match":
            // Tap the first matching element from expected_elements or target_element.
            // Useful for dynamic lists (e.g., model cards) where exact IDs are unknown.
            let candidates = step.targetElements ?? step.expectedElements ?? (step.targetElement.map { [$0] } ?? [])
            guard !candidates.isEmpty else {
                throw FlowRunnerError.missingField("target_elements, target_element, or expected_elements", step: step.step)
            }
            var tapped = false
            for candidate in candidates {
                // Use resolveElement() which supports partial/CONTAINS matching,
                // so "Gemma 4 E2B" matches "Gemma 4 E2B · Desktop GPU+CPU".
                if let element = resolveElement(candidate, timeout: timeout) {
                    if element.isHittable {
                        element.tap()
                    } else {
                        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                    }
                    tapped = true
                    break
                }
            }
            if !tapped {
                // Fallback: try tapping the first cell in the first collection/table
                let firstCell = app.cells.firstMatch
                if firstCell.waitForExistence(timeout: timeout) && firstCell.isHittable {
                    firstCell.tap()
                    tapped = true
                }
            }
            XCTAssertTrue(tapped, "tap_first_match: No matching element found from \(candidates)")

        case "tap_if_exists":
            // Tap the element if it exists, otherwise skip silently.
            // Used for optional UI (e.g., onboarding screens that may not appear).
            guard let target = step.targetElement else {
                throw FlowRunnerError.missingField("target_element", step: step.step)
            }
            let element = app.descendants(matching: .any)[target]
            if element.waitForExistence(timeout: timeout) && element.isHittable {
                element.tap()
                print("[FLOW_RUNNER]   tap_if_exists: tapped '\(target)'")
            } else {
                print("[FLOW_RUNNER]   tap_if_exists: '\(target)' not found, skipping")
            }

        default:
            throw FlowRunnerError.unknownAction(step.action, step: step.step)
        }
    }

    // MARK: - Element Resolution

    /// Resolve a target string to an XCUIElement using multi-strategy lookup.
    ///
    /// Strategy order:
    /// 1. **Accessibility Identifier** — exact match via `identifier == target`
    /// 2. **Accessibility Label** — exact match via `label == target`
    /// 3. **Broad Descendant Predicate** — partial match on identifier or label
    ///
    /// Returns the first match that passes `waitForExistence(timeout:)`.
    func resolveElement(_ target: String, timeout: TimeInterval? = nil) -> XCUIElement? {
        let resolveTimeout = timeout ?? stepTimeout

        // Strategy 1+2: Identifier OR Label (combined to avoid wasting full
        // timeout on identifier-only when the element is found by label, e.g.
        // tab bar buttons like "Models", "Chat", "Settings").
        let byIdOrLabel = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier == %@ OR label == %@",
                target, target
            ))
            .firstMatch
        if byIdOrLabel.waitForExistence(timeout: resolveTimeout) {
            return byIdOrLabel
        }

        // Strategy 3: Broad descendant predicate (partial match fallback)
        let byPartial = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier CONTAINS[cd] %@ OR label CONTAINS[cd] %@",
                target, target
            ))
            .firstMatch
        if byPartial.waitForExistence(timeout: min(resolveTimeout, 2.0)) {
            return byPartial
        }

        return nil
    }


    // MARK: - Action Handlers

    /// Verify that all expected elements exist in the accessibility tree.
    func performVerifyUI(expectedElements: [String], timeout: TimeInterval? = nil) throws {
        let verifyTimeout = timeout ?? stepTimeout
        var missingElements: [String] = []

        for elementId in expectedElements {
            if resolveElement(elementId, timeout: verifyTimeout) == nil {
                missingElements.append(elementId)
            }
        }

        if !missingElements.isEmpty {
            let missing = missingElements.joined(separator: ", ")
            XCTFail(
                "verify_ui: Missing elements: \(missing). "
                + "Expected \(expectedElements.count), "
                + "found \(expectedElements.count - missingElements.count)."
            )
            throw FlowRunnerError.verificationFailed(
                "Missing elements: \(missing)"
            )
        }
    }

    /// Verify that at least one element from `candidates` exists.
    ///
    /// Used by `verify_ui` when the flow JSON specifies `expected_elements_any`
    /// instead of `expected_elements`. This is for cases like "show at least one
    /// model card" where any one match is sufficient.
    func performVerifyUIAny(candidates: [String], timeout: TimeInterval? = nil) throws {
        let verifyTimeout = timeout ?? stepTimeout

        for candidate in candidates {
            if resolveElement(candidate, timeout: min(verifyTimeout, 5.0)) != nil {
                return // Found at least one — pass
            }
        }

        let candidateList = candidates.joined(separator: ", ")
        XCTFail(
            "verify_ui (any): None of the expected elements found: \(candidateList)"
        )
        throw FlowRunnerError.verificationFailed(
            "None of the expected elements found: \(candidateList)"
        )
    }

    /// Tap/click an element resolved by `resolveElement`.
    ///
    /// Handles the macOS NavigationSplitView a11y quirk: if the resolved
    /// element is not hittable (common in collapsed split view columns),
    /// falls back to a coordinate-based click at the element's center.
    func performTap(target: String, timeout: TimeInterval? = nil) throws {
        guard let element = resolveElement(target, timeout: timeout) else {
            XCTFail("tap: Could not find element '\(target)'")
            throw FlowRunnerError.elementNotFound(target)
        }

        if element.isHittable {
            element.tap()
        } else {
            // iOS fallback: elements may exist in the a11y tree but not be
            // "hittable". Use coordinate-based tap.
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        // Brief pause to allow SwiftUI state propagation
        usleep(300_000)
    }

    /// Type text into a target text field.
    ///
    /// Supports environment variable interpolation (`$VAR_NAME`).
    func performTypeText(target: String, value: String, timeout: TimeInterval? = nil) throws {
        guard let element = resolveElement(target, timeout: timeout) else {
            XCTFail("type_text: Could not find element '\(target)'")
            throw FlowRunnerError.elementNotFound(target)
        }

        // Interpolate environment variables
        let interpolatedValue = interpolateEnvironmentVariables(value)

        // Click to focus, then type
        element.tap()
        usleep(200_000) // Brief pause for focus
        element.typeText(interpolatedValue)
        usleep(200_000)
    }

    /// Wait for a condition to be met by polling.
    ///
    /// Supported conditions:
    ///   - `element_exists:<identifier>` — wait until element appears
    ///   - `element_not_exists:<identifier>` — wait until element disappears
    func performWait(condition: String, timeout: TimeInterval) throws {
        let parts = condition.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else {
            XCTFail("wait: Invalid condition format '\(condition)'. Expected 'type:value'")
            throw FlowRunnerError.invalidCondition(condition)
        }

        let conditionType = String(parts[0])
        let conditionValue = String(parts[1])

        print("[FLOW_RUNNER]   wait: \(conditionType) → \(conditionValue) (timeout: \(Int(timeout))s)")

        switch conditionType {
        case "element_exists":
            let element = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == %@ OR label == %@",
                                      conditionValue, conditionValue))
                .firstMatch
            let appeared = element.waitForExistence(timeout: timeout)
            if !appeared {
                XCTFail("wait: Element '\(conditionValue)' did not appear within \(Int(timeout))s")
                throw FlowRunnerError.waitTimeout(condition, timeout: timeout)
            }

        case "element_not_exists":
            // Poll until the element is gone
            let pollInterval: useconds_t = 500_000 // 0.5s
            let maxPolls = Int(timeout * 2)
            for poll in 0..<maxPolls {
                let element = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "identifier == %@ OR label == %@",
                                          conditionValue, conditionValue))
                    .firstMatch
                if !element.exists {
                    return // Condition met
                }
                if poll % 4 == 0 && poll > 0 {
                    print("[FLOW_RUNNER]   Still waiting (\(poll / 2)s / \(Int(timeout))s)...")
                }
                usleep(pollInterval)
            }
            XCTFail("wait: Element '\(conditionValue)' did not disappear within \(Int(timeout))s")
            throw FlowRunnerError.waitTimeout(condition, timeout: timeout)

        default:
            XCTFail("wait: Unknown condition type '\(conditionType)'")
            throw FlowRunnerError.invalidCondition(condition)
        }
    }

    /// Capture a screenshot and attach it to the test results.
    func performScreenshot(filename: String?) {
        let name = filename ?? "flow_screenshot_\(Int(Date().timeIntervalSince1970))"
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        // Note: Attachments need to be added via XCTActivity or XCTestCase.
        // In standalone usage, the screenshot is captured but not auto-attached.
        print("[FLOW_RUNNER]   Screenshot captured: \(name)")
    }

    /// Press a keyboard shortcut (macOS only).
    ///
    /// Modifier names: "command", "shift", "option", "control".
    func performKeyboardShortcut(key: String, modifiers: [String]) throws {
        #if os(macOS)
        var flags: XCUIElement.KeyModifierFlags = []
        for modifier in modifiers {
            switch modifier.lowercased() {
            case "command", "cmd": flags.insert(.command)
            case "shift": flags.insert(.shift)
            case "option", "alt": flags.insert(.option)
            case "control", "ctrl": flags.insert(.control)
            default:
                print("[FLOW_RUNNER]   Warning: Unknown modifier '\(modifier)'")
            }
        }

        // Handle special key names
        let xcuiKey: XCUIKeyboardKey? = {
            switch key.lowercased() {
            case "escape", "esc": return .escape
            case "return", "enter": return .return
            case "tab": return .tab
            case "delete", "backspace": return .delete
            case "space": return .space
            case "up": return .upArrow
            case "down": return .downArrow
            case "left": return .leftArrow
            case "right": return .rightArrow
            default: return nil
            }
        }()

        if let xcuiKey = xcuiKey {
            app.typeKey(xcuiKey, modifierFlags: flags)
        } else {
            app.typeKey(key, modifierFlags: flags)
        }

        usleep(500_000) // Pause for shortcut action to take effect
        #else
        print("[FLOW_RUNNER]   keyboard_shortcut skipped (not macOS)")
        #endif
    }

    /// Scroll within a container until the target element is visible.
    ///
    /// Uses coordinate-based drag scrolling (proven pattern from
    /// `EdgeAILabUITests.testAddMCPServer`).
    func performScrollTo(identifier: String, maxAttempts: Int = 6) throws {
        // Match by both identifier AND label (mirrors resolveElement strategy)
        let element = app.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier == %@ OR label == %@",
                identifier, identifier
            ))
            .firstMatch

        if element.exists && element.isHittable {
            return // Already visible
        }

        // Brief pause to let any pending animations settle
        usleep(500_000)

        // Re-check after settling — element may exist but not be hittable
        if element.exists {
            print("[FLOW_RUNNER]   scroll_to: Found '\(identifier)' (already in tree)")
            return
        }

        #if os(macOS)
        let window = app.windows.firstMatch
        guard window.exists else {
            throw FlowRunnerError.elementNotFound("window (for scrollTo)")
        }

        for attempt in 0..<maxAttempts {
            let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let to = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            from.press(forDuration: 0.05, thenDragTo: to)
            usleep(500_000)

            if element.exists {
                print("[FLOW_RUNNER]   scroll_to: Found '\(identifier)' after \(attempt + 1) scroll(s)")
                return
            }
        }

        XCTFail("scroll_to: Element '\(identifier)' not found after \(maxAttempts) scroll attempts")
        throw FlowRunnerError.elementNotFound(identifier)
        #else
        // On iOS, use coordinate-based drag scrolling.
        // `app.swipeUp()` triggers XCUITest's idle-wait system which hangs
        // indefinitely on iOS 26 physical devices with Liquid Glass momentum
        // scrolling. Coordinate-based drag avoids the idle-wait.
        for attempt in 0..<maxAttempts {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            from.press(forDuration: 0.05, thenDragTo: to)
            usleep(500_000)
            if element.exists {
                print("[FLOW_RUNNER]   scroll_to: Found '\(identifier)' after \(attempt + 1) scroll(s)")
                return
            }
        }
        XCTFail("scroll_to: Element '\(identifier)' not found after \(maxAttempts) scroll attempts")
        throw FlowRunnerError.elementNotFound(identifier)
        #endif
    }

    /// Navigate to a settings tab by label.
    ///
    /// Mirrors the `navigateToSettingsTab` pattern from EdgeAILabUITests:
    /// tries radioButton → button → broad label search.
    func performNavigateTab(label: String) throws {
        #if os(macOS)
        // macOS SwiftUI TabView tab items appear as radioButtons
        let radioButton = app.radioButtons[label]
        if radioButton.waitForExistence(timeout: 3.0) {
            radioButton.tap()
            usleep(500_000)
            return
        }

        // Fallback: try as a button
        let button = app.buttons[label]
        if button.waitForExistence(timeout: 2.0) {
            button.tap()
            usleep(500_000)
            return
        }

        // Last resort: broad search by label
        let anyElement = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
        if anyElement.waitForExistence(timeout: 2.0) {
            anyElement.tap()
            usleep(500_000)
            return
        }

        XCTFail("navigate_tab: Could not find tab '\(label)'")
        throw FlowRunnerError.elementNotFound(label)
        #else
        // On iOS, tabs are typically buttons in the tab bar
        let tabButton = app.buttons[label]
        if tabButton.waitForExistence(timeout: 3.0) {
            tabButton.tap()
            usleep(300_000)
            return
        }
        throw FlowRunnerError.elementNotFound(label)
        #endif
    }

    /// Dismiss a modal sheet.
    ///
    /// If `buttonId` is provided, clicks that button. Otherwise sends
    /// Escape (macOS) or performs no-op (iOS sheets auto-dismiss).
    func performDismissSheet(buttonId: String?) throws {
        if let buttonId = buttonId {
            try performTap(target: buttonId)
        } else {
            #if os(macOS)
            app.typeKey(.escape, modifierFlags: [])
            usleep(500_000)
            #endif
        }
    }

    /// Assert that an element does NOT exist in the accessibility tree.
    func performVerifyNotExists(target: String) throws {
        let element = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ OR label == %@", target, target))
            .firstMatch

        // Brief wait to allow any pending animations
        usleep(300_000)

        if element.exists {
            XCTFail("verify_not_exists: Element '\(target)' should not exist but was found")
            throw FlowRunnerError.verificationFailed(
                "Element '\(target)' should not exist"
            )
        }
    }

    /// Assert that an element exists and is enabled.
    func performVerifyEnabled(target: String, timeout: TimeInterval? = nil) throws {
        guard let element = resolveElement(target, timeout: timeout) else {
            XCTFail("verify_enabled: Could not find element '\(target)'")
            throw FlowRunnerError.elementNotFound(target)
        }

        XCTAssertTrue(
            element.isEnabled,
            "verify_enabled: Element '\(target)' exists but is not enabled"
        )

        if !element.isEnabled {
            throw FlowRunnerError.verificationFailed(
                "Element '\(target)' is not enabled"
            )
        }
    }

    /// Assert that an element's accessibility value matches the expected value.
    func performVerifyValue(target: String, expected: String, timeout: TimeInterval? = nil) throws {
        guard let element = resolveElement(target, timeout: timeout) else {
            XCTFail("verify_value: Could not find element '\(target)'")
            throw FlowRunnerError.elementNotFound(target)
        }

        let actualValue = element.value as? String ?? ""
        XCTAssertEqual(
            actualValue, expected,
            "verify_value: Element '\(target)' value '\(actualValue)' != expected '\(expected)'"
        )

        if actualValue != expected {
            throw FlowRunnerError.verificationFailed(
                "Element '\(target)' value '\(actualValue)' != '\(expected)'"
            )
        }
    }

    // MARK: - Post-Step Assertion Evaluation

    /// Evaluate a post-step assertion from the flow JSON.
    private func evaluateAssertion(_ assertion: FlowStepAssertion, stepNumber: Int) throws {
        switch assertion.type {
        case "element_exists":
            guard let elementId = assertion.element else {
                throw FlowRunnerError.missingField("assertion.element", step: stepNumber)
            }
            let element = resolveElement(elementId)
            XCTAssertNotNil(element, "Assertion: element '\(elementId)' should exist")
            if element == nil {
                throw FlowRunnerError.verificationFailed(
                    "Assertion element_exists failed: '\(elementId)'"
                )
            }

        case "element_value_contains":
            guard let elementId = assertion.element,
                  let expected = assertion.expected else {
                throw FlowRunnerError.missingField("assertion.element/expected", step: stepNumber)
            }
            guard let element = resolveElement(elementId) else {
                XCTFail("Assertion: element '\(elementId)' not found")
                throw FlowRunnerError.elementNotFound(elementId)
            }
            let value = element.value as? String ?? ""
            XCTAssertTrue(
                value.localizedCaseInsensitiveContains(expected),
                "Assertion: element '\(elementId)' value '\(value)' does not contain '\(expected)'"
            )

        case "element_value_equals":
            guard let elementId = assertion.element,
                  let expected = assertion.expected else {
                throw FlowRunnerError.missingField("assertion.element/expected", step: stepNumber)
            }
            guard let element = resolveElement(elementId) else {
                XCTFail("Assertion: element '\(elementId)' not found")
                throw FlowRunnerError.elementNotFound(elementId)
            }
            let value = element.value as? String ?? ""
            XCTAssertEqual(
                value, expected,
                "Assertion: element '\(elementId)' value '\(value)' != '\(expected)'"
            )

        default:
            throw FlowRunnerError.unknownAction(
                "assertion type '\(assertion.type)'", step: stepNumber
            )
        }
    }

    // MARK: - Utilities

    /// Interpolates environment variables in a string.
    /// Replaces `$VAR_NAME` with the value of the environment variable.
    /// Mirrors `AutomationFlowRunner.interpolateEnvironmentVariables`.
    private func interpolateEnvironmentVariables(_ input: String) -> String {
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
}

// MARK: - Error Types

/// Errors thrown by the `FlowDrivenUITestRunner`.
enum FlowRunnerError: Error, LocalizedError {
    case flowNotFound(String)
    case missingField(String, step: Int)
    case elementNotFound(String)
    case unknownAction(String, step: Int)
    case invalidCondition(String)
    case waitTimeout(String, timeout: TimeInterval)
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .flowNotFound(let name):
            return "Flow '\(name)' not found in test bundle or project directory"
        case .missingField(let field, let step):
            return "Step \(step): Required field '\(field)' is missing"
        case .elementNotFound(let target):
            return "Element '\(target)' not found in accessibility tree"
        case .unknownAction(let action, let step):
            return "Step \(step): Unknown action '\(action)'"
        case .invalidCondition(let condition):
            return "Invalid wait condition format: '\(condition)'"
        case .waitTimeout(let condition, let timeout):
            return "Wait condition timed out after \(Int(timeout))s: \(condition)"
        case .verificationFailed(let message):
            return "Verification failed: \(message)"
        }
    }
}
