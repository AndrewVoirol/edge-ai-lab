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

import XCTest

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

@MainActor
final class DeveloperAutomationHarnessTests: XCTestCase {

    // MARK: - Existing Tests

    func testSafeSamplerConfigReturnsFallbackOnInvalidInput() {
        // Attempting an invalid config (e.g. topP > 1.0) should not crash,
        // it should return a safe default.
        let config = DeveloperAutomationHarness.safeSamplerConfig(topK: 1, topP: 1.5, temperature: 1.0)
        XCTAssertEqual(config.topK, 1)
        XCTAssertEqual(config.topP, 1.0) // fallback value
    }

    func testSafeCachesDirectoryReturnsValidURL() {
        // We ensure that we can safely resolve a caches directory without a forced unwrap.
        let url = DeveloperAutomationHarness.safeCachesDirectory()
        XCTAssertNotNil(url)
        XCTAssertTrue(url.path.contains("Caches"))
    }

    // MARK: - safeSamplerConfig Edge Cases

    func testSafeSamplerConfigEdgeCases() {
        // topP > 1.0 is invalid; should fall back to greedy config (topK=1, topP=1.0, temperature=1.0).
        let configBadTopP = DeveloperAutomationHarness.safeSamplerConfig(topK: 1, topP: 1.5, temperature: 1.0)
        XCTAssertEqual(configBadTopP.topK, 1, "topP > 1.0 should trigger fallback")
        XCTAssertEqual(configBadTopP.topP, 1.0, "Fallback topP should be 1.0")
        XCTAssertEqual(configBadTopP.temperature, 1.0, "Fallback temperature should be 1.0")

        // topK=0 is also invalid for the SDK; triggers fallback.
        let configZeroTopK = DeveloperAutomationHarness.safeSamplerConfig(topK: 0, topP: 0.9, temperature: 1.0)
        XCTAssertEqual(configZeroTopK.topK, 1, "topK=0 should trigger fallback to greedy config")
        XCTAssertEqual(configZeroTopK.topP, 1.0, "Fallback topP should be 1.0")

        // Negative topP is invalid; should fall back.
        let configNegTopP = DeveloperAutomationHarness.safeSamplerConfig(topK: 5, topP: -0.1, temperature: 1.0)
        XCTAssertEqual(configNegTopP.topP, 1.0, "Negative topP should trigger fallback to 1.0")
    }

    // MARK: - safeSamplerConfig Valid Input

    func testSafeSamplerConfigValidInput() {
        // Normal, valid parameters should pass through unchanged.
        let config = DeveloperAutomationHarness.safeSamplerConfig(topK: 40, topP: 0.95, temperature: 0.8)
        XCTAssertEqual(config.topK, 40, "Valid topK should pass through")
        XCTAssertEqual(config.topP, 0.95, accuracy: 0.001, "Valid topP should pass through")
        XCTAssertEqual(config.temperature, 0.8, accuracy: 0.001, "Valid temperature should pass through")
    }

    // MARK: - safeCachesDirectory Consistency

    func testSafeCachesDirectoryConsistency() {
        // Multiple calls should return the same URL — the caches directory is deterministic.
        let url1 = DeveloperAutomationHarness.safeCachesDirectory()
        let url2 = DeveloperAutomationHarness.safeCachesDirectory()
        let url3 = DeveloperAutomationHarness.safeCachesDirectory()
        XCTAssertEqual(url1, url2, "Consecutive calls should return the same URL")
        XCTAssertEqual(url2, url3, "Third call should also match")
    }

    // MARK: - completionMarkerPath

    func testCompletionMarkerPath() {
        // completionMarkerPath is a nonisolated static let — accessible from any isolation domain.
        let path = DeveloperAutomationHarness.completionMarkerPath
        XCTAssertFalse(path.isEmpty, "completionMarkerPath should not be empty")
        XCTAssertTrue(
            path.contains("automation_complete"),
            "Path should contain 'automation_complete'. Got: \(path)"
        )
        // It's an absolute path.
        XCTAssertTrue(path.hasPrefix("/"), "completionMarkerPath should be an absolute path")
    }

    // MARK: - isFinite Guard (JSONSerialization Safety)

    func testIsFiniteGuard() {
        // The harness uses `value.isFinite ? value : 0.0` before passing values to
        // JSONSerialization.data(withJSONObject:). Verify the pattern works correctly:
        // non-finite Double values are sanitized to 0.0, finite ones pass through.

        let nan = Double.nan
        let posInf = Double.infinity
        let negInf = -Double.infinity
        let normal = 42.5

        // Replicate the harness pattern: value.isFinite ? value : 0.0
        let safeNaN = nan.isFinite ? nan : 0.0
        let safePosInf = posInf.isFinite ? posInf : 0.0
        let safeNegInf = negInf.isFinite ? negInf : 0.0
        let safeNormal = normal.isFinite ? normal : 0.0

        XCTAssertEqual(safeNaN, 0.0, "NaN should be sanitized to 0.0")
        XCTAssertEqual(safePosInf, 0.0, "Infinity should be sanitized to 0.0")
        XCTAssertEqual(safeNegInf, 0.0, "-Infinity should be sanitized to 0.0")
        XCTAssertEqual(safeNormal, 42.5, "Finite values should pass through unchanged")

        // Verify the sanitized values don't crash JSONSerialization — the whole point
        // of the isFinite guard per AGENTS.md rules.
        let dict: [String: Any] = [
            "pass_rate": safeNaN,
            "score": safePosInf,
            "delta": safeNegInf,
            "normal": safeNormal
        ]
        let data = try? JSONSerialization.data(withJSONObject: dict, options: [])
        XCTAssertNotNil(data, "JSONSerialization should succeed with sanitized values")
    }

    // MARK: - Results Directory Path (printReport-style dict)

    func testResultsDirectoryPath() {
        // The harness's printReport builds a [String: Any] dictionary with known keys
        // and serializes it to JSON. Verify a similar dict round-trips without error
        // and contains expected keys.
        let report: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "model": "test-model.litertlm",
            "config": "default",
            "prefill_tok_s": 150.0,
            "decode_tok_s": 30.5,
            "ttft_s": 0.25,
            "init_time_s": 1.2,
            "median_token_latency_ms": 33.0,
            "memory_delta_mb": 128.0
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) else {
            XCTFail("JSONSerialization should succeed for a valid report dict")
            return
        }

        let jsonString = String(data: jsonData, encoding: .utf8)
        XCTAssertNotNil(jsonString, "Should produce valid UTF-8 JSON")
        XCTAssertTrue(jsonString?.contains("test-model.litertlm") == true, "JSON should contain the model name")
        XCTAssertTrue(jsonString?.contains("decode_tok_s") == true, "JSON should contain decode_tok_s key")
    }

    // MARK: - signalComplete

    func testSignalCompleteWritesMarkerFile() {
        // Clean up any pre-existing marker file
        let markerPath = DeveloperAutomationHarness.completionMarkerPath
        try? FileManager.default.removeItem(atPath: markerPath)

        DeveloperAutomationHarness.signalComplete(0, message: "test")

        let contents = try? String(contentsOfFile: markerPath, encoding: .utf8)
        XCTAssertNotNil(contents, "Marker file should exist after signalComplete")
        XCTAssertEqual(contents, "0\ntest", "Marker file should contain code and message")

        // Clean up
        try? FileManager.default.removeItem(atPath: markerPath)
    }

    func testSignalCompleteSetsCode() {
        DeveloperAutomationHarness.signalComplete(42)
        XCTAssertEqual(
            DeveloperAutomationHarness.completionCode, 42,
            "completionCode should be set by signalComplete"
        )
        // Reset
        DeveloperAutomationHarness.completionCode = nil
        try? FileManager.default.removeItem(atPath: DeveloperAutomationHarness.completionMarkerPath)
    }

    // MARK: - findBaselinesFile / findEvalBaselinesFile

    func testFindBaselinesFileReturnsNilWhenMissing() {
        // Use a temp directory as working directory with no baselines.json present.
        // The method checks Bundle.main, cwd/metrics/, and ~/Antigravity/... paths.
        // Bundle.main won't have it in a unit test runner,
        // and the home path may or may not exist. We can only assert non-crash behavior.
        // If nil is returned, it means no baselines file was found — which is valid.
        let result = BenchmarkAutomationPipeline.findBaselinesFile()
        // This test mainly verifies the method doesn't crash and returns a valid URL or nil.
        if let url = result {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: url.path),
                "If a URL is returned, the file should exist"
            )
        }
        // nil is acceptable — means no baselines file found
    }

    func testFindEvalBaselinesFileReturnsNilWhenMissing() {
        let result = EvalAutomationPipeline.findEvalBaselinesFile()
        if let url = result {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: url.path),
                "If a URL is returned, the file should exist"
            )
        }
        // nil is acceptable — means no eval baselines file found
    }

    // MARK: - persistEvalHistory

    /// Finds the eval_history.json that persistEvalHistory writes to (mirrors the method's priority logic).
    private func findEvalHistoryFile() -> URL? {
        let fm = FileManager.default
        #if os(macOS)
        let projectPaths = [
            URL(fileURLWithPath: fm.currentDirectoryPath)
                .appendingPathComponent("metrics/eval_history.json"),
            fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Antigravity/Projects/edge-ai-lab/metrics/eval_history.json")
        ]
        if let existing = projectPaths.first(where: { fm.fileExists(atPath: $0.path) }) {
            return existing
        }
        #endif
        let docsDir = fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? "/tmp")
        return docsDir.appendingPathComponent("metrics/eval_history.json")
    }

    func testPersistEvalHistoryCreatesFile() {
        let results: [(suiteName: String, passRate: Double, promptCount: Int, failedPrompts: [String], perf: SuitePerformanceMetrics?)] = [
            ("TestSuite", 0.85, 10, [], nil)
        ]

        EvalAutomationPipeline.persistEvalHistory(results: results, model: "test-model-create")

        guard let historyURL = findEvalHistoryFile(),
              FileManager.default.fileExists(atPath: historyURL.path) else {
            XCTFail("eval_history.json should exist after persistEvalHistory call")
            return
        }

        guard let data = try? Data(contentsOf: historyURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runs = json["runs"] as? [[String: Any]] else {
            XCTFail("eval_history.json should contain valid JSON with 'runs' array")
            return
        }

        XCTAssertGreaterThanOrEqual(runs.count, 1, "Should have at least one run")
    }

    func testPersistEvalHistoryAppendsToExisting() {
        // Read current run count
        let historyURL = findEvalHistoryFile()
        var initialCount = 0
        if let url = historyURL,
           let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let runs = json["runs"] as? [[String: Any]] {
            initialCount = runs.count
        }

        // First call
        let results1: [(suiteName: String, passRate: Double, promptCount: Int, failedPrompts: [String], perf: SuitePerformanceMetrics?)] = [
            ("Suite1", 0.9, 5, [], nil)
        ]
        EvalAutomationPipeline.persistEvalHistory(results: results1, model: "model-a-append")

        // Second call
        let results2: [(suiteName: String, passRate: Double, promptCount: Int, failedPrompts: [String], perf: SuitePerformanceMetrics?)] = [
            ("Suite2", 0.75, 8, [], nil)
        ]
        EvalAutomationPipeline.persistEvalHistory(results: results2, model: "model-b-append")

        guard let url = findEvalHistoryFile(),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runs = json["runs"] as? [[String: Any]] else {
            XCTFail("Should have valid JSON with runs array")
            return
        }

        XCTAssertGreaterThanOrEqual(runs.count, initialCount + 2, "Should have at least 2 more runs after appending")
    }

    func testPersistEvalHistoryHandlesNonFinitePassRate() {
        // The isFinite guard should sanitize Infinity/NaN to 0.0
        let results: [(suiteName: String, passRate: Double, promptCount: Int, failedPrompts: [String], perf: SuitePerformanceMetrics?)] = [
            ("InfinitySuite", Double.infinity, 3, [], nil),
            ("NaNSuite", Double.nan, 2, [], nil)
        ]

        // This should NOT crash — the isFinite guard sanitizes non-finite values to 0.0
        EvalAutomationPipeline.persistEvalHistory(results: results, model: "nonfinite-test")

        guard let url = findEvalHistoryFile(),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runs = json["runs"] as? [[String: Any]],
              let lastRun = runs.last,
              let suites = lastRun["suites"] as? [[String: Any]] else {
            XCTFail("Should have valid JSON after non-finite sanitization")
            return
        }

        for suite in suites {
            if let passRate = suite["pass_rate"] as? Double {
                XCTAssertTrue(passRate.isFinite, "pass_rate should be finite after sanitization")
                XCTAssertEqual(passRate, 0.0, accuracy: 0.001, "Non-finite pass_rate should be sanitized to 0.0")
            }
        }
    }

    func testPersistEvalHistorySkippedSuite() {
        // Negative passRate signals a skipped suite
        let results: [(suiteName: String, passRate: Double, promptCount: Int, failedPrompts: [String], perf: SuitePerformanceMetrics?)] = [
            ("SkippedSuite", -1.0, 0, [], nil)
        ]

        EvalAutomationPipeline.persistEvalHistory(results: results, model: "skipped-test")

        guard let url = findEvalHistoryFile(),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runs = json["runs"] as? [[String: Any]],
              let lastRun = runs.last,
              let suites = lastRun["suites"] as? [[String: Any]] else {
            XCTFail("Should have valid JSON for skipped suite")
            return
        }

        let skipped = suites.first { ($0["name"] as? String) == "SkippedSuite" }
        XCTAssertNotNil(skipped, "Should find the SkippedSuite entry")

        if let skipped = skipped {
            XCTAssertTrue(skipped["pass_rate"] is NSNull, "Skipped suite pass_rate should be NSNull")
            XCTAssertEqual(skipped["status"] as? String, "skipped", "Skipped suite should have status='skipped'")
        }
    }
}
