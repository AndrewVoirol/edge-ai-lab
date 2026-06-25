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

/// Aggregated benchmark summary for a single model, derived from all of its
/// ``MetricsStore.Entry`` records.
struct ModelBenchmarkSummary: Identifiable, Equatable {
    var id: String { modelName }

    /// Display name (matches ``MetricsStore.Entry.model``).
    let modelName: String

    /// Total number of benchmark runs recorded for this model.
    let runCount: Int

    /// Best (highest) decode speed in tokens/second across all runs.
    let bestDecodeSpeed: Double

    /// Best (lowest) time-to-first-token in seconds across all runs.
    let bestTTFT: Double

    /// Average total decode token count across all runs.
    let averageDecodeTokens: Double

    /// Average total prefill token count across all runs.
    let averagePrefillTokens: Double
}

/// Pure-function logic extracted from ``BenchmarkComparisonView`` for testability.
enum BenchmarkComparisonLogic {

    /// Build model benchmark summaries from metrics entries.
    ///
    /// Groups by model name, calculates best decode speed, best TTFT,
    /// average decode/prefill tokens, and sorts by best decode speed descending.
    static func buildSummaries(from entries: [MetricsStore.Entry]) -> [ModelBenchmarkSummary] {
        // Group by model name.
        let grouped = Dictionary(grouping: entries, by: \.model)

        // Build summaries, sorted by best decode speed descending.
        return grouped.map { modelName, modelEntries in
            let bestDecode = modelEntries.map(\.metrics.decodeTokensPerSecond).max() ?? 0
            let bestTTFT = modelEntries.map(\.metrics.ttftSeconds).min() ?? 0
            let avgDecodeTokens = modelEntries.map { Double($0.metrics.lastDecodeTokenCount) }
                .reduce(0, +) / Double(modelEntries.count)
            let avgPrefillTokens = modelEntries.map { Double($0.metrics.lastPrefillTokenCount) }
                .reduce(0, +) / Double(modelEntries.count)

            return ModelBenchmarkSummary(
                modelName: modelName,
                runCount: modelEntries.count,
                bestDecodeSpeed: bestDecode,
                bestTTFT: bestTTFT,
                averageDecodeTokens: avgDecodeTokens,
                averagePrefillTokens: avgPrefillTokens
            )
        }
        .sorted { $0.bestDecodeSpeed > $1.bestDecodeSpeed }
    }

    /// Format decode speed as a string (e.g. "12.3").
    static func formatSpeed(_ speed: Double) -> String {
        String(format: "%.1f", speed)
    }

    /// Format time-to-first-token as a string (e.g. "0.12").
    static func formatTTFT(_ ttft: Double) -> String {
        String(format: "%.2f", ttft)
    }

    /// Format token count as a string (e.g. "43").
    static func formatTokens(_ count: Double) -> String {
        String(format: "%.0f", count)
    }
}
