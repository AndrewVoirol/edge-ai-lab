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

    @Test("Groups results by baseline ID")
    func groupsByBaselineId() {
        let results: [String: Double] = ["sdk_decode_tok_s": 95.0, "ttft_s": 0.55]
        let baselines = makeBaselines()
        let grouped = BenchmarkRegressionChecker.checkRegressionAll(
            results: results,
            baselines: baselines
        )
        // baseline-1 has both metrics, baseline-2 has only sdk_decode_tok_s
        #expect(grouped.keys.count >= 1)
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
    func multipleBaselines() {
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
    func regressionDetected() {
        let results: [String: Double] = ["sdk_decode_tok_s": 80.0]  // 20% drop from 100
        let baselines = makeBaselines()
        let grouped = BenchmarkRegressionChecker.checkRegressionAll(
            results: results,
            baselines: baselines
        )
        // baseline-1: 80 vs 100 = -20% deviation, threshold is 10% → regression
        let checks = grouped["baseline-1"]!
        #expect(checks[0].isRegression == true)
        #expect(checks[0].status == "regression")
    }

    @Test("Improvement detected for higherIsBetter when value increases")
    func improvement() {
        let results: [String: Double] = ["sdk_decode_tok_s": 120.0]  // 20% improvement
        let baselines = makeBaselines()
        let grouped = BenchmarkRegressionChecker.checkRegressionAll(
            results: results,
            baselines: baselines
        )
        let checks = grouped["baseline-1"]!
        let speedCheck = checks.first { $0.metricKey == "sdk_decode_tok_s" }!
        #expect(speedCheck.isRegression == false)
        #expect(speedCheck.status == "improved")
    }

    @Test("Stable when within threshold")
    func stable() {
        let results: [String: Double] = ["sdk_decode_tok_s": 95.0]  // 5% drop, threshold 10%
        let baselines = makeBaselines()
        let grouped = BenchmarkRegressionChecker.checkRegressionAll(
            results: results,
            baselines: baselines
        )
        let checks = grouped["baseline-1"]!
        let speedCheck = checks.first { $0.metricKey == "sdk_decode_tok_s" }!
        #expect(speedCheck.isRegression == false)
    }

    @Test("lowerIsBetter regression when value increases >threshold")
    func lowerIsBetterRegression() {
        let results: [String: Double] = ["ttft_s": 0.8]  // 60% increase from 0.5, threshold 20%
        let baselines = makeBaselines()
        let grouped = BenchmarkRegressionChecker.checkRegressionAll(
            results: results,
            baselines: baselines
        )
        let checks = grouped["baseline-1"]!
        let ttftCheck = checks.first { $0.metricKey == "ttft_s" }!
        #expect(ttftCheck.isRegression == true)
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
