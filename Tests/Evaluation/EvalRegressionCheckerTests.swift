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

import Testing
import Foundation

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - Eval Regression Checker Tests (Swift Testing)

/// Validates the eval regression checker infrastructure:
/// - Pass rate regression detection (degradation, improvement, within-threshold)
/// - Absolute minimum floor enforcement
/// - Suite/model matching behavior
/// - Severity-based sorting of results
///
/// These tests use in-memory fixtures and do NOT require model files or
/// external JSON — they exercise the Codable models and regression checker
/// logic directly.
@Suite("Eval Regression Checker")
struct EvalRegressionCheckerTests {

    // MARK: - Test Fixtures

    /// The model identifier used across all test fixtures.
    private let testModel = "gemma-3n-E4B-it"

    /// Builds a minimal `EvalBaselines` for testing with configurable entries and rules.
    private func makeBaselines(
        entries: [EvalBaselineEntry],
        rules: [String: EvalRegressionRule] = [:],
        defaultThresholdPct: Int = 10
    ) -> EvalBaselines {
        EvalBaselines(
            meta: EvalBaselineMeta(
                version: 1,
                description: "Test baselines",
                lastUpdated: "2026-06-16",
                defaultThresholdPct: defaultThresholdPct
            ),
            baselines: entries,
            regressionRules: rules
        )
    }

    /// Creates a single `EvalBaselineEntry` with sensible defaults.
    private func makeEntry(
        suite: String,
        model: String? = nil,
        baselinePassRate: Double = 0.90,
        minPassRate: Double = 0.70,
        promptCount: Int = 50
    ) -> EvalBaselineEntry {
        EvalBaselineEntry(
            suite: suite,
            model: model ?? testModel,
            baselinePassRate: baselinePassRate,
            minPassRate: minPassRate,
            promptCount: promptCount,
            source: "test_fixture",
            notes: nil
        )
    }

    /// Creates an `EvalRegressionRule` with the given parameters.
    private func makeRule(
        direction: MetricDirection = .higherIsBetter,
        thresholdPct: Int = 10,
        severity: RegressionSeverity = .warning,
        description: String = "Test rule"
    ) -> EvalRegressionRule {
        EvalRegressionRule(
            direction: direction,
            thresholdPct: thresholdPct,
            severity: severity,
            description: description
        )
    }

    // MARK: - No Regression When Above Baseline

    @Test("No regression when pass rate is at or above baseline")
    func testNoRegressionWhenAboveBaseline() throws {
        let baselines = makeBaselines(
            entries: [makeEntry(suite: "safety_basics", baselinePassRate: 0.90, minPassRate: 0.70)],
            rules: ["safety_basics": makeRule(thresholdPct: 10, severity: .critical)]
        )

        // Pass rate exactly at baseline
        let results: [(suite: String, passRate: Double)] = [
            (suite: "safety_basics", passRate: 0.90)
        ]

        let checks = EvalRegressionChecker.checkRegression(
            results: results,
            baselines: baselines,
            model: testModel
        )

        #expect(checks.count == 1)
        #expect(!checks[0].isRegression, "Exact match should not be a regression")
        #expect(!checks[0].belowMinFloor, "Should not be below min floor")
        #expect(abs(checks[0].deviationPct) < 0.01, "Deviation should be ~0%")
        #expect(checks[0].status == "stable")
    }

    // MARK: - Regression Detected When Below Threshold

    @Test("Regression detected when pass rate drops more than threshold")
    func testRegressionDetectedWhenBelowThreshold() throws {
        let baselines = makeBaselines(
            entries: [makeEntry(suite: "safety_basics", baselinePassRate: 0.90, minPassRate: 0.70)],
            rules: ["safety_basics": makeRule(thresholdPct: 10, severity: .critical)]
        )

        // Pass rate drops by ~16.7% (from 0.90 to 0.75) — exceeds 10% threshold
        let results: [(suite: String, passRate: Double)] = [
            (suite: "safety_basics", passRate: 0.75)
        ]

        let checks = EvalRegressionChecker.checkRegression(
            results: results,
            baselines: baselines,
            model: testModel
        )

        #expect(checks.count == 1)
        #expect(checks[0].isRegression, "16.7% drop should exceed 10% threshold")
        #expect(checks[0].deviationPct < 0, "Deviation should be negative for regression")
        #expect(checks[0].status == "regression")
        #expect(checks[0].severity == .critical)
        #expect(!checks[0].belowMinFloor, "0.75 is above the 0.70 min floor")
    }

    // MARK: - Improvement Detected

    @Test("Improvement detected when pass rate increases significantly")
    func testImprovementDetected() throws {
        let baselines = makeBaselines(
            entries: [makeEntry(suite: "instruction_following", baselinePassRate: 0.80, minPassRate: 0.60)],
            rules: ["instruction_following": makeRule(thresholdPct: 10, severity: .warning)]
        )

        // Pass rate improves from 0.80 to 0.95 (+18.75%)
        let results: [(suite: String, passRate: Double)] = [
            (suite: "instruction_following", passRate: 0.95)
        ]

        let checks = EvalRegressionChecker.checkRegression(
            results: results,
            baselines: baselines,
            model: testModel
        )

        #expect(checks.count == 1)
        #expect(!checks[0].isRegression, "Improvement should not be flagged as regression")
        #expect(checks[0].deviationPct > 0, "Deviation should be positive for improvement")
        #expect(checks[0].status == "improved")
    }

    // MARK: - Min Floor Violation

    @Test("Regression flagged when pass rate falls below absolute minimum floor")
    func testMinFloorViolation() throws {
        let baselines = makeBaselines(
            entries: [makeEntry(suite: "safety_basics", baselinePassRate: 0.90, minPassRate: 0.80)],
            rules: ["safety_basics": makeRule(thresholdPct: 50, severity: .critical)]
        )

        // Pass rate is 0.78 — above threshold deviation (only ~13.3% drop, within 50%)
        // but below the 0.80 absolute minimum floor
        let results: [(suite: String, passRate: Double)] = [
            (suite: "safety_basics", passRate: 0.78)
        ]

        let checks = EvalRegressionChecker.checkRegression(
            results: results,
            baselines: baselines,
            model: testModel
        )

        #expect(checks.count == 1)
        #expect(checks[0].isRegression, "Should be flagged because measured is below min floor")
        #expect(checks[0].belowMinFloor, "Should indicate below-min-floor violation")
        #expect(checks[0].status == "regression")
    }

    // MARK: - No Matching Baseline Skipped

    @Test("Suite with no matching baseline is skipped")
    func testNoMatchingBaselineSkipped() throws {
        let baselines = makeBaselines(
            entries: [makeEntry(suite: "safety_basics", baselinePassRate: 0.90, minPassRate: 0.70)],
            rules: ["safety_basics": makeRule()]
        )

        // Result for a suite that has no baseline entry
        let results: [(suite: String, passRate: Double)] = [
            (suite: "unknown_suite", passRate: 0.50)
        ]

        let checks = EvalRegressionChecker.checkRegression(
            results: results,
            baselines: baselines,
            model: testModel
        )

        #expect(checks.isEmpty, "Suite with no matching baseline should produce no check results")
    }

    // MARK: - Multiple Suites Sorted by Severity

    @Test("Multiple suites sorted by severity with critical regressions first")
    func testMultipleSuitesSortedBySeverity() throws {
        let baselines = makeBaselines(
            entries: [
                makeEntry(suite: "safety_basics", baselinePassRate: 0.90, minPassRate: 0.70),
                makeEntry(suite: "instruction_following", baselinePassRate: 0.85, minPassRate: 0.60),
                makeEntry(suite: "factuality", baselinePassRate: 0.80, minPassRate: 0.50),
            ],
            rules: [
                // info-severity suite will regress but with lowest priority
                "safety_basics": makeRule(thresholdPct: 10, severity: .info),
                // critical-severity suite will regress with highest priority
                "instruction_following": makeRule(thresholdPct: 10, severity: .critical),
                // warning-severity suite will regress with medium priority
                "factuality": makeRule(thresholdPct: 10, severity: .warning),
            ]
        )

        // All suites drop by ~22% — enough to trigger regression for all
        let results: [(suite: String, passRate: Double)] = [
            (suite: "safety_basics", passRate: 0.70),
            (suite: "instruction_following", passRate: 0.66),
            (suite: "factuality", passRate: 0.62),
        ]

        let checks = EvalRegressionChecker.checkRegression(
            results: results,
            baselines: baselines,
            model: testModel
        )

        #expect(checks.count == 3)

        // All should be regressions
        for check in checks {
            #expect(check.isRegression, "All suites should be flagged as regression")
        }

        // Verify sort order: critical first, then warning, then info
        #expect(checks[0].severity == .critical, "First result should be critical severity")
        #expect(checks[0].suiteName == "instruction_following")
        #expect(checks[1].severity == .warning, "Second result should be warning severity")
        #expect(checks[1].suiteName == "factuality")
        #expect(checks[2].severity == .info, "Third result should be info severity")
        #expect(checks[2].suiteName == "safety_basics")
    }

    // MARK: - Stable Within Threshold

    @Test("Small drop within threshold is reported as stable")
    func testStableWithinThreshold() throws {
        let baselines = makeBaselines(
            entries: [makeEntry(suite: "safety_basics", baselinePassRate: 0.90, minPassRate: 0.70)],
            rules: ["safety_basics": makeRule(thresholdPct: 10, severity: .warning)]
        )

        // Pass rate drops by ~5.6% (from 0.90 to 0.85) — within 10% threshold
        let results: [(suite: String, passRate: Double)] = [
            (suite: "safety_basics", passRate: 0.85)
        ]

        let checks = EvalRegressionChecker.checkRegression(
            results: results,
            baselines: baselines,
            model: testModel
        )

        #expect(checks.count == 1)
        #expect(!checks[0].isRegression, "5.6% drop should be within 10% threshold")
        #expect(checks[0].deviationPct < 0, "Deviation should be negative for a small drop")
        #expect(checks[0].status == "stable", "Status should be 'stable' when within threshold")
        #expect(!checks[0].belowMinFloor, "0.85 is above the 0.70 min floor")
    }
}
