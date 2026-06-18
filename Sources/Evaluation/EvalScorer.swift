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
import os

/// Stateless scoring engine for eval prompt results.
///
/// Each scoring variant is a pure function: (response, toolCallEvents, expectedBehavior) → EvalScore.
/// No dependencies on engine, store, or runner state.
struct EvalScorer {

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.edgeailab",
        category: "EvalScorer"
    )

    /// Score a model's response against an expected behavior.
    ///
    /// - Parameters:
    ///   - response: The model's full response text.
    ///   - toolCallEvents: Tool call events that occurred during inference.
    ///   - expectedBehavior: The expected behavior to check against.
    /// - Returns: An `EvalScore` indicating pass, fail, or other outcome.
    static func score(
        response: String,
        toolCallEvents: [ToolCallEvent],
        against expectedBehavior: ExpectedBehavior
    ) -> EvalScore {
        switch expectedBehavior {
        case .containsText(let expected):
            if response.localizedCaseInsensitiveContains(expected) {
                return .pass
            }
            return .fail(reason: "Response does not contain expected text: \"\(expected)\"")

        case .toolCall(toolName: let expected):
            if toolCallEvents.contains(where: { $0.toolName == expected && $0.succeeded }) {
                return .pass
            }
            let calledTools = toolCallEvents.map(\.toolName).joined(separator: ", ")
            if calledTools.isEmpty {
                return .fail(reason: "Expected tool call '\(expected)' but no tools were called")
            }
            return .fail(reason: "Expected tool '\(expected)' but called: \(calledTools)")

        case .toolCallWithArgs(toolName: let name, key: let key, expectedValue: let expectedValue):
            guard let event = toolCallEvents.first(where: { $0.toolName == name && $0.succeeded }) else {
                return .fail(reason: "Tool '\(name)' was not called")
            }
            // Parse the arguments JSON to check for the expected key-value pair
            if let data = event.arguments.data(using: .utf8),
               let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let value = args[key] as? String,
               value == expectedValue {
                return .pass
            }
            return .fail(reason: "Tool '\(name)' called but argument \(key)=\"\(expectedValue)\" not found in: \(event.arguments)")

        case .toolCallChain(let expectedChain):
            let calledNames = toolCallEvents
                .filter(\.succeeded)
                .map(\.toolName)
            // Check that the expected chain appears in order (not necessarily contiguous)
            var chainIndex = 0
            for calledName in calledNames {
                if chainIndex < expectedChain.count && calledName == expectedChain[chainIndex] {
                    chainIndex += 1
                }
            }
            if chainIndex == expectedChain.count {
                return .pass
            }
            let expected = expectedChain.joined(separator: " → ")
            let actual = calledNames.joined(separator: " → ")
            return .fail(reason: "Expected tool chain [\(expected)] but got [\(actual)]")

        case .nonEmpty:
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return .pass
            }
            return .fail(reason: "Response is empty")

        case .matchesRegex(let pattern):
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                let range = NSRange(response.startIndex..., in: response)
                if regex.firstMatch(in: response, range: range) != nil {
                    return .pass
                }
                return .fail(reason: "Response does not match regex: /\(pattern)/")
            } catch {
                return .error("Invalid regex pattern: \(error.localizedDescription)")
            }

        case .custom(description: let desc):
            logger.info("⚠️ Manual review needed: \(desc, privacy: .public)")
            return .manualReviewNeeded
        }
    }
}
