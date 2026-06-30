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

// MARK: - MetricsStore Tests (Swift Testing)

/// Comprehensive tests for `MetricsStore` covering:
/// - Initialization with custom file URLs
/// - JSON persistence (load/append round-trip)
/// - Query methods (lastEntries, entries by model, average speed, trends, unique models)
/// - JSONL streaming (appendTurn, appendRaw, clear)
///
/// Each test uses an isolated temp directory to avoid cross-test interference.
/// The `createEntry(from:)` static factory is intentionally skipped because it
/// depends on `LiteRTLM.BenchmarkInfo` which cannot be constructed in unit tests.
@Suite("MetricsStore")
struct MetricsStoreSwiftTestingTests {

    // MARK: - Test Helpers

    /// Creates a `MetricsStore` backed by a unique temp file.
    /// Returns both the store and the temp directory URL for cleanup.
    private func makeTempStore() -> (store: MetricsStore, tempDir: URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MetricsStoreTests-\(UUID().uuidString)")
        let fileURL = tempDir
            .appendingPathComponent("metrics")
            .appendingPathComponent("history.json")
        let store = MetricsStore(fileURL: fileURL)
        return (store, tempDir)
    }

    /// Removes the temp directory after each test.
    private func cleanup(_ tempDir: URL) {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Creates a test `MetricsStore.Entry` with configurable values.
    private func makeEntry(
        model: String = "test-model",
        decodeSpeed: Double = 100.0,
        timestamp: String = "2026-06-19T12:00:00.000Z"
    ) -> MetricsStore.Entry {
        MetricsStore.Entry(
            timestamp: timestamp,
            model: model,
            platform: "macOS",
            device: "Test Mac",
            metrics: MetricsStore.Entry.Metrics(
                initTimeSeconds: 2.5,
                ttftSeconds: 0.15,
                decodeTokensPerSecond: decodeSpeed,
                prefillTokensPerSecond: 200.0,
                lastPrefillTokenCount: 10,
                lastDecodeTokenCount: 256,
                thermalStateAtStart: nil,
                thermalStateAtEnd: nil,
                availableMemoryAtStartMB: nil,
                availableMemoryAtEndMB: nil,
                medianTokenLatencyMs: nil,
                p95TokenLatencyMs: nil,
                decodeLatenciesMs: nil,
                latencyHistogram: nil,
                thermalTransitions: nil,
                estimatedMemoryBandwidthGBps: nil,
                modelLoadDurationMs: nil,
                gpuAllocatedMemoryAtStartMB: nil,
                gpuAllocatedMemoryAtEndMB: nil
            ),
            flags: ExperimentalFlagsState(
                enableBenchmark: false,
                enableSpeculativeDecoding: nil,
                enableConversationConstrainedDecoding: false,
                visualTokenBudget: nil
            )
        )
    }

    /// Creates a test `MetricsStore.Entry` with all optional metrics populated.
    private func makeDetailedEntry(
        model: String = "detailed-model",
        decodeSpeed: Double = 150.0
    ) -> MetricsStore.Entry {
        MetricsStore.Entry(
            timestamp: "2026-06-19T14:30:00.000Z",
            model: model,
            platform: "iOS",
            device: "iPhone16,2",
            metrics: MetricsStore.Entry.Metrics(
                initTimeSeconds: 3.2,
                ttftSeconds: 0.22,
                decodeTokensPerSecond: decodeSpeed,
                prefillTokensPerSecond: 350.0,
                lastPrefillTokenCount: 20,
                lastDecodeTokenCount: 512,
                thermalStateAtStart: "nominal",
                thermalStateAtEnd: "fair",
                availableMemoryAtStartMB: 2048.0,
                availableMemoryAtEndMB: 1536.0,
                medianTokenLatencyMs: 6.5,
                p95TokenLatencyMs: 12.3,
                decodeLatenciesMs: [5.0, 6.0, 6.5, 7.0, 12.3],
                latencyHistogram: ["0-10ms": 5, "10-20ms": 0, "20-50ms": 0, "50-100ms": 0, "100-200ms": 0, "200ms+": 0],
                thermalTransitions: nil,
                estimatedMemoryBandwidthGBps: 0.5,
                modelLoadDurationMs: 3200.0,
                gpuAllocatedMemoryAtStartMB: nil,
                gpuAllocatedMemoryAtEndMB: nil
            ),
            flags: ExperimentalFlagsState(
                enableBenchmark: true,
                enableSpeculativeDecoding: true,
                enableConversationConstrainedDecoding: true,
                visualTokenBudget: 256
            )
        )
    }

    // MARK: - Init

    @Test("Custom fileURL constructor sets storage location")
    func testInitWithCustomURL() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        // Store should be usable immediately — no file needs to exist yet
        let entries = try store.loadEntries()
        #expect(entries.isEmpty)
    }

    // MARK: - loadEntries

    @Test("loadEntries returns empty array when file does not exist")
    func testLoadEntriesEmptyWhenNoFile() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let entries = try store.loadEntries()
        #expect(entries.isEmpty)
    }

    @Test("loadEntries returns persisted entries after append")
    func testLoadEntriesReturnsPersisted() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let entry = makeEntry()
        try store.append(entry: entry)

        let loaded = try store.loadEntries()
        #expect(loaded.count == 1)
        #expect(loaded[0].model == "test-model")
        #expect(loaded[0].platform == "macOS")
        #expect(loaded[0].device == "Test Mac")
        #expect(loaded[0].metrics.decodeTokensPerSecond == 100.0)
    }

    // MARK: - append

    @Test("append creates directory structure and persists entry")
    func testAppendCreatesDirectoryAndPersists() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let entry = makeEntry()
        try store.append(entry: entry)

        // Verify directory was created
        let metricsDir = tempDir.appendingPathComponent("metrics")
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: metricsDir.path, isDirectory: &isDir))
        #expect(isDir.boolValue)

        // Verify file contents
        let loaded = try store.loadEntries()
        #expect(loaded.count == 1)
    }

    @Test("append accumulates multiple entries")
    func testAppendAccumulatesEntries() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        try store.append(entry: makeEntry(model: "model-a", decodeSpeed: 80.0))
        try store.append(entry: makeEntry(model: "model-b", decodeSpeed: 120.0))
        try store.append(entry: makeEntry(model: "model-a", decodeSpeed: 90.0))

        let loaded = try store.loadEntries()
        #expect(loaded.count == 3)
        #expect(loaded[0].model == "model-a")
        #expect(loaded[1].model == "model-b")
        #expect(loaded[2].model == "model-a")
    }

    @Test("append preserves all Entry fields through round-trip")
    func testAppendPreservesAllFields() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let entry = makeDetailedEntry()
        try store.append(entry: entry)

        let loaded = try store.loadEntries()
        #expect(loaded.count == 1)

        let e = loaded[0]
        #expect(e.timestamp == "2026-06-19T14:30:00.000Z")
        #expect(e.model == "detailed-model")
        #expect(e.platform == "iOS")
        #expect(e.device == "iPhone16,2")
        #expect(e.metrics.initTimeSeconds == 3.2)
        #expect(e.metrics.ttftSeconds == 0.22)
        #expect(e.metrics.decodeTokensPerSecond == 150.0)
        #expect(e.metrics.prefillTokensPerSecond == 350.0)
        #expect(e.metrics.lastPrefillTokenCount == 20)
        #expect(e.metrics.lastDecodeTokenCount == 512)
        #expect(e.metrics.thermalStateAtStart == "nominal")
        #expect(e.metrics.thermalStateAtEnd == "fair")
        #expect(e.metrics.availableMemoryAtStartMB == 2048.0)
        #expect(e.metrics.availableMemoryAtEndMB == 1536.0)
        #expect(e.metrics.medianTokenLatencyMs == 6.5)
        #expect(e.metrics.p95TokenLatencyMs == 12.3)
        #expect(e.metrics.decodeLatenciesMs == [5.0, 6.0, 6.5, 7.0, 12.3])

        // Flags round-trip
        #expect(e.flags.enableBenchmark == true)
        #expect(e.flags.enableSpeculativeDecoding == true)
        #expect(e.flags.enableConversationConstrainedDecoding == true)
        #expect(e.flags.visualTokenBudget == 256)
    }

    // MARK: - lastEntries

    @Test("lastEntries returns suffix of requested count")
    func testLastEntriesReturnsSuffix() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        for i in 1...5 {
            try store.append(entry: makeEntry(
                model: "model-\(i)",
                decodeSpeed: Double(i * 10)
            ))
        }

        let last3 = try store.lastEntries(3)
        #expect(last3.count == 3)
        #expect(last3[0].model == "model-3")
        #expect(last3[1].model == "model-4")
        #expect(last3[2].model == "model-5")
    }

    @Test("lastEntries returns all when count exceeds total")
    func testLastEntriesReturnsAllWhenCountExceedsTotal() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        try store.append(entry: makeEntry(model: "only-one"))

        let result = try store.lastEntries(10)
        #expect(result.count == 1)
        #expect(result[0].model == "only-one")
    }

    @Test("lastEntries returns empty for empty store")
    func testLastEntriesEmptyStore() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let result = try store.lastEntries(5)
        #expect(result.isEmpty)
    }

    // MARK: - entries(forModel:)

    @Test("entries(forModel:) filters by exact model name")
    func testEntriesForModelFilters() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        try store.append(entry: makeEntry(model: "gemma-2b"))
        try store.append(entry: makeEntry(model: "gemma-7b"))
        try store.append(entry: makeEntry(model: "gemma-2b"))
        try store.append(entry: makeEntry(model: "phi-3"))

        let gemma2b = try store.entries(forModel: "gemma-2b")
        #expect(gemma2b.count == 2)
        #expect(gemma2b.allSatisfy { $0.model == "gemma-2b" })

        let phi3 = try store.entries(forModel: "phi-3")
        #expect(phi3.count == 1)
    }

    @Test("entries(forModel:) returns empty for non-existent model")
    func testEntriesForModelReturnsEmptyForMissing() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        try store.append(entry: makeEntry(model: "gemma-2b"))

        let result = try store.entries(forModel: "nonexistent-model")
        #expect(result.isEmpty)
    }

    // MARK: - averageDecodeSpeed

    @Test("averageDecodeSpeed computes correct average across all entries")
    func testAverageDecodeSpeedAllEntries() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        try store.append(entry: makeEntry(decodeSpeed: 80.0))
        try store.append(entry: makeEntry(decodeSpeed: 120.0))
        try store.append(entry: makeEntry(decodeSpeed: 100.0))

        let avg = try store.averageDecodeSpeed()
        #expect(avg == 100.0)
    }

    @Test("averageDecodeSpeed filters by model when specified")
    func testAverageDecodeSpeedFilteredByModel() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        try store.append(entry: makeEntry(model: "fast", decodeSpeed: 200.0))
        try store.append(entry: makeEntry(model: "fast", decodeSpeed: 300.0))
        try store.append(entry: makeEntry(model: "slow", decodeSpeed: 50.0))

        let avgFast = try store.averageDecodeSpeed(forModel: "fast")
        #expect(avgFast == 250.0)

        let avgSlow = try store.averageDecodeSpeed(forModel: "slow")
        #expect(avgSlow == 50.0)
    }

    @Test("averageDecodeSpeed returns 0 for empty store")
    func testAverageDecodeSpeedEmptyStore() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let avg = try store.averageDecodeSpeed()
        #expect(avg == 0)
    }

    @Test("averageDecodeSpeed returns 0 for non-existent model")
    func testAverageDecodeSpeedNonExistentModel() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        try store.append(entry: makeEntry(model: "exists", decodeSpeed: 100.0))

        let avg = try store.averageDecodeSpeed(forModel: "does-not-exist")
        #expect(avg == 0)
    }

    // MARK: - decodeSpeedTrend

    @Test("decodeSpeedTrend returns indexed tuples for all entries")
    func testDecodeSpeedTrendAllEntries() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        try store.append(entry: makeEntry(model: "m1", decodeSpeed: 10.0))
        try store.append(entry: makeEntry(model: "m2", decodeSpeed: 20.0))
        try store.append(entry: makeEntry(model: "m1", decodeSpeed: 30.0))

        let trend = try store.decodeSpeedTrend()
        #expect(trend.count == 3)
        #expect(trend[0].index == 0)
        #expect(trend[0].speed == 10.0)
        #expect(trend[0].model == "m1")
        #expect(trend[1].index == 1)
        #expect(trend[1].speed == 20.0)
        #expect(trend[2].index == 2)
        #expect(trend[2].speed == 30.0)
    }

    @Test("decodeSpeedTrend filters by model")
    func testDecodeSpeedTrendFilteredByModel() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        try store.append(entry: makeEntry(model: "alpha", decodeSpeed: 50.0))
        try store.append(entry: makeEntry(model: "beta", decodeSpeed: 60.0))
        try store.append(entry: makeEntry(model: "alpha", decodeSpeed: 70.0))

        let trend = try store.decodeSpeedTrend(forModel: "alpha")
        #expect(trend.count == 2)
        #expect(trend[0].speed == 50.0)
        #expect(trend[1].speed == 70.0)
        #expect(trend.allSatisfy { $0.model == "alpha" })
    }

    @Test("decodeSpeedTrend respects lastN limit")
    func testDecodeSpeedTrendRespectsLastN() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        for i in 1...10 {
            try store.append(entry: makeEntry(decodeSpeed: Double(i * 10)))
        }

        let trend = try store.decodeSpeedTrend(lastN: 3)
        #expect(trend.count == 3)
        // Should be the last 3: speeds 80, 90, 100
        #expect(trend[0].speed == 80.0)
        #expect(trend[1].speed == 90.0)
        #expect(trend[2].speed == 100.0)
        // Indices should be re-enumerated from 0
        #expect(trend[0].index == 0)
        #expect(trend[1].index == 1)
        #expect(trend[2].index == 2)
    }

    @Test("decodeSpeedTrend returns empty for empty store")
    func testDecodeSpeedTrendEmptyStore() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let trend = try store.decodeSpeedTrend()
        #expect(trend.isEmpty)
    }

    // MARK: - uniqueModels

    @Test("uniqueModels returns deduplicated sorted model names")
    func testUniqueModelsSortedAndDeduplicated() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        try store.append(entry: makeEntry(model: "gemma-7b"))
        try store.append(entry: makeEntry(model: "phi-3"))
        try store.append(entry: makeEntry(model: "gemma-2b"))
        try store.append(entry: makeEntry(model: "gemma-7b"))  // duplicate
        try store.append(entry: makeEntry(model: "phi-3"))      // duplicate

        let models = try store.uniqueModels()
        #expect(models == ["gemma-2b", "gemma-7b", "phi-3"])
    }

    @Test("uniqueModels returns empty for empty store")
    func testUniqueModelsEmptyStore() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let models = try store.uniqueModels()
        #expect(models.isEmpty)
    }

    @Test("uniqueModels with single model returns single-element array")
    func testUniqueModelsSingleModel() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        try store.append(entry: makeEntry(model: "only-model"))
        try store.append(entry: makeEntry(model: "only-model"))

        let models = try store.uniqueModels()
        #expect(models == ["only-model"])
    }

    // MARK: - JSONL Streaming: appendTurnToJSONL

    @Test("appendTurnToJSONL creates JSONL file with valid JSON line")
    func testAppendTurnToJSONLCreatesFile() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let entry = makeEntry()
        store.appendTurnToJSONL(
            entry,
            runId: "run-001",
            configId: "config-A",
            turnIndex: 0
        )

        // The JSONL file should exist alongside history.json
        let jsonlURL = tempDir
            .appendingPathComponent("metrics")
            .appendingPathComponent("benchmark-results.jsonl")
        #expect(FileManager.default.fileExists(atPath: jsonlURL.path))

        // Each line should be valid JSON
        let content = try String(contentsOf: jsonlURL, encoding: .utf8)
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 1)

        // Parse the line as JSON and verify TurnEntry fields
        let lineData = try #require(lines[0].data(using: .utf8))
        let decoded = try JSONDecoder().decode(MetricsStore.TurnEntry.self, from: lineData)
        #expect(decoded.runId == "run-001")
        #expect(decoded.configId == "config-A")
        #expect(decoded.turnIndex == 0)
        #expect(decoded.entry.model == "test-model")
        #expect(decoded.entry.metrics.decodeTokensPerSecond == 100.0)
    }

    @Test("appendTurnToJSONL appends multiple lines incrementally")
    func testAppendTurnToJSONLMultipleLines() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        for i in 0..<3 {
            store.appendTurnToJSONL(
                makeEntry(model: "turn-model-\(i)"),
                runId: "run-002",
                configId: "config-B",
                turnIndex: i
            )
        }

        let jsonlURL = tempDir
            .appendingPathComponent("metrics")
            .appendingPathComponent("benchmark-results.jsonl")
        let content = try String(contentsOf: jsonlURL, encoding: .utf8)
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 3)

        // Verify each line has the correct turn index
        for (i, line) in lines.enumerated() {
            let lineData = try #require(line.data(using: .utf8))
            let decoded = try JSONDecoder().decode(MetricsStore.TurnEntry.self, from: lineData)
            #expect(decoded.turnIndex == i)
            #expect(decoded.entry.model == "turn-model-\(i)")
        }
    }

    // MARK: - JSONL Streaming: appendRawJSONL

    @Test("appendRawJSONL creates file and appends raw JSON string")
    func testAppendRawJSONLCreatesFile() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        store.appendRawJSONL(#"{"event":"warmup","status":"started"}"#)

        let jsonlURL = tempDir
            .appendingPathComponent("metrics")
            .appendingPathComponent("benchmark-results.jsonl")
        #expect(FileManager.default.fileExists(atPath: jsonlURL.path))

        let content = try String(contentsOf: jsonlURL, encoding: .utf8)
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 1)
        #expect(lines[0] == #"{"event":"warmup","status":"started"}"#)
    }

    @Test("appendRawJSONL appends to existing file")
    func testAppendRawJSONLAppendsToExisting() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        store.appendRawJSONL(#"{"line":1}"#)
        store.appendRawJSONL(#"{"line":2}"#)
        store.appendRawJSONL(#"{"line":3}"#)

        let jsonlURL = tempDir
            .appendingPathComponent("metrics")
            .appendingPathComponent("benchmark-results.jsonl")
        let content = try String(contentsOf: jsonlURL, encoding: .utf8)
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 3)
        #expect(lines[0] == #"{"line":1}"#)
        #expect(lines[1] == #"{"line":2}"#)
        #expect(lines[2] == #"{"line":3}"#)
    }

    @Test("appendRawJSONL and appendTurnToJSONL share the same file")
    func testRawAndTurnShareSameJSONLFile() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        store.appendRawJSONL(#"{"event":"start"}"#)
        store.appendTurnToJSONL(
            makeEntry(),
            runId: "shared-run",
            configId: "shared-config",
            turnIndex: 0
        )
        store.appendRawJSONL(#"{"event":"end"}"#)

        let jsonlURL = tempDir
            .appendingPathComponent("metrics")
            .appendingPathComponent("benchmark-results.jsonl")
        let content = try String(contentsOf: jsonlURL, encoding: .utf8)
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        #expect(lines.count == 3)
    }

    // MARK: - JSONL Streaming: clearJSONLFile

    @Test("clearJSONLFile removes the JSONL file")
    func testClearJSONLFileRemovesFile() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        // Write some data first
        store.appendRawJSONL(#"{"data":"test"}"#)

        let jsonlURL = tempDir
            .appendingPathComponent("metrics")
            .appendingPathComponent("benchmark-results.jsonl")
        #expect(FileManager.default.fileExists(atPath: jsonlURL.path))

        // Clear should remove the file
        store.clearJSONLFile()
        #expect(!FileManager.default.fileExists(atPath: jsonlURL.path))
    }

    @Test("clearJSONLFile is safe to call when file does not exist")
    func testClearJSONLFileNoOpWhenMissing() {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        // Should not throw or crash
        store.clearJSONLFile()
    }

    @Test("clearJSONLFile does not affect history.json")
    func testClearJSONLFilePreservesHistoryJSON() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        // Append to history.json
        try store.append(entry: makeEntry())

        // Write and clear JSONL
        store.appendRawJSONL(#"{"data":"ephemeral"}"#)
        store.clearJSONLFile()

        // history.json should still be intact
        let loaded = try store.loadEntries()
        #expect(loaded.count == 1)
    }

    // MARK: - Edge Cases

    @Test("Multiple stores with different file URLs are independent")
    func testMultipleStoresAreIndependent() throws {
        let (store1, tempDir1) = makeTempStore()
        let (store2, tempDir2) = makeTempStore()
        defer {
            cleanup(tempDir1)
            cleanup(tempDir2)
        }

        try store1.append(entry: makeEntry(model: "store1-model"))
        try store2.append(entry: makeEntry(model: "store2-model"))

        let entries1 = try store1.loadEntries()
        let entries2 = try store2.loadEntries()
        #expect(entries1.count == 1)
        #expect(entries1[0].model == "store1-model")
        #expect(entries2.count == 1)
        #expect(entries2[0].model == "store2-model")
    }

    @Test("Entries with nil optional metrics decode correctly")
    func testNilOptionalMetricsRoundTrip() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let entry = makeEntry()  // all optionals are nil
        try store.append(entry: entry)

        let loaded = try store.loadEntries()
        #expect(loaded.count == 1)
        #expect(loaded[0].metrics.thermalStateAtStart == nil)
        #expect(loaded[0].metrics.thermalStateAtEnd == nil)
        #expect(loaded[0].metrics.availableMemoryAtStartMB == nil)
        #expect(loaded[0].metrics.availableMemoryAtEndMB == nil)
        #expect(loaded[0].metrics.medianTokenLatencyMs == nil)
        #expect(loaded[0].metrics.p95TokenLatencyMs == nil)
        #expect(loaded[0].metrics.decodeLatenciesMs == nil)
    }

    @Test("Large batch of entries persists and queries correctly")
    func testLargeBatchPersistence() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let count = 50
        for i in 0..<count {
            try store.append(entry: makeEntry(
                model: i % 2 == 0 ? "even-model" : "odd-model",
                decodeSpeed: Double(i)
            ))
        }

        let all = try store.loadEntries()
        #expect(all.count == count)

        let evenEntries = try store.entries(forModel: "even-model")
        #expect(evenEntries.count == 25)

        let oddEntries = try store.entries(forModel: "odd-model")
        #expect(oddEntries.count == 25)

        let models = try store.uniqueModels()
        #expect(models == ["even-model", "odd-model"])

        // Average of 0,2,4,...,48 = 24.0
        let evenAvg = try store.averageDecodeSpeed(forModel: "even-model")
        #expect(evenAvg == 24.0)

        // Average of 1,3,5,...,49 = 25.0
        let oddAvg = try store.averageDecodeSpeed(forModel: "odd-model")
        #expect(oddAvg == 25.0)
    }

    @Test("decodeSpeedTrend with lastN greater than available returns all")
    func testDecodeSpeedTrendLastNGreaterThanAvailable() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        try store.append(entry: makeEntry(decodeSpeed: 42.0))
        try store.append(entry: makeEntry(decodeSpeed: 84.0))

        let trend = try store.decodeSpeedTrend(lastN: 100)
        #expect(trend.count == 2)
        #expect(trend[0].speed == 42.0)
        #expect(trend[1].speed == 84.0)
    }

    // MARK: - createEntry(from: EnginePerformanceMetrics)

    @Test("createEntry from EnginePerformanceMetrics maps fields correctly")
    func testCreateEntryFromEnginePerformanceMetrics() {
        let metrics = EnginePerformanceMetrics(
            tokensPerSecond: 45.2,
            promptTokensPerSecond: 120.5,
            timeToFirstToken: 0.35,
            peakMemoryBytes: nil,
            tokenCount: 128,
            memoryDeltaMB: nil,
            thermalStateChanged: nil,
            runtimeType: .mlx
        )

        let entry = MetricsStore.createEntry(
            from: metrics,
            modelName: "gemma-4-e2b-it-4bit",
            runtimeType: .mlx
        )

        // Core metrics should map directly
        #expect(entry.metrics.decodeTokensPerSecond == 45.2)
        #expect(entry.metrics.prefillTokensPerSecond == 120.5)
        #expect(entry.metrics.ttftSeconds == 0.35)
        #expect(entry.metrics.lastDecodeTokenCount == 128)

        // Model name should include runtime type tag
        #expect(entry.model == "gemma-4-e2b-it-4bit [MLX]")

        // Fields not tracked by EnginePerformanceMetrics
        #expect(entry.metrics.initTimeSeconds == 0)
        #expect(entry.metrics.lastPrefillTokenCount == 0)
        #expect(entry.metrics.thermalStateAtStart == nil)
        #expect(entry.metrics.thermalStateAtEnd == nil)
        #expect(entry.metrics.medianTokenLatencyMs == nil)
        #expect(entry.metrics.p95TokenLatencyMs == nil)
        #expect(entry.metrics.decodeLatenciesMs == nil)

        // Platform should be set
        #if os(macOS)
        #expect(entry.platform == "macOS")
        #elseif os(iOS)
        #expect(entry.platform == "iOS")
        #endif

        // Flags should have benchmark enabled
        #expect(entry.flags.enableBenchmark == true)
    }

    @Test("createEntry from EnginePerformanceMetrics handles nil optional fields")
    func testCreateEntryFromEnginePerformanceMetricsNils() {
        let metrics = EnginePerformanceMetrics(
            tokensPerSecond: 30.0,
            promptTokensPerSecond: nil,
            timeToFirstToken: nil,
            peakMemoryBytes: nil,
            tokenCount: nil,
            memoryDeltaMB: nil,
            thermalStateChanged: nil,
            runtimeType: .litertlm
        )

        let entry = MetricsStore.createEntry(
            from: metrics,
            modelName: "gemma-2b",
            runtimeType: .litertlm
        )

        #expect(entry.metrics.decodeTokensPerSecond == 30.0)
        #expect(entry.metrics.prefillTokensPerSecond == 0)  // nil → 0
        #expect(entry.metrics.ttftSeconds == 0)              // nil → 0
        #expect(entry.metrics.lastDecodeTokenCount == 0)     // nil → 0
        #expect(entry.model == "gemma-2b [LiteRT-LM]")
    }

    @Test("createEntry from EnginePerformanceMetrics persists and loads correctly")
    func testCreateEntryFromEnginePerformanceMetricsRoundTrip() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let metrics = EnginePerformanceMetrics(
            tokensPerSecond: 55.8,
            promptTokensPerSecond: 200.3,
            timeToFirstToken: 0.12,
            peakMemoryBytes: 4_000_000_000,
            tokenCount: 256,
            memoryDeltaMB: 1.5,
            thermalStateChanged: false,
            runtimeType: .mlx
        )

        let entry = MetricsStore.createEntry(
            from: metrics,
            modelName: "test-mlx-model",
            runtimeType: .mlx
        )

        try store.append(entry: entry)

        let loaded = try store.loadEntries()
        #expect(loaded.count == 1)
        #expect(loaded[0].metrics.decodeTokensPerSecond == 55.8)
        #expect(loaded[0].metrics.prefillTokensPerSecond == 200.3)
        #expect(loaded[0].metrics.ttftSeconds == 0.12)
        #expect(loaded[0].metrics.lastDecodeTokenCount == 256)
        #expect(loaded[0].model == "test-mlx-model [MLX]")
    }
}
