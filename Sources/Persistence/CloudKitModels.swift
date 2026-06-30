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
import CloudKit

// MARK: - Device Info

/// Information about the device that produced a benchmark entry.
/// Used to tag CloudKit records so entries can be grouped by device.
struct DeviceInfo: Codable, Sendable, Equatable {
    /// User-facing device name (e.g., "Andrew's MacBook Pro", "Andrew's iPhone")
    let deviceName: String
    /// Hardware model identifier (e.g., "arm64", "iPhone17,2")
    let deviceModel: String
    /// OS version string (e.g., "macOS 26.0", "iOS 26.5")
    let osVersion: String
    /// App version string from the bundle
    let appVersion: String

    /// Capture current device info.
    static func current() -> DeviceInfo {
        let deviceName: String
        let osVersion: String

        #if os(macOS)
        deviceName = Host.current().localizedName ?? "Mac"
        osVersion = "macOS \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.minorVersion)"
        #elseif os(iOS)
        // UIDevice is not available in unit tests without a host app,
        // so we use ProcessInfo for OS version and utsname for device name
        let version = ProcessInfo.processInfo.operatingSystemVersion
        osVersion = "iOS \(version.majorVersion).\(version.minorVersion)"
        deviceName = ProcessInfo.processInfo.hostName
        #else
        deviceName = "Unknown"
        osVersion = "Unknown"
        #endif

        let deviceModel: String = {
            var systemInfo = utsname()
            uname(&systemInfo)
            return withUnsafePointer(to: &systemInfo.machine) {
                $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                    String(cString: $0)
                }
            }
        }()

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

        return DeviceInfo(
            deviceName: deviceName,
            deviceModel: deviceModel,
            osVersion: osVersion,
            appVersion: appVersion
        )
    }
}

// MARK: - CloudKit Models

/// Pure-function logic for converting between `MetricsStore.Entry` and `CKRecord`.
/// Uses an enum namespace to prevent accidental instantiation (project convention).
enum CloudKitModels {

    /// The CloudKit record type name for benchmark entries.
    static let recordType = "BenchmarkEntry"

    /// The CloudKit container identifier.
    static let containerIdentifier = "iCloud.com.andrewvoirol.EdgeAILab"

    // MARK: - To CKRecord

    /// Convert a MetricsStore.Entry + DeviceInfo into a CKRecord for CloudKit storage.
    ///
    /// The record ID is based on the entry's UUID to ensure idempotent upserts.
    /// All optional metric fields are set only when non-nil.
    static func toRecord(_ entry: MetricsStore.Entry, deviceInfo: DeviceInfo) -> CKRecord {
        let recordID = CKRecord.ID(recordName: entry.id)
        let record = CKRecord(recordType: recordType, recordID: recordID)

        // Core fields
        record["entryId"] = entry.id as NSString
        record["timestamp"] = entry.timestamp as NSString
        record["model"] = entry.model as NSString
        record["platform"] = entry.platform as NSString
        record["device"] = entry.device as NSString

        // Device info
        record["deviceName"] = deviceInfo.deviceName as NSString
        record["deviceModel"] = deviceInfo.deviceModel as NSString
        record["osVersion"] = deviceInfo.osVersion as NSString
        record["appVersion"] = deviceInfo.appVersion as NSString

        // Core metrics (always present)
        record["initTimeSeconds"] = entry.metrics.initTimeSeconds as NSNumber
        record["ttftSeconds"] = entry.metrics.ttftSeconds as NSNumber
        record["decodeTokensPerSecond"] = entry.metrics.decodeTokensPerSecond as NSNumber
        record["prefillTokensPerSecond"] = entry.metrics.prefillTokensPerSecond as NSNumber
        record["lastPrefillTokenCount"] = entry.metrics.lastPrefillTokenCount as NSNumber
        record["lastDecodeTokenCount"] = entry.metrics.lastDecodeTokenCount as NSNumber

        // Optional device-level instrumentation
        setOptional(record, key: "thermalStateAtStart", value: entry.metrics.thermalStateAtStart)
        setOptional(record, key: "thermalStateAtEnd", value: entry.metrics.thermalStateAtEnd)
        setOptional(record, key: "availableMemoryAtStartMB", value: entry.metrics.availableMemoryAtStartMB)
        setOptional(record, key: "availableMemoryAtEndMB", value: entry.metrics.availableMemoryAtEndMB)
        setOptional(record, key: "medianTokenLatencyMs", value: entry.metrics.medianTokenLatencyMs)
        setOptional(record, key: "p95TokenLatencyMs", value: entry.metrics.p95TokenLatencyMs)

        // Enhanced instrumentation (optional)
        setOptional(record, key: "estimatedMemoryBandwidthGBps", value: entry.metrics.estimatedMemoryBandwidthGBps)
        setOptional(record, key: "modelLoadDurationMs", value: entry.metrics.modelLoadDurationMs)
        setOptional(record, key: "gpuAllocatedMemoryAtStartMB", value: entry.metrics.gpuAllocatedMemoryAtStartMB)
        setOptional(record, key: "gpuAllocatedMemoryAtEndMB", value: entry.metrics.gpuAllocatedMemoryAtEndMB)

        // Complex fields serialized as JSON Data
        if let latenciesData = encodeJSON(entry.metrics.decodeLatenciesMs) {
            record["decodeLatenciesMs"] = latenciesData as NSData
        }
        if let histogramData = encodeJSON(entry.metrics.latencyHistogram) {
            record["latencyHistogram"] = histogramData as NSData
        }
        if let transitionsData = encodeJSON(entry.metrics.thermalTransitions) {
            record["thermalTransitions"] = transitionsData as NSData
        }

        // Flags serialized as JSON Data
        if let flagsData = encodeJSON(entry.flags) {
            record["flags"] = flagsData as NSData
        }

        return record
    }

    // MARK: - From CKRecord

    /// Convert a CKRecord back to a MetricsStore.Entry.
    ///
    /// Returns nil if required fields are missing (defensive against schema evolution).
    static func fromRecord(_ record: CKRecord) -> MetricsStore.Entry? {
        // Required fields
        guard let entryId = record["entryId"] as? String,
              let timestamp = record["timestamp"] as? String,
              let model = record["model"] as? String,
              let platform = record["platform"] as? String,
              let device = record["device"] as? String,
              let initTimeSeconds = record["initTimeSeconds"] as? Double,
              let ttftSeconds = record["ttftSeconds"] as? Double,
              let decodeTokensPerSecond = record["decodeTokensPerSecond"] as? Double,
              let prefillTokensPerSecond = record["prefillTokensPerSecond"] as? Double,
              let lastPrefillTokenCount = record["lastPrefillTokenCount"] as? Int,
              let lastDecodeTokenCount = record["lastDecodeTokenCount"] as? Int else {
            return nil
        }

        // Optional fields
        let thermalStateAtStart = record["thermalStateAtStart"] as? String
        let thermalStateAtEnd = record["thermalStateAtEnd"] as? String
        let availableMemoryAtStartMB = record["availableMemoryAtStartMB"] as? Double
        let availableMemoryAtEndMB = record["availableMemoryAtEndMB"] as? Double
        let medianTokenLatencyMs = record["medianTokenLatencyMs"] as? Double
        let p95TokenLatencyMs = record["p95TokenLatencyMs"] as? Double
        let estimatedMemoryBandwidthGBps = record["estimatedMemoryBandwidthGBps"] as? Double
        let modelLoadDurationMs = record["modelLoadDurationMs"] as? Double
        let gpuAllocatedMemoryAtStartMB = record["gpuAllocatedMemoryAtStartMB"] as? Double
        let gpuAllocatedMemoryAtEndMB = record["gpuAllocatedMemoryAtEndMB"] as? Double

        // Complex JSON fields
        let decodeLatenciesMs: [Double]? = decodeJSON(record["decodeLatenciesMs"] as? Data)
        let latencyHistogram: [String: Int]? = decodeJSON(record["latencyHistogram"] as? Data)
        let thermalTransitions: [MetricsStore.ThermalTransitionRecord]? = decodeJSON(record["thermalTransitions"] as? Data)

        // Flags — fall back to defaults if missing
        let flags: RuntimeFlags = decodeJSON(record["flags"] as? Data) ?? RuntimeFlags(
            enableBenchmark: false,
            enableSpeculativeDecoding: nil,
            enableConversationConstrainedDecoding: false,
            visualTokenBudget: nil
        )

        // Device info for the entry
        let deviceName = record["deviceName"] as? String
        let deviceModel = record["deviceModel"] as? String
        let osVersion = record["osVersion"] as? String
        let appVersion = record["appVersion"] as? String

        let syncDeviceInfo: DeviceInfo?
        if let deviceName, let deviceModel, let osVersion, let appVersion {
            syncDeviceInfo = DeviceInfo(
                deviceName: deviceName,
                deviceModel: deviceModel,
                osVersion: osVersion,
                appVersion: appVersion
            )
        } else {
            syncDeviceInfo = nil
        }

        let metrics = MetricsStore.Entry.Metrics(
            initTimeSeconds: initTimeSeconds,
            ttftSeconds: ttftSeconds,
            decodeTokensPerSecond: decodeTokensPerSecond,
            prefillTokensPerSecond: prefillTokensPerSecond,
            lastPrefillTokenCount: lastPrefillTokenCount,
            lastDecodeTokenCount: lastDecodeTokenCount,
            thermalStateAtStart: thermalStateAtStart,
            thermalStateAtEnd: thermalStateAtEnd,
            availableMemoryAtStartMB: availableMemoryAtStartMB,
            availableMemoryAtEndMB: availableMemoryAtEndMB,
            medianTokenLatencyMs: medianTokenLatencyMs,
            p95TokenLatencyMs: p95TokenLatencyMs,
            decodeLatenciesMs: decodeLatenciesMs,
            latencyHistogram: latencyHistogram,
            thermalTransitions: thermalTransitions,
            estimatedMemoryBandwidthGBps: estimatedMemoryBandwidthGBps,
            modelLoadDurationMs: modelLoadDurationMs,
            gpuAllocatedMemoryAtStartMB: gpuAllocatedMemoryAtStartMB,
            gpuAllocatedMemoryAtEndMB: gpuAllocatedMemoryAtEndMB
        )

        return MetricsStore.Entry(
            id: entryId,
            timestamp: timestamp,
            model: model,
            platform: platform,
            device: device,
            metrics: metrics,
            flags: flags,
            syncDeviceInfo: syncDeviceInfo
        )
    }

    /// Extract DeviceInfo from a CKRecord if present.
    static func deviceInfoFromRecord(_ record: CKRecord) -> DeviceInfo? {
        guard let deviceName = record["deviceName"] as? String,
              let deviceModel = record["deviceModel"] as? String,
              let osVersion = record["osVersion"] as? String,
              let appVersion = record["appVersion"] as? String else {
            return nil
        }
        return DeviceInfo(
            deviceName: deviceName,
            deviceModel: deviceModel,
            osVersion: osVersion,
            appVersion: appVersion
        )
    }

    // MARK: - JSON Helpers

    /// Encode a Codable value to JSON Data for storage in a CKRecord.
    private static func encodeJSON<T: Encodable>(_ value: T?) -> Data? {
        guard let value else { return nil }
        return try? JSONEncoder().encode(value)
    }

    /// Decode JSON Data from a CKRecord field back to a Codable type.
    private static func decodeJSON<T: Decodable>(_ data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Set an optional String value on a CKRecord only if non-nil.
    private static func setOptional(_ record: CKRecord, key: String, value: String?) {
        if let value {
            record[key] = value as NSString
        }
    }

    /// Set an optional Double value on a CKRecord only if non-nil.
    private static func setOptional(_ record: CKRecord, key: String, value: Double?) {
        if let value {
            record[key] = value as NSNumber
        }
    }
}
