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

// MARK: - Benchmark Pipeline Tests (Swift Testing)

/// Check if baselines.json is accessible from the project root via `#filePath`.
/// Returns `false` on device where the compile-time source path doesn't exist.
/// Defined at file scope to avoid circular reference with the `@Suite` macro.
private let _benchmarkBaselinesAccessible: Bool = {
    let testFile = URL(fileURLWithPath: #filePath)
    let baselinesURL = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("metrics")
        .appendingPathComponent("baselines.json")
    return FileManager.default.fileExists(atPath: baselinesURL.path)
}()

/// Validates the benchmark pipeline plumbing:
/// - baselines.json parsing and schema integrity
/// - Regression rule coverage for all baseline metrics
/// - Regression detection logic (degradation, improvement, within-threshold)
///
/// These tests do NOT require a model file — they exercise the Codable models
/// and regression checker logic using the actual baselines.json and mock results.
///
/// **Note:** These tests require access to the project filesystem (`metrics/baselines.json`)
/// via `#filePath`. On physical devices, `#filePath` resolves to a compile-time path that
/// doesn't exist on the device filesystem, so the suite is automatically disabled.
@Suite("Benchmark Pipeline", .enabled(if: _benchmarkBaselinesAccessible))
struct BenchmarkPipelineTests {

    // MARK: - Helpers

    /// Loads and parses the actual `metrics/baselines.json` from the project.
    ///
    /// Uses `#filePath` to navigate from `Tests/Benchmarking/` up to the project root,
    /// then into `metrics/baselines.json`. This approach works for both macOS and iOS
    /// test targets since `#filePath` resolves to the source file's compile-time path.
    private func loadBaselines() throws -> BenchmarkBaselines {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()  // Tests/Benchmarking/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // project root
        let baselinesURL = projectRoot
            .appendingPathComponent("metrics")
            .appendingPathComponent("baselines.json")

        // On-device, #filePath resolves to the compile-time source path which
        // doesn't exist. Use #require so the test is recorded as a known
        // precondition failure rather than an unexpected test failure.
        try #require(
            FileManager.default.fileExists(atPath: baselinesURL.path),
            "baselines.json not available at \(baselinesURL.path) — test requires project filesystem (skipped on device)"
        )

        let data = try Data(contentsOf: baselinesURL)
        let decoder = JSONDecoder()
        return try decoder.decode(BenchmarkBaselines.self, from: data)
    }

    /// Returns the first GPU baseline entry for constructing test results.
    private func firstGPUBaseline(from baselines: BenchmarkBaselines) throws -> BenchmarkBaselineEntry {
        guard let entry = baselines.baselines.first(where: { $0.backend == "gpu" }) else {
            throw BaselineTestError.noGPUBaseline
        }
        return entry
    }

    /// Scales all metrics in a baseline entry by a given factor.
    /// For `higher_is_better` metrics, factor < 1.0 = degradation.
    /// For `lower_is_better` metrics, factor > 1.0 = degradation.
    private func scaledResults(
        from baseline: BenchmarkBaselineEntry,
        rules: [String: RegressionRule],
        factor: Double
    ) -> [String: Double] {
        var results: [String: Double] = [:]
        for (key, value) in baseline.metrics {
            guard let rule = rules[key] else {
                results[key] = value
                continue
            }
            switch rule.direction {
            case .higherIsBetter:
                // factor < 1.0 makes it worse (lower), factor > 1.0 makes it better (higher)
                results[key] = value * factor
            case .lowerIsBetter:
                // factor > 1.0 makes it worse (higher), factor < 1.0 makes it better (lower)
                results[key] = value * (1.0 / factor)
            }
        }
        return results
    }

    /// Internal error for test setup failures.
    private enum BaselineTestError: Error, CustomStringConvertible {
        case noGPUBaseline
        case fileNotFound(String)

        var description: String {
            switch self {
            case .noGPUBaseline:
                return "No GPU baseline entry found in baselines.json"
            case .fileNotFound(let path):
                return "baselines.json not found at \(path) — skipped on device"
            }
        }
    }

    // MARK: - JSON Parsing

    @Test("baselines.json parses correctly with all expected fields")
    func testBaselinesJSONParsesCorrectly() throws {
        let baselines = try loadBaselines()

        // Verify metadata
        #expect(baselines.meta.version >= 1)
        #expect(!baselines.meta.description.isEmpty)
        #expect(!baselines.meta.lastUpdated.isEmpty)
        #expect(!baselines.meta.methodology.isEmpty)
        #expect(baselines.meta.thresholdPct > 0)

        // Verify we have baseline entries
        #expect(!baselines.baselines.isEmpty, "Expected at least one baseline entry")

        // Verify each entry has required fields
        for entry in baselines.baselines {
            #expect(!entry.id.isEmpty, "Baseline entry ID should not be empty")
            #expect(!entry.model.isEmpty, "Baseline entry model should not be empty")
            #expect(!entry.variant.isEmpty, "Baseline entry variant should not be empty")
            #expect(!entry.backend.isEmpty, "Baseline entry backend should not be empty")
            #expect(!entry.deviceFamily.isEmpty, "Baseline entry device_family should not be empty")
            #expect(!entry.metrics.isEmpty, "Baseline entry should have at least one metric")
            #expect(!entry.source.isEmpty, "Baseline entry source should not be empty")

            // All metric values should be non-negative
            for (key, value) in entry.metrics {
                #expect(value >= 0, "Metric '\(key)' in baseline '\(entry.id)' should be non-negative")
            }
        }

        // Verify we have regression rules
        #expect(!baselines.regressionRules.isEmpty, "Expected at least one regression rule")

        // Verify each rule has valid fields
        for (key, rule) in baselines.regressionRules {
            #expect(rule.thresholdPct > 0, "Threshold for '\(key)' should be positive")
            #expect(!rule.description.isEmpty, "Description for '\(key)' should not be empty")
        }
    }

    // MARK: - Regression Rule Coverage

    @Test("Regression rules cover all baseline metric keys")
    func testRegressionRulesCoverAllBaselineMetrics() throws {
        let baselines = try loadBaselines()

        // Collect all unique metric keys across all baselines
        var allMetricKeys = Set<String>()
        for entry in baselines.baselines {
            for key in entry.metrics.keys {
                allMetricKeys.insert(key)
            }
        }

        // Every metric key should have a corresponding regression rule
        let ruleKeys = Set(baselines.regressionRules.keys)
        for metricKey in allMetricKeys {
            #expect(
                ruleKeys.contains(metricKey),
                "Metric '\(metricKey)' found in baselines but has no regression rule"
            )
        }

        // Bonus: verify no orphan rules (rules without any matching baseline metric)
        for ruleKey in ruleKeys {
            #expect(
                allMetricKeys.contains(ruleKey),
                "Regression rule '\(ruleKey)' has no matching metric in any baseline"
            )
        }
    }

    // MARK: - Schema Validation

    @Test("Mock benchmark result can be checked against baselines")
    func testBenchmarkResultSchemaMatchesExpected() throws {
        let baselines = try loadBaselines()
        let baseline = try firstGPUBaseline(from: baselines)

        // Create a mock result dict matching the baseline's metrics exactly
        let mockResults = baseline.metrics

        let checks = BenchmarkRegressionChecker.checkRegression(
            results: mockResults,
            baseline: baseline,
            rules: baselines.regressionRules
        )

        // Every metric in the mock results should produce a check result
        let checkedKeys = Set(checks.map(\.metricKey))
        for key in mockResults.keys {
            // Only expect a check if there's a matching regression rule
            if baselines.regressionRules[key] != nil {
                #expect(
                    checkedKeys.contains(key),
                    "Expected check result for metric '\(key)'"
                )
            }
        }

        // When results exactly match baseline, no regressions should be detected
        for check in checks {
            #expect(!check.isRegression, "Exact match should not be a regression for '\(check.metricKey)'")
            #expect(
                abs(check.deviationPct) < 0.01,
                "Exact match deviation should be ~0% for '\(check.metricKey)', got \(check.deviationPct)%"
            )
        }
    }

    // MARK: - Regression Detection: Critical Degradation

    @Test("Regression detection identifies critical degradation at 20% worse")
    func testRegressionDetectionIdentifiesCriticalDegradation() throws {
        let baselines = try loadBaselines()
        let baseline = try firstGPUBaseline(from: baselines)

        // Create results that are 20% worse than baseline across all metrics.
        // factor = 0.80 → higher_is_better metrics drop 20%, lower_is_better metrics rise 25%
        // (both exceeding the 10% threshold for critical metrics)
        let degradedResults = scaledResults(
            from: baseline,
            rules: baselines.regressionRules,
            factor: 0.80
        )

        let checks = BenchmarkRegressionChecker.checkRegression(
            results: degradedResults,
            baseline: baseline,
            rules: baselines.regressionRules
        )

        // At least one regression should be detected
        let regressions = checks.filter(\.isRegression)
        #expect(!regressions.isEmpty, "Expected at least one regression with 20% degradation")

        // All critical metrics with threshold ≤ 20% should be flagged
        for check in checks {
            guard let rule = baselines.regressionRules[check.metricKey] else { continue }
            if rule.severity == .critical && rule.thresholdPct <= 20 {
                #expect(
                    check.isRegression,
                    "Critical metric '\(check.metricKey)' with \(rule.thresholdPct)% threshold should be flagged as regression at 20% degradation"
                )
            }
        }

        // Verify deviation is negative (indicating degradation)
        for check in regressions {
            #expect(check.deviationPct < 0, "Regression deviation should be negative for '\(check.metricKey)'")
            #expect(check.status == "regression", "Status should be 'regression' for '\(check.metricKey)'")
        }
    }

    // MARK: - Regression Detection: Improvements

    @Test("Regression detection allows improvements (20% better)")
    func testRegressionDetectionAllowsImprovements() throws {
        let baselines = try loadBaselines()
        let baseline = try firstGPUBaseline(from: baselines)

        // Create results that are 20% better than baseline.
        // factor = 1.20 → higher_is_better metrics increase 20%, lower_is_better metrics decrease
        let improvedResults = scaledResults(
            from: baseline,
            rules: baselines.regressionRules,
            factor: 1.20
        )

        let checks = BenchmarkRegressionChecker.checkRegression(
            results: improvedResults,
            baseline: baseline,
            rules: baselines.regressionRules
        )

        // No regressions should be detected — improvements are always fine
        let regressions = checks.filter(\.isRegression)
        #expect(
            regressions.isEmpty,
            "No regressions expected with 20% improvement, but found: \(regressions.map(\.metricKey).joined(separator: ", "))"
        )

        // All deviations should be positive (improvement)
        for check in checks {
            #expect(
                check.deviationPct > 0,
                "Improvement deviation should be positive for '\(check.metricKey)', got \(check.deviationPct)%"
            )
            #expect(
                check.status == "improved",
                "Status should be 'improved' for '\(check.metricKey)', got '\(check.status)'"
            )
        }
    }

    // MARK: - Regression Detection: Within Threshold

    @Test("Regression detection reports stable when within threshold")
    func testRegressionDetectionWithinThreshold() throws {
        let baselines = try loadBaselines()
        let baseline = try firstGPUBaseline(from: baselines)

        // Create results that are 5% worse — within any reasonable threshold.
        // The smallest threshold in the real baselines is 10%, so 5% should be stable.
        let slightlyWorseResults = scaledResults(
            from: baseline,
            rules: baselines.regressionRules,
            factor: 0.95
        )

        let checks = BenchmarkRegressionChecker.checkRegression(
            results: slightlyWorseResults,
            baseline: baseline,
            rules: baselines.regressionRules
        )

        // No regressions should be detected — 5% is within all thresholds
        let regressions = checks.filter(\.isRegression)
        #expect(
            regressions.isEmpty,
            "No regressions expected within threshold, but found: \(regressions.map { "\($0.metricKey) (\($0.deviationPct)%)" }.joined(separator: ", "))"
        )

        // Deviations should be small and negative (slightly worse but within tolerance)
        for check in checks {
            #expect(!check.isRegression, "'\(check.metricKey)' should not be flagged within threshold")
            #expect(
                check.status == "stable",
                "Status should be 'stable' for '\(check.metricKey)' within threshold, got '\(check.status)'"
            )
        }
    }
}
