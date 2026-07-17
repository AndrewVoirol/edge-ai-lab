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

// MARK: - Suite Performance Metrics

/// Performance data captured per-suite during an eval run.
/// Persisted to eval_history.json alongside quality scores.
struct SuitePerformanceMetrics: Sendable {
    let durationSeconds: Double
    let decodeSpeed: Double // tok/s
    let prefillSpeed: Double? // tok/s
    let ttftSeconds: Double // time to first token
    let p95Latency: Double // ms per token
    let totalTokens: Int
    let peakMemoryDeltaMB: Double?
    let thermalTransitions: Int
}

// MARK: - Eval Pipeline Logic

/// Pure-function logic extracted from `EvalAutomationPipeline` for testability.
///
/// All methods are deterministic, side-effect-free, and independent of
/// `@MainActor` or any external state.
enum EvalPipelineLogic {

    // MARK: - Pass Rate Calculation

    /// Calculates the pass rate as a fraction of `passed` over `total`.
    ///
    /// Returns `0.0` when `total` is zero (avoids division by zero).
    ///
    /// - Parameters:
    ///   - passed: The number of passing prompts.
    ///   - total: The total number of prompts evaluated.
    /// - Returns: A value in the range `0.0...1.0`.
    static func calculatePassRate(passed: Int, total: Int) -> Double {
        guard total > 0 else { return 0.0 }
        return Double(passed) / Double(total)
    }

    // MARK: - Pass Rate Formatting

    /// Returns an emoji icon representing the pass-rate tier.
    ///
    /// Thresholds (matching `EvalAutomationPipeline` line 201):
    /// - `>= 0.7` → ✅
    /// - `>= 0.4` → ⚠️
    /// - `< 0.4`  → ❌
    ///
    /// - Parameter passRate: A value in `0.0...1.0`.
    /// - Returns: An emoji string.
    static func formatPassRateIcon(passRate: Double) -> String {
        if passRate >= 0.7 {
            return "✅"
        } else if passRate >= 0.4 {
            return "⚠️"
        } else {
            return "❌"
        }
    }

    // MARK: - Suite Skip Detection

    /// Determines whether a suite was skipped based on its pass rate.
    ///
    /// Skipped suites are encoded with a negative pass rate
    /// (see `EvalAutomationPipeline` line 191).
    ///
    /// - Parameter passRate: The recorded pass rate for the suite.
    /// - Returns: `true` if the suite was skipped.
    static func isSuiteSkipped(passRate: Double) -> Bool {
        return passRate < 0
    }

    // MARK: - CI Gate Decision

    /// Determines whether the CI gate should fail based on regression results.
    ///
    /// Logic extracted from `EvalAutomationPipeline` lines 249–258:
    /// - When `isGated` is `true`, any critical regressions or floor violations
    ///   cause the gate to fail.
    /// - When `isGated` is `false`, regressions are informational only.
    ///
    /// - Parameters:
    ///   - criticalRegressions: Number of critical-severity regressions detected.
    ///   - floorViolations: Number of suites below their minimum floor.
    ///   - isGated: Whether the pipeline is running in gated (CI) mode.
    /// - Returns: A tuple with `shouldFail` indicating whether the gate failed,
    ///   and `issueCount` with the combined count of critical issues.
    static func determineGateResult(
        criticalRegressions: Int,
        floorViolations: Int,
        isGated: Bool
    ) -> (shouldFail: Bool, issueCount: Int) {
        let issueCount = criticalRegressions + floorViolations
        let shouldFail = isGated && issueCount > 0
        return (shouldFail: shouldFail, issueCount: issueCount)
    }
}
