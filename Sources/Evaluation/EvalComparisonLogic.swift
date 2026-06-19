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

// MARK: - Eval Comparison Logic

/// Pure, testable logic extracted from `EvalComparisonView`.
///
/// Empty enum prevents accidental instantiation — all members are static.
enum EvalComparisonLogic {

    // MARK: - Decode Speed

    /// Average decode speed across all prompt results from all model results.
    ///
    /// Collects every non-nil `decodeSpeed` from every `PromptEvalResult`
    /// across all provided `ModelEvalResult`s and returns their arithmetic mean.
    ///
    /// - Parameter modelResults: The model results to aggregate.
    /// - Returns: The mean decode speed in tokens/second, or `nil` if no
    ///   prompt results have a recorded decode speed.
    static func averageDecodeSpeed(from modelResults: [ModelEvalResult]) -> Double? {
        let speeds = modelResults.flatMap(\.promptResults).compactMap(\.decodeSpeed)
        guard !speeds.isEmpty else { return nil }
        return speeds.reduce(0, +) / Double(speeds.count)
    }

    // MARK: - Duration Formatting

    /// Format a `TimeInterval` as "Xm Ys" or "Ys" for short durations.
    ///
    /// - Parameter interval: The duration in seconds.
    /// - Returns: A human-readable string like `"1m 23s"` or `"45s"`.
    static func formatDuration(_ interval: TimeInterval) -> String {
        let mins = Int(interval) / 60
        let secs = Int(interval) % 60
        if mins > 0 { return "\(mins)m \(secs)s" }
        return "\(secs)s"
    }

    // MARK: - Prompt Counting

    /// Total prompt count across all model results.
    ///
    /// - Parameter modelResults: The model results to aggregate.
    /// - Returns: The sum of `promptResults.count` across all models.
    static func totalPromptCount(from modelResults: [ModelEvalResult]) -> Int {
        modelResults.reduce(0) { $0 + $1.promptResults.count }
    }
}
