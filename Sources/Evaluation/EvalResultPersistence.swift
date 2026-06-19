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
import Observation
import os

// MARK: - Portable Export Record

/// A self-contained, portable snapshot of an evaluation run for external consumption.
///
/// Unlike `EvalRun` (which uses UUID-based filenames and is managed by `EvalStore`),
/// this record is designed for human-readable exports with timestamped filenames.
/// It flattens the hierarchy into a single JSON document that includes all context
/// needed to interpret the results without access to the app's internal data.
struct EvalExportRecord: Codable, Sendable {

    /// Metadata about the export itself.
    let exportVersion: String

    /// When this export was created.
    let exportedAt: Date

    // MARK: - Run Context

    /// The original eval run ID for traceability.
    let runId: UUID

    /// Name of the suite that was evaluated.
    let suiteName: String

    /// Category of the suite (e.g., "math", "reasoning").
    let suiteCategory: String

    /// Platform the eval ran on (e.g., "iOS", "macOS").
    let platform: String

    /// Device name (e.g., "iPhone 16 Pro Max", "MacBook Pro (M4 Max)").
    let deviceName: String

    /// When the eval run started.
    let startedAt: Date

    /// When the eval run completed (nil if incomplete).
    let completedAt: Date?

    // MARK: - Aggregate Metrics

    /// Overall pass rate across all models (0.0–1.0).
    let overallPassRate: Double

    /// Total number of models evaluated.
    let modelCount: Int

    /// Total number of prompts per model.
    let totalPrompts: Int

    // MARK: - Per-Model Results

    /// Detailed results for each model.
    let models: [ExportModelResult]

    /// Initialize from an `EvalRun`.
    init(from run: EvalRun) {
        self.exportVersion = "1.0"
        self.exportedAt = Date()
        self.runId = run.id
        self.suiteName = run.suiteName
        self.suiteCategory = run.suiteCategory.rawValue
        self.platform = run.platform
        self.deviceName = run.deviceName
        self.startedAt = run.startedAt
        self.completedAt = run.completedAt
        self.overallPassRate = run.overallPassRate
        self.modelCount = run.modelCount
        self.totalPrompts = run.modelResults.first?.promptResults.count ?? 0
        self.models = run.modelResults.map { ExportModelResult(from: $0) }
    }
}

// MARK: - Export Model Result

/// Flattened model result for export.
struct ExportModelResult: Codable, Sendable {
    /// Model display name.
    let modelName: String

    /// Model filename on disk.
    let modelFile: String

    /// Pass rate for this model (0.0–1.0).
    let passRate: Double

    /// Average decode speed in tokens/second.
    let avgDecodeSpeed: Double

    /// Average time to first token in seconds.
    let avgTTFT: Double

    /// 95th percentile latency in milliseconds.
    let p95Latency: Double

    /// Total tokens generated across all prompts.
    let totalTokensGenerated: Int

    /// Total evaluation duration in seconds.
    let totalDuration: TimeInterval

    /// Tool call accuracy (nil if no tool-calling prompts).
    let toolCallAccuracy: Double?

    /// Peak memory delta in MB (nil if unavailable).
    let peakMemoryDeltaMB: Double?

    /// Number of thermal state transitions.
    let thermalTransitions: Int

    /// Per-prompt scores.
    let prompts: [ExportPromptScore]

    /// Initialize from a `ModelEvalResult`.
    init(from result: ModelEvalResult) {
        self.modelName = result.modelName
        self.modelFile = result.modelFile
        self.passRate = result.passRate
        self.avgDecodeSpeed = result.avgDecodeSpeed
        self.avgTTFT = result.avgTTFT
        self.p95Latency = result.p95Latency
        self.totalTokensGenerated = result.totalTokensGenerated
        self.totalDuration = result.totalDuration
        self.toolCallAccuracy = result.toolCallAccuracy
        self.peakMemoryDeltaMB = result.peakMemoryDeltaMB
        self.thermalTransitions = result.thermalTransitions
        self.prompts = result.promptResults.map { ExportPromptScore(from: $0) }
    }
}

// MARK: - Export Prompt Score

/// Flattened prompt score for export. Includes the prompt text, response,
/// pass/fail status, score label, and performance metrics.
struct ExportPromptScore: Codable, Sendable {
    /// The prompt text that was sent.
    let promptText: String

    /// The model's response (truncated to 500 chars for export readability).
    let response: String

    /// Whether this prompt passed.
    let passed: Bool

    /// Score label (e.g., "Pass", "Fail", "Timeout").
    let scoreLabel: String

    /// Score reason (nil for pass, descriptive for failures).
    let scoreReason: String?

    /// Decode speed in tokens/second (nil if unavailable).
    let decodeSpeed: Double?

    /// Time to first token in seconds (nil if unavailable).
    let ttft: Double?

    /// Duration of this prompt evaluation in seconds.
    let duration: TimeInterval

    /// Names of tools called during this prompt (empty if none).
    let toolsCalled: [String]

    /// Initialize from a `PromptEvalResult`.
    init(from result: PromptEvalResult) {
        self.promptText = result.promptText
        // Truncate very long responses for export readability
        if result.response.count > 500 {
            self.response = String(result.response.prefix(497)) + "..."
        } else {
            self.response = result.response
        }
        self.passed = result.passed
        self.scoreLabel = result.score.displayLabel
        self.scoreReason = result.score.reason
        self.decodeSpeed = result.decodeSpeed
        self.ttft = result.ttft
        self.duration = result.duration
        self.toolsCalled = result.toolNamesUsed
    }
}

// MARK: - Eval Result Persistence

/// Portable JSON export persistence for evaluation results.
///
/// Complements `EvalStore` (which manages internal UUID-based run files) by
/// producing human-readable, timestamped JSON exports suitable for sharing,
/// archiving, or external analysis.
///
/// **Storage Locations**:
/// - **iOS**: Documents directory — user-visible in Files app
/// - **macOS**: Application Support — consistent with `EvalStore`
///
/// **File Naming**: `eval_results_<ISO8601_timestamp>.json`
///
/// Usage:
/// ```swift
/// let persistence = EvalResultPersistence()
/// let url = try persistence.save(run)
/// ```
@Observable
@MainActor
final class EvalResultPersistence {

    private static let logger = Logger(
        subsystem: "com.andrewvoirol.EdgeAILab",
        category: "evalResultPersistence"
    )

    // MARK: - Observable State

    /// URL of the most recently saved export file (nil if none saved yet).
    var lastExportURL: URL?

    /// Human-readable status message for the last export operation.
    var lastExportStatus: String = ""

    /// List of all export file URLs found on disk, sorted newest first.
    var exportHistory: [URL] = []

    // MARK: - Storage

    /// Root directory for eval exports.
    let exportDirectory: URL

    /// JSON encoder configured for pretty-printing and ISO-8601 dates.
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    /// JSON decoder configured for ISO-8601 dates.
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// ISO 8601 date formatter for file naming (compact, filesystem-safe).
    private static let filenameDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withFullTime]
        formatter.timeZone = .current
        return formatter
    }()

    // MARK: - Init

    /// Initialize with an optional custom directory (for testing).
    /// - Parameter exportDirectory: Custom export directory. If nil, uses the
    ///   platform-appropriate default (Documents on iOS, Application Support on macOS).
    init(exportDirectory: URL? = nil) {
        if let dir = exportDirectory {
            self.exportDirectory = dir
        } else {
            #if os(iOS)
            // iOS: Documents directory — visible in Files app
            let baseDir = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first!
            #else
            // macOS: Application Support — consistent with EvalStore
            let baseDir = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            #endif

            self.exportDirectory = baseDir
                .appendingPathComponent("EdgeAILab", isDirectory: true)
                .appendingPathComponent("EvalExports", isDirectory: true)
        }

        ensureExportDirectory()
        loadExportHistory()
    }

    // MARK: - Save

    /// Save an eval run as a portable, timestamped JSON export.
    ///
    /// - Parameter run: The completed eval run to export.
    /// - Returns: The file URL where the export was saved.
    /// - Throws: `EvalExportError.saveFailed` if the write fails.
    @discardableResult
    func save(_ run: EvalRun) throws -> URL {
        let record = EvalExportRecord(from: run)
        let filename = generateFilename(for: run.completedAt ?? run.startedAt)
        let fileURL = exportDirectory.appendingPathComponent(filename)

        do {
            let data = try encoder.encode(record)
            try data.write(to: fileURL, options: .atomic)

            lastExportURL = fileURL
            lastExportStatus = "Exported: \(filename)"
            exportHistory.insert(fileURL, at: 0)

            Self.logger.info(
                "📤 Exported eval results: \(filename, privacy: .public) (\(data.count) bytes)"
            )

            return fileURL
        } catch {
            lastExportStatus = "Export failed: \(error.localizedDescription)"
            Self.logger.error(
                "❌ Failed to export eval results: \(error.localizedDescription, privacy: .public)"
            )
            throw EvalExportError.saveFailed(error)
        }
    }

    // MARK: - Load

    /// Load an export record from a specific file URL.
    ///
    /// - Parameter url: The file URL to load from.
    /// - Returns: The decoded `EvalExportRecord`.
    /// - Throws: `EvalExportError.loadFailed` if decoding fails.
    func load(from url: URL) throws -> EvalExportRecord {
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(EvalExportRecord.self, from: data)
        } catch {
            Self.logger.error(
                "❌ Failed to load export: \(url.lastPathComponent, privacy: .public) — \(error.localizedDescription, privacy: .public)"
            )
            throw EvalExportError.loadFailed(error)
        }
    }

    // MARK: - Delete

    /// Delete an export file.
    ///
    /// - Parameter url: The file URL to delete.
    /// - Throws: `EvalExportError.deleteFailed` if removal fails.
    func delete(url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
            exportHistory.removeAll { $0 == url }
            if lastExportURL == url {
                lastExportURL = exportHistory.first
            }
            Self.logger.info("🗑️ Deleted export: \(url.lastPathComponent, privacy: .public)")
        } catch {
            Self.logger.error(
                "❌ Failed to delete export: \(error.localizedDescription, privacy: .public)"
            )
            throw EvalExportError.deleteFailed(error)
        }
    }

    // MARK: - Private Helpers

    /// Generate a filename with ISO 8601 timestamp.
    /// e.g., `eval_results_2026-06-18T200339-0400.json`
    private func generateFilename(for date: Date) -> String {
        let timestamp = Self.filenameDateFormatter.string(from: date)
        // Replace colons with empty string for filesystem safety
        let safeTimestamp = timestamp.replacingOccurrences(of: ":", with: "")
        return "eval_results_\(safeTimestamp).json"
    }

    /// Ensure the export directory exists, creating it if needed.
    private func ensureExportDirectory() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: exportDirectory.path) {
            do {
                try fm.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
                Self.logger.info("📁 Created eval export directory")
            } catch {
                Self.logger.error(
                    "❌ Failed to create export directory: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    /// Scan the export directory and populate `exportHistory`.
    private func loadExportHistory() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: exportDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else {
            exportHistory = []
            return
        }

        exportHistory = files
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("eval_results_") }
            .sorted { url1, url2 in
                // Sort by filename descending (timestamps sort lexicographically)
                url1.lastPathComponent > url2.lastPathComponent
            }

        lastExportURL = exportHistory.first

        if !exportHistory.isEmpty {
            Self.logger.info("📋 Found \(self.exportHistory.count) existing export(s)")
        }
    }
}

// MARK: - Errors

/// Errors specific to eval result export operations.
enum EvalExportError: LocalizedError {
    case saveFailed(Error)
    case loadFailed(Error)
    case deleteFailed(Error)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let error):
            return "Failed to save eval export: \(error.localizedDescription)"
        case .loadFailed(let error):
            return "Failed to load eval export: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete eval export: \(error.localizedDescription)"
        }
    }
}
