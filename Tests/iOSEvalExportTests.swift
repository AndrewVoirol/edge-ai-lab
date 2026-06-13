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
@testable import GemmaEdgeGallery_iOS
#elseif os(macOS)
@testable import GemmaEdgeGallery_macOS
#endif

/// Tests for iOS Eval Export functionality — verifying that `EvalStore`
/// can export eval runs as JSON and CSV data suitable for sharing.
final class iOSEvalExportTests: XCTestCase {

    /// Temporary directory for test storage — cleaned up in tearDown.
    private var tempDir: URL!
    private var store: EvalStore!

    @MainActor
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("iOSEvalExportTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = EvalStore(storageDirectory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Export JSON

    @MainActor
    func testEvalStoreExportJSONProducesData() throws {
        let run = makeTestRunWithResults()
        try store.save(run)

        let data = try store.exportJSON(id: run.id)
        XCTAssertGreaterThan(data.count, 0, "exportJSON should return non-empty Data")
    }

    // MARK: - Export CSV

    @MainActor
    func testEvalStoreExportCSVProducesData() throws {
        let run = makeTestRunWithResults()
        try store.save(run)

        let data = try store.exportCSV(id: run.id)
        XCTAssertGreaterThan(data.count, 0, "exportCSV should return non-empty Data")
    }

    // MARK: - CSV Header Row

    @MainActor
    func testExportCSVContainsHeaderRow() throws {
        let run = makeTestRunWithResults()
        try store.save(run)

        let data = try store.exportCSV(id: run.id)
        let csv = String(data: data, encoding: .utf8)!
        let lines = csv.components(separatedBy: "\n")

        // First line should be the header row
        let header = lines[0]
        let expectedColumns = [
            "run_id", "suite_name", "platform", "device",
            "model_name", "model_file", "prompt_text", "response",
            "passed", "score", "decode_speed_tps", "ttft_s",
            "tool_calls", "duration_s", "avg_decode_speed",
            "avg_ttft", "pass_rate",
        ]
        for column in expectedColumns {
            XCTAssertTrue(
                header.contains(column),
                "CSV header should contain column '\(column)' but was: \(header)"
            )
        }
    }

    // MARK: - Valid JSON

    @MainActor
    func testExportJSONIsValidJSON() throws {
        let run = makeTestRunWithResults()
        try store.save(run)

        let data = try store.exportJSON(id: run.id)

        // Verify the data is valid JSON via JSONSerialization
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        XCTAssertTrue(
            jsonObject is [String: Any],
            "Exported JSON should deserialize to a dictionary"
        )
    }

    // MARK: - Helpers

    /// Creates a test `EvalRun` populated with model and prompt results,
    /// suitable for export testing.
    private func makeTestRunWithResults() -> EvalRun {
        let promptResult = makeTestPromptResult(passed: true)
        let modelResult = makeTestModelResult(
            modelName: "Export Test Model",
            promptResults: [promptResult]
        )
        return makeTestRun(
            suiteName: "Export Test Suite",
            modelResults: [modelResult]
        )
    }

    private func makeTestRun(
        suiteName: String = "Test Suite",
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        modelResults: [ModelEvalResult] = []
    ) -> EvalRun {
        EvalRun(
            suiteId: UUID(),
            suiteName: suiteName,
            startedAt: startedAt,
            completedAt: completedAt,
            platform: "macOS",
            deviceName: "Test Mac",
            modelResults: modelResults
        )
    }

    private func makeTestModelResult(
        modelName: String = "Test Model",
        promptResults: [PromptEvalResult] = []
    ) -> ModelEvalResult {
        ModelEvalResult(
            modelName: modelName,
            modelFile: "test.litertlm",
            avgDecodeSpeed: 40.0,
            avgTTFT: 0.5,
            p95Latency: 25.0,
            totalTokensGenerated: 1000,
            totalDuration: 60.0,
            promptResults: promptResults
        )
    }

    private func makeTestPromptResult(passed: Bool = true) -> PromptEvalResult {
        PromptEvalResult(
            promptId: UUID(),
            promptText: "Test prompt",
            response: "Test response",
            passed: passed,
            score: passed ? .pass : .fail(reason: "Failed"),
            decodeSpeed: 40.0,
            ttft: 0.5,
            duration: 5.0
        )
    }
}
