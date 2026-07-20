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
import Observation
import os

// MARK: - Dynamic Model Catalog

/// Persistent catalog that merges the built-in model registry with user-imported models.
///
/// Follows the `ConversationStore` persistence pattern:
/// - Storage in `~/Library/Application Support/EdgeAILab/ModelCatalog/`
/// - Single `catalog.json` file for all imported models
/// - Atomic writes for crash safety
/// - In-memory cache for fast access
///
/// **Merge Strategy:** Known registry models always take precedence. If an imported
/// model has the same `modelFile` as a known model, the known model's metadata is
/// used but the import entry is preserved for source tracking.
///
/// **Thread Safety:** All mutations occur on the MainActor. File I/O is synchronous
/// but fast (catalog is typically small — tens of entries at most).
@Observable
@MainActor
final class DynamicModelCatalog {

    private static let logger = Logger(
        subsystem: "com.andrewvoirol.EdgeAILab",
        category: "dynamicModelCatalog"
    )

    // MARK: - State

    /// Imported model entries (excludes known registry models).
    /// Updated via CRUD operations and persisted to `catalog.json`.
    var entries: [DynamicModelMetadata] = []

    // MARK: - Storage

    /// Root directory for catalog storage.
    let storageDirectory: URL

    /// Path to the catalog JSON file.
    private var catalogFileURL: URL {
        storageDirectory.appendingPathComponent("catalog.json")
    }

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

    /// Initialize the catalog with an optional custom storage directory.
    ///
    /// - Parameter storageDirectory: Custom directory for persistence (primarily for testing).
    ///   Defaults to `~/Library/Application Support/EdgeAILab/ModelCatalog/`.
    init(storageDirectory: URL? = nil) {
        if let dir = storageDirectory {
            self.storageDirectory = dir
        } else {
            // Default: ~/Library/Application Support/EdgeAILab/ModelCatalog/
            let appSupport = DirectoryHelper.applicationSupport
            self.storageDirectory = appSupport
                .appendingPathComponent("EdgeAILab", isDirectory: true)
                .appendingPathComponent("ModelCatalog", isDirectory: true)
        }

        ensureStorageDirectory()
        loadCatalog()
    }

    // MARK: - Merged View

    /// Returns all models: known registry models merged with imported models.
    ///
    /// Known registry models always appear first and take precedence over imported
    /// models with matching `modelFile`. Imported models that don't overlap with
    /// the registry appear after the known models.
    ///
    /// - Returns: Combined array of `DynamicModelMetadata` entries.
    func allModels() -> [DynamicModelMetadata] {
        // Convert known models to DynamicModelMetadata
        let knownEntries = KnownModelCatalog.allModels.map { DynamicModelMetadata.fromKnownModel($0) }

        // Collect known model file names to avoid duplicates
        let knownFiles = Set(KnownModelCatalog.allModels.compactMap(\.modelFile))

        // Filter imported entries that don't overlap with known models
        let importedOnly = entries.filter { entry in
            guard let file = entry.metadata.modelFile else { return true }
            return !knownFiles.contains(file)
        }

        return knownEntries + importedOnly
    }

    // MARK: - CRUD Operations

    /// Add a new model entry to the catalog.
    ///
    /// - Parameter metadata: The `DynamicModelMetadata` to add.
    /// - Throws: `DynamicModelCatalogError.duplicateEntry` if an entry with the same ID already exists.
    func add(_ metadata: DynamicModelMetadata) throws {
        guard !entries.contains(where: { $0.id == metadata.id }) else {
            throw DynamicModelCatalogError.duplicateEntry(metadata.id)
        }

        entries.append(metadata)
        persistCatalog()

        Self.logger.info("➕ Added model to catalog: \(metadata.id, privacy: .public) (source: \(metadata.source.rawValue, privacy: .public))")
    }

    /// Remove a model entry from the catalog by ID.
    ///
    /// Only removes imported models. Known registry models cannot be removed.
    ///
    /// - Parameter id: The unique identifier of the entry to remove.
    /// - Throws: `DynamicModelCatalogError.notFound` if no entry with the ID exists.
    func remove(id: String) throws {
        guard entries.contains(where: { $0.id == id }) else {
            throw DynamicModelCatalogError.notFound(id)
        }

        entries.removeAll { $0.id == id }
        persistCatalog()

        Self.logger.info("🗑️ Removed model from catalog: \(id, privacy: .public)")
    }

    /// Update an existing model entry in the catalog.
    ///
    /// - Parameter metadata: The updated `DynamicModelMetadata`.
    /// - Throws: `DynamicModelCatalogError.notFound` if no entry with the ID exists.
    func update(_ metadata: DynamicModelMetadata) throws {
        guard let index = entries.firstIndex(where: { $0.id == metadata.id }) else {
            throw DynamicModelCatalogError.notFound(metadata.id)
        }

        entries[index] = metadata
        persistCatalog()

        Self.logger.info("✏️ Updated model in catalog: \(metadata.id, privacy: .public)")
    }

    // MARK: - Search & Filter

    /// Search for models by name, description, or model ID.
    ///
    /// Searches across all models (known + imported). The search is case-insensitive
    /// and matches partial strings.
    ///
    /// - Parameter query: The search query string.
    /// - Returns: Models matching the query.
    func search(query: String) -> [DynamicModelMetadata] {
        let lowered = query.lowercased()
        return allModels().filter { entry in
            entry.metadata.displayName.lowercased().contains(lowered)
                || (entry.metadata.modelDescription ?? "").lowercased().contains(lowered)
                || (entry.metadata.modelId ?? "").lowercased().contains(lowered)
                || entry.id.lowercased().contains(lowered)
        }
    }

    /// Filter models by runtime type.
    ///
    /// - Parameter runtime: The `RuntimeType` to filter by.
    /// - Returns: Models matching the specified runtime.
    func filter(by runtime: RuntimeType) -> [DynamicModelMetadata] {
        allModels().filter { $0.metadata.runtimeType == runtime }
    }

    /// Filter models by capability string.
    ///
    /// Matches against capability flags such as `hasVision`, `hasAudio`, `hasMTP`,
    /// `hasThinking`, and `hasToolCalling` on the `ModelCapabilityProfile`.
    ///
    /// - Parameter capability: The capability to filter by.
    /// - Returns: Models that have the specified capability.
    func filter(by capability: String) -> [DynamicModelMetadata] {
        let lowered = capability.lowercased()
        return allModels().filter { entry in
            switch lowered {
            case "image", "vision":
                return entry.metadata.hasVision
            case "audio":
                return entry.metadata.hasAudio
            case "mtp", "speculative_decoding":
                return entry.metadata.hasMTP
            case "thinking", "llm_thinking":
                return entry.metadata.hasThinking
            case "tool_calling":
                return entry.metadata.hasToolCalling
            default:
                return entry.metadata.tags.contains(where: { $0.lowercased() == lowered })
            }
        }
    }

    /// Find a model entry by its unique identifier.
    ///
    /// Searches across all models (known + imported).
    ///
    /// - Parameter id: The unique identifier to search for.
    /// - Returns: The matching `DynamicModelMetadata`, or `nil` if not found.
    func find(id: String) -> DynamicModelMetadata? {
        entries.first(where: { $0.id == id })
    }

    /// Reload the catalog from disk.
    ///
    /// Call this if you suspect external changes to the catalog file.
    func refresh() {
        loadCatalog()
    }

    // MARK: - Private — Storage

    /// Ensure the storage directory exists, creating it if necessary.
    private func ensureStorageDirectory() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: storageDirectory.path) {
            do {
                try fm.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
                Self.logger.info("📁 Created model catalog storage directory")
            } catch {
                Self.logger.error("❌ Failed to create catalog directory: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Load catalog entries from the JSON file.
    private func loadCatalog() {
        let fm = FileManager.default

        guard fm.fileExists(atPath: catalogFileURL.path),
              let data = try? Data(contentsOf: catalogFileURL) else {
            entries = []
            Self.logger.info("📋 No existing catalog found — starting fresh")
            return
        }

        do {
            entries = try decoder.decode([DynamicModelMetadata].self, from: data)
            Self.logger.info("📋 Loaded catalog with \(self.entries.count) imported model(s)")
        } catch {
            // Backup corrupted file before overwriting
            let backupURL = catalogFileURL.deletingPathExtension().appendingPathExtension("bak.json")
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.copyItem(at: catalogFileURL, to: backupURL)
            Self.logger.error("❌ Catalog decode failed, backup at: \(backupURL.path, privacy: .public)")
            entries = []
        }
    }

    /// Persist the current entries to the JSON file.
    private func persistCatalog() {
        do {
            let data = try encoder.encode(entries)
            try data.write(to: catalogFileURL, options: .atomic)
            Self.logger.debug("💾 Persisted catalog with \(self.entries.count) entries")
        } catch {
            Self.logger.error("❌ Failed to persist catalog: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Catalog Errors

/// Errors specific to `DynamicModelCatalog` operations.
enum DynamicModelCatalogError: LocalizedError {
    /// An entry with the same ID already exists in the catalog.
    case duplicateEntry(String)
    /// No entry with the specified ID was found.
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .duplicateEntry(let id):
            return "Model '\(id)' is already in the catalog."
        case .notFound(let id):
            return "Model '\(id)' not found in the catalog."
        }
    }
}
