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

// MARK: - Eval Suite Editor Logic

/// Pure, testable logic extracted from `EvalSuiteEditorView`.
///
/// Empty enum prevents accidental instantiation — all members are static.
enum EvalSuiteEditorLogic {

    // MARK: - Validation

    /// Determines whether a suite configuration is valid for saving.
    ///
    /// A suite is valid when:
    /// 1. The name is non-empty after trimming whitespace.
    /// 2. At least one prompt exists.
    /// 3. Every prompt has non-empty text after trimming whitespace.
    ///
    /// - Parameters:
    ///   - name: The suite name entered by the user.
    ///   - promptTexts: The text content of each prompt in the suite.
    /// - Returns: `true` if the suite can be saved.
    static func isValid(name: String, promptTexts: [String]) -> Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
        && !promptTexts.isEmpty
        && promptTexts.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // MARK: - Behavior Type Comparison

    /// Determines whether two `ExpectedBehavior` values are the same type,
    /// ignoring their associated values.
    ///
    /// Used by the editor UI to highlight the active behavior picker button.
    ///
    /// - Parameters:
    ///   - lhs: The first behavior to compare.
    ///   - rhs: The second behavior to compare.
    /// - Returns: `true` if both behaviors are the same enum case.
    static func isSameBehaviorType(
        _ lhs: ExpectedBehavior,
        _ rhs: ExpectedBehavior
    ) -> Bool {
        switch (lhs, rhs) {
        case (.nonEmpty, .nonEmpty): return true
        case (.containsText, .containsText): return true
        case (.containsAny, .containsAny): return true
        case (.containsAll, .containsAll): return true
        case (.toolCall, .toolCall): return true
        case (.toolCallWithArgs, .toolCallWithArgs): return true
        case (.toolCallChain, .toolCallChain): return true
        case (.matchesRegex, .matchesRegex): return true
        case (.custom, .custom): return true
        default: return false
        }
    }

    // MARK: - Suite Assembly

    /// Assembles an `EvalSuite` from editor form state.
    ///
    /// Handles both new suite creation (when `existingSuiteId` is nil)
    /// and editing (preserving the existing suite's ID and creation date).
    ///
    /// - Parameters:
    ///   - existingSuiteId: The ID of the suite being edited, or `nil` for new.
    ///   - name: The suite name (will be trimmed).
    ///   - description: The suite description (will be trimmed).
    ///   - category: The selected category.
    ///   - prompts: The assembled `EvalPrompt` array.
    ///   - existingCreatedAt: The original creation date (for edits), or `nil`.
    /// - Returns: A fully constructed `EvalSuite` ready for persistence.
    static func buildSuite(
        existingSuiteId: UUID?,
        name: String,
        description: String,
        category: EvalCategory,
        prompts: [EvalPrompt],
        existingCreatedAt: Date?
    ) -> EvalSuite {
        EvalSuite(
            id: existingSuiteId ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            description: description.trimmingCharacters(in: .whitespaces),
            category: category,
            prompts: prompts,
            isBuiltIn: false,
            createdAt: existingCreatedAt ?? Date()
        )
    }
}
