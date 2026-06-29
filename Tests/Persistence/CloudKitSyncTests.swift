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

// MARK: - CloudKit Sync Tests

/// Tests for CloudKit sync logic:
/// - Merge deduplication by UUID
/// - Device grouping
/// - Sync status transitions
/// - Pending queue behavior
///
/// These tests focus on the testable logic rather than live CloudKit operations.
/// CloudKit API calls are tested via the MetricsStoreSyncTests integration layer.
@Suite("CloudKitSync")
struct CloudKitSyncTests {

    // MARK: - Test Helpers

    private func makeTempStore() -> (store: MetricsStore, tempDir: URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudKitSyncTests-\(UUID().uuidString)")
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
        device: String = "Test Mac",
        decodeSpeed: Double = 100.0,
        syncDeviceInfo: DeviceInfo? = nil
    ) -> MetricsStore.Entry {
        MetricsStore.Entry(
            id: id,
            timestamp: "2026-06-28T12:00:00.000Z",
            model: model,
            platform: "macOS",
            device: device,
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
            ),
            syncDeviceInfo: syncDeviceInfo
        )
    }

    // MARK: - Merge Deduplication Tests

    @Test("mergeRemoteEntries adds new entries")
    func testMergeAddsNewEntries() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let local = makeEntry(id: "local-1")
        try store.append(entry: local)

        let remote = [
            makeEntry(id: "remote-1"),
            makeEntry(id: "remote-2"),
        ]
        try store.mergeRemoteEntries(remote)

        let all = try store.loadEntries()
        #expect(all.count == 3)
    }

    @Test("mergeRemoteEntries deduplicates by UUID")
    func testMergeDeduplicatesByUUID() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let sharedID = "shared-uuid"
        let local = makeEntry(id: sharedID)
        try store.append(entry: local)

        let remote = [
            makeEntry(id: sharedID),  // Duplicate
            makeEntry(id: "new-remote"),
        ]
        try store.mergeRemoteEntries(remote)

        let all = try store.loadEntries()
        #expect(all.count == 2)

        let ids = Set(all.map(\.id))
        #expect(ids.contains(sharedID))
        #expect(ids.contains("new-remote"))
    }

    @Test("mergeRemoteEntries with all duplicates is a no-op")
    func testMergeAllDuplicatesIsNoOp() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let entry = makeEntry(id: "existing")
        try store.append(entry: entry)

        let remote = [makeEntry(id: "existing")]
        try store.mergeRemoteEntries(remote)

        let all = try store.loadEntries()
        #expect(all.count == 1)
    }

    @Test("mergeRemoteEntries with empty remote is a no-op")
    func testMergeEmptyRemoteIsNoOp() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let local = makeEntry(id: "local-1")
        try store.append(entry: local)

        try store.mergeRemoteEntries([])

        let all = try store.loadEntries()
        #expect(all.count == 1)
    }

    @Test("mergeRemoteEntries into empty store adds all")
    func testMergeIntoEmptyStore() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let remote = [
            makeEntry(id: "remote-1"),
            makeEntry(id: "remote-2"),
            makeEntry(id: "remote-3"),
        ]
        try store.mergeRemoteEntries(remote)

        let all = try store.loadEntries()
        #expect(all.count == 3)
    }

    @Test("mergeRemoteEntries preserves entry data fidelity")
    func testMergePreservesData() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let remote = [
            makeEntry(id: "data-fidelity", model: "special-model", decodeSpeed: 999.0)
        ]
        try store.mergeRemoteEntries(remote)

        let all = try store.loadEntries()
        #expect(all.count == 1)
        #expect(all[0].id == "data-fidelity")
        #expect(all[0].model == "special-model")
        #expect(all[0].metrics.decodeTokensPerSecond == 999.0)
    }

    // MARK: - Device Grouping Tests

    @Test("allDeviceEntries groups by device name")
    func testDeviceGrouping() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        try store.append(entry: makeEntry(id: "mac-1", device: "MacBook Pro"))
        try store.append(entry: makeEntry(id: "mac-2", device: "MacBook Pro"))
        try store.append(entry: makeEntry(id: "iphone-1", device: "iPhone"))
        try store.append(entry: makeEntry(id: "ipad-1", device: "iPad"))

        let grouped = store.allDeviceEntries
        #expect(grouped.count == 3)
        #expect(grouped["MacBook Pro"]?.count == 2)
        #expect(grouped["iPhone"]?.count == 1)
        #expect(grouped["iPad"]?.count == 1)
    }

    @Test("allDeviceEntries prefers syncDeviceInfo.deviceName for grouping")
    func testDeviceGroupingPrefersSyncDeviceInfo() throws {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let syncInfo = DeviceInfo(
            deviceName: "Andrew's MacBook Pro",
            deviceModel: "arm64",
            osVersion: "macOS 26.0",
            appVersion: "1.0.0"
        )

        try store.append(entry: makeEntry(id: "synced-1", device: "arm64", syncDeviceInfo: syncInfo))
        try store.append(entry: makeEntry(id: "local-1", device: "Test Mac"))

        let grouped = store.allDeviceEntries
        #expect(grouped.count == 2)
        #expect(grouped["Andrew's MacBook Pro"]?.count == 1)
        #expect(grouped["Test Mac"]?.count == 1)
    }

    @Test("allDeviceEntries returns empty for empty store")
    func testDeviceGroupingEmptyStore() {
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        let grouped = store.allDeviceEntries
        #expect(grouped.isEmpty)
    }

    // MARK: - SyncStatus Tests

    @Test("SyncStatus descriptions are human-readable")
    func testSyncStatusDescriptions() {
        #expect(SyncStatus.idle.description == "Up to date")
        #expect(SyncStatus.syncing.description == "Syncing…")
        #expect(SyncStatus.error("Network unavailable").description == "Error: Network unavailable")
    }

    @Test("SyncStatus equality works correctly")
    func testSyncStatusEquality() {
        #expect(SyncStatus.idle == SyncStatus.idle)
        #expect(SyncStatus.syncing == SyncStatus.syncing)
        #expect(SyncStatus.error("a") == SyncStatus.error("a"))
        #expect(SyncStatus.error("a") != SyncStatus.error("b"))
        #expect(SyncStatus.idle != SyncStatus.syncing)
    }

    // MARK: - CloudKitSyncManager State Tests

    @Test("CloudKitSyncManager initializes with idle status")
    func testSyncManagerInitialState() {
        // Use the testing init to avoid CKContainer entitlement crashes.
        // Real CKContainer integration is validated by manual iCloud sign-in testing.
        let testDevice = DeviceInfo(
            deviceName: "Test Mac",
            deviceModel: "arm64",
            osVersion: "macOS 26.0",
            appVersion: "1.0.0"
        )
        let manager = CloudKitSyncManager(testingDeviceInfo: testDevice)
        #expect(manager.syncStatus == .idle)
        #expect(manager.lastSyncDate == nil)
        #expect(manager.pendingCount == 0)
        #expect(!manager.isCloudKitAvailable)  // Testing init has no container
        #expect(!manager.isSyncEnabled)
    }

    @Test("CloudKitSyncManager testing init disables sync safely")
    func testSyncManagerTestingInitSafe() async throws {
        let testDevice = DeviceInfo(
            deviceName: "Test Mac",
            deviceModel: "arm64",
            osVersion: "macOS 26.0",
            appVersion: "1.0.0"
        )
        let manager = CloudKitSyncManager(testingDeviceInfo: testDevice)

        // All operations should safely no-op without CloudKit
        let fetched = try await manager.fetchAllEntries()
        #expect(fetched.isEmpty)
        try await manager.subscribeToChanges()
        try await manager.flushPendingQueue()
        #expect(manager.syncStatus == .idle)
    }

    // MARK: - Entry ID Generation Tests

    @Test("Entry auto-generates unique IDs when not specified")
    func testEntryAutoGeneratesID() {
        let entry1 = makeEntry()
        let entry2 = makeEntry()
        #expect(!entry1.id.isEmpty)
        #expect(!entry2.id.isEmpty)
        #expect(entry1.id != entry2.id)
    }

    @Test("Entry preserves explicit ID")
    func testEntryPreservesExplicitID() {
        let entry = makeEntry(id: "explicit-id-123")
        #expect(entry.id == "explicit-id-123")
    }
}
