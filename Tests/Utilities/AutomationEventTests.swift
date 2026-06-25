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

// MARK: - Test Helpers

/// A labeled wrapper that pairs a human-readable name with an AutomationEvent.
/// Conforms to CustomTestStringConvertible so parameterized test output is readable.
struct LabeledEvent: Sendable, CustomTestStringConvertible {
    let label: String
    let event: AutomationEvent
    var testDescription: String { label }
}

/// All 17 AutomationEvent cases with representative payloads.
let allEvents: [LabeledEvent] = [
    LabeledEvent(label: "flowStarted", event: .flowStarted(
        FlowStartedPayload(flowName: "onboarding", stepCount: 5, timestamp: "2026-01-01T00:00:00Z")
    )),
    LabeledEvent(label: "stepStarted", event: .stepStarted(
        StepStartedPayload(step: 1, action: "verify_ui", description: "Check welcome screen")
    )),
    LabeledEvent(label: "verifyUI", event: .verifyUI(
        VerifyUIPayload(expectedElements: ["welcomeLabel", "startButton"], timeout: 5.0)
    )),
    LabeledEvent(label: "tap", event: .tap(
        TapPayload(target: "startButton")
    )),
    LabeledEvent(label: "typeText", event: .typeText(
        TypeTextPayload(target: "nameField", value: "Alice")
    )),
    LabeledEvent(label: "waitCondition", event: .waitCondition(
        WaitConditionPayload(condition: "element_exists:loadingSpinner", timeout: 10.0)
    )),
    LabeledEvent(label: "screenshot", event: .screenshot(
        ScreenshotPayload(filename: "welcome_screen")
    )),
    LabeledEvent(label: "keyboardShortcut", event: .keyboardShortcut(
        KeyboardShortcutPayload(key: "n", modifiers: ["command"])
    )),
    LabeledEvent(label: "scrollToElement", event: .scrollToElement(
        ScrollToPayload(identifier: "bottomLabel", maxAttempts: 3)
    )),
    LabeledEvent(label: "navigateTab", event: .navigateTab(
        NavigateTabPayload(label: "Settings")
    )),
    LabeledEvent(label: "openSheet", event: .openSheet(
        OpenSheetPayload(triggerButtonId: "addButton", expectedContentId: "sheetTitle")
    )),
    LabeledEvent(label: "dismissSheet", event: .dismissSheet(
        DismissSheetPayload(buttonId: "doneButton")
    )),
    LabeledEvent(label: "verifyNotExists", event: .verifyNotExists(
        VerifyNotExistsPayload(target: "errorBanner")
    )),
    LabeledEvent(label: "verifyEnabled", event: .verifyEnabled(
        VerifyEnabledPayload(target: "submitButton")
    )),
    LabeledEvent(label: "verifyValue", event: .verifyValue(
        VerifyValuePayload(target: "counterLabel", expected: "42")
    )),
    LabeledEvent(label: "stepCompleted", event: .stepCompleted(
        StepCompletedPayload(step: 1, passed: true, message: "OK", durationMs: 123.45)
    )),
    LabeledEvent(label: "flowCompleted", event: .flowCompleted(
        FlowCompletedPayload(flowName: "onboarding", passed: true, totalDurationMs: 5432.1, failedStep: nil, timestamp: "2026-01-01T00:01:00Z")
    )),
]

// MARK: - Codable Round-Trip Tests

@Suite("AutomationEvent Codable Round-Trips")
struct AutomationEventCodableTests {

    @Test("Round-trip encode → decode preserves event", arguments: allEvents)
    func codableRoundTrip(labeled: LabeledEvent) throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(labeled.event)
        let decoded = try decoder.decode(AutomationEvent.self, from: data)

        // Re-encode both and compare JSON for structural equality
        let originalData = try encoder.encode(labeled.event)
        let decodedData = try encoder.encode(decoded)

        let originalJSON = try JSONSerialization.jsonObject(with: originalData) as? NSDictionary
        let decodedJSON = try JSONSerialization.jsonObject(with: decodedData) as? NSDictionary

        #expect(originalJSON == decodedJSON, "Round-trip JSON mismatch for \(labeled.label)")
    }

    @Test("Encoded JSON is valid and non-empty", arguments: allEvents)
    func encodedJSONIsValid(labeled: LabeledEvent) throws {
        let data = try JSONEncoder().encode(labeled.event)
        #expect(data.count > 2, "Encoded data should contain more than empty braces")

        let json = try JSONSerialization.jsonObject(with: data)
        #expect(json is [String: Any], "Top-level JSON should be a dictionary")
    }
}

// MARK: - Payload Field Verification

@Suite("AutomationEvent Payload Fields")
struct AutomationEventPayloadTests {

    @Test("FlowStartedPayload stores fields correctly")
    func flowStartedPayloadFields() {
        let payload = FlowStartedPayload(flowName: "test_flow", stepCount: 10, timestamp: "2026-06-19T00:00:00Z")
        #expect(payload.flowName == "test_flow")
        #expect(payload.stepCount == 10)
        #expect(payload.timestamp == "2026-06-19T00:00:00Z")
    }

    @Test("StepStartedPayload stores fields correctly")
    func stepStartedPayloadFields() {
        let payload = StepStartedPayload(step: 3, action: "tap", description: "Tap the button")
        #expect(payload.step == 3)
        #expect(payload.action == "tap")
        #expect(payload.description == "Tap the button")
    }

    @Test("VerifyUIPayload stores fields including optional timeout")
    func verifyUIPayloadFields() {
        let withTimeout = VerifyUIPayload(expectedElements: ["a", "b"], timeout: 2.5)
        #expect(withTimeout.expectedElements == ["a", "b"])
        #expect(withTimeout.timeout == 2.5)

        let withoutTimeout = VerifyUIPayload(expectedElements: ["x"], timeout: nil)
        #expect(withoutTimeout.timeout == nil)
    }

    @Test("TapPayload stores target")
    func tapPayloadFields() {
        let payload = TapPayload(target: "myButton")
        #expect(payload.target == "myButton")
    }

    @Test("TypeTextPayload stores target and value")
    func typeTextPayloadFields() {
        let payload = TypeTextPayload(target: "emailField", value: "user@example.com")
        #expect(payload.target == "emailField")
        #expect(payload.value == "user@example.com")
    }

    @Test("WaitConditionPayload stores condition and timeout")
    func waitConditionPayloadFields() {
        let payload = WaitConditionPayload(condition: "element_exists:spinner", timeout: 30.0)
        #expect(payload.condition == "element_exists:spinner")
        #expect(payload.timeout == 30.0)
    }

    @Test("ScreenshotPayload stores optional filename")
    func screenshotPayloadFields() {
        let withName = ScreenshotPayload(filename: "capture_01")
        #expect(withName.filename == "capture_01")

        let withoutName = ScreenshotPayload(filename: nil)
        #expect(withoutName.filename == nil)
    }

    @Test("KeyboardShortcutPayload stores key and modifiers")
    func keyboardShortcutPayloadFields() {
        let payload = KeyboardShortcutPayload(key: "d", modifiers: ["command", "shift"])
        #expect(payload.key == "d")
        #expect(payload.modifiers == ["command", "shift"])
    }

    @Test("ScrollToPayload stores identifier and optional maxAttempts")
    func scrollToPayloadFields() {
        let withMax = ScrollToPayload(identifier: "footer", maxAttempts: 5)
        #expect(withMax.identifier == "footer")
        #expect(withMax.maxAttempts == 5)

        let withoutMax = ScrollToPayload(identifier: "footer", maxAttempts: nil)
        #expect(withoutMax.maxAttempts == nil)
    }

    @Test("NavigateTabPayload stores label")
    func navigateTabPayloadFields() {
        let payload = NavigateTabPayload(label: "AI Features")
        #expect(payload.label == "AI Features")
    }

    @Test("OpenSheetPayload stores triggerButtonId and optional expectedContentId")
    func openSheetPayloadFields() {
        let withContent = OpenSheetPayload(triggerButtonId: "add", expectedContentId: "sheetBody")
        #expect(withContent.triggerButtonId == "add")
        #expect(withContent.expectedContentId == "sheetBody")

        let withoutContent = OpenSheetPayload(triggerButtonId: "add", expectedContentId: nil)
        #expect(withoutContent.expectedContentId == nil)
    }

    @Test("DismissSheetPayload stores optional buttonId")
    func dismissSheetPayloadFields() {
        let withButton = DismissSheetPayload(buttonId: "close")
        #expect(withButton.buttonId == "close")

        let withoutButton = DismissSheetPayload(buttonId: nil)
        #expect(withoutButton.buttonId == nil)
    }

    @Test("VerifyNotExistsPayload stores target")
    func verifyNotExistsPayloadFields() {
        let payload = VerifyNotExistsPayload(target: "deletedItem")
        #expect(payload.target == "deletedItem")
    }

    @Test("VerifyEnabledPayload stores target")
    func verifyEnabledPayloadFields() {
        let payload = VerifyEnabledPayload(target: "submitButton")
        #expect(payload.target == "submitButton")
    }

    @Test("VerifyValuePayload stores target and expected")
    func verifyValuePayloadFields() {
        let payload = VerifyValuePayload(target: "slider", expected: "0.5")
        #expect(payload.target == "slider")
        #expect(payload.expected == "0.5")
    }

    @Test("StepCompletedPayload stores all fields including durationMs")
    func stepCompletedPayloadFields() {
        let payload = StepCompletedPayload(step: 7, passed: false, message: "Timeout", durationMs: 999.99)
        #expect(payload.step == 7)
        #expect(payload.passed == false)
        #expect(payload.message == "Timeout")
        #expect(payload.durationMs == 999.99)
    }

    @Test("FlowCompletedPayload stores all fields including optional failedStep")
    func flowCompletedPayloadFields() {
        let passed = FlowCompletedPayload(
            flowName: "smoke", passed: true, totalDurationMs: 1234.0,
            failedStep: nil, timestamp: "2026-01-01T00:00:00Z"
        )
        #expect(passed.flowName == "smoke")
        #expect(passed.passed == true)
        #expect(passed.totalDurationMs == 1234.0)
        #expect(passed.failedStep == nil)

        let failed = FlowCompletedPayload(
            flowName: "smoke", passed: false, totalDurationMs: 500.0,
            failedStep: 3, timestamp: "2026-01-01T00:00:00Z"
        )
        #expect(failed.failedStep == 3)
        #expect(failed.passed == false)
    }
}

// MARK: - Edge Cases

@Suite("AutomationEvent Edge Cases")
struct AutomationEventEdgeCaseTests {

    @Test("Empty strings round-trip correctly")
    func emptyStringsRoundTrip() throws {
        let event = AutomationEvent.flowStarted(
            FlowStartedPayload(flowName: "", stepCount: 0, timestamp: "")
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AutomationEvent.self, from: data)

        if case .flowStarted(let payload) = decoded {
            #expect(payload.flowName == "")
            #expect(payload.stepCount == 0)
            #expect(payload.timestamp == "")
        } else {
            Issue.record("Expected .flowStarted case")
        }
    }

    @Test("Empty array in VerifyUIPayload round-trips correctly")
    func emptyArrayRoundTrip() throws {
        let event = AutomationEvent.verifyUI(
            VerifyUIPayload(expectedElements: [], timeout: nil)
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AutomationEvent.self, from: data)

        if case .verifyUI(let payload) = decoded {
            #expect(payload.expectedElements.isEmpty)
            #expect(payload.timeout == nil)
        } else {
            Issue.record("Expected .verifyUI case")
        }
    }

    @Test("Empty modifiers array in KeyboardShortcutPayload round-trips")
    func emptyModifiersRoundTrip() throws {
        let event = AutomationEvent.keyboardShortcut(
            KeyboardShortcutPayload(key: "escape", modifiers: [])
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AutomationEvent.self, from: data)

        if case .keyboardShortcut(let payload) = decoded {
            #expect(payload.key == "escape")
            #expect(payload.modifiers.isEmpty)
        } else {
            Issue.record("Expected .keyboardShortcut case")
        }
    }

    @Test("Zero durationMs in StepCompletedPayload round-trips")
    func zeroDurationRoundTrip() throws {
        let event = AutomationEvent.stepCompleted(
            StepCompletedPayload(step: 1, passed: true, message: "instant", durationMs: 0.0)
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AutomationEvent.self, from: data)

        if case .stepCompleted(let payload) = decoded {
            #expect(payload.durationMs == 0.0)
        } else {
            Issue.record("Expected .stepCompleted case")
        }
    }

    @Test("Nil optionals encode without the key or as null and decode back to nil")
    func nilOptionalsRoundTrip() throws {
        let events: [AutomationEvent] = [
            .screenshot(ScreenshotPayload(filename: nil)),
            .scrollToElement(ScrollToPayload(identifier: "x", maxAttempts: nil)),
            .openSheet(OpenSheetPayload(triggerButtonId: "btn", expectedContentId: nil)),
            .dismissSheet(DismissSheetPayload(buttonId: nil)),
            .verifyUI(VerifyUIPayload(expectedElements: ["e"], timeout: nil)),
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for event in events {
            let data = try encoder.encode(event)
            let decoded = try decoder.decode(AutomationEvent.self, from: data)
            // Re-encode and compare to verify structural equality
            let reEncoded = try encoder.encode(decoded)
            let originalJSON = try JSONSerialization.jsonObject(with: data) as? NSDictionary
            let decodedJSON = try JSONSerialization.jsonObject(with: reEncoded) as? NSDictionary
            #expect(originalJSON == decodedJSON)
        }
    }

    @Test("TypeTextPayload with special characters round-trips")
    func specialCharactersRoundTrip() throws {
        let event = AutomationEvent.typeText(
            TypeTextPayload(target: "input", value: "Hello 🌍 \"world\" \\ \n\t $ENV_VAR")
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AutomationEvent.self, from: data)

        if case .typeText(let payload) = decoded {
            #expect(payload.value.contains("🌍"))
            #expect(payload.value.contains("$ENV_VAR"))
        } else {
            Issue.record("Expected .typeText case")
        }
    }
}

// MARK: - AutomationEventBus Tests

@Suite("AutomationEventBus")
struct AutomationEventBusTests {

    @Test("Shared singleton exists and is the same instance")
    func sharedSingletonExists() {
        let bus1 = AutomationEventBus.shared
        let bus2 = AutomationEventBus.shared
        #expect(bus1 === bus2)
    }

    @Test("Subscribe returns a stream and unique ID")
    func subscribeReturnsStreamAndID() {
        let bus = AutomationEventBus.shared
        let (_, id1) = bus.subscribe()
        let (_, id2) = bus.subscribe()
        #expect(id1 != id2)

        // Clean up
        bus.unsubscribe(id: id1)
        bus.unsubscribe(id: id2)
    }

    @Test("Emit delivers event to subscriber")
    func emitDeliversEvent() async {
        let bus = AutomationEventBus.shared
        let (stream, subId) = bus.subscribe()

        let expectedEvent = AutomationEvent.tap(TapPayload(target: "testButton"))
        bus.emit(expectedEvent)
        bus.unsubscribe(id: subId)

        var received: AutomationEvent?
        for await event in stream {
            received = event
            break
        }

        #expect(received != nil, "Should have received an event")
        if case .tap(let payload) = received {
            #expect(payload.target == "testButton")
        } else {
            Issue.record("Expected .tap event")
        }
    }

    @Test("Emit delivers events to multiple subscribers")
    func emitDeliversToMultipleSubscribers() async {
        let bus = AutomationEventBus.shared
        let (stream1, id1) = bus.subscribe()
        let (stream2, id2) = bus.subscribe()

        let event = AutomationEvent.navigateTab(NavigateTabPayload(label: "Home"))
        bus.emit(event)
        bus.unsubscribe(id: id1)
        bus.unsubscribe(id: id2)

        var count = 0
        for await evt in stream1 {
            if case .navigateTab = evt { count += 1 }
            break
        }
        for await evt in stream2 {
            if case .navigateTab = evt { count += 1 }
            break
        }

        #expect(count == 2, "Both subscribers should receive the event")
    }

    @Test("Unsubscribe finishes the stream")
    func unsubscribeFinishesStream() async {
        let bus = AutomationEventBus.shared
        let (stream, subId) = bus.subscribe()

        // Unsubscribe immediately
        bus.unsubscribe(id: subId)

        var eventCount = 0
        for await _ in stream {
            eventCount += 1
        }

        #expect(eventCount == 0, "Stream should be finished with no events")
    }

    @Test("Unsubscribe is safe to call multiple times")
    func unsubscribeIdempotent() {
        let bus = AutomationEventBus.shared
        let (_, subId) = bus.subscribe()

        // Should not crash when called multiple times
        bus.unsubscribe(id: subId)
        bus.unsubscribe(id: subId)
        bus.unsubscribe(id: subId)
    }

    @Test("Events emitted before subscribe are not received")
    func eventsBeforeSubscribeNotReceived() async {
        let bus = AutomationEventBus.shared

        // Emit before subscribing
        bus.emit(.tap(TapPayload(target: "pre")))

        let (stream, subId) = bus.subscribe()

        // Emit after subscribing
        bus.emit(.tap(TapPayload(target: "post")))
        bus.unsubscribe(id: subId)

        var targets: [String] = []
        for await event in stream {
            if case .tap(let payload) = event {
                targets.append(payload.target)
            }
        }

        #expect(!targets.contains("pre"), "Pre-subscribe events should not be delivered")
        #expect(targets.contains("post"), "Post-subscribe events should be delivered")
    }
}
