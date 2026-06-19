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

/// Tests for `ToolRegistry`, the free `jsonString(from:)` helper,
/// and `ToolCallEvent` serialization.
///
/// Uses `SwiftTests` suffix to avoid potential name collisions with
/// the existing XCTest class `ToolCallingTests`.
@Suite struct ToolRegistrySwiftTests {

    // MARK: - ToolRegistry.defaultTools

    @Test("defaultTools contains exactly 6 tools")
    func defaultToolsCount() {
        #expect(ToolRegistry.defaultTools.count == 6)
    }

    // MARK: - ToolRegistry.createToolManager()

    @Test("createToolManager returns a ToolManager with non-empty JSON description")
    func createToolManagerReturnsToolManager() {
        let manager = ToolRegistry.createToolManager()
        #expect(!manager.toolsJsonDescription.isEmpty)
        #expect(manager.toolsJsonDescription != "[]")
    }

    // MARK: - jsonString(from:) — Normal Cases

    @Test("jsonString with normal dictionary produces valid JSON")
    func jsonStringNormalDictionary() {
        let dict: [String: Any] = ["key": "value", "number": 42]
        let result = jsonString(from: dict)
        #expect(result.contains("key"))
        #expect(result.contains("value"))
        #expect(result.contains("42"))
        // Verify it's parseable JSON
        let data = result.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: data)
        #expect(parsed != nil)
    }

    @Test("jsonString with empty dictionary produces valid JSON object")
    func jsonStringEmptyDictionary() {
        let dict: [String: Any] = [:]
        let result = jsonString(from: dict)
        // Should be "{}" or "{\n\n}" depending on pretty-printing
        let data = result.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any]
        #expect(parsed != nil)
        #expect(parsed?.isEmpty == true)
    }

    // MARK: - jsonString(from:) — Non-Finite Sanitization

    @Test("jsonString sanitizes Infinity to string 'Infinity' (no crash)")
    func jsonStringSanitizesInfinity() {
        let dict: [String: Any] = ["val": Double.infinity]
        let result = jsonString(from: dict)
        // Should NOT crash, and should contain the string "Infinity"
        #expect(result.contains("Infinity"))
        // Verify it's still valid JSON (Infinity was converted to a string)
        let data = result.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: data)
        #expect(parsed != nil)
    }

    @Test("jsonString sanitizes NaN to string 'NaN' (no crash)")
    func jsonStringSanitizesNaN() {
        let dict: [String: Any] = ["val": Double.nan]
        let result = jsonString(from: dict)
        #expect(result.contains("NaN"))
        let data = result.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: data)
        #expect(parsed != nil)
    }

    @Test("jsonString sanitizes -Infinity to string '-Infinity' (no crash)")
    func jsonStringSanitizesNegativeInfinity() {
        let dict: [String: Any] = ["val": -Double.infinity]
        let result = jsonString(from: dict)
        #expect(result.contains("-Infinity"))
        let data = result.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: data)
        #expect(parsed != nil)
    }

    @Test("jsonString with mixed finite and non-finite values sanitizes correctly")
    func jsonStringMixedValues() {
        let dict: [String: Any] = [
            "normal": 42.0,
            "inf": Double.infinity,
            "nan": Double.nan,
            "text": "hello"
        ]
        let result = jsonString(from: dict)
        #expect(result.contains("42"))
        #expect(result.contains("Infinity"))
        #expect(result.contains("NaN"))
        #expect(result.contains("hello"))
        // Still valid JSON
        let data = result.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: data)
        #expect(parsed != nil)
    }

    // MARK: - ToolCallEvent Creation and Codable Round-Trip

    @Test("ToolCallEvent creation sets all properties correctly")
    func toolCallEventCreation() {
        let timestamp = Date()
        let event = ToolCallEvent(
            toolName: "test_tool",
            arguments: "{\"key\": \"value\"}",
            result: "{\"answer\": 42}",
            durationMs: 3.14,
            timestamp: timestamp,
            succeeded: true
        )
        #expect(event.toolName == "test_tool")
        #expect(event.arguments == "{\"key\": \"value\"}")
        #expect(event.result == "{\"answer\": 42}")
        #expect(event.durationMs > 3.0 && event.durationMs < 3.5)
        #expect(event.succeeded == true)
        #expect(!event.id.uuidString.isEmpty)
    }

    @Test("ToolCallEvent Codable round-trip preserves all fields")
    func toolCallEventCodableRoundTrip() throws {
        let original = ToolCallEvent(
            toolName: "calculate",
            arguments: "{\"expression\": \"1+1\"}",
            result: "{\"result\": 2}",
            durationMs: 1.25,
            timestamp: Date(),
            succeeded: true
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ToolCallEvent.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.toolName == original.toolName)
        #expect(decoded.arguments == original.arguments)
        #expect(decoded.result == original.result)
        #expect(decoded.succeeded == original.succeeded)
        // Duration should survive the round trip
        #expect(abs(decoded.durationMs - original.durationMs) < 0.001)
        // Timestamp within 1 second (Date Codable uses timeIntervalSinceReferenceDate)
        #expect(
            abs(decoded.timestamp.timeIntervalSince1970
                - original.timestamp.timeIntervalSince1970) < 1.0
        )
    }

    @Test("ToolCallEvent with succeeded=false encodes and decodes correctly")
    func toolCallEventFailedRoundTrip() throws {
        let original = ToolCallEvent(
            toolName: "convert_units",
            arguments: "{}",
            result: "{\"error\": \"Unknown unit\"}",
            durationMs: 0.5,
            timestamp: Date(),
            succeeded: false
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            ToolCallEvent.self, from: data
        )

        #expect(decoded.succeeded == false)
        #expect(decoded.toolName == "convert_units")
    }
}
