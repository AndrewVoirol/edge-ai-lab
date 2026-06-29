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
import CloudKit

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - CloudKit Models Tests

/// Tests for `CloudKitModels` CKRecord conversion logic:
/// - Round-trip conversion (Entry → CKRecord → Entry)
/// - Optional field handling (nil fields survive round-trip)
/// - DeviceInfo tagging
/// - Nil safety for missing required fields
@Suite("CloudKitModels")
struct CloudKitModelsTests {

    // MARK: - Test Helpers

    private func makeTestDeviceInfo() -> DeviceInfo {
        DeviceInfo(
            deviceName: "Test MacBook Pro",
            deviceModel: "arm64",
            osVersion: "macOS 26.0",
            appVersion: "1.0.0"
        )
    }

    private func makeMinimalEntry(id: String = UUID().uuidString) -> MetricsStore.Entry {
        MetricsStore.Entry(
            id: id,
            timestamp: "2026-06-28T12:00:00.000Z",
            model: "gemma-4-1b",
            platform: "macOS",
            device: "Test Mac",
            metrics: MetricsStore.Entry.Metrics(
                initTimeSeconds: 2.5,
                ttftSeconds: 0.15,
                decodeTokensPerSecond: 45.0,
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

    private func makeFullEntry(id: String = UUID().uuidString) -> MetricsStore.Entry {
        MetricsStore.Entry(
            id: id,
            timestamp: "2026-06-28T14:30:00.000Z",
            model: "gemma-4-4b",
            platform: "iOS",
            device: "iPhone17,2",
            metrics: MetricsStore.Entry.Metrics(
                initTimeSeconds: 3.2,
                ttftSeconds: 0.22,
                decodeTokensPerSecond: 150.0,
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
                latencyHistogram: ["0-10ms": 4, "10-20ms": 1, "20-50ms": 0, "50-100ms": 0, "100-200ms": 0, "200ms+": 0],
                thermalTransitions: [
                    MetricsStore.ThermalTransitionRecord(from: "nominal", to: "fair", timestamp: "2026-06-28T14:31:00.000Z")
                ],
                estimatedMemoryBandwidthGBps: 0.5,
                modelLoadDurationMs: 3200.0,
                gpuAllocatedMemoryAtStartMB: 128.0,
                gpuAllocatedMemoryAtEndMB: 512.0
            ),
            flags: ExperimentalFlagsState(
                enableBenchmark: true,
                enableSpeculativeDecoding: true,
                enableConversationConstrainedDecoding: true,
                visualTokenBudget: 256
            )
        )
    }

    // MARK: - Round-Trip Tests

    @Test("Minimal entry survives CKRecord round-trip")
    func testMinimalEntryRoundTrip() {
        let original = makeMinimalEntry(id: "test-id-001")
        let deviceInfo = makeTestDeviceInfo()

        let record = CloudKitModels.toRecord(original, deviceInfo: deviceInfo)
        let decoded = CloudKitModels.fromRecord(record)

        let result = try? #require(decoded)
        #expect(result?.id == "test-id-001")
        #expect(result?.timestamp == "2026-06-28T12:00:00.000Z")
        #expect(result?.model == "gemma-4-1b")
        #expect(result?.platform == "macOS")
        #expect(result?.device == "Test Mac")
        #expect(result?.metrics.decodeTokensPerSecond == 45.0)
        #expect(result?.metrics.prefillTokensPerSecond == 200.0)
        #expect(result?.metrics.initTimeSeconds == 2.5)
        #expect(result?.metrics.ttftSeconds == 0.15)
        #expect(result?.metrics.lastPrefillTokenCount == 10)
        #expect(result?.metrics.lastDecodeTokenCount == 256)
    }

    @Test("Full entry with all optional fields survives CKRecord round-trip")
    func testFullEntryRoundTrip() {
        let original = makeFullEntry(id: "test-id-002")
        let deviceInfo = makeTestDeviceInfo()

        let record = CloudKitModels.toRecord(original, deviceInfo: deviceInfo)
        let decoded = CloudKitModels.fromRecord(record)

        let result = try? #require(decoded)
        #expect(result?.id == "test-id-002")
        #expect(result?.model == "gemma-4-4b")
        #expect(result?.platform == "iOS")
        #expect(result?.device == "iPhone17,2")

        // Core metrics
        #expect(result?.metrics.decodeTokensPerSecond == 150.0)
        #expect(result?.metrics.prefillTokensPerSecond == 350.0)

        // Device instrumentation
        #expect(result?.metrics.thermalStateAtStart == "nominal")
        #expect(result?.metrics.thermalStateAtEnd == "fair")
        #expect(result?.metrics.availableMemoryAtStartMB == 2048.0)
        #expect(result?.metrics.availableMemoryAtEndMB == 1536.0)
        #expect(result?.metrics.medianTokenLatencyMs == 6.5)
        #expect(result?.metrics.p95TokenLatencyMs == 12.3)

        // Enhanced instrumentation
        #expect(result?.metrics.estimatedMemoryBandwidthGBps == 0.5)
        #expect(result?.metrics.modelLoadDurationMs == 3200.0)
        #expect(result?.metrics.gpuAllocatedMemoryAtStartMB == 128.0)
        #expect(result?.metrics.gpuAllocatedMemoryAtEndMB == 512.0)
    }

    @Test("Decode latencies array survives CKRecord round-trip")
    func testDecodeLatenciesRoundTrip() {
        let original = makeFullEntry()
        let record = CloudKitModels.toRecord(original, deviceInfo: makeTestDeviceInfo())
        let decoded = CloudKitModels.fromRecord(record)

        let latencies = decoded?.metrics.decodeLatenciesMs
        #expect(latencies == [5.0, 6.0, 6.5, 7.0, 12.3])
    }

    @Test("Latency histogram survives CKRecord round-trip")
    func testLatencyHistogramRoundTrip() {
        let original = makeFullEntry()
        let record = CloudKitModels.toRecord(original, deviceInfo: makeTestDeviceInfo())
        let decoded = CloudKitModels.fromRecord(record)

        let histogram = decoded?.metrics.latencyHistogram
        #expect(histogram?["0-10ms"] == 4)
        #expect(histogram?["10-20ms"] == 1)
        #expect(histogram?["20-50ms"] == 0)
    }

    @Test("Thermal transitions survive CKRecord round-trip")
    func testThermalTransitionsRoundTrip() {
        let original = makeFullEntry()
        let record = CloudKitModels.toRecord(original, deviceInfo: makeTestDeviceInfo())
        let decoded = CloudKitModels.fromRecord(record)

        let transitions = decoded?.metrics.thermalTransitions
        #expect(transitions?.count == 1)
        #expect(transitions?.first?.from == "nominal")
        #expect(transitions?.first?.to == "fair")
    }

    @Test("Flags survive CKRecord round-trip")
    func testFlagsRoundTrip() {
        let original = makeFullEntry()
        let record = CloudKitModels.toRecord(original, deviceInfo: makeTestDeviceInfo())
        let decoded = CloudKitModels.fromRecord(record)

        #expect(decoded?.flags.enableBenchmark == true)
        #expect(decoded?.flags.enableSpeculativeDecoding == true)
        #expect(decoded?.flags.enableConversationConstrainedDecoding == true)
        #expect(decoded?.flags.visualTokenBudget == 256)
    }

    // MARK: - Nil Safety Tests

    @Test("All nil optional metrics survive CKRecord round-trip as nil")
    func testNilOptionalFieldsRoundTrip() {
        let original = makeMinimalEntry()
        let record = CloudKitModels.toRecord(original, deviceInfo: makeTestDeviceInfo())
        let decoded = CloudKitModels.fromRecord(record)

        #expect(decoded?.metrics.thermalStateAtStart == nil)
        #expect(decoded?.metrics.thermalStateAtEnd == nil)
        #expect(decoded?.metrics.availableMemoryAtStartMB == nil)
        #expect(decoded?.metrics.availableMemoryAtEndMB == nil)
        #expect(decoded?.metrics.medianTokenLatencyMs == nil)
        #expect(decoded?.metrics.p95TokenLatencyMs == nil)
        #expect(decoded?.metrics.decodeLatenciesMs == nil)
        #expect(decoded?.metrics.latencyHistogram == nil)
        #expect(decoded?.metrics.thermalTransitions == nil)
        #expect(decoded?.metrics.estimatedMemoryBandwidthGBps == nil)
        #expect(decoded?.metrics.modelLoadDurationMs == nil)
        #expect(decoded?.metrics.gpuAllocatedMemoryAtStartMB == nil)
        #expect(decoded?.metrics.gpuAllocatedMemoryAtEndMB == nil)
    }

    @Test("fromRecord returns nil when required field is missing")
    func testFromRecordReturnsNilForMissingRequiredField() {
        // Create a record missing required 'model' field
        let record = CKRecord(recordType: CloudKitModels.recordType)
        record["entryId"] = "test" as NSString
        record["timestamp"] = "2026-06-28T12:00:00.000Z" as NSString
        // Intentionally omit 'model'
        record["platform"] = "macOS" as NSString
        record["device"] = "Mac" as NSString

        let result = CloudKitModels.fromRecord(record)
        #expect(result == nil)
    }

    @Test("fromRecord returns nil for completely empty record")
    func testFromRecordReturnsNilForEmptyRecord() {
        let record = CKRecord(recordType: CloudKitModels.recordType)
        let result = CloudKitModels.fromRecord(record)
        #expect(result == nil)
    }

    // MARK: - DeviceInfo Tests

    @Test("DeviceInfo is tagged on CKRecord and recovered")
    func testDeviceInfoTagging() {
        let deviceInfo = makeTestDeviceInfo()
        let entry = makeMinimalEntry()

        let record = CloudKitModels.toRecord(entry, deviceInfo: deviceInfo)

        // Verify device info fields are on the record
        #expect(record["deviceName"] as? String == "Test MacBook Pro")
        #expect(record["deviceModel"] as? String == "arm64")
        #expect(record["osVersion"] as? String == "macOS 26.0")
        #expect(record["appVersion"] as? String == "1.0.0")

        // Verify extraction helper
        let extracted = CloudKitModels.deviceInfoFromRecord(record)
        #expect(extracted == deviceInfo)
    }

    @Test("deviceInfoFromRecord returns nil when fields are missing")
    func testDeviceInfoFromRecordMissingFields() {
        let record = CKRecord(recordType: CloudKitModels.recordType)
        record["deviceName"] = "Mac" as NSString
        // Intentionally omit other device info fields

        let result = CloudKitModels.deviceInfoFromRecord(record)
        #expect(result == nil)
    }

    @Test("Decoded entry includes syncDeviceInfo from CKRecord")
    func testSyncDeviceInfoIncluded() {
        let entry = makeMinimalEntry()
        let deviceInfo = makeTestDeviceInfo()

        let record = CloudKitModels.toRecord(entry, deviceInfo: deviceInfo)
        let decoded = CloudKitModels.fromRecord(record)

        #expect(decoded?.syncDeviceInfo?.deviceName == "Test MacBook Pro")
        #expect(decoded?.syncDeviceInfo?.deviceModel == "arm64")
        #expect(decoded?.syncDeviceInfo?.osVersion == "macOS 26.0")
        #expect(decoded?.syncDeviceInfo?.appVersion == "1.0.0")
    }

    // MARK: - Record ID Tests

    @Test("Record ID is based on entry UUID for idempotent upserts")
    func testRecordIDMatchesEntryID() {
        let id = "unique-entry-id-123"
        let entry = makeMinimalEntry(id: id)
        let record = CloudKitModels.toRecord(entry, deviceInfo: makeTestDeviceInfo())

        #expect(record.recordID.recordName == id)
    }

    @Test("Same entry produces same record ID (idempotent)")
    func testIdempotentRecordID() {
        let id = "idempotent-test-id"
        let entry = makeMinimalEntry(id: id)
        let deviceInfo = makeTestDeviceInfo()

        let record1 = CloudKitModels.toRecord(entry, deviceInfo: deviceInfo)
        let record2 = CloudKitModels.toRecord(entry, deviceInfo: deviceInfo)

        #expect(record1.recordID.recordName == record2.recordID.recordName)
    }

    // MARK: - DeviceInfo.current() Tests

    @Test("DeviceInfo.current() returns non-empty values")
    func testDeviceInfoCurrentReturnsValues() {
        let info = DeviceInfo.current()
        #expect(!info.deviceName.isEmpty)
        #expect(!info.deviceModel.isEmpty)
        #expect(!info.osVersion.isEmpty)
        // appVersion may be "unknown" in test environment
    }

    @Test("DeviceInfo Codable round-trip")
    func testDeviceInfoCodableRoundTrip() throws {
        let original = makeTestDeviceInfo()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DeviceInfo.self, from: data)

        #expect(decoded == original)
    }

    // MARK: - Record Type Constant

    @Test("Record type constant matches expected value")
    func testRecordTypeConstant() {
        #expect(CloudKitModels.recordType == "BenchmarkEntry")
    }

    @Test("Container identifier matches expected value")
    func testContainerIdentifier() {
        #expect(CloudKitModels.containerIdentifier == "iCloud.com.andrewvoirol.EdgeAILab")
    }

    // MARK: - Flags Default Fallback

    @Test("fromRecord uses default flags when flags field is missing")
    func testDefaultFlagsFallback() {
        let record = CKRecord(recordType: CloudKitModels.recordType)
        record["entryId"] = "fallback-test" as NSString
        record["timestamp"] = "2026-06-28T12:00:00.000Z" as NSString
        record["model"] = "test-model" as NSString
        record["platform"] = "macOS" as NSString
        record["device"] = "Mac" as NSString
        record["initTimeSeconds"] = 1.0 as NSNumber
        record["ttftSeconds"] = 0.1 as NSNumber
        record["decodeTokensPerSecond"] = 50.0 as NSNumber
        record["prefillTokensPerSecond"] = 100.0 as NSNumber
        record["lastPrefillTokenCount"] = 10 as NSNumber
        record["lastDecodeTokenCount"] = 100 as NSNumber
        // Intentionally omit flags

        let decoded = CloudKitModels.fromRecord(record)
        #expect(decoded?.flags.enableBenchmark == false)
        #expect(decoded?.flags.enableSpeculativeDecoding == nil)
        #expect(decoded?.flags.enableConversationConstrainedDecoding == false)
        #expect(decoded?.flags.visualTokenBudget == nil)
    }
}
