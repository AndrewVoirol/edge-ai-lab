// Copyright 2026 Andrew Voirol. Apache-2.0
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

// MARK: - Benchmark Pipeline Logic

/// Pure-function helpers extracted from ``BenchmarkAutomationPipeline``.
///
/// All methods are deterministic and side-effect-free, making them
/// straightforward to unit-test without mocking UserDefaults, engines, or
/// view-models.
enum BenchmarkPipelineLogic {

    // MARK: - Metric Conversion

    /// Filters a heterogeneous `[String: Any]` dictionary to only `Double` values.
    ///
    /// Benchmark metrics arrive as `[String: Any]` from `JSONSerialization`.
    /// Regression checking requires `[String: Double]`. This function performs
    /// the safe cast and discards non-numeric entries.
    ///
    /// - Parameter metrics: Raw metrics dictionary (may contain `String`,
    ///   `Int`, `Double`, nested collections, etc.).
    /// - Returns: A dictionary containing only the entries whose values are
    ///   `Double`.
    static func convertMetricsToDoubles(metrics: [String: Any]) -> [String: Double] {
        var result: [String: Double] = [:]
        for (key, value) in metrics {
            if let d = value as? Double {
                result[key] = d
            }
        }
        return result
    }

    // MARK: - Config ID Construction

    /// Builds a deterministic configuration identifier from benchmark parameters.
    ///
    /// The identifier is used for crash-recovery bookkeeping and baseline
    /// matching. Format: `"<modelFile>_<backend>_<samplingStrategy>"`.
    ///
    /// - Parameters:
    ///   - modelFile: The model filename (e.g. `"gemma-4-E2B-it.litertlm"`).
    ///   - backend: The accelerator backend (e.g. `"gpu"`, `"cpu"`).
    ///   - samplingStrategy: The sampling strategy label (e.g. `"greedy"`).
    /// - Returns: A deterministic string identifier.
    static func buildConfigId(modelFile: String, backend: String, samplingStrategy: String) -> String {
        "\(modelFile)_\(backend)_\(samplingStrategy)"
    }

    // MARK: - Crash Recovery

    /// Returns whether a configuration should be skipped during crash recovery.
    ///
    /// After a crash-interrupted benchmark run, the pipeline relaunches and
    /// checks which configurations were already completed. Completed config IDs
    /// are persisted in UserDefaults and passed here.
    ///
    /// - Parameters:
    ///   - configId: The configuration identifier to check.
    ///   - processedConfigs: List of already-completed configuration IDs.
    /// - Returns: `true` if `configId` appears in `processedConfigs`.
    static func shouldSkipConfig(configId: String, processedConfigs: [String]) -> Bool {
        processedConfigs.contains(configId)
    }

    // MARK: - Regression Analysis

    /// Returns `true` if any result in `results` is both a regression **and**
    /// has ``RegressionSeverity/critical`` severity.
    ///
    /// Used to decide whether the pipeline exits with a non-zero status code.
    ///
    /// - Parameter results: The regression-check results for a benchmark run.
    /// - Returns: `true` if at least one critical regression exists.
    static func hasCriticalRegressions(results: [RegressionCheckResult]) -> Bool {
        results.contains { $0.isRegression && $0.severity == .critical }
    }

    // MARK: - Formatting

    /// Returns an emoji icon summarising a single regression-check result.
    ///
    /// | `isRegression` | `deviationPct` | Icon |
    /// |----------------|----------------|------|
    /// | `true`         | any            | ❌   |
    /// | `false`        | > 0            | 🎉   |
    /// | `false`        | ≤ 0            | ✅   |
    ///
    /// - Parameters:
    ///   - isRegression: Whether the metric regressed beyond its threshold.
    ///   - deviationPct: Signed percentage deviation from the baseline.
    /// - Returns: A single-character emoji string.
    static func formatRegressionIcon(isRegression: Bool, deviationPct: Double) -> String {
        if isRegression {
            return "❌"
        } else if deviationPct > 0 {
            return "🎉"
        } else {
            return "✅"
        }
    }
}
