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
import LiteRTLM

// MARK: - CalculatorTool

/// Evaluates mathematical expressions safely using NSExpression.
///
/// Supports basic arithmetic (+, -, *, /), parentheses, and common math functions
/// available through NSExpression. Does **not** execute arbitrary code — NSExpression
/// is limited to a safe subset of operations.
///
/// Example prompts the model might generate:
/// - `calculate(expression: "2 + 3 * 4")` → 14
/// - `calculate(expression: "(100 - 32) * 5 / 9")` → 37.78
struct CalculatorTool: Tool {
    static let name = "calculate"
    static let description = "Evaluate a mathematical expression safely and return the result"

    @ToolParam(description: "The mathematical expression to evaluate, e.g. '2 + 3 * 4'")
    var expression: String

    func run() async throws -> Any {
        let startTime = CFAbsoluteTimeGetCurrent()
        let argumentsDict = ["expression": expression]
        var resultString = ""
        defer {
            let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            let succeeded = !resultString.isEmpty && !resultString.contains("\"error\"")
            let event = ToolCallEvent(
                toolName: Self.name,
                arguments: jsonString(from: argumentsDict),
                result: resultString,
                durationMs: duration,
                timestamp: Date(),
                succeeded: succeeded
            )
            ToolExecutionTracker.shared.notify(event)
        }
                let regex = try! NSRegularExpression(pattern: "(?<!\\.)\\b(\\d+)\\b(?!\\.)")
        let doubleExpression = regex.stringByReplacingMatches(in: expression, range: NSRange(expression.startIndex..., in: expression), withTemplate: "$1.0")
        let nsExpression = NSExpression(format: doubleExpression)
        guard let result = nsExpression.expressionValue(with: nil, context: nil) as? NSNumber else {
            resultString = jsonString(from: [
                "error": "Expression did not evaluate to a number",
                "expression": expression
            ])
            return resultString
        }

        let doubleResult = result.doubleValue
        // Format nicely: strip trailing .0 for integer results
        let formatted: String
        if doubleResult == doubleResult.rounded() && !doubleResult.isInfinite && !doubleResult.isNaN {
            formatted = String(format: "%.0f", doubleResult)
        } else {
            formatted = String(format: "%.6g", doubleResult)
        }

        resultString = jsonString(from: [
            "expression": expression,
            "result": doubleResult,
            "formatted_result": formatted
        ])
        return resultString
    }
}
