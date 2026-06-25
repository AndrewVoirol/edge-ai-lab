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

// MARK: - Automation Event Protocol

/// Structured events emitted by the flow runner for consumption by
/// external test harnesses (XCUITest bridge, xcodebuild-mcp, etc.).
///
/// ## Two Paths
///
/// **Path 1 — In-App Self-Inspection**: The app loads flow JSONs and inspects
/// its own UI via `AccessibilityTreeInspector`. Used for on-device testing,
/// benchmarking, and CI without XCUITest. Events are logged to stdout.
///
/// **Path 2 — External Test Runner (XCUITest Bridge)**: An XCUITest process
/// loads the same flow JSONs and performs real `XCUIElement` queries from
/// outside the app. Events drive the `FlowDrivenUITestRunner`.
///
/// Both paths share the same flow JSON definitions — the JSON is the single
/// source of truth.
enum AutomationEvent: Codable, Sendable {
    case flowStarted(FlowStartedPayload)
    case stepStarted(StepStartedPayload)
    case verifyUI(VerifyUIPayload)
    case tap(TapPayload)
    case typeText(TypeTextPayload)
    case waitCondition(WaitConditionPayload)
    case screenshot(ScreenshotPayload)
    case keyboardShortcut(KeyboardShortcutPayload)
    case scrollToElement(ScrollToPayload)
    case navigateTab(NavigateTabPayload)
    case openSheet(OpenSheetPayload)
    case dismissSheet(DismissSheetPayload)
    case verifyNotExists(VerifyNotExistsPayload)
    case verifyEnabled(VerifyEnabledPayload)
    case verifyValue(VerifyValuePayload)
    case stepCompleted(StepCompletedPayload)
    case flowCompleted(FlowCompletedPayload)
}

// MARK: - Event Payloads

/// Emitted when a flow begins execution.
struct FlowStartedPayload: Codable, Sendable {
    /// The flow name (from the JSON `name` field).
    let flowName: String
    /// Total number of steps in the flow.
    let stepCount: Int
    /// ISO 8601 timestamp when execution started.
    let timestamp: String
}

/// Emitted when an individual step begins execution.
struct StepStartedPayload: Codable, Sendable {
    /// 1-based step index.
    let step: Int
    /// The action type (e.g., "verify_ui", "tap", "wait").
    let action: String
    /// Human-readable description from the flow JSON.
    let description: String
}

/// Payload for `verify_ui` actions: assert that expected elements exist.
struct VerifyUIPayload: Codable, Sendable {
    /// Accessibility identifiers or labels that must be present.
    let expectedElements: [String]
    /// Per-element timeout override (seconds). `nil` uses the default.
    let timeout: TimeInterval?
}

/// Payload for `tap` actions: tap/click an element.
struct TapPayload: Codable, Sendable {
    /// Accessibility identifier or label of the element to tap.
    let target: String
}

/// Payload for `type_text` actions: type text into a field.
struct TypeTextPayload: Codable, Sendable {
    /// Accessibility identifier or label of the target text field.
    let target: String
    /// The text to type. May contain `$ENV_VAR` references
    /// (interpolated before execution).
    let value: String
}

/// Payload for `wait` actions: poll until a condition is met.
struct WaitConditionPayload: Codable, Sendable {
    /// Condition string (e.g., `element_exists:identifier`).
    let condition: String
    /// Maximum time to wait (seconds).
    let timeout: TimeInterval
}

/// Payload for `screenshot` actions: capture the current screen.
struct ScreenshotPayload: Codable, Sendable {
    /// Desired filename (without extension). `nil` auto-generates a name.
    let filename: String?
}

/// Payload for `keyboard_shortcut` actions: press a key combination.
struct KeyboardShortcutPayload: Codable, Sendable {
    /// The key to press (e.g., "n", "d", "escape").
    let key: String
    /// Modifier flags (e.g., ["command"], ["command", "shift"]).
    let modifiers: [String]
}

/// Payload for `scroll_to` actions: scroll until an element is visible.
struct ScrollToPayload: Codable, Sendable {
    /// Accessibility identifier of the element to scroll into view.
    let identifier: String
    /// Maximum number of scroll attempts before giving up.
    let maxAttempts: Int?
}

/// Payload for `navigate_tab` actions: select a tab in a TabView.
struct NavigateTabPayload: Codable, Sendable {
    /// The label of the tab to select (e.g., "General", "AI Features").
    let label: String
}

/// Payload for `open_sheet` actions: open a modal sheet.
struct OpenSheetPayload: Codable, Sendable {
    /// Accessibility identifier of the button that opens the sheet.
    let triggerButtonId: String
    /// Accessibility identifier of an element expected inside the sheet,
    /// used to confirm the sheet appeared.
    let expectedContentId: String?
}

/// Payload for `dismiss_sheet` actions: dismiss a modal sheet.
struct DismissSheetPayload: Codable, Sendable {
    /// Accessibility identifier of the dismiss button.
    /// `nil` sends Escape key (macOS) or swipe-down (iOS).
    let buttonId: String?
}

/// Payload for `verify_not_exists`: assert an element does NOT exist.
struct VerifyNotExistsPayload: Codable, Sendable {
    /// Accessibility identifier or label that must NOT be present.
    let target: String
}

/// Payload for `verify_enabled`: assert an element exists and is enabled.
struct VerifyEnabledPayload: Codable, Sendable {
    /// Accessibility identifier or label of the element.
    let target: String
}

/// Payload for `verify_value`: assert an element's accessibility value.
struct VerifyValuePayload: Codable, Sendable {
    /// Accessibility identifier or label of the element.
    let target: String
    /// The expected value (exact match).
    let expected: String
}

/// Emitted when an individual step completes.
struct StepCompletedPayload: Codable, Sendable {
    /// 1-based step index.
    let step: Int
    /// Whether the step passed.
    let passed: Bool
    /// Human-readable result message.
    let message: String
    /// Wall-clock duration of this step in milliseconds.
    let durationMs: Double
}

/// Emitted when an entire flow completes.
struct FlowCompletedPayload: Codable, Sendable {
    /// The flow name.
    let flowName: String
    /// Whether all steps passed.
    let passed: Bool
    /// Total wall-clock duration in milliseconds.
    let totalDurationMs: Double
    /// The step number of the first failure, or `nil` if all passed.
    let failedStep: Int?
    /// ISO 8601 timestamp when execution completed.
    let timestamp: String
}

// MARK: - Automation Event Bus

/// Channel for streaming automation events to external consumers.
/// Both the in-app flow runner and XCUITest bridge can subscribe.
///
/// Thread-safe via `NSLock`. Each subscriber gets an independent
/// `AsyncStream` that receives all events emitted after subscription.
/// Subscribers should call `unsubscribe(id:)` when done to prevent
/// continuation leaks.
final class AutomationEventBus: @unchecked Sendable {
    static let shared = AutomationEventBus()

    private var continuations: [UUID: AsyncStream<AutomationEvent>.Continuation] = [:]
    private let lock = NSLock()

    private init() {}

    /// Create a new subscription. Returns the stream and a unique ID
    /// that must be passed to `unsubscribe(id:)` when done.
    func subscribe() -> (stream: AsyncStream<AutomationEvent>, id: UUID) {
        let id = UUID()
        let stream = AsyncStream<AutomationEvent> { continuation in
            lock.lock()
            continuations[id] = continuation
            lock.unlock()

            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(id: id)
            }
        }
        return (stream, id)
    }

    /// Emit an event to all current subscribers.
    func emit(_ event: AutomationEvent) {
        lock.lock()
        let activeContinuations = continuations.values
        lock.unlock()

        for continuation in activeContinuations {
            continuation.yield(event)
        }
    }

    /// Remove a subscription. Safe to call multiple times.
    func unsubscribe(id: UUID) {
        lock.lock()
        let continuation = continuations.removeValue(forKey: id)
        lock.unlock()

        continuation?.finish()
    }

    /// Internal helper called on stream termination.
    private func removeContinuation(id: UUID) {
        lock.lock()
        continuations.removeValue(forKey: id)
        lock.unlock()
    }
}
