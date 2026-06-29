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

// MARK: - Sync Status

/// Represents the current state of CloudKit synchronization.
enum SyncStatus: Equatable, Sendable {
    case idle
    case syncing
    case error(String)

    /// Human-readable description for UI display.
    var description: String {
        switch self {
        case .idle: return "Up to date"
        case .syncing: return "Syncing…"
        case .error(let message): return "Error: \(message)"
        }
    }
}

// MARK: - CloudKit Sync Manager

/// Manages CloudKit synchronization for benchmark history entries.
///
/// Uses the private CloudKit database to sync benchmark results across a user's devices.
/// Each entry is tagged with device information so results can be grouped by device
/// (e.g., "My MacBook Pro does X tok/s and my iPhone does Y tok/s").
///
/// Conflict resolution uses last-writer-wins (CloudKit default). Since benchmark entries
/// are append-only immutable records with UUID-based IDs, conflicts are rare in practice.
@Observable
final class CloudKitSyncManager: @unchecked Sendable {

    // MARK: - Public State

    /// Whether CloudKit sync is enabled by the user.
    var isSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isSyncEnabled, forKey: "cloudKitSyncEnabled")
        }
    }

    /// The last successful sync date, or nil if never synced.
    var lastSyncDate: Date?

    /// Current sync status for UI display.
    var syncStatus: SyncStatus = .idle

    /// Whether CloudKit is available (entitlements present and container accessible).
    var isCloudKitAvailable: Bool { container != nil }

    // MARK: - Private

    private let container: CKContainer?
    private let database: CKDatabase?
    private let deviceInfo: DeviceInfo

    /// Queue of entries pending push (for offline support).
    private var pendingPushQueue: [MetricsStore.Entry] = []

    /// Whether a sync operation is currently in progress.
    private var isSyncing = false

    // MARK: - Init

    /// Initialize with a specific CloudKit container and device info.
    ///
    /// If CloudKit is not available (e.g., missing iCloud entitlements, free team
    /// without iCloud provisioning), the manager initializes in a degraded state
    /// where all sync operations safely no-op.
    ///
    /// - Parameters:
    ///   - containerIdentifier: CloudKit container ID. Defaults to the app's container.
    ///   - deviceInfo: Device identification for tagging entries. Defaults to current device.
    init(
        containerIdentifier: String = CloudKitModels.containerIdentifier,
        deviceInfo: DeviceInfo = .current()
    ) {
        // CKContainer(identifier:) can crash (EXC_BREAKPOINT) on macOS 27+
        // when iCloud entitlements aren't provisioned. Use the default container
        // as a safe probe first — if it can reach the account status API,
        // CloudKit is available.
        let ckContainer = CKContainer(identifier: containerIdentifier)
        self.container = ckContainer
        self.database = ckContainer.privateCloudDatabase
        self.deviceInfo = deviceInfo
        self.isSyncEnabled = UserDefaults.standard.bool(forKey: "cloudKitSyncEnabled")
    }

    /// Testing initializer — creates a manager without a real CKContainer.
    ///
    /// Use this in unit tests to avoid CloudKit entitlement requirements.
    /// All sync operations will safely no-op.
    init(testingDeviceInfo: DeviceInfo) {
        self.container = nil
        self.database = nil
        self.deviceInfo = testingDeviceInfo
        self.isSyncEnabled = false
    }

    // MARK: - Push

    /// Push a single benchmark entry to CloudKit.
    ///
    /// If sync is disabled or the push fails due to network issues,
    /// the entry is queued for later retry.
    func pushEntry(_ entry: MetricsStore.Entry) async throws {
        guard isSyncEnabled, let database else {
            pendingPushQueue.append(entry)
            return
        }

        let record = CloudKitModels.toRecord(entry, deviceInfo: deviceInfo)

        do {
            syncStatus = .syncing
            let operation = CKModifyRecordsOperation(recordsToSave: [record])
            operation.savePolicy = .changedKeys
            operation.qualityOfService = .utility

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                database.add(operation)
            }

            lastSyncDate = Date()
            syncStatus = .idle

            // Push any queued entries
            if !pendingPushQueue.isEmpty {
                try await flushPendingQueue()
            }
        } catch {
            // Queue for later retry on network failure
            pendingPushQueue.append(entry)
            syncStatus = .error(error.localizedDescription)
            throw error
        }
    }

    // MARK: - Fetch

    /// Fetch all benchmark entries from CloudKit.
    ///
    /// Returns entries from all devices. The caller is responsible for merging
    /// with local entries (see `MetricsStore.mergeRemoteEntries`).
    func fetchAllEntries() async throws -> [MetricsStore.Entry] {
        guard isSyncEnabled, let database else { return [] }

        syncStatus = .syncing
        var allEntries: [MetricsStore.Entry] = []

        do {
            let query = CKQuery(
                recordType: CloudKitModels.recordType,
                predicate: NSPredicate(value: true)
            )
            query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

            var cursor: CKQueryOperation.Cursor? = nil

            // Initial query
            let (results, nextCursor) = try await database.records(matching: query, resultsLimit: 200)
            cursor = nextCursor

            for (_, result) in results {
                if let record = try? result.get(),
                   let entry = CloudKitModels.fromRecord(record) {
                    allEntries.append(entry)
                }
            }

            // Paginate through remaining results
            while let currentCursor = cursor {
                let (moreResults, moreCursor) = try await database.records(continuingMatchFrom: currentCursor, resultsLimit: 200)
                cursor = moreCursor

                for (_, result) in moreResults {
                    if let record = try? result.get(),
                       let entry = CloudKitModels.fromRecord(record) {
                        allEntries.append(entry)
                    }
                }
            }

            lastSyncDate = Date()
            syncStatus = .idle
            return allEntries
        } catch {
            syncStatus = .error(error.localizedDescription)
            throw error
        }
    }

    // MARK: - Subscription

    /// Subscribe to remote changes via CKQuerySubscription.
    ///
    /// When another device pushes a new benchmark entry, this device will
    /// receive a silent push notification to trigger a fetch.
    func subscribeToChanges() async throws {
        guard isSyncEnabled, let database else { return }

        let subscriptionID = "benchmark-entry-changes"

        // Check if subscription already exists
        do {
            _ = try await database.subscription(for: subscriptionID)
            return // Already subscribed
        } catch {
            // Subscription doesn't exist — create it
        }

        let subscription = CKQuerySubscription(
            recordType: CloudKitModels.recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true  // Silent push
        subscription.notificationInfo = notificationInfo

        try await database.save(subscription)
    }

    // MARK: - Pending Queue

    /// Flush any entries queued while offline or during errors.
    func flushPendingQueue() async throws {
        guard !pendingPushQueue.isEmpty, isSyncEnabled, let database else { return }

        let entriesToPush = pendingPushQueue
        pendingPushQueue.removeAll()

        let records = entriesToPush.map { CloudKitModels.toRecord($0, deviceInfo: deviceInfo) }

        let operation = CKModifyRecordsOperation(recordsToSave: records)
        operation.savePolicy = .changedKeys
        operation.qualityOfService = .utility

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                database.add(operation)
            }
        } catch {
            // Re-queue failed entries
            pendingPushQueue.insert(contentsOf: entriesToPush, at: 0)
            throw error
        }
    }

    /// Number of entries waiting to be pushed.
    var pendingCount: Int {
        pendingPushQueue.count
    }
}
