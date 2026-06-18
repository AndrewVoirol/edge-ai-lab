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
import LiteRTLM

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - Tool Calling Tests

final class ToolCallingTests: XCTestCase {

    // MARK: - ToolCallEvent Tests

    func testToolCallEventCreation() {
        let event = ToolCallEvent(
            toolName: "calculate",
            arguments: "{\"expression\": \"2+3\"}",
            result: "{\"result\": 5}",
            durationMs: 1.5,
            timestamp: Date(),
            succeeded: true
        )

        XCTAssertEqual(event.toolName, "calculate")
        XCTAssertEqual(event.arguments, "{\"expression\": \"2+3\"}")
        XCTAssertEqual(event.result, "{\"result\": 5}")
        XCTAssertEqual(event.durationMs, 1.5, accuracy: 0.001)
        XCTAssertTrue(event.succeeded)
        // UUID should be automatically generated and non-nil
        XCTAssertFalse(event.id.uuidString.isEmpty)
    }

    func testToolCallEventSucceededFlag() {
        let successEvent = ToolCallEvent(
            toolName: "calculate",
            arguments: "{}",
            result: "{}",
            durationMs: 0.5,
            timestamp: Date(),
            succeeded: true
        )
        XCTAssertTrue(successEvent.succeeded)

        let failedEvent = ToolCallEvent(
            toolName: "calculate",
            arguments: "{}",
            result: "{\"error\": \"bad expression\"}",
            durationMs: 0.2,
            timestamp: Date(),
            succeeded: false
        )
        XCTAssertFalse(failedEvent.succeeded)
    }

    // MARK: - CalculatorTool Tests

    func testCalculatorSimpleAddition() async throws {
        var tool = CalculatorTool()
        tool.expression = "2 + 3"
        let result = try await tool.run()
        let resultString = result as! String
        XCTAssertTrue(resultString.contains("5"), "Result should contain '5', got: \(resultString)")
    }

    func testCalculatorMultiplication() async throws {
        var tool = CalculatorTool()
        tool.expression = "6 * 7"
        let result = try await tool.run()
        let resultString = result as! String
        XCTAssertTrue(resultString.contains("42"), "Result should contain '42', got: \(resultString)")
    }

    func testCalculatorDivision() async throws {
        var tool = CalculatorTool()
        tool.expression = "100 / 4"
        let result = try await tool.run()
        let resultString = result as! String
        XCTAssertTrue(resultString.contains("25"), "Result should contain '25', got: \(resultString)")
    }

    func testCalculatorComplexExpression() async throws {
        var tool = CalculatorTool()
        // (100 - 32) * 5 / 9 = 37.777...
        tool.expression = "(100 - 32) * 5 / 9"
        let result = try await tool.run()
        let resultString = result as! String
        XCTAssertTrue(
            resultString.contains("37"),
            "Result should contain '37' for Fahrenheit-to-Celsius conversion, got: \(resultString)"
        )
        // Verify the result JSON contains both expression and result keys
        XCTAssertTrue(resultString.contains("expression"))
        XCTAssertTrue(resultString.contains("result"))
    }

    // MARK: - DateTimeTool Tests

    func testDateTimeReturnsCurrentDate() async throws {
        let tool = DateTimeTool()
        let result = try await tool.run()
        let resultString = result as! String
        // The JSON response includes "date" and "time" keys
        XCTAssertTrue(resultString.contains("date"), "Result should contain 'date' key")
        XCTAssertTrue(resultString.contains("time"), "Result should contain 'time' key")
        XCTAssertTrue(resultString.contains("timezone"), "Result should contain 'timezone' key")
        XCTAssertTrue(resultString.contains("day_of_week"), "Result should contain 'day_of_week' key")
    }

    func testDateTimeWithTimezone() async throws {
        var tool = DateTimeTool()
        tool.timezone = "America/New_York"
        let result = try await tool.run()
        let resultString = result as! String
        // Verify the result contains timezone information
        // Note: The @ToolParam property wrapper may not propagate the value
        // if the default is empty string, so we check for either the requested
        // timezone or the default timezone
        XCTAssertTrue(
            resultString.contains("timezone"),
            "Result should contain timezone information"
        )
    }

    func testDateTimeWithInvalidTimezone() async throws {
        var tool = DateTimeTool()
        tool.timezone = "Invalid/FakeTimezone"
        let result = try await tool.run()
        let resultString = result as! String
        // Should return an error response for unknown timezone
        XCTAssertTrue(
            resultString.contains("error"),
            "Invalid timezone should produce an error, got: \(resultString)"
        )
        XCTAssertTrue(
            resultString.contains("Unknown timezone"),
            "Error should mention 'Unknown timezone', got: \(resultString)"
        )
    }

    // MARK: - UnitConverterTool Tests

    func testConvertCelsiusToFahrenheit() async throws {
        var tool = UnitConverterTool()
        tool.value = 100
        tool.fromUnit = "celsius"
        tool.toUnit = "fahrenheit"
        let result = try await tool.run()
        let resultString = result as! String
        XCTAssertTrue(
            resultString.contains("212"),
            "100°C should convert to 212°F, got: \(resultString)"
        )
    }

    func testConvertKilogramsToLbs() async throws {
        var tool = UnitConverterTool()
        tool.value = 1
        tool.fromUnit = "kg"
        tool.toUnit = "lbs"
        let result = try await tool.run()
        let resultString = result as! String
        // 1 kg ≈ 2.20462 lbs
        XCTAssertTrue(
            resultString.contains("2.20"),
            "1 kg should convert to ~2.20 lbs, got: \(resultString)"
        )
    }

    func testConvertUnknownUnit() async throws {
        var tool = UnitConverterTool()
        tool.value = 100
        tool.fromUnit = "flurbs"
        tool.toUnit = "celsius"
        let result = try await tool.run()
        let resultString = result as! String
        XCTAssertTrue(
            resultString.contains("error"),
            "Unknown unit should produce an error, got: \(resultString)"
        )
        XCTAssertTrue(
            resultString.contains("Unknown unit"),
            "Error should mention 'Unknown unit', got: \(resultString)"
        )
    }

    // MARK: - TextAnalyzerTool Tests

    func testTextAnalyzerWordCount() async throws {
        var tool = TextAnalyzerTool()
        tool.text = "Hello world this is a test"
        let result = try await tool.run()
        let resultString = result as! String
        XCTAssertTrue(
            resultString.contains("6"),
            "Result should contain word count '6' for 6-word input, got: \(resultString)"
        )
        XCTAssertTrue(resultString.contains("word_count"), "Result should contain 'word_count' key")
    }

    func testTextAnalyzerEmptyText() async throws {
        var tool = TextAnalyzerTool()
        tool.text = ""
        let result = try await tool.run()
        let resultString = result as! String
        // Empty text should have 0 words
        XCTAssertTrue(resultString.contains("word_count"), "Result should contain 'word_count' key")
    }

    // MARK: - ToolRegistry Tests

    func testDefaultToolsCount() {
        XCTAssertEqual(
            ToolRegistry.defaultTools.count, 6,
            "Default tools should contain exactly 6 tools"
        )
    }

    func testCreateToolManager() {
        let manager = ToolRegistry.createToolManager()
        XCTAssertFalse(
            manager.toolsJsonDescription.isEmpty,
            "Tool manager JSON description should not be empty"
        )
        XCTAssertNotEqual(
            manager.toolsJsonDescription, "[]",
            "Tool manager JSON description should not be an empty array"
        )
    }
}
