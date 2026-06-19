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

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Tests for `CalculatorTool`, which evaluates mathematical expressions
/// via NSExpression and returns JSON-encoded results.
@Suite struct CalculatorToolTests {

    // MARK: - Division Edge Cases

    @Test("Division by zero returns JSON error about infinity")
    func divisionByZeroReturnsInfinityError() async throws {
        var tool = CalculatorTool()
        tool.expression = "1 / 0"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("error"))
        #expect(json.contains("infinity"))
        #expect(json.contains("Infinity"))
    }

    @Test("0/0 returns JSON error about NaN")
    func zeroOverZeroReturnsNaNError() async throws {
        var tool = CalculatorTool()
        tool.expression = "0 / 0"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("error"))
        #expect(json.contains("NaN") || json.contains("not a number"))
    }

    // MARK: - Basic Arithmetic

    @Test("Simple addition: 2 + 3 = 5")
    func simpleAddition() async throws {
        var tool = CalculatorTool()
        tool.expression = "2 + 3"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("\"result\" : 5"))
        #expect(json.contains("expression"))
    }

    @Test("Subtraction: 10 - 4 = 6")
    func subtraction() async throws {
        var tool = CalculatorTool()
        tool.expression = "10 - 4"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("6"))
    }

    @Test("Multiplication: 7 * 8 = 56")
    func multiplication() async throws {
        var tool = CalculatorTool()
        tool.expression = "7 * 8"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("56"))
    }

    // MARK: - Complex Expressions

    @Test("Parenthesized expression: (10 + 5) * 2 = 30")
    func expressionWithParentheses() async throws {
        var tool = CalculatorTool()
        tool.expression = "(10 + 5) * 2"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("30"))
    }

    @Test("Nested parentheses: ((2 + 3) * (4 + 1)) = 25")
    func nestedParentheses() async throws {
        var tool = CalculatorTool()
        tool.expression = "((2 + 3) * (4 + 1))"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("25"))
    }

    // MARK: - Decimal Precision

    @Test("Decimal result: 10 / 3 contains 3.33")
    func decimalPrecision() async throws {
        var tool = CalculatorTool()
        tool.expression = "10 / 3"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("3.33"))
    }

    @Test("Integer result formatted without decimals: 100 / 4 = 25")
    func integerResultFormatting() async throws {
        var tool = CalculatorTool()
        tool.expression = "100 / 4"
        let result = try await tool.run()
        let json = try #require(result as? String)
        // formatted_result should be "25" (no trailing .0)
        #expect(json.contains("\"formatted_result\" : \"25\""))
    }

    // MARK: - Negative Numbers

    @Test("Negative result: 3 - 10 = -7")
    func negativeResult() async throws {
        var tool = CalculatorTool()
        tool.expression = "3 - 10"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("-7"))
    }

    @Test("Negative division by zero returns -Infinity")
    func negativeDivisionByZero() async throws {
        var tool = CalculatorTool()
        tool.expression = "-1 / 0"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("error"))
        #expect(json.contains("-Infinity"))
    }

    // MARK: - JSON Structure

    @Test("Result JSON contains expression and result keys")
    func resultContainsExpectedKeys() async throws {
        var tool = CalculatorTool()
        tool.expression = "1 + 1"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("expression"))
        #expect(json.contains("result"))
        #expect(json.contains("formatted_result"))
    }
}
