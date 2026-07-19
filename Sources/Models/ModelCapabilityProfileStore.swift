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
import os

// MARK: - Profile Store

/// Persistence layer for `ModelCapabilityProfile` instances.
///
/// Profiles are stored as JSON at:
/// `~/Library/Application Support/EdgeAILab/ModelCatalog/profiles.json`
///
/// This matches the `DynamicModelCatalog` storage convention. Profiles are loaded
/// eagerly on init (for instant app launch) and lazily refreshed in the background
/// when the app foregrounds and the last check was >24h ago.
///
/// ## Thread Safety
/// All mutations are serialized through an internal lock. Read access is lock-free
/// after initial load.
@MainActor
final class ModelCapabilityProfileStore {

    // MARK: - Constants

    private static let logger = Logger(
        subsystem: "com.andrewvoirol.EdgeAILab",
        category: "ProfileStore"
    )

    /// How long before profiles are considered stale and should be refreshed.
    nonisolated static let refreshInterval: TimeInterval = 24 * 60 * 60  // 24 hours

    // MARK: - Storage

    /// In-memory cache of all profiles, keyed by profile ID.
    private var profiles: [String: ModelCapabilityProfile] = [:]

    /// When we last refreshed profiles from the network.
    private var lastRefreshDate: Date?

    /// File URL for persisted profiles.
    private let storageURL: URL

    // MARK: - JSON Coding

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Init

    init() {
        // Use the same directory as DynamicModelCatalog
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let catalogDir = appSupport
            .appendingPathComponent("EdgeAILab", isDirectory: true)
            .appendingPathComponent("ModelCatalog", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(
            at: catalogDir, withIntermediateDirectories: true
        )

        self.storageURL = catalogDir.appendingPathComponent("profiles.json")
        loadFromDisk()
    }

    // MARK: - Public API

    /// Get the profile for a model, by its ID.
    func profile(for id: String) -> ModelCapabilityProfile? {
        profiles[id]
    }

    /// Get all stored profiles.
    var allProfiles: [ModelCapabilityProfile] {
        Array(profiles.values)
    }

    /// Number of stored profiles.
    var count: Int {
        profiles.count
    }

    /// Store or update a profile.
    func upsert(_ profile: ModelCapabilityProfile) {
        profiles[profile.id] = profile
        saveToDisk()
    }

    /// Store or update multiple profiles at once (single disk write).
    func upsertBatch(_ newProfiles: [ModelCapabilityProfile]) {
        for profile in newProfiles {
            profiles[profile.id] = profile
        }
        saveToDisk()
    }

    /// Remove a profile by ID.
    func remove(id: String) {
        profiles.removeValue(forKey: id)
        saveToDisk()
    }

    /// Whether profiles should be refreshed based on staleness.
    var needsRefresh: Bool {
        guard let lastRefresh = lastRefreshDate else { return true }
        return Date().timeIntervalSince(lastRefresh) > Self.refreshInterval
    }

    /// Record that a refresh just completed.
    func markRefreshed() {
        lastRefreshDate = Date()
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            Self.logger.info("📂 No profiles.json found — starting fresh")
            return
        }

        do {
            let data = try Data(contentsOf: storageURL)
            let container = try decoder.decode(ProfileContainer.self, from: data)
            profiles = Dictionary(
                uniqueKeysWithValues: container.profiles.map { ($0.id, $0) }
            )
            lastRefreshDate = container.lastRefreshDate
            Self.logger.info("📂 Loaded \(self.profiles.count) profiles from disk")
        } catch {
            Self.logger.error("❌ Failed to load profiles.json: \(error.localizedDescription, privacy: .public)")
            // Back up corrupted file
            let backupURL = storageURL.deletingLastPathComponent()
                .appendingPathComponent("profiles.bak.json")
            try? FileManager.default.moveItem(at: storageURL, to: backupURL)
        }
    }

    private func saveToDisk() {
        let container = ProfileContainer(
            profiles: Array(profiles.values),
            lastRefreshDate: lastRefreshDate
        )

        do {
            let data = try encoder.encode(container)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            Self.logger.error("❌ Failed to save profiles.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Container

    /// Wrapper for serialization — includes both profiles and refresh timestamp.
    private struct ProfileContainer: Codable {
        let profiles: [ModelCapabilityProfile]
        let lastRefreshDate: Date?
    }
}
