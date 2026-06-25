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

/// Manages a local JSON-based metrics store for tracking benchmark results over time.
/// Each inference run appends an entry to `metrics/history.json` in the project root.
/// The AI agent queries this file for trend analysis and regression detection.
final class MetricsStore {

    // MARK: - Schema

    /// A single benchmark measurement entry.
    struct Entry: Codable {
        let timestamp: String
        let model: String
        let platform: String
        let device: String
        let metrics: Metrics
        let flags: ExperimentalFlagsState

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
        }
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
        flags: ExperimentalFlagsState,
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
                decodeLatenciesMs: inferenceMetrics?.decodeLatenciesMs
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
