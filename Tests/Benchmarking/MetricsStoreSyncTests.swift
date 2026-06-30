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

// MARK: - MetricsStore Sync Integration Tests

/// Tests for MetricsStore's CloudKit sync integration:
/// - Local save triggers push (sync manager wiring)
/// - JSON backward compatibility (old history.json without id/syncDeviceInfo fields)
/// - Entry UUID round-trip through JSON
/// - syncDeviceInfo round-trip through JSON
@Suite("MetricsStoreSync")
struct MetricsStoreSyncTests {

    // MARK: - Test Helpers

    private func makeTempStore() -> (store: MetricsStore, tempDir: URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MetricsStoreSyncTests-\(UUID().uuidString)")
        let fileURL = tempDir
            .appendingPathComponent("metrics")
            .appendingPathComponent("history.json")
        let store = MetricsStore(fileURL: fileURL)
        return (store, tempDir)
    }

    private func cleanup(_ tempDir: URL) {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeEntry(
        id: String = UUID().uuidString,
        model: String = "test-model",
        decodeSpeed: Double = 100.0,
        syncDeviceInfo: DeviceInfo? = nil
    ) -> MetricsStore.Entry {
        MetricsStore.Entry(
            id: id,
            timestamp: "2026-06-28T12:00:00.000Z",
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
            flags: RuntimeFlags(
                enableBenchmark: false,
                enableSpeculativeDecoding: nil,
                enableConversationConstrainedDecoding: false,
                visualTokenBudget: nil
            ),
            syncDeviceInfo: syncDeviceInfo
        )
    }

    // MARK: - JSON Backward Compatibility

    @Test("Old JSON without id field decodes with auto-generated id")
    func testOldJSONWithoutIdField() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        // Write JSON in the old format (no id, no syncDeviceInfo)
        let oldFormatJSON = """
        [
            {
                "timestamp": "2026-06-19T12:00:00.000Z",
                "model": "old-model",
                "platform": "macOS",
                "device": "Old Mac",
                "metrics": {
                    "initTimeSeconds": 2.5,
                    "ttftSeconds": 0.15,
                    "decodeTokensPerSecond": 100.0,
                    "prefillTokensPerSecond": 200.0,
                    "lastPrefillTokenCount": 10,
                    "lastDecodeTokenCount": 256
                },
                "flags": {
                    "enableBenchmark": false,
                    "enableConversationConstrainedDecoding": false
                }
            }
        ]
        """

        // Write directly to the file
        let fileURL = tempDir
            .appendingPathComponent("metrics")
            .appendingPathComponent("history.json")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try oldFormatJSON.data(using: .utf8)!.write(to: fileURL)

        // Load should succeed
        let entries = try store.loadEntries()
        #expect(entries.count == 1)
        #expect(entries[0].model == "old-model")
        #expect(!entries[0].id.isEmpty)  // Auto-generated
        #expect(entries[0].syncDeviceInfo == nil)
    }

    @Test("New JSON with id and syncDeviceInfo decodes correctly")
    func testNewJSONWithSyncFields() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let newFormatJSON = """
        [
            {
                "id": "explicit-uuid-123",
                "timestamp": "2026-06-28T12:00:00.000Z",
                "model": "new-model",
                "platform": "macOS",
                "device": "New Mac",
                "metrics": {
                    "initTimeSeconds": 2.5,
                    "ttftSeconds": 0.15,
                    "decodeTokensPerSecond": 100.0,
                    "prefillTokensPerSecond": 200.0,
                    "lastPrefillTokenCount": 10,
                    "lastDecodeTokenCount": 256
                },
                "flags": {
                    "enableBenchmark": false,
                    "enableConversationConstrainedDecoding": false
                },
                "syncDeviceInfo": {
                    "deviceName": "Andrew's iPhone",
                    "deviceModel": "iPhone17,2",
                    "osVersion": "iOS 26.5",
                    "appVersion": "1.0.0"
                }
            }
        ]
        """

        let fileURL = tempDir
            .appendingPathComponent("metrics")
            .appendingPathComponent("history.json")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try newFormatJSON.data(using: .utf8)!.write(to: fileURL)

        let entries = try store.loadEntries()
        #expect(entries.count == 1)
        #expect(entries[0].id == "explicit-uuid-123")
        #expect(entries[0].syncDeviceInfo?.deviceName == "Andrew's iPhone")
        #expect(entries[0].syncDeviceInfo?.deviceModel == "iPhone17,2")
        #expect(entries[0].syncDeviceInfo?.osVersion == "iOS 26.5")
    }

    @Test("Mixed old and new format entries decode together")
    func testMixedFormatEntries() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let mixedJSON = """
        [
            {
                "timestamp": "2026-06-19T12:00:00.000Z",
                "model": "old-model",
                "platform": "macOS",
                "device": "Old Mac",
                "metrics": {
                    "initTimeSeconds": 2.5,
                    "ttftSeconds": 0.15,
                    "decodeTokensPerSecond": 100.0,
                    "prefillTokensPerSecond": 200.0,
                    "lastPrefillTokenCount": 10,
                    "lastDecodeTokenCount": 256
                },
                "flags": {
                    "enableBenchmark": false,
                    "enableConversationConstrainedDecoding": false
                }
            },
            {
                "id": "new-entry-id",
                "timestamp": "2026-06-28T12:00:00.000Z",
                "model": "new-model",
                "platform": "iOS",
                "device": "iPhone17,2",
                "metrics": {
                    "initTimeSeconds": 3.0,
                    "ttftSeconds": 0.2,
                    "decodeTokensPerSecond": 80.0,
                    "prefillTokensPerSecond": 150.0,
                    "lastPrefillTokenCount": 15,
                    "lastDecodeTokenCount": 128
                },
                "flags": {
                    "enableBenchmark": true,
                    "enableConversationConstrainedDecoding": false
                }
            }
        ]
        """

        let fileURL = tempDir
            .appendingPathComponent("metrics")
            .appendingPathComponent("history.json")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try mixedJSON.data(using: .utf8)!.write(to: fileURL)

        let entries = try store.loadEntries()
        #expect(entries.count == 2)
        #expect(!entries[0].id.isEmpty)  // Auto-generated for old entry
        #expect(entries[1].id == "new-entry-id")
    }

    // MARK: - Entry UUID Round-Trip

    @Test("Entry id survives JSON encode/decode round-trip")
    func testEntryIdJsonRoundTrip() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let entry = makeEntry(id: "round-trip-uuid")
        try store.append(entry: entry)

        let loaded = try store.loadEntries()
        #expect(loaded.count == 1)
        #expect(loaded[0].id == "round-trip-uuid")
    }

    @Test("Entry syncDeviceInfo survives JSON encode/decode round-trip")
    func testSyncDeviceInfoJsonRoundTrip() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let deviceInfo = DeviceInfo(
            deviceName: "Test iPhone",
            deviceModel: "iPhone17,2",
            osVersion: "iOS 26.5",
            appVersion: "1.0.0"
        )
        let entry = makeEntry(syncDeviceInfo: deviceInfo)
        try store.append(entry: entry)

        let loaded = try store.loadEntries()
        #expect(loaded.count == 1)
        #expect(loaded[0].syncDeviceInfo?.deviceName == "Test iPhone")
        #expect(loaded[0].syncDeviceInfo?.deviceModel == "iPhone17,2")
    }

    @Test("Entry without syncDeviceInfo has nil syncDeviceInfo after round-trip")
    func testNilSyncDeviceInfoRoundTrip() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let entry = makeEntry()
        try store.append(entry: entry)

        let loaded = try store.loadEntries()
        #expect(loaded.count == 1)
        #expect(loaded[0].syncDeviceInfo == nil)
    }

    // MARK: - Sync Manager Integration

    @Test("MetricsStore starts with nil syncManager")
    func testSyncManagerInitiallyNil() {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        #expect(store.syncManager == nil)
    }

    @Test("MetricsStore can assign syncManager")
    func testSyncManagerAssignment() {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let testDevice = DeviceInfo(
            deviceName: "Test Mac",
            deviceModel: "arm64",
            osVersion: "macOS 26.0",
            appVersion: "1.0.0"
        )
        let manager = CloudKitSyncManager(testingDeviceInfo: testDevice)
        store.syncManager = manager

        #expect(store.syncManager != nil)
    }

    // MARK: - Append with Default ID

    @Test("append generates unique IDs for entries without explicit id")
    func testAppendGeneratesUniqueIDs() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        // Create entries using the default init (no explicit id)
        let entry1 = MetricsStore.Entry(
            timestamp: "2026-06-28T12:00:00.000Z",
            model: "model-a",
            platform: "macOS",
            device: "Test Mac",
            metrics: MetricsStore.Entry.Metrics(
                initTimeSeconds: 2.5,
                ttftSeconds: 0.15,
                decodeTokensPerSecond: 100.0,
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
            flags: RuntimeFlags(
                enableBenchmark: false,
                enableSpeculativeDecoding: nil,
                enableConversationConstrainedDecoding: false,
                visualTokenBudget: nil
            )
        )

        let entry2 = MetricsStore.Entry(
            timestamp: "2026-06-28T13:00:00.000Z",
            model: "model-b",
            platform: "macOS",
            device: "Test Mac",
            metrics: MetricsStore.Entry.Metrics(
                initTimeSeconds: 3.0,
                ttftSeconds: 0.2,
                decodeTokensPerSecond: 120.0,
                prefillTokensPerSecond: 250.0,
                lastPrefillTokenCount: 15,
                lastDecodeTokenCount: 512,
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
            flags: RuntimeFlags(
                enableBenchmark: false,
                enableSpeculativeDecoding: nil,
                enableConversationConstrainedDecoding: false,
                visualTokenBudget: nil
            )
        )

        try store.append(entry: entry1)
        try store.append(entry: entry2)

        let loaded = try store.loadEntries()
        #expect(loaded.count == 2)
        #expect(loaded[0].id != loaded[1].id)
        #expect(!loaded[0].id.isEmpty)
        #expect(!loaded[1].id.isEmpty)
    }

    // MARK: - Existing Functionality Preserved

    @Test("Existing MetricsStore queries work with new id field")
    func testExistingQueriesWorkWithIdField() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        try store.append(entry: makeEntry(model: "gemma-2b", decodeSpeed: 80.0))
        try store.append(entry: makeEntry(model: "gemma-7b", decodeSpeed: 120.0))
        try store.append(entry: makeEntry(model: "gemma-2b", decodeSpeed: 90.0))

        // entries(forModel:) still works
        let gemma2b = try store.entries(forModel: "gemma-2b")
        #expect(gemma2b.count == 2)

        // averageDecodeSpeed still works
        let avg = try store.averageDecodeSpeed(forModel: "gemma-2b")
        #expect(avg == 85.0)

        // uniqueModels still works
        let models = try store.uniqueModels()
        #expect(models == ["gemma-2b", "gemma-7b"])
    }
}
