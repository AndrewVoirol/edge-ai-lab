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
import LiteRTLM

// MARK: - Device Info

/// Information about the device that produced a benchmark entry.
/// Used to tag entries so they can be grouped by device for cross-device comparison.
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

/// Manages a local JSON-based metrics store for tracking benchmark results over time.
/// Each inference run appends an entry to `metrics/history.json` in the project root.
/// The AI agent queries this file for trend analysis and regression detection.
final class MetricsStore {

    // MARK: - Schema

    /// A single benchmark measurement entry.
    struct Entry: Codable {
        /// Unique identifier for deduplication during CloudKit sync.
        /// Auto-generated for new entries; preserved across encode/decode.
        let id: String
        let timestamp: String
        let model: String
        let platform: String
        let device: String
        let metrics: Metrics
        let flags: RuntimeFlags

        /// Device information from CloudKit sync (nil for locally-created entries
        /// that haven't been synced yet).
        let syncDeviceInfo: DeviceInfo?

        /// Memberwise initializer with defaults for backward-compatible call sites.
        init(
            id: String = UUID().uuidString,
            timestamp: String,
            model: String,
            platform: String,
            device: String,
            metrics: Metrics,
            flags: RuntimeFlags,
            syncDeviceInfo: DeviceInfo? = nil
        ) {
            self.id = id
            self.timestamp = timestamp
            self.model = model
            self.platform = platform
            self.device = device
            self.metrics = metrics
            self.flags = flags
            self.syncDeviceInfo = syncDeviceInfo
        }

        /// Custom decoder for backward compatibility: old JSON without `id` or
        /// `syncDeviceInfo` fields will auto-generate an id and default to nil.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
            self.timestamp = try container.decode(String.self, forKey: .timestamp)
            self.model = try container.decode(String.self, forKey: .model)
            self.platform = try container.decode(String.self, forKey: .platform)
            self.device = try container.decode(String.self, forKey: .device)
            self.metrics = try container.decode(Metrics.self, forKey: .metrics)
            self.flags = try container.decode(RuntimeFlags.self, forKey: .flags)
            self.syncDeviceInfo = try container.decodeIfPresent(DeviceInfo.self, forKey: .syncDeviceInfo)
        }

        private enum CodingKeys: String, CodingKey {
            case id, timestamp, model, platform, device, metrics, flags, syncDeviceInfo
        }

        struct Metrics: Codable {
            let initTimeSeconds: Double
            let ttftSeconds: Double
            let decodeTokensPerSecond: Double
            let prefillTokensPerSecond: Double
            let lastPrefillTokenCount: Int
            let lastDecodeTokenCount: Int

            // Device-level instrumentation (optional for backward compatibility)
            let thermalStateAtStart: String?
            let thermalStateAtEnd: String?
            let availableMemoryAtStartMB: Double?
            let availableMemoryAtEndMB: Double?
            let medianTokenLatencyMs: Double?
            let p95TokenLatencyMs: Double?
            let decodeLatenciesMs: [Double]?

            // Enhanced instrumentation fields (optional for backward compatibility)
            let latencyHistogram: [String: Int]?
            let thermalTransitions: [ThermalTransitionRecord]?
            let estimatedMemoryBandwidthGBps: Double?
            let modelLoadDurationMs: Double?
            let gpuAllocatedMemoryAtStartMB: Double?
            let gpuAllocatedMemoryAtEndMB: Double?
        }
    }

    /// Lightweight Codable record for thermal transitions in the metrics store.
    /// Uses String raw values for thermal levels instead of importing the full ThermalTransition struct.
    struct ThermalTransitionRecord: Codable {
        let from: String
        let to: String
        let timestamp: String
    }

    // MARK: - Storage

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder


    /// Initialize with a custom file URL (useful for testing).
    /// Defaults to `metrics/history.json` relative to the app's documents directory.
    init(fileURL: URL? = nil) {
        if let url = fileURL {
            self.fileURL = url
        } else {
            // Default to safe app storage directory
            #if os(macOS)
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appDir = appSupport.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.andrewvoirol.EdgeAILab")
            self.fileURL = appDir.appendingPathComponent("metrics").appendingPathComponent("history.json")
            #else
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            self.fileURL = docs.appendingPathComponent("metrics").appendingPathComponent("history.json")
            #endif
        }

        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Read

    /// Load all entries from the metrics store.
    func loadEntries() throws -> [Entry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([Entry].self, from: data)
    }

    // MARK: - Write

    /// Append a new benchmark entry to the metrics store.
    func append(entry: Entry) throws {
        var entries = (try? loadEntries()) ?? []
        entries.append(entry)

        // Ensure directory exists
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Create an entry from BenchmarkInfo, optional InferenceMetrics, and current state.
    static func createEntry(
        from benchmarkInfo: BenchmarkInfo,
        modelName: String,
        flags: RuntimeFlags,
        inferenceMetrics: InferenceMetrics? = nil
    ) -> Entry {
        let platform: String
        #if os(iOS)
        platform = "iOS"
        #elseif os(macOS)
        platform = "macOS"
        #else
        platform = "unknown"
        #endif

        let device: String
        #if os(iOS)
        var systemInfo = utsname()
        uname(&systemInfo)
        device = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        #elseif os(macOS)
        device = Host.current().localizedName ?? "Mac"
        #else
        device = "unknown"
        #endif

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return Entry(
            timestamp: formatter.string(from: Date()),
            model: modelName,
            platform: platform,
            device: device,
            metrics: Entry.Metrics(
                initTimeSeconds: benchmarkInfo.initTimeInSecond,
                ttftSeconds: benchmarkInfo.timeToFirstTokenInSecond,
                decodeTokensPerSecond: benchmarkInfo.lastDecodeTokensPerSecond,
                prefillTokensPerSecond: benchmarkInfo.lastPrefillTokensPerSecond,
                lastPrefillTokenCount: benchmarkInfo.lastPrefillTokenCount,
                lastDecodeTokenCount: benchmarkInfo.lastDecodeTokenCount,
                thermalStateAtStart: inferenceMetrics?.startSnapshot.thermalLevel.rawValue,
                thermalStateAtEnd: inferenceMetrics?.endSnapshot.thermalLevel.rawValue,
                availableMemoryAtStartMB: inferenceMetrics?.startSnapshot.availableMemoryMB,
                availableMemoryAtEndMB: inferenceMetrics?.endSnapshot.availableMemoryMB,
                medianTokenLatencyMs: inferenceMetrics?.medianTokenLatencyMs,
                p95TokenLatencyMs: inferenceMetrics?.p95TokenLatencyMs,
                decodeLatenciesMs: inferenceMetrics?.decodeLatenciesMs,
                latencyHistogram: inferenceMetrics?.latencyHistogram,
                thermalTransitions: nil,  // Populated separately by caller with ThermalMonitor data
                estimatedMemoryBandwidthGBps: inferenceMetrics?.estimatedMemoryBandwidthGBps,
                modelLoadDurationMs: nil,  // Populated separately by caller with engine data
                gpuAllocatedMemoryAtStartMB: inferenceMetrics?.startSnapshot.gpuAllocatedMemoryMB,
                gpuAllocatedMemoryAtEndMB: inferenceMetrics?.endSnapshot.gpuAllocatedMemoryMB
            ),
            flags: flags
        )
    }

    /// Create an entry from `EnginePerformanceMetrics` — runtime-agnostic overload.
    ///
    /// Used by non-LiteRT engines (MLX, future runtimes) that don't produce
    /// `BenchmarkInfo`. Fields unavailable from `EnginePerformanceMetrics`
    /// (e.g., `initTimeSeconds`, per-token latencies) default to zero/nil.
    static func createEntry(
        from metrics: EnginePerformanceMetrics,
        modelName: String,
        runtimeType: RuntimeType
    ) -> Entry {
        let platform: String
        #if os(iOS)
        platform = "iOS"
        #elseif os(macOS)
        platform = "macOS"
        #else
        platform = "unknown"
        #endif

        let device: String
        #if os(iOS)
        var systemInfo = utsname()
        uname(&systemInfo)
        device = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        #elseif os(macOS)
        device = Host.current().localizedName ?? "Mac"
        #else
        device = "unknown"
        #endif

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Default RuntimeFlags for non-LiteRT engines.
        let flags = RuntimeFlags(
            enableBenchmark: true,
            enableSpeculativeDecoding: nil,
            enableConversationConstrainedDecoding: false,
            visualTokenBudget: nil
        )

        return Entry(
            timestamp: formatter.string(from: Date()),
            model: "\(modelName) [\(runtimeType.rawValue)]",
            platform: platform,
            device: device,
            metrics: Entry.Metrics(
                initTimeSeconds: 0,  // Not tracked by EnginePerformanceMetrics
                ttftSeconds: metrics.timeToFirstToken ?? 0,
                decodeTokensPerSecond: metrics.tokensPerSecond,
                prefillTokensPerSecond: metrics.promptTokensPerSecond ?? 0,
                lastPrefillTokenCount: 0,  // Not tracked
                lastDecodeTokenCount: metrics.tokenCount ?? 0,
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
            flags: flags
        )
    }

    // MARK: - Queries

    /// Get the last N entries from the store.
    func lastEntries(_ count: Int) throws -> [Entry] {
        let entries = try loadEntries()
        return Array(entries.suffix(count))
    }

    /// Get entries for a specific model.
    func entries(forModel model: String) throws -> [Entry] {
        return try loadEntries().filter { $0.model == model }
    }

    /// Get the average decode speed across all entries (or filtered by model).
    func averageDecodeSpeed(forModel model: String? = nil) throws -> Double {
        let entries = try loadEntries()
        let filtered = model != nil ? entries.filter { $0.model == model! } : entries
        guard !filtered.isEmpty else { return 0 }
        let total = filtered.reduce(0.0) { $0 + $1.metrics.decodeTokensPerSecond }
        return total / Double(filtered.count)
    }

    /// Get decode speed trend data — pairs of (index, decodeSpeed) for charting.
    func decodeSpeedTrend(forModel model: String? = nil, lastN: Int = 20) throws -> [(index: Int, speed: Double, model: String)] {
        let entries = try loadEntries()
        let filtered = model != nil ? entries.filter { $0.model == model! } : entries
        let recent = Array(filtered.suffix(lastN))
        return recent.enumerated().map { (index: $0.offset, speed: $0.element.metrics.decodeTokensPerSecond, model: $0.element.model) }
    }

    /// Get unique model names from the store.
    func uniqueModels() throws -> [String] {
        let entries = try loadEntries()
        return Array(Set(entries.map(\.model))).sorted()
    }

    // MARK: - Cross-Device Merge

    /// Merge remote entries into the local store.
    ///
    /// Deduplicates by entry UUID — remote entries with IDs already present
    /// locally are skipped. New remote entries are appended and persisted.
    func mergeRemoteEntries(_ remote: [Entry]) throws {
        var local = (try? loadEntries()) ?? []
        let existingIDs = Set(local.map(\.id))

        var newEntries: [Entry] = []
        for entry in remote {
            if !existingIDs.contains(entry.id) {
                newEntries.append(entry)
            }
        }

        guard !newEntries.isEmpty else { return }

        local.append(contentsOf: newEntries)

        // Ensure directory exists
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try encoder.encode(local)
        try data.write(to: fileURL, options: .atomic)
    }

    /// All entries grouped by device name for cross-device comparison.
    ///
    /// Uses the `device` field from the entry (which captures the hardware identifier
    /// or host name at benchmark time). Entries from this device and synced entries
    /// from other devices are all included.
    var allDeviceEntries: [String: [Entry]] {
        let entries = (try? loadEntries()) ?? []
        return Dictionary(grouping: entries) { entry in
            // Prefer syncDeviceInfo.deviceName for synced entries,
            // fall back to the entry's device field for local entries
            entry.syncDeviceInfo?.deviceName ?? entry.device
        }
    }

    // MARK: - JSONL Streaming

    /// A single JSONL turn entry that extends the core Entry fields with benchmark context.
    struct TurnEntry: Codable {
        let runId: String
        let configId: String
        let turnIndex: Int
        let timestamp: String
        let entry: Entry
    }

    /// URL for the JSONL streaming output file.
    /// Lives alongside history.json in the same metrics directory.
    private var jsonlFileURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("benchmark-results.jsonl")
    }

    /// Append a single turn's metrics to the JSONL streaming file.
    ///
    /// Each line is a self-contained JSON object containing the full Entry plus
    /// benchmark context fields (runId, configId, turnIndex, timestamp).
    /// Uses FileHandle append for crash-safe incremental writes (ported from
    /// IO 2026 Concierge InferenceBenchmark).
    ///
    /// Also prints the JSON line to stdout with a `[BENCHMARK_TURN]` prefix
    /// for log parsing by automation scripts.
    func appendTurnToJSONL(
        _ entry: Entry,
        runId: String,
        configId: String,
        turnIndex: Int
    ) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let turnEntry = TurnEntry(
            runId: runId,
            configId: configId,
            turnIndex: turnIndex,
            timestamp: formatter.string(from: Date()),
            entry: entry
        )

        let lineEncoder = JSONEncoder()
        lineEncoder.outputFormatting = [.sortedKeys]

        guard let jsonData = try? lineEncoder.encode(turnEntry),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }

        // Print to stdout for automation log parsing
        print("[BENCHMARK_TURN] \(jsonString)")

        // Ensure the metrics directory exists
        let directory = jsonlFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Append to JSONL file using FileHandle (crash-safe incremental write)
        if let fileHandle = try? FileHandle(forWritingTo: jsonlFileURL) {
            fileHandle.seekToEndOfFile()
            if let lineData = "\(jsonString)\n".data(using: .utf8) {
                fileHandle.write(lineData)
            }
            fileHandle.closeFile()
        } else {
            // File doesn't exist yet — create it with the first line
            try? "\(jsonString)\n".write(to: jsonlFileURL, atomically: true, encoding: .utf8)
        }
    }

    /// Append a pre-serialized JSON string as a single line to the JSONL file.
    ///
    /// Used for non-Entry events (e.g. crash recovery logs, warmup markers).
    func appendRawJSONL(_ jsonString: String) {
        // Ensure the metrics directory exists
        let directory = jsonlFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if let fileHandle = try? FileHandle(forWritingTo: jsonlFileURL) {
            fileHandle.seekToEndOfFile()
            if let lineData = "\(jsonString)\n".data(using: .utf8) {
                fileHandle.write(lineData)
            }
            fileHandle.closeFile()
        } else {
            try? "\(jsonString)\n".write(to: jsonlFileURL, atomically: true, encoding: .utf8)
        }
    }

    /// Clear the JSONL file for a fresh benchmark run.
    func clearJSONLFile() {
        try? FileManager.default.removeItem(at: jsonlFileURL)
    }
}
