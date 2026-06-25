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

import Testing
import Foundation
#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

@Suite("BenchmarkRegressionChecker — checkRegressionAll")
struct BenchmarkRegressionCheckerAllSwiftTests {

    // MARK: - Helpers

    private func makeBaselines() -> BenchmarkBaselines {
        BenchmarkBaselines(
            meta: BaselineMeta(
                version: 1,
                description: "Test",
                lastUpdated: "2026-01-01",
                thresholdPct: 10,
                methodology: "median of 3"
            ),
            baselines: [
                BenchmarkBaselineEntry(
                    id: "baseline-1",
                    model: "Model A",
                    variant: "standard",
                    backend: "gpu",
                    deviceFamily: "Mac",
                    metrics: ["sdk_decode_tok_s": 100.0, "ttft_s": 0.5],
                    source: "test",
                    notes: "test"
                ),
                BenchmarkBaselineEntry(
                    id: "baseline-2",
                    model: "Model B",
                    variant: "web",
                    backend: "gpu",
                    deviceFamily: "Mac",
                    metrics: ["sdk_decode_tok_s": 50.0],
                    source: "test",
                    notes: "test"
                ),
            ],
            regressionRules: [
                "sdk_decode_tok_s": RegressionRule(
                    direction: .higherIsBetter,
                    thresholdPct: 10,
                    severity: .critical,
                    description: "Decode speed"
                ),
                "ttft_s": RegressionRule(
                    direction: .lowerIsBetter,
                    thresholdPct: 20,
                    severity: .warning,
                    description: "Time to first token"
                ),
            ]
        )
    }

    @Test("Groups results by baseline ID with exact expected count")
    func groupsByBaselineId() throws {
        let results: [String: Double] = ["sdk_decode_tok_s": 95.0, "ttft_s": 0.55]
        let baselines = makeBaselines()
        let grouped = BenchmarkRegressionChecker.checkRegressionAll(
            results: results,
            baselines: baselines
        )
        // baseline-1 has both metrics, baseline-2 has only sdk_decode_tok_s
        #expect(grouped.keys.count == 2)
        let b1Checks = try #require(grouped["baseline-1"])
        #expect(b1Checks.count == 2, "baseline-1 should match both sdk_decode_tok_s and ttft_s")
        let b2Checks = try #require(grouped["baseline-2"])
        #expect(b2Checks.count == 1, "baseline-2 should match only sdk_decode_tok_s")
        #expect(b2Checks[0].metricKey == "sdk_decode_tok_s")
    }

    @Test("Returns empty when results don't match any baseline metrics")
    func noMatchingMetrics() {
        let results: [String: Double] = ["unknown_metric": 42.0]
        let baselines = makeBaselines()
        let grouped = BenchmarkRegressionChecker.checkRegressionAll(
            results: results,
            baselines: baselines
        )
        #expect(grouped.isEmpty)
    }

    @Test("Multiple baselines get separate entries")
    func multipleBaselines() throws {
        let results: [String: Double] = ["sdk_decode_tok_s": 80.0]
        let baselines = makeBaselines()
        let grouped = BenchmarkRegressionChecker.checkRegressionAll(
            results: results,
            baselines: baselines
        )
        // Both baselines have sdk_decode_tok_s, so both should have results
        #expect(grouped.count == 2)
        #expect(grouped["baseline-1"] != nil)
        #expect(grouped["baseline-2"] != nil)
    }

    @Test("Regression detected for higherIsBetter when value drops >threshold")
    func regressionDetected() throws {
        let results: [String: Double] = ["sdk_decode_tok_s": 80.0]  // 20% drop from 100
        let baselines = makeBaselines()
        let grouped = BenchmarkRegressionChecker.checkRegressionAll(
            results: results,
            baselines: baselines
        )
        // baseline-1: 80 vs 100 = -20% deviation, threshold is 10% → regression
        let checks = try #require(grouped["baseline-1"])
        let speedCheck = try #require(checks.first { $0.metricKey == "sdk_decode_tok_s" })
        #expect(speedCheck.isRegression == true)
        #expect(speedCheck.status == "regression")
        #expect(speedCheck.severity == .critical)
    }

    @Test("Improvement detected for higherIsBetter when value increases")
    func improvement() throws {
        let results: [String: Double] = ["sdk_decode_tok_s": 120.0]  // 20% improvement
        let baselines = makeBaselines()
        let grouped = BenchmarkRegressionChecker.checkRegressionAll(
            results: results,
            baselines: baselines
        )
        let checks = try #require(grouped["baseline-1"])
        let speedCheck = try #require(checks.first { $0.metricKey == "sdk_decode_tok_s" })
        #expect(speedCheck.isRegression == false)
        #expect(speedCheck.status == "improved")
    }

    @Test("Stable when within threshold — includes status check")
    func stable() throws {
        let results: [String: Double] = ["sdk_decode_tok_s": 95.0]  // 5% drop, threshold 10%
        let baselines = makeBaselines()
        let grouped = BenchmarkRegressionChecker.checkRegressionAll(
            results: results,
            baselines: baselines
        )
        let checks = try #require(grouped["baseline-1"])
        let speedCheck = try #require(checks.first { $0.metricKey == "sdk_decode_tok_s" })
        #expect(speedCheck.isRegression == false)
        #expect(speedCheck.status == "stable")
    }

    @Test("lowerIsBetter regression when value increases >threshold")
    func lowerIsBetterRegression() throws {
        let results: [String: Double] = ["ttft_s": 0.8]  // 60% increase from 0.5, threshold 20%
        let baselines = makeBaselines()
        let grouped = BenchmarkRegressionChecker.checkRegressionAll(
            results: results,
            baselines: baselines
        )
        let checks = try #require(grouped["baseline-1"])
        let ttftCheck = try #require(checks.first { $0.metricKey == "ttft_s" })
        #expect(ttftCheck.isRegression == true)
        #expect(ttftCheck.status == "regression")
        #expect(ttftCheck.severity == .warning)
    }

    @Test("lowerIsBetter improvement when value decreases")
    func lowerIsBetterImprovement() throws {
        let results: [String: Double] = ["ttft_s": 0.3]  // 40% decrease from 0.5 = improvement
        let baselines = makeBaselines()
        let grouped = BenchmarkRegressionChecker.checkRegressionAll(
            results: results,
            baselines: baselines
        )
        let checks = try #require(grouped["baseline-1"])
        let ttftCheck = try #require(checks.first { $0.metricKey == "ttft_s" })
        #expect(ttftCheck.isRegression == false)
        #expect(ttftCheck.status == "improved")
    }

    @Test("Exactly at threshold is NOT a regression (strict greater-than)")
    func exactlyAtThreshold() throws {
        // sdk_decode_tok_s: baseline=100, threshold=10%
        // 90.0 = exactly 10% drop → rawPct = -10.0, threshold = 10
        // isRegression = rawPct < 0 && abs(rawPct) > threshold → abs(-10) > 10 is false
        let results: [String: Double] = ["sdk_decode_tok_s": 90.0]
        let baselines = makeBaselines()
        let grouped = BenchmarkRegressionChecker.checkRegressionAll(
            results: results,
            baselines: baselines
        )
        let checks = try #require(grouped["baseline-1"])
        let speedCheck = try #require(checks.first { $0.metricKey == "sdk_decode_tok_s" })
        #expect(speedCheck.isRegression == false, "Exactly at threshold should NOT be flagged as regression")
        #expect(speedCheck.status == "stable")
    }

    @Test("Zero baseline value is skipped to avoid division by zero")
    func zeroBaselineSkipped() {
        let zeroBaselines = BenchmarkBaselines(
            meta: BaselineMeta(
                version: 1, description: "Test", lastUpdated: "2026-01-01",
                thresholdPct: 10, methodology: "test"
            ),
            baselines: [
                BenchmarkBaselineEntry(
                    id: "zero-baseline",
                    model: "Model Z", variant: "standard", backend: "gpu",
                    deviceFamily: "Mac", metrics: ["sdk_decode_tok_s": 0.0],
                    source: "test", notes: "test"
                ),
            ],
            regressionRules: [
                "sdk_decode_tok_s": RegressionRule(
                    direction: .higherIsBetter, thresholdPct: 10,
                    severity: .critical, description: "Decode speed"
                ),
            ]
        )
        let results: [String: Double] = ["sdk_decode_tok_s": 50.0]
        let grouped = BenchmarkRegressionChecker.checkRegressionAll(
            results: results,
            baselines: zeroBaselines
        )
        // Zero baseline should be skipped (guard baselineValue != 0)
        #expect(grouped.isEmpty, "Zero baseline should produce no results")
    }

    @Test("Results sorted by severity then metric key")
    func resultsSortedBySeverityThenKey() throws {
        // Supply both metrics: sdk_decode_tok_s (critical) and ttft_s (warning)
        // Both should regress to verify ordering
        let results: [String: Double] = [
            "sdk_decode_tok_s": 80.0,  // 20% drop → critical regression
            "ttft_s": 0.8,             // 60% increase → warning regression
        ]
        let baselines = makeBaselines()
        let grouped = BenchmarkRegressionChecker.checkRegressionAll(
            results: results,
            baselines: baselines
        )
        let checks = try #require(grouped["baseline-1"])
        #expect(checks.count == 2)
        // Critical should come first
        #expect(checks[0].severity == .critical)
        #expect(checks[0].metricKey == "sdk_decode_tok_s")
        #expect(checks[1].severity == .warning)
        #expect(checks[1].metricKey == "ttft_s")
    }

    @Test("RegressionCheckResult.status values")
    func statusValues() {
        let regression = RegressionCheckResult(
            metricKey: "test",
            baselineValue: 100,
            measuredValue: 50,
            deviationPct: -50,
            thresholdPct: 10,
            severity: .critical,
            isRegression: true
        )
        #expect(regression.status == "regression")

        let improved = RegressionCheckResult(
            metricKey: "test",
            baselineValue: 100,
            measuredValue: 120,
            deviationPct: 20,
            thresholdPct: 10,
            severity: .info,
            isRegression: false
        )
        #expect(improved.status == "improved")

        let stable = RegressionCheckResult(
            metricKey: "test",
            baselineValue: 100,
            measuredValue: 100,
            deviationPct: 0,
            thresholdPct: 10,
            severity: .info,
            isRegression: false
        )
        #expect(stable.status == "stable")
    }

    @Test("BenchmarkBaselines Codable round-trip")
    func codable() throws {
        let baselines = makeBaselines()
        let data = try JSONEncoder().encode(baselines)
        let decoded = try JSONDecoder().decode(BenchmarkBaselines.self, from: data)
        #expect(decoded.baselines.count == 2)
        #expect(decoded.regressionRules.count == 2)
        #expect(decoded.meta.version == 1)
    }

    @Test("RegressionSeverity ordering")
    func severityOrdering() {
        #expect(RegressionSeverity.critical > RegressionSeverity.warning)
        #expect(RegressionSeverity.warning > RegressionSeverity.info)
        #expect(RegressionSeverity.info < RegressionSeverity.critical)
    }

    @Test("MetricDirection Codable round-trip")
    func metricDirectionCodable() throws {
        for direction in [MetricDirection.higherIsBetter, .lowerIsBetter] {
            let data = try JSONEncoder().encode(direction)
            let decoded = try JSONDecoder().decode(MetricDirection.self, from: data)
            #expect(decoded == direction)
        }
    }
}
