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

// MARK: - Top-Level Container

/// Top-level Codable model for `metrics/baselines.json`.
/// Contains baseline entries for each model/backend combination and
/// regression rules that define thresholds and directions for each metric.
struct BenchmarkBaselines: Codable {
    let meta: BaselineMeta
    let baselines: [BenchmarkBaselineEntry]
    let regressionRules: [String: RegressionRule]

    enum CodingKeys: String, CodingKey {
        case meta = "_meta"
        case baselines
        case regressionRules = "regression_rules"
    }
}

// MARK: - Metadata

/// Metadata block from the baselines file header.
struct BaselineMeta: Codable {
    let version: Int
    let description: String
    let lastUpdated: String
    let thresholdPct: Int
    let methodology: String

    enum CodingKeys: String, CodingKey {
        case version
        case description
        case lastUpdated = "last_updated"
        case thresholdPct = "threshold_pct"
        case methodology
    }
}

// MARK: - Baseline Entry

/// A single baseline entry representing expected performance for a specific
/// model + backend + device combination.
struct BenchmarkBaselineEntry: Codable {
    let id: String
    let model: String
    let variant: String
    let backend: String
    let deviceFamily: String
    let metrics: [String: Double]
    let source: String
    let notes: String

    enum CodingKeys: String, CodingKey {
        case id
        case model
        case variant
        case backend
        case deviceFamily = "device_family"
        case metrics
        case source
        case notes
    }
}

// MARK: - Regression Rule

/// Defines how a specific metric should be evaluated for regressions.
/// Each metric has a direction (higher or lower is better), a percentage
/// threshold beyond which a regression is flagged, and a severity level.
struct RegressionRule: Codable {
    let direction: MetricDirection
    let thresholdPct: Int
    let severity: RegressionSeverity
    let description: String

    enum CodingKeys: String, CodingKey {
        case direction
        case thresholdPct = "threshold_pct"
        case severity
        case description
    }
}

/// Whether a higher or lower value indicates better performance.
enum MetricDirection: String, Codable {
    case higherIsBetter = "higher_is_better"
    case lowerIsBetter = "lower_is_better"
}

/// Severity level for a detected regression.
enum RegressionSeverity: String, Codable, Comparable {
    case critical
    case warning
    case info

    // Comparable conformance: critical > warning > info
    private var sortOrder: Int {
        switch self {
        case .critical: return 2
        case .warning: return 1
        case .info: return 0
        }
    }

    static func < (lhs: RegressionSeverity, rhs: RegressionSeverity) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

// MARK: - Regression Check Result

/// Result of comparing a single metric's measured value against its baseline.
struct RegressionCheckResult {
    /// The metric key (e.g. "sdk_decode_tok_s").
    let metricKey: String

    /// The baseline value from baselines.json.
    let baselineValue: Double

    /// The measured value from the current benchmark run.
    let measuredValue: Double

    /// The percentage deviation from baseline. Positive = improvement, negative = regression
    /// (normalized so that "better" is always positive regardless of direction).
    let deviationPct: Double

    /// The threshold percentage from the regression rule.
    let thresholdPct: Int

    /// The severity of this metric's regression rule.
    let severity: RegressionSeverity

    /// Whether this result constitutes a regression (deviation exceeds threshold in the wrong direction).
    let isRegression: Bool

    /// Human-readable status: "regression", "stable", or "improved".
    var status: String {
        if isRegression {
            return "regression"
        } else if deviationPct > 0 {
            return "improved"
        } else {
            return "stable"
        }
    }
}

// MARK: - Regression Checker

/// Compares benchmark results against baselines to detect performance regressions.
///
/// Usage:
/// ```swift
/// let baselines = try JSONDecoder().decode(BenchmarkBaselines.self, from: data)
/// let results: [String: Double] = ["sdk_decode_tok_s": 95.0, ...]
/// let checks = BenchmarkRegressionChecker.checkRegression(
///     results: results,
///     baseline: baselines.baselines[0],
///     rules: baselines.regressionRules
/// )
/// ```
struct BenchmarkRegressionChecker {

    /// Compare measured results against a single baseline entry using the provided regression rules.
    ///
    /// - Parameters:
    ///   - results: Dictionary of metric key → measured value from the current run.
    ///   - baseline: The baseline entry to compare against.
    ///   - rules: The regression rules defining thresholds and directions.
    /// - Returns: An array of `RegressionCheckResult` for each metric that exists in both
    ///            the results and the baseline and has a matching regression rule.
    static func checkRegression(
        results: [String: Double],
        baseline: BenchmarkBaselineEntry,
        rules: [String: RegressionRule]
    ) -> [RegressionCheckResult] {
        var checks: [RegressionCheckResult] = []

        for (metricKey, measuredValue) in results {
            guard let baselineValue = baseline.metrics[metricKey],
                  let rule = rules[metricKey] else {
                continue
            }

            // Skip if baseline is zero to avoid division by zero
            guard baselineValue != 0 else { continue }

            // Calculate deviation as a percentage.
            // Normalize so that positive = improvement, negative = regression.
            let rawPct: Double
            switch rule.direction {
            case .higherIsBetter:
                // Higher measured value is better → positive deviation = improvement
                rawPct = ((measuredValue - baselineValue) / baselineValue) * 100.0
            case .lowerIsBetter:
                // Lower measured value is better → flip sign so positive = improvement
                rawPct = ((baselineValue - measuredValue) / baselineValue) * 100.0
            }

            // A regression occurs when the deviation is negative (performance got worse)
            // and the magnitude exceeds the threshold.
            let isRegression = rawPct < 0 && abs(rawPct) > Double(rule.thresholdPct)

            checks.append(RegressionCheckResult(
                metricKey: metricKey,
                baselineValue: baselineValue,
                measuredValue: measuredValue,
                deviationPct: rawPct,
                thresholdPct: rule.thresholdPct,
                severity: rule.severity,
                isRegression: isRegression
            ))
        }

        // Sort by severity (critical first) then by metric key for deterministic output
        return checks.sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return lhs.severity > rhs.severity
            }
            return lhs.metricKey < rhs.metricKey
        }
    }

    /// Convenience: check results against all baselines, returning results grouped by baseline ID.
    static func checkRegressionAll(
        results: [String: Double],
        baselines: BenchmarkBaselines
    ) -> [String: [RegressionCheckResult]] {
        var grouped: [String: [RegressionCheckResult]] = [:]
        for baseline in baselines.baselines {
            let checks = checkRegression(
                results: results,
                baseline: baseline,
                rules: baselines.regressionRules
            )
            if !checks.isEmpty {
                grouped[baseline.id] = checks
            }
        }
        return grouped
    }
}
