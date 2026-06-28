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
                // Sanitize expression: convert percentage notation to division
        // NSExpression(format:) interprets % as a format specifier, causing an
        // uncatchable NSInvalidArgumentException. Convert "15%" to "(15/100)".
        var sanitized = expression
        // Replace percentage patterns: "15%" → "(15/100)", "15.5%" → "(15.5/100)"
        let pctRegex = try! NSRegularExpression(pattern: "([\\d.]+)\\s*%")
        sanitized = pctRegex.stringByReplacingMatches(
            in: sanitized,
            range: NSRange(sanitized.startIndex..., in: sanitized),
            withTemplate: "($1/100)"
        )

        // Reject expressions with text that NSExpression can't parse.
        // The model sometimes generates natural language like "15% of 2026 == 1".
        let unsafePatterns = ["==", "!=", "<", ">", " of ", " is ", " equals "]
        for pattern in unsafePatterns {
            if sanitized.contains(pattern) {
                resultString = jsonString(from: [
                    "error": "Expression contains unsupported operator: \(pattern.trimmingCharacters(in: .whitespaces))",
                    "expression": expression
                ])
                return resultString
            }
        }

        let regex = try! NSRegularExpression(pattern: "(?<!\\.)\\b(\\d+)\\b(?!\\.)")
        let doubleExpression = regex.stringByReplacingMatches(in: sanitized, range: NSRange(sanitized.startIndex..., in: sanitized), withTemplate: "$1.0")

        // Validate expression only contains characters safe for NSExpression.
        // NSExpression(format:) throws an uncatchable ObjC exception for invalid input.
        let allowedChars = CharacterSet(charactersIn: "0123456789.+-*/() ")
        if doubleExpression.unicodeScalars.contains(where: { !allowedChars.contains($0) }) {
            resultString = jsonString(from: [
                "error": "Expression contains invalid characters",
                "expression": expression
            ])
            return resultString
        }

        // Structural validation: catch expressions that pass the character filter
        // but would crash NSExpression with an uncatchable ObjC exception.
        if let validationError = CalculatorValidation.validateStructure(doubleExpression) {
            resultString = jsonString(from: [
                "error": validationError,
                "expression": expression
            ])
            return resultString
        }

        let nsExpression = NSExpression(format: doubleExpression)
        guard let result = nsExpression.expressionValue(with: nil, context: nil) as? NSNumber else {
            resultString = jsonString(from: [
                "error": "Expression did not evaluate to a number",
                "expression": expression
            ])
            return resultString
        }

        let doubleResult = result.doubleValue
        
        // Guard against non-finite values (e.g., 1/0 = Infinity, 0/0 = NaN)
        // JSONSerialization throws an uncatchable NSInvalidArgumentException for Infinity/NaN
        guard doubleResult.isFinite else {
            let errorDescription = doubleResult.isInfinite ? "infinity" : "not a number"
            resultString = jsonString(from: [
                "error": "Result is \(errorDescription)",
                "expression": expression,
                "formatted_result": doubleResult.isInfinite
                    ? (doubleResult > 0 ? "Infinity" : "-Infinity")
                    : "NaN"
            ])
            return resultString
        }
        
        // Format nicely: strip trailing .0 for integer results
        let formatted: String
        if doubleResult == doubleResult.rounded() {
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

// MARK: - CalculatorValidation

/// Validates that math expressions are structurally safe before passing to
/// `NSExpression(format:)`, which throws uncatchable ObjC exceptions on
/// malformed input. See code-safety skill § "NSExpression Safety".
enum CalculatorValidation {
    /// Validates that an expression is structurally safe for NSExpression.
    /// Returns nil if valid, or an error description if invalid.
    static func validateStructure(_ expression: String) -> String? {
        let trimmed = expression.trimmingCharacters(in: .whitespaces)

        // 1. Reject empty/whitespace-only
        if trimmed.isEmpty {
            return "Expression is empty"
        }

        // 2. Validate balanced parentheses
        var depth = 0
        for char in trimmed {
            if char == "(" { depth += 1 }
            else if char == ")" {
                depth -= 1
                if depth < 0 {
                    return "Unbalanced parentheses: unexpected ')'"
                }
            }
        }
        if depth != 0 {
            return "Unbalanced parentheses: missing ')'"
        }

        // 3. Reject leading * or / (leading - is valid for negation, + allowed for consistency)
        if let first = trimmed.first, first == "*" || first == "/" {
            return "Expression starts with invalid operator: \(first)"
        }

        // 4. Reject trailing operators
        if let last = trimmed.last, "+-*/".contains(last) {
            return "Expression ends with operator: \(last)"
        }

        // 5. Reject consecutive operators (allow - after another operator for negation, e.g. "3 * -2")
        let operators = CharacterSet(charactersIn: "+-*/")
        let chars = Array(trimmed.unicodeScalars)
        var i = 0
        while i < chars.count {
            if operators.contains(chars[i]) {
                var j = i + 1
                // Skip whitespace between operators
                while j < chars.count && chars[j] == " " { j += 1 }
                if j < chars.count && operators.contains(chars[j]) {
                    // Allow minus after another operator (e.g., "3 * -2")
                    let secondOp = Character(UnicodeScalar(chars[j]))
                    if secondOp != "-" {
                        return "Consecutive operators: '\(Character(UnicodeScalar(chars[i])))\(secondOp)'"
                    }
                }
            }
            i += 1
        }

        // 6. Reject expressions with no digits at all (e.g., "+-*/", "()", "...")
        if !trimmed.contains(where: { $0.isNumber }) {
            return "Expression contains no numbers"
        }

        return nil
    }
}
