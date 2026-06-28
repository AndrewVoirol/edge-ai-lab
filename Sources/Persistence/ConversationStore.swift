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

// MARK: - Conversation Store

/// JSON file-based persistence layer for saved experiment conversations.
///
/// Each conversation is stored as a single JSON file in:
/// `~/Library/Application Support/EdgeAILab/Conversations/{uuid}.json`
///
/// An index file (`index.json`) caches titles, summaries, and metadata for
/// fast sidebar rendering without deserializing every conversation file.
///
/// **Thread Safety**: All mutations are performed synchronously on the file system.
/// The `@Observable` properties should only be updated from the MainActor.
@Observable
@MainActor
final class ConversationStore {

    private static let logger = Logger(
        subsystem: "com.andrewvoirol.EdgeAILab",
        category: "conversationStore"
    )

    // MARK: - Published State

    /// Cached list of conversation index entries, sorted by lastModifiedAt descending.
    /// Used for sidebar rendering without loading full conversation data.
    var indexEntries: [ConversationIndexEntry] = []

    // MARK: - Storage

    /// Root directory for conversation storage.
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
            // Default: ~/Library/Application Support/EdgeAILab/Conversations/
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            self.storageDirectory = appSupport
                .appendingPathComponent("EdgeAILab", isDirectory: true)
                .appendingPathComponent("Conversations", isDirectory: true)
        }

        ensureStorageDirectory()
        loadIndex()
    }

    // MARK: - CRUD Operations

    /// Save a conversation to disk and update the index.
    func save(_ conversation: SavedConversation) throws {
        let fileURL = fileURL(for: conversation.id)

        do {
            let data = try encoder.encode(conversation)
            try data.write(to: fileURL, options: .atomic)
            Self.logger.info("💾 Saved conversation: \(conversation.title, privacy: .public) (\(conversation.id))")
        } catch {
            Self.logger.error("❌ Failed to save conversation: \(error.localizedDescription, privacy: .public)")
            throw ConversationStoreError.saveFailed(error)
        }

        // Update index
        let entry = ConversationIndexEntry(from: conversation)
        if let existingIndex = indexEntries.firstIndex(where: { $0.id == conversation.id }) {
            indexEntries[existingIndex] = entry
        } else {
            indexEntries.insert(entry, at: 0)
        }
        sortIndex()
        persistIndex()
    }

    /// Load a full conversation from disk by ID.
    ///
    /// If the file exists but is corrupt (truncated JSON, incompatible schema),
    /// the stale index entry is removed so the sidebar self-heals.
    func load(id: UUID) throws -> SavedConversation {
        let fileURL = fileURL(for: id)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            // File is gone — clean up the index entry if present
            if indexEntries.contains(where: { $0.id == id }) {
                indexEntries.removeAll { $0.id == id }
                persistIndex()
                Self.logger.warning("🧹 Removed stale index entry for missing file: \(id)")
            }
            throw ConversationStoreError.notFound(id)
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let conversation = try decoder.decode(SavedConversation.self, from: data)
            Self.logger.info("📂 Loaded conversation: \(conversation.title, privacy: .public)")
            return conversation
        } catch {
            // File exists but is corrupt (truncated write, schema mismatch).
            // Remove the stale index entry and quarantine the file so the
            // sidebar doesn't repeatedly show a broken conversation.
            Self.logger.error("❌ Corrupt conversation file \(id): \(error.localizedDescription, privacy: .public)")
            indexEntries.removeAll { $0.id == id }
            persistIndex()
            // Rename corrupt file instead of deleting — preserves data for debugging
            let corruptURL = fileURL.appendingPathExtension("corrupt")
            try? FileManager.default.moveItem(at: fileURL, to: corruptURL)
            Self.logger.warning("🧹 Quarantined corrupt file: \(corruptURL.lastPathComponent, privacy: .public)")
            throw ConversationStoreError.loadFailed(error)
        }
    }

    /// Delete a conversation from disk and remove from the index.
    func delete(id: UUID) throws {
        let fileURL = fileURL(for: id)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try FileManager.default.removeItem(at: fileURL)
                Self.logger.info("🗑️ Deleted conversation: \(id)")
            } catch {
                Self.logger.error("❌ Failed to delete conversation: \(error.localizedDescription, privacy: .public)")
                throw ConversationStoreError.deleteFailed(error)
            }
        }

        indexEntries.removeAll { $0.id == id }
        persistIndex()
    }

    // MARK: - Bulk Delete Operations

    /// Delete all conversations from disk and clear the index.
    ///
    /// Continues deleting remaining conversations if individual deletions fail.
    /// - Returns: The number of conversations that were successfully deleted.
    /// - Throws: `ConversationStoreError.deleteFailed` if any deletion fails,
    ///   after attempting all deletions.
    @discardableResult
    func deleteAll() throws -> Int {
        let entriesToDelete = indexEntries
        var deletedCount = 0
        var lastError: Error?

        for entry in entriesToDelete {
            let fileURL = fileURL(for: entry.id)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    try FileManager.default.removeItem(at: fileURL)
                    deletedCount += 1
                } catch {
                    Self.logger.error("❌ Failed to delete conversation \(entry.id): \(error.localizedDescription, privacy: .public)")
                    lastError = error
                }
            } else {
                // File already gone — still counts as "deleted" for index cleanup
                deletedCount += 1
            }
        }

        indexEntries.removeAll()
        persistIndex()
        Self.logger.info("🗑️ Bulk deleted \(deletedCount) conversations")

        if let error = lastError {
            throw ConversationStoreError.deleteFailed(error)
        }
        return deletedCount
    }

    /// Delete multiple conversations by their IDs.
    ///
    /// Continues deleting remaining conversations if individual deletions fail.
    /// - Parameter ids: Set of conversation UUIDs to delete.
    /// - Returns: The number of conversations that were successfully deleted.
    /// - Throws: `ConversationStoreError.deleteFailed` if any deletion fails,
    ///   after attempting all deletions.
    @discardableResult
    func deleteMultiple(ids: Set<UUID>) throws -> Int {
        var deletedCount = 0
        var lastError: Error?

        for id in ids {
            let fileURL = fileURL(for: id)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    try FileManager.default.removeItem(at: fileURL)
                    deletedCount += 1
                } catch {
                    Self.logger.error("❌ Failed to delete conversation \(id): \(error.localizedDescription, privacy: .public)")
                    lastError = error
                }
            } else {
                deletedCount += 1
            }
        }

        indexEntries.removeAll { ids.contains($0.id) }
        persistIndex()
        Self.logger.info("🗑️ Bulk deleted \(deletedCount) of \(ids.count) conversations")

        if let error = lastError {
            throw ConversationStoreError.deleteFailed(error)
        }
        return deletedCount
    }

    /// Delete all conversations older than the given date.
    ///
    /// Uses `lastModifiedAt` from the index to determine age.
    /// - Parameter date: Conversations with `lastModifiedAt` before this date are deleted.
    /// - Returns: The number of conversations that were successfully deleted.
    /// - Throws: `ConversationStoreError.deleteFailed` if any deletion fails,
    ///   after attempting all deletions.
    @discardableResult
    func deleteOlderThan(_ date: Date) throws -> Int {
        let oldIds = Set(indexEntries.filter { $0.lastModifiedAt < date }.map(\.id))
        guard !oldIds.isEmpty else { return 0 }
        return try deleteMultiple(ids: oldIds)
    }

    /// Rename a conversation's title.
    func rename(id: UUID, newTitle: String) throws {
        var conversation = try load(id: id)
        conversation = SavedConversation(
            id: conversation.id,
            title: newTitle,
            config: conversation.config,
            messages: conversation.messages,
            summary: conversation.summary,
            createdAt: conversation.createdAt,
            lastModifiedAt: conversation.lastModifiedAt,
            forkedFrom: conversation.forkedFrom
        )
        try save(conversation)
    }

    /// Export a conversation as raw JSON data (for file export).
    func exportJSON(id: UUID) throws -> Data {
        let fileURL = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ConversationStoreError.notFound(id)
        }
        return try Data(contentsOf: fileURL)
    }

    /// Reload the index from disk (e.g., after external changes).
    func refresh() {
        loadIndex()
    }

    // MARK: - Private Helpers

    /// File URL for a specific conversation.
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
                Self.logger.info("📁 Created conversation storage directory")
            } catch {
                Self.logger.error("❌ Failed to create storage directory: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Load index entries from the index file, or rebuild from conversation files.
    ///
    /// After loading the index, cross-checks the entry count against the actual
    /// number of conversation JSON files on disk. If they differ (e.g., due to
    /// a crash between file write and index update), triggers a rebuild to
    /// restore consistency.
    private func loadIndex() {
        let fm = FileManager.default

        // Try to load the index file first (fast path)
        if fm.fileExists(atPath: indexFileURL.path),
           let data = try? Data(contentsOf: indexFileURL),
           let entries = try? decoder.decode([ConversationIndexEntry].self, from: data) {
            indexEntries = entries
            sortIndex()

            // Staleness check: compare index entry count against actual files on disk.
            // If a crash occurred between a file write and index update, they'll differ.
            let fileCount = conversationFileCount()
            if fileCount != entries.count {
                Self.logger.warning("⚠️ Index stale: \(entries.count) entries vs \(fileCount) files — rebuilding")
                rebuildIndex()
            } else {
                Self.logger.info("📋 Loaded index with \(entries.count) entries")
            }
            return
        }

        // Rebuild index from conversation files (slow path, first launch or corruption)
        rebuildIndex()
    }

    /// Count the number of conversation JSON files on disk (excluding index.json).
    private func conversationFileCount() -> Int {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil) else {
            return 0
        }
        return files.filter { $0.pathExtension == "json" && $0.lastPathComponent != "index.json" }.count
    }

    /// Rebuild the index by scanning all conversation files.
    private func rebuildIndex() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "json" && $0.lastPathComponent != "index.json" }) else {
            indexEntries = []
            return
        }

        var entries: [ConversationIndexEntry] = []
        for file in files {
            if let data = try? Data(contentsOf: file),
               let conversation = try? decoder.decode(SavedConversation.self, from: data) {
                entries.append(ConversationIndexEntry(from: conversation))
            }
        }

        indexEntries = entries
        sortIndex()
        persistIndex()
        Self.logger.info("🔄 Rebuilt index from \(entries.count) conversation files")
    }

    /// Sort index entries by lastModifiedAt descending (newest first).
    private func sortIndex() {
        indexEntries.sort { $0.lastModifiedAt > $1.lastModifiedAt }
    }

    /// Persist the current index to disk.
    private func persistIndex() {
        do {
            let data = try encoder.encode(indexEntries)
            try data.write(to: indexFileURL, options: .atomic)
        } catch {
            Self.logger.error("❌ Failed to persist index: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Conversation Index Entry

/// Lightweight index entry for sidebar rendering without loading the full conversation.
///
/// Contains just enough data to render a conversation row in the sidebar:
/// title, model name, summary, timestamps, and active feature badges.
struct ConversationIndexEntry: Codable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let modelShortName: String
    let configLightSummary: String
    let activeFeatureBadges: [String]
    let messageCount: Int
    let averageDecodeSpeed: Double?
    let totalTokens: Int
    let createdAt: Date
    let lastModifiedAt: Date
    let forkedFrom: UUID?

    init(from conversation: SavedConversation) {
        self.id = conversation.id
        self.title = conversation.title
        self.modelShortName = conversation.config.modelShortName
        self.configLightSummary = conversation.config.lightSummary
        self.activeFeatureBadges = conversation.config.activeFeatureBadges
        self.messageCount = conversation.summary.messageCount
        self.averageDecodeSpeed = conversation.summary.averageDecodeSpeed
        self.totalTokens = conversation.summary.totalTokens
        self.createdAt = conversation.createdAt
        self.lastModifiedAt = conversation.lastModifiedAt
        self.forkedFrom = conversation.forkedFrom
    }
}

// MARK: - Errors

/// Errors specific to conversation storage operations.
enum ConversationStoreError: LocalizedError {
    case saveFailed(Error)
    case loadFailed(Error)
    case deleteFailed(Error)
    case notFound(UUID)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let error):
            return "Failed to save conversation: \(error.localizedDescription)"
        case .loadFailed(let error):
            return "Failed to load conversation: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete conversation: \(error.localizedDescription)"
        case .notFound(let id):
            return "Conversation not found: \(id)"
        }
    }
}
