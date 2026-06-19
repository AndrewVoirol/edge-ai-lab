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

    // MARK: - Prompt Filtering

    /// The result filter used for the prompt results table.
    enum ResultFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case passed = "Passed"
        case failed = "Failed"

        var id: String { rawValue }
    }

    /// Filter prompt results by pass/fail status.
    ///
    /// - Parameters:
    ///   - model: The model result whose prompts to filter.
    ///   - filter: The filter to apply (all, passed, or failed).
    /// - Returns: The filtered list of prompt results.
    static func filteredPromptResults(
        from model: ModelEvalResult?,
        filter: ResultFilter
    ) -> [PromptEvalResult] {
        guard let model = model else { return [] }
        switch filter {
        case .all: return model.promptResults
        case .passed: return model.promptResults.filter { $0.passed }
        case .failed: return model.promptResults.filter { !$0.passed }
        }
    }

    /// Count prompt results matching a filter for a given model.
    ///
    /// - Parameters:
    ///   - filter: The filter to count matches for.
    ///   - model: The model result to count within.
    /// - Returns: The number of matching prompt results.
    static func countForFilter(
        _ filter: ResultFilter,
        in model: ModelEvalResult?
    ) -> Int {
        guard let model = model else { return 0 }
        switch filter {
        case .all: return model.promptResults.count
        case .passed: return model.promptResults.filter { $0.passed }.count
        case .failed: return model.promptResults.filter { !$0.passed }.count
        }
    }

    // MARK: - Model Selection

    /// Safely select a model result by index.
    ///
    /// - Parameters:
    ///   - index: The selected index.
    ///   - modelResults: The available model results.
    /// - Returns: The model result at the index, or nil if out of bounds.
    static func activeModelResult(
        at index: Int,
        from modelResults: [ModelEvalResult]
    ) -> ModelEvalResult? {
        guard index < modelResults.count else { return nil }
        return modelResults[index]
    }

    // MARK: - Formatting

    /// Format a pass rate as a percentage string (e.g., 0.875 → "88%").
    ///
    /// - Parameter rate: The pass rate as a decimal (0.0–1.0).
    /// - Returns: A formatted percentage string.
    static func passRateLabel(_ rate: Double) -> String {
        String(format: "%.0f%%", rate * 100)
    }

    /// Format a decode speed as a label (e.g., 42.5 → "42.5 tok/s").
    ///
    /// - Parameter speed: The decode speed in tokens per second.
    /// - Returns: A formatted speed string.
    static func speedLabel(_ speed: Double) -> String {
        String(format: "%.1f tok/s", speed)
    }

    /// Format a time-to-first-token value (e.g., 0.87 → "0.87s").
    ///
    /// - Parameter ttft: The TTFT in seconds.
    /// - Returns: A formatted TTFT string.
    static func ttftLabel(_ ttft: Double) -> String {
        String(format: "%.2fs", ttft)
    }

    /// Generate an export filename for a JSON eval run export.
    ///
    /// - Parameters:
    ///   - suiteName: The eval suite name.
    ///   - id: The eval run UUID.
    /// - Returns: A sanitized filename like "eval_Math_Accuracy_abc12345.json".
    static func exportFilename(suiteName: String, id: UUID) -> String {
        "eval_\(suiteName.replacingOccurrences(of: " ", with: "_"))_\(id.uuidString.prefix(8)).json"
    }

    /// Format a model count with correct pluralization (e.g., "1 model", "3 models").
    ///
    /// - Parameter count: The number of models.
    /// - Returns: A pluralized label string.
    static func modelCountLabel(_ count: Int) -> String {
        "\(count) model\(count == 1 ? "" : "s")"
    }
}
