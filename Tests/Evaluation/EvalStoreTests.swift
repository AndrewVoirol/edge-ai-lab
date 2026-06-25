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
import XCTest

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Tests for `EvalStore` — the JSON file-based persistence layer for evaluation runs.
///
/// Uses a temporary directory for each test to ensure isolation and prevent
/// interference with real eval storage.
final class EvalStoreTests: XCTestCase {

    /// Temporary directory for test storage — cleaned up in tearDown.
    private var tempDir: URL!
    private var store: EvalStore!

    @MainActor
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EvalStoreTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = EvalStore(storageDirectory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Save & Load

    @MainActor
    func testSaveAndLoad() throws {
        let run = makeTestRun(suiteName: "Test Save & Load")
        try store.save(run)

        let loaded = try store.load(id: run.id)
        XCTAssertEqual(loaded.id, run.id)
        XCTAssertEqual(loaded.suiteName, run.suiteName)
        XCTAssertEqual(loaded.platform, run.platform)
        XCTAssertEqual(loaded.deviceName, run.deviceName)
    }

    @MainActor
    func testSaveUpdatesIndex() throws {
        let run = makeTestRun(suiteName: "Index Test")
        XCTAssertTrue(store.indexEntries.isEmpty)

        try store.save(run)
        XCTAssertEqual(store.indexEntries.count, 1)
        XCTAssertEqual(store.indexEntries.first?.suiteName, "Index Test")
    }

    @MainActor
    func testSaveExistingUpdatesInPlace() throws {
        var run = makeTestRun(suiteName: "Version 1")
        try store.save(run)
        XCTAssertEqual(store.indexEntries.count, 1)

        run.completedAt = Date()
        try store.save(run)
        XCTAssertEqual(store.indexEntries.count, 1)
    }

    // MARK: - Delete

    @MainActor
    func testDeleteRemovesFileAndIndex() throws {
        let run = makeTestRun(suiteName: "Delete Me")
        try store.save(run)
        XCTAssertEqual(store.indexEntries.count, 1)

        try store.delete(id: run.id)
        XCTAssertEqual(store.indexEntries.count, 0)

        XCTAssertThrowsError(try store.load(id: run.id))
    }

    @MainActor
    func testDeleteNonexistentDoesNotThrow() throws {
        try store.delete(id: UUID())
    }

    // MARK: - List

    @MainActor
    func testListReturnsIndexEntries() throws {
        for i in 0..<3 {
            let run = makeTestRun(suiteName: "Run \(i)")
            try store.save(run)
        }
        XCTAssertEqual(store.list().count, 3)
    }

    // MARK: - Index Sorting

    @MainActor
    func testIndexSortedByStartedAtDescending() throws {
        let earlier = makeTestRun(
            suiteName: "Earlier",
            startedAt: Date(timeIntervalSinceNow: -3600)
        )
        let later = makeTestRun(
            suiteName: "Later",
            startedAt: Date()
        )

        try store.save(earlier)
        try store.save(later)

        XCTAssertEqual(store.indexEntries.count, 2)
        XCTAssertEqual(store.indexEntries.first?.suiteName, "Later")
        XCTAssertEqual(store.indexEntries.last?.suiteName, "Earlier")
    }

    // MARK: - Export

    @MainActor
    func testExportJSON() throws {
        let run = makeTestRun(suiteName: "Export JSON")
        try store.save(run)

        let data = try store.exportJSON(id: run.id)
        XCTAssertGreaterThan(data.count, 0)

        // Verify it's valid JSON by decoding
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(EvalRun.self, from: data)
        XCTAssertEqual(decoded.id, run.id)
    }

    @MainActor
    func testExportCSV() throws {
        let promptResult = makeTestPromptResult(passed: true)
        let modelResult = makeTestModelResult(modelName: "CSV Model", promptResults: [promptResult])
        let run = makeTestRun(suiteName: "Export CSV", modelResults: [modelResult])
        try store.save(run)

        let data = try store.exportCSV(id: run.id)
        let csv = String(data: data, encoding: .utf8)!
        XCTAssertTrue(csv.contains("run_id"))
        XCTAssertTrue(csv.contains("suite_name"))
        XCTAssertTrue(csv.contains("CSV Model"))
    }

    @MainActor
    func testExportNonexistentThrows() {
        XCTAssertThrowsError(try store.exportJSON(id: UUID()))
    }

    // MARK: - Index Persistence

    @MainActor
    func testIndexPersistedAndReloaded() throws {
        let run = makeTestRun(suiteName: "Persist Index")
        try store.save(run)

        // Create a new store pointing at the same directory
        let store2 = EvalStore(storageDirectory: tempDir)
        XCTAssertEqual(store2.indexEntries.count, 1)
        XCTAssertEqual(store2.indexEntries.first?.suiteName, "Persist Index")
    }

    // MARK: - Load Nonexistent

    @MainActor
    func testLoadNonexistentThrows() {
        XCTAssertThrowsError(try store.load(id: UUID()))
    }

    // MARK: - Helpers

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
