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

// MARK: - Eval Store

/// JSON file-based persistence layer for evaluation runs.
///
/// Each eval run is stored as a single JSON file in:
/// `~/Library/Application Support/EdgeAILab/EvalRuns/{uuid}.json`
///
/// An index file (`index.json`) caches summaries and metadata for
/// fast listing without deserializing every run file.
///
/// **Thread Safety**: All mutations are performed synchronously on the file system.
/// The `@Observable` properties should only be updated from the MainActor.
@Observable
@MainActor
final class EvalStore {

    private static let logger = Logger(
        subsystem: "com.andrewvoirol.EdgeAILab",
        category: "evalStore"
    )

    // MARK: - Published State

    /// Cached list of eval run index entries, sorted by startedAt descending.
    /// Used for list rendering without loading full run data.
    var indexEntries: [EvalRunIndexEntry] = []

    // MARK: - Storage

    /// Root directory for eval run storage.
    let storageDirectory: URL

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

    // MARK: - Init

    /// Initialize with a custom storage directory (primarily for testing).
    init(storageDirectory: URL? = nil) {
        if let dir = storageDirectory {
            self.storageDirectory = dir
        } else {
            // Default: ~/Library/Application Support/EdgeAILab/EvalRuns/
            // force-unwrap is safe: applicationSupportDirectory always exists in userDomainMask
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            self.storageDirectory = appSupport
                .appendingPathComponent("EdgeAILab", isDirectory: true)
                .appendingPathComponent("EvalRuns", isDirectory: true)
        }

        ensureStorageDirectory()
        loadIndex()
    }

    // MARK: - CRUD Operations

    /// Save an eval run to disk and update the index.
    func save(_ run: EvalRun) throws {
        let fileURL = fileURL(for: run.id)

        do {
            let data = try encoder.encode(run)
            try data.write(to: fileURL, options: .atomic)
            Self.logger.info("💾 Saved eval run: \(run.suiteName, privacy: .public) (\(run.id))")
        } catch {
            Self.logger.error("❌ Failed to save eval run: \(error.localizedDescription, privacy: .public)")
            throw EvalStoreError.saveFailed(error)
        }

        // Update index
        let entry = EvalRunIndexEntry(from: run)
        if let existingIndex = indexEntries.firstIndex(where: { $0.id == run.id }) {
            indexEntries[existingIndex] = entry
        } else {
            indexEntries.insert(entry, at: 0)
        }
        sortIndex()
        persistIndex()
    }

    /// Load a full eval run from disk by ID.
    func load(id: UUID) throws -> EvalRun {
        let fileURL = fileURL(for: id)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw EvalStoreError.notFound(id)
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let run = try decoder.decode(EvalRun.self, from: data)
            Self.logger.info("📂 Loaded eval run: \(run.suiteName, privacy: .public)")
            return run
        } catch {
            Self.logger.error("❌ Failed to load eval run \(id): \(error.localizedDescription, privacy: .public)")
            throw EvalStoreError.loadFailed(error)
        }
    }

    /// Delete an eval run from disk and remove from the index.
    func delete(id: UUID) throws {
        let fileURL = fileURL(for: id)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try FileManager.default.removeItem(at: fileURL)
                Self.logger.info("🗑️ Deleted eval run: \(id)")
            } catch {
                Self.logger.error("❌ Failed to delete eval run: \(error.localizedDescription, privacy: .public)")
                throw EvalStoreError.deleteFailed(error)
            }
        }

        indexEntries.removeAll { $0.id == id }
        persistIndex()
    }

    /// List all eval runs (returns cached index entries).
    func list() -> [EvalRunIndexEntry] {
        indexEntries
    }

    // MARK: - Export

    /// Export an eval run as raw JSON data (for file export or sharing).
    func exportJSON(id: UUID) throws -> Data {
        let fileURL = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw EvalStoreError.notFound(id)
        }
        return try Data(contentsOf: fileURL)
    }

    /// Export an eval run as CSV data with flattened results.
    ///
    /// The CSV contains one row per prompt per model, with columns:
    /// `run_id, suite_name, platform, device, model_name, model_file,
    ///  prompt_text, response, passed, score, decode_speed, ttft,
    ///  tool_calls, duration`
    func exportCSV(id: UUID) throws -> Data {
        let run = try load(id: id)

        var csv = "run_id,suite_name,platform,device,model_name,model_file,"
        csv += "prompt_text,response,passed,score,decode_speed_tps,ttft_s,"
        csv += "tool_calls,duration_s,avg_decode_speed,avg_ttft,pass_rate\n"

        for modelResult in run.modelResults {
            for promptResult in modelResult.promptResults {
                let fields: [String] = [
                    csvEscape(run.id.uuidString),
                    csvEscape(run.suiteName),
                    csvEscape(run.platform),
                    csvEscape(run.deviceName),
                    csvEscape(modelResult.modelName),
                    csvEscape(modelResult.modelFile),
                    csvEscape(promptResult.promptText),
                    csvEscape(promptResult.truncatedResponse),
                    promptResult.passed ? "true" : "false",
                    csvEscape(promptResult.score.displayLabel),
                    promptResult.decodeSpeed.map { String(format: "%.2f", $0) } ?? "",
                    promptResult.ttft.map { String(format: "%.3f", $0) } ?? "",
                    csvEscape(promptResult.toolNamesUsed.joined(separator: ";")),
                    String(format: "%.2f", promptResult.duration),
                    String(format: "%.2f", modelResult.avgDecodeSpeed),
                    String(format: "%.3f", modelResult.avgTTFT),
                    String(format: "%.2f", modelResult.passRate),
                ]
                csv += fields.joined(separator: ",") + "\n"
            }
        }

        guard let data = csv.data(using: .utf8) else {
            throw EvalStoreError.exportFailed("Failed to encode CSV as UTF-8")
        }
        return data
    }

    /// Reload the index from disk (e.g., after external changes).
    func refresh() {
        loadIndex()
    }

    // MARK: - Custom Suite Persistence

    /// Directory for custom suite storage.
    private var customSuitesDirectory: URL {
        storageDirectory
            .deletingLastPathComponent()  // EdgeAILab/
            .appendingPathComponent("CustomSuites", isDirectory: true)
    }

    /// Save a custom suite to disk.
    func saveCustomSuite(_ suite: EvalSuite) {
        let dir = customSuitesDirectory
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let fileURL = dir.appendingPathComponent("\(suite.id.uuidString).json")
        do {
            let data = try encoder.encode(suite)
            try data.write(to: fileURL, options: .atomic)
            Self.logger.info("💾 Saved custom suite: \(suite.name, privacy: .public)")
        } catch {
            Self.logger.error("❌ Failed to save custom suite: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Load all saved custom suites from disk.
    func loadCustomSuites() -> [EvalSuite] {
        let dir = customSuitesDirectory
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "json" }) else {
            return []
        }

        var suites: [EvalSuite] = []
        for file in files {
            if let data = try? Data(contentsOf: file),
               let suite = try? decoder.decode(EvalSuite.self, from: data) {
                suites.append(suite)
            }
        }
        Self.logger.info("📋 Loaded \(suites.count) custom suite(s)")
        return suites
    }

    /// Delete a saved custom suite from disk.
    func deleteCustomSuite(id: UUID) {
        let fileURL = customSuitesDirectory.appendingPathComponent("\(id.uuidString).json")
        try? FileManager.default.removeItem(at: fileURL)
        Self.logger.info("🗑️ Deleted custom suite: \(id)")
    }

    // MARK: - Private Helpers

    /// File URL for a specific eval run.
    private func fileURL(for id: UUID) -> URL {
        storageDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    /// Index file URL.
    private var indexFileURL: URL {
        storageDirectory.appendingPathComponent("index.json")
    }

    /// Ensure the storage directory exists.
    private func ensureStorageDirectory() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: storageDirectory.path) {
            do {
                try fm.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
                Self.logger.info("📁 Created eval run storage directory")
            } catch {
                Self.logger.error("❌ Failed to create storage directory: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Load index entries from the index file, or rebuild from run files.
    private func loadIndex() {
        let fm = FileManager.default

        // Try to load the index file first (fast path)
        if fm.fileExists(atPath: indexFileURL.path),
           let data = try? Data(contentsOf: indexFileURL),
           let entries = try? decoder.decode([EvalRunIndexEntry].self, from: data) {
            indexEntries = entries
            sortIndex()
            Self.logger.info("📋 Loaded eval index with \(entries.count) entries")
            return
        }

        // Rebuild index from run files (slow path, first launch or corruption)
        rebuildIndex()
    }

    /// Rebuild the index by scanning all eval run files.
    private func rebuildIndex() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "json" && $0.lastPathComponent != "index.json" }) else {
            indexEntries = []
            return
        }

        var entries: [EvalRunIndexEntry] = []
        for file in files {
            if let data = try? Data(contentsOf: file),
               let run = try? decoder.decode(EvalRun.self, from: data) {
                entries.append(EvalRunIndexEntry(from: run))
            }
        }

        indexEntries = entries
        sortIndex()
        persistIndex()
        Self.logger.info("🔄 Rebuilt eval index from \(entries.count) run files")
    }

    /// Sort index entries by startedAt descending (newest first).
    private func sortIndex() {
        indexEntries.sort { $0.startedAt > $1.startedAt }
    }

    /// Persist the current index to disk.
    private func persistIndex() {
        do {
            let data = try encoder.encode(indexEntries)
            try data.write(to: indexFileURL, options: .atomic)
        } catch {
            Self.logger.error("❌ Failed to persist eval index: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Escape a string for CSV output (wraps in quotes, doubles internal quotes).
    private func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        // Wrap in quotes if contains comma, newline, or quote
        if escaped.contains(",") || escaped.contains("\n") || escaped.contains("\"") {
            return "\"\(escaped)\""
        }
        return escaped
    }
}

// MARK: - Errors

/// Errors specific to eval store operations.
enum EvalStoreError: LocalizedError {
    case saveFailed(Error)
    case loadFailed(Error)
    case deleteFailed(Error)
    case notFound(UUID)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let error):
            return "Failed to save eval run: \(error.localizedDescription)"
        case .loadFailed(let error):
            return "Failed to load eval run: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete eval run: \(error.localizedDescription)"
        case .notFound(let id):
            return "Eval run not found: \(id)"
        case .exportFailed(let reason):
            return "Failed to export eval run: \(reason)"
        }
    }
}
