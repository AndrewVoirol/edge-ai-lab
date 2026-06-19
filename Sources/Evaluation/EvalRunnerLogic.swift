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

// MARK: - Eval Runner Logic

/// Pure, testable logic extracted from `EvalRunnerView`.
///
/// Empty enum prevents accidental instantiation — all members are static.
enum EvalRunnerLogic {

    // MARK: - Time Formatting

    /// Formats a remaining-time interval as a human-readable string.
    ///
    /// - Parameter seconds: The time remaining, in seconds.
    /// - Returns: A string like `"~2m 15s remaining"` or `"~45s remaining"`.
    static func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins > 0 {
            return "~\(mins)m \(secs)s remaining"
        }
        return "~\(secs)s remaining"
    }

    // MARK: - Suite Aggregation

    /// Merges built-in and custom suites into a single ordered array.
    ///
    /// Built-in suites appear first, followed by custom suites. No deduplication
    /// is performed — callers are expected to provide disjoint lists.
    ///
    /// - Parameters:
    ///   - builtIn: The app-shipped evaluation suites.
    ///   - custom: User-created evaluation suites.
    /// - Returns: A combined array preserving input order.
    static func allSuites(builtIn: [EvalSuite], custom: [EvalSuite]) -> [EvalSuite] {
        builtIn + custom
    }

    // MARK: - Run-Gate Check

    /// Determines whether an evaluation run can be started.
    ///
    /// All three conditions must be met:
    /// 1. A suite is selected.
    /// 2. At least one model file is selected.
    /// 3. No evaluation is currently running.
    ///
    /// - Parameters:
    ///   - selectedSuiteId: The currently selected suite's identifier, if any.
    ///   - selectedModelFiles: The set of selected model filenames.
    ///   - isRunning: Whether an evaluation is already in progress.
    /// - Returns: `true` if the Run button should be enabled.
    static func canRun(
        selectedSuiteId: UUID?,
        selectedModelFiles: Set<String>,
        isRunning: Bool
    ) -> Bool {
        selectedSuiteId != nil && !selectedModelFiles.isEmpty && !isRunning
    }
}
