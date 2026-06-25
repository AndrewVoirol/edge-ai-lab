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

/// Top-level Codable model for eval baselines JSON.
/// Contains baseline entries for each suite/model combination and
/// regression rules that define thresholds for pass rate metrics.
struct EvalBaselines: Codable {
    let meta: EvalBaselineMeta
    let baselines: [EvalBaselineEntry]
    let regressionRules: [String: EvalRegressionRule]

    enum CodingKeys: String, CodingKey {
        case meta = "_meta"
        case baselines
        case regressionRules = "regression_rules"
    }
}

// MARK: - Metadata

/// Metadata block from the eval baselines file header.
struct EvalBaselineMeta: Codable {
    let version: Int
    let description: String
    let lastUpdated: String
    let defaultThresholdPct: Int

    enum CodingKeys: String, CodingKey {
        case version
        case description
        case lastUpdated = "last_updated"
        case defaultThresholdPct = "default_threshold_pct"
    }
}

// MARK: - Baseline Entry

/// A single eval baseline entry representing expected pass rate for a specific
/// eval suite + model combination.
struct EvalBaselineEntry: Codable {
    /// The eval suite name (e.g. "safety_basics", "instruction_following").
    let suite: String

    /// The model identifier (e.g. "gemma-3n-E4B-it").
    let model: String

    /// The expected pass rate as a fraction (0.0–1.0).
    let baselinePassRate: Double

    /// The absolute minimum pass rate floor. Any measured value below this
    /// is flagged as a regression regardless of percentage threshold.
    let minPassRate: Double

    /// The number of prompts in this eval suite.
    let promptCount: Int

    /// Where this baseline was sourced from (e.g. "ci_run_2026-06-15").
    let source: String?

    /// Optional human-readable notes about this baseline.
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case suite
        case model
        case baselinePassRate = "baseline_pass_rate"
        case minPassRate = "min_pass_rate"
        case promptCount = "prompt_count"
        case source
        case notes
    }
}

// MARK: - Regression Rule

/// Defines how an eval pass rate metric should be evaluated for regressions.
/// Reuses `MetricDirection` and `RegressionSeverity` from BenchmarkBaseline.swift.
struct EvalRegressionRule: Codable {
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

// MARK: - Regression Check Result

/// Result of comparing a single eval suite's measured pass rate against its baseline.
struct EvalRegressionCheckResult {
    /// The eval suite name.
    let suiteName: String

    /// The baseline pass rate from the baselines file (0.0–1.0).
    let baselinePassRate: Double

    /// The measured pass rate from the current eval run (0.0–1.0).
    let measuredPassRate: Double

    /// The percentage deviation from baseline.
    /// Positive = improvement, negative = regression.
    let deviationPct: Double

    /// The threshold percentage from the regression rule.
    let thresholdPct: Int

    /// The severity of this check's regression rule.
    let severity: RegressionSeverity

    /// Whether this result constitutes a regression (deviation exceeds threshold
    /// in the wrong direction, or measured pass rate is below the minimum floor).
    let isRegression: Bool

    /// Whether the measured pass rate is below the absolute minimum floor.
    let belowMinFloor: Bool

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

/// Compares eval results against baselines to detect pass rate regressions.
///
/// Usage:
/// ```swift
/// let baselines = try JSONDecoder().decode(EvalBaselines.self, from: data)
/// let results: [(suite: String, passRate: Double)] = [
///     (suite: "safety_basics", passRate: 0.85),
///     (suite: "instruction_following", passRate: 0.72),
/// ]
/// let checks = EvalRegressionChecker.checkRegression(
///     results: results,
///     baselines: baselines,
///     model: "gemma-3n-E4B-it"
/// )
/// ```
struct EvalRegressionChecker {

    /// Compare measured eval results against baselines for a specific model.
    ///
    /// - Parameters:
    ///   - results: Array of tuples containing suite name and measured pass rate.
    ///   - baselines: The parsed eval baselines containing entries and regression rules.
    ///   - model: The model identifier to match baseline entries against.
    /// - Returns: An array of `EvalRegressionCheckResult` for each result that has
    ///            a matching baseline entry. Results are sorted by severity (critical first).
    static func checkRegression(
        results: [(suite: String, passRate: Double)],
        baselines: EvalBaselines,
        model: String
    ) -> [EvalRegressionCheckResult] {
        var checks: [EvalRegressionCheckResult] = []

        for result in results {
            // Find a matching baseline by suite name AND model
            guard let baselineEntry = baselines.baselines.first(where: {
                $0.suite == result.suite && $0.model == model
            }) else {
                // No matching baseline — skip this suite
                continue
            }

            // Determine the regression rule for this suite.
            // Fall back to the default threshold if no suite-specific rule exists.
            let rule = baselines.regressionRules[result.suite]
            let thresholdPct = rule?.thresholdPct ?? baselines.meta.defaultThresholdPct
            let severity = rule?.severity ?? .warning

            // Skip if baseline is zero to avoid division by zero
            guard baselineEntry.baselinePassRate != 0 else { continue }

            // Calculate deviation as a percentage.
            // For pass rates, higher is always better → positive deviation = improvement.
            let deviationPct = ((result.passRate - baselineEntry.baselinePassRate)
                / baselineEntry.baselinePassRate) * 100.0

            // Check if the measured pass rate is below the absolute minimum floor
            let belowMinFloor = result.passRate < baselineEntry.minPassRate

            // A regression occurs when:
            // 1. The deviation is negative AND its magnitude exceeds the threshold, OR
            // 2. The measured pass rate is below the absolute minimum floor
            let isRegression = (deviationPct < 0 && abs(deviationPct) > Double(thresholdPct))
                || belowMinFloor

            checks.append(EvalRegressionCheckResult(
                suiteName: result.suite,
                baselinePassRate: baselineEntry.baselinePassRate,
                measuredPassRate: result.passRate,
                deviationPct: deviationPct,
                thresholdPct: thresholdPct,
                severity: severity,
                isRegression: isRegression,
                belowMinFloor: belowMinFloor
            ))
        }

        // Sort by severity (critical first) then by suite name for deterministic output
        return checks.sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return lhs.severity > rhs.severity
            }
            return lhs.suiteName < rhs.suiteName
        }
    }
}
