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

import Testing
import Foundation

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - BenchmarkPipelineLogicTests

@Suite("BenchmarkPipelineLogic")
struct BenchmarkPipelineLogicTests {

    // MARK: - convertMetricsToDoubles

    @Test("convertMetricsToDoubles keeps only Double values")
    func convertMetricsKeepsDoubles() {
        let input: [String: Any] = [
            "ttft_ms": 42.5,
            "decode_tok_s": 18.3,
            "model_name": "gemma",
            "token_count": 256,
        ]
        let result = BenchmarkPipelineLogic.convertMetricsToDoubles(metrics: input)
        #expect(result.count == 2)
        #expect(result["ttft_ms"] == 42.5)
        #expect(result["decode_tok_s"] == 18.3)
    }

    @Test("convertMetricsToDoubles returns empty for no Doubles")
    func convertMetricsReturnsEmptyWhenNoDoubles() {
        let input: [String: Any] = [
            "model_name": "gemma",
            "token_count": 256,
            "nested": ["a": 1],
        ]
        let result = BenchmarkPipelineLogic.convertMetricsToDoubles(metrics: input)
        #expect(result.isEmpty)
    }

    @Test("convertMetricsToDoubles handles empty input")
    func convertMetricsHandlesEmptyInput() {
        let result = BenchmarkPipelineLogic.convertMetricsToDoubles(metrics: [:])
        #expect(result.isEmpty)
    }

    @Test("convertMetricsToDoubles preserves all keys when all are Double")
    func convertMetricsPreservesAllDoubles() {
        let input: [String: Any] = [
            "ttft_ms": 100.0,
            "decode_tok_s": 25.0,
            "prefill_tok_s": 300.0,
        ]
        let result = BenchmarkPipelineLogic.convertMetricsToDoubles(metrics: input)
        #expect(result.count == 3)
        #expect(result["ttft_ms"] == 100.0)
        #expect(result["decode_tok_s"] == 25.0)
        #expect(result["prefill_tok_s"] == 300.0)
    }

    // MARK: - buildConfigId

    @Test("buildConfigId produces correct format")
    func buildConfigIdFormat() {
        let result = BenchmarkPipelineLogic.buildConfigId(
            modelFile: "gemma-4-E2B-it.litertlm",
            backend: "gpu",
            samplingStrategy: "greedy"
        )
        #expect(result == "gemma-4-E2B-it.litertlm_gpu_greedy")
    }

    @Test("buildConfigId with different backend")
    func buildConfigIdCPU() {
        let result = BenchmarkPipelineLogic.buildConfigId(
            modelFile: "gemma-4-12B-it.litertlm",
            backend: "cpu",
            samplingStrategy: "topk"
        )
        #expect(result == "gemma-4-12B-it.litertlm_cpu_topk")
    }

    @Test("buildConfigId is deterministic")
    func buildConfigIdDeterministic() {
        let a = BenchmarkPipelineLogic.buildConfigId(modelFile: "m", backend: "b", samplingStrategy: "s")
        let b = BenchmarkPipelineLogic.buildConfigId(modelFile: "m", backend: "b", samplingStrategy: "s")
        #expect(a == b)
    }

    @Test("buildConfigId with empty components")
    func buildConfigIdEmptyComponents() {
        let result = BenchmarkPipelineLogic.buildConfigId(modelFile: "", backend: "", samplingStrategy: "")
        #expect(result == "__")
    }

    // MARK: - shouldSkipConfig

    @Test("shouldSkipConfig returns true when config is in processed list")
    func shouldSkipProcessedConfig() {
        let processed = ["config_a", "config_b", "config_c"]
        #expect(BenchmarkPipelineLogic.shouldSkipConfig(configId: "config_b", processedConfigs: processed))
    }

    @Test("shouldSkipConfig returns false when config is not in processed list")
    func shouldNotSkipNewConfig() {
        let processed = ["config_a", "config_b"]
        #expect(!BenchmarkPipelineLogic.shouldSkipConfig(configId: "config_d", processedConfigs: processed))
    }

    @Test("shouldSkipConfig returns false for empty processed list")
    func shouldNotSkipWhenNoProcessed() {
        #expect(!BenchmarkPipelineLogic.shouldSkipConfig(configId: "config_a", processedConfigs: []))
    }

    @Test("shouldSkipConfig is case-sensitive")
    func shouldSkipIsCaseSensitive() {
        let processed = ["Config_A"]
        #expect(!BenchmarkPipelineLogic.shouldSkipConfig(configId: "config_a", processedConfigs: processed))
    }

    // MARK: - hasCriticalRegressions

    @Test("hasCriticalRegressions returns true with critical regression present")
    func hasCriticalRegressionsDetected() {
        let results = [
            RegressionCheckResult(
                metricKey: "ttft_ms",
                baselineValue: 100.0,
                measuredValue: 200.0,
                deviationPct: -50.0,
                thresholdPct: 20,
                severity: .critical,
                isRegression: true
            ),
        ]
        #expect(BenchmarkPipelineLogic.hasCriticalRegressions(results: results))
    }

    @Test("hasCriticalRegressions returns false with only warning severity")
    func hasCriticalRegressionsFalseForWarning() {
        let results = [
            RegressionCheckResult(
                metricKey: "decode_tok_s",
                baselineValue: 20.0,
                measuredValue: 16.0,
                deviationPct: -20.0,
                thresholdPct: 15,
                severity: .warning,
                isRegression: true
            ),
        ]
        #expect(!BenchmarkPipelineLogic.hasCriticalRegressions(results: results))
    }

    @Test("hasCriticalRegressions returns false when critical but not a regression")
    func hasCriticalRegressionsNotRegressed() {
        let results = [
            RegressionCheckResult(
                metricKey: "ttft_ms",
                baselineValue: 100.0,
                measuredValue: 90.0,
                deviationPct: 10.0,
                thresholdPct: 20,
                severity: .critical,
                isRegression: false
            ),
        ]
        #expect(!BenchmarkPipelineLogic.hasCriticalRegressions(results: results))
    }

    @Test("hasCriticalRegressions returns false for empty results")
    func hasCriticalRegressionsEmptyResults() {
        #expect(!BenchmarkPipelineLogic.hasCriticalRegressions(results: []))
    }

    // MARK: - formatRegressionIcon

    @Test("formatRegressionIcon returns ❌ for regression")
    func formatIconRegression() {
        let icon = BenchmarkPipelineLogic.formatRegressionIcon(isRegression: true, deviationPct: -30.0)
        #expect(icon == "❌")
    }

    @Test("formatRegressionIcon returns 🎉 for improvement")
    func formatIconImprovement() {
        let icon = BenchmarkPipelineLogic.formatRegressionIcon(isRegression: false, deviationPct: 15.0)
        #expect(icon == "🎉")
    }

    @Test("formatRegressionIcon returns ✅ for stable (zero deviation)")
    func formatIconStableZero() {
        let icon = BenchmarkPipelineLogic.formatRegressionIcon(isRegression: false, deviationPct: 0.0)
        #expect(icon == "✅")
    }

    @Test("formatRegressionIcon returns ✅ for stable (negative but not regression)")
    func formatIconStableNegative() {
        let icon = BenchmarkPipelineLogic.formatRegressionIcon(isRegression: false, deviationPct: -5.0)
        #expect(icon == "✅")
    }

    @Test("formatRegressionIcon regression overrides positive deviation")
    func formatIconRegressionOverridesPositive() {
        // Even with positive deviation, isRegression=true should show ❌
        let icon = BenchmarkPipelineLogic.formatRegressionIcon(isRegression: true, deviationPct: 10.0)
        #expect(icon == "❌")
    }
}
