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
#if os(iOS)
import UserNotifications
#endif

/// Manages downloading model files from HuggingFace, integrated with the ModelRegistry.
///
/// **Download strategy:**
/// 1. Check if the model file already exists in the app's Documents directory.
/// 2. Show pre-download confirmation with model size + available storage.
/// 3. Queue download (serial by default, configurable concurrency).
/// 4. Download uses background URLSession for transfers that survive app suspension.
/// 5. Supports pause/resume via `resumeData` capture.
/// 6. If the server returns 401, prompt for a HuggingFace API token and retry.
///
/// **File placement:** Models are downloaded to the app's Documents directory,
/// the same location `GalleryModelDiscovery` scans for local models. Each file
/// has `isExcludedFromBackup = true` to prevent iCloud backup bloat.
///
/// **Background session architecture:**
/// - Uses `URLSessionConfiguration.background(withIdentifier:)` for resilient downloads
/// - Delegate-based API (required for background sessions)
/// - AppDelegate handles `handleEventsForBackgroundURLSession:` for iOS session reattachment
/// - Download metadata persisted to UserDefaults to survive app termination
@Observable
final class ModelDownloadManager: NSObject, URLSessionDownloadDelegate {

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "EdgeAILab",
        category: "ModelDownloadManager"
    )

    // MARK: - Static Identifier

    /// Fixed background session identifier. Must be consistent across app launches.
    private static let backgroundSessionIdentifier = "com.andrewvoirol.GemmaEdgeGallery.downloads"

    // MARK: - Download State

    /// The download state for a specific model.
    enum DownloadState: Sendable {
        /// Model file exists on disk.
        case downloaded(URL)
        /// Download is in progress.
        case downloading(progress: Double)
        /// Waiting in serial download queue.
        case queued(position: Int)
        /// Download paused by user — can resume from saved progress.
        case paused(resumeData: Data, progress: Double)
        /// Not downloaded and not in progress.
        case notDownloaded
        /// Download failed.
        case failed(String)
        /// Server returned 401 — needs HuggingFace token.
        case authRequired
    }

    // MARK: - Download Progress

    /// Rich download progress metrics for UI display.
    struct DownloadProgress: Sendable {
        let progress: Double              // 0.0–1.0
        let bytesWritten: Int64
        let totalBytes: Int64
        let speedBytesPerSecond: Double   // Rolling average
        let estimatedSecondsRemaining: Double?

        var formattedSpeed: String {
            ByteCountFormatter.string(fromByteCount: Int64(speedBytesPerSecond), countStyle: .file) + "/s"
        }

        var formattedETA: String? {
            guard let seconds = estimatedSecondsRemaining, seconds > 0, seconds < 86400 else { return nil }
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = seconds > 3600 ? [.hour, .minute] : [.minute, .second]
            formatter.unitsStyle = .abbreviated
            return formatter.string(from: seconds)
        }

        var formattedBytesWritten: String {
            ByteCountFormatter.string(fromByteCount: bytesWritten, countStyle: .file)
        }

        var formattedTotalBytes: String {
            ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        }
    }

    // MARK: - Storage Check

    /// Pre-download storage validation result.
    struct StorageCheck: Sendable {
        let modelSize: Int64
        let availableSpace: Int64
        let hasEnoughSpace: Bool

        var formattedModelSize: String {
            ByteCountFormatter.string(fromByteCount: modelSize, countStyle: .file)
        }

        var formattedAvailableSpace: String {
            ByteCountFormatter.string(fromByteCount: availableSpace, countStyle: .file)
        }
    }

    // MARK: - Download Record (Persistence)

    /// Metadata for an active/queued download, persisted to UserDefaults.
    private struct DownloadRecord: Codable {
        let modelFile: String
        let downloadURLString: String
        let destinationPath: String
        var taskIdentifier: Int?
        var progress: Double
        var bytesWritten: Int64
        var totalBytes: Int64
        var startedAt: Date
        var resumeData: Data?
        var queuePosition: Int?
        var isCommunityModel: Bool
    }

    // MARK: - Published State

    /// Download state keyed by model file name.
    var downloadStates: [String: DownloadState] = [:]

    /// Rich download progress keyed by model file name.
    var downloadProgress: [String: DownloadProgress] = [:]

    /// Whether a token prompt should be shown (set when a download returns 401).
    var showTokenPrompt = false

    /// The model that triggered the token prompt (to retry after token entry).
    var pendingAuthModel: ModelMetadata?

    /// Maximum concurrent downloads (user-configurable in Settings).
    var maxConcurrentDownloads: Int = 1 {
        didSet {
            UserDefaults.standard.set(maxConcurrentDownloads, forKey: "maxConcurrentDownloads")
            processQueue()
        }
    }

    // MARK: - Background Session Support

    /// Completion handler from AppDelegate's `handleEventsForBackgroundURLSession`.
    /// Called after all pending background events are processed.
    var backgroundSessionCompletionHandler: (() -> Void)?

    // MARK: - Private State

    /// The background URLSession — created once and held for the app's lifetime.
    /// Marked @ObservationIgnored because `lazy` is incompatible with @Observable's
    /// property transformation, and this is internal state not observed by views.
    @ObservationIgnored
    private lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(
            withIdentifier: ModelDownloadManager.backgroundSessionIdentifier
        )
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false           // User explicitly requested — don't defer
        config.allowsCellularAccess = true       // Default: allow cellular (power users)
        config.timeoutIntervalForResource = 7200 // 2 hours for large models
        config.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    /// Active download records keyed by URLSessionTask.taskIdentifier.
    @ObservationIgnored
    private var activeRecords: [Int: DownloadRecord] = [:]

    /// Reverse mapping: model file name → task identifier.
    @ObservationIgnored
    private var fileToTaskId: [String: Int] = [:]

    /// Thread-safe record lookup for URLSession delegate callbacks.
    /// The delegate callbacks run on a background queue, but `activeRecords` is main-actor-isolated.
    /// This lock-protected copy allows synchronous access from `didFinishDownloadingTo`.
    @ObservationIgnored
    private let taskRecordLock = NSLock()
    @ObservationIgnored
    private var taskRecordMap: [Int: DownloadRecord] = [:]

    /// Update the thread-safe task record map (call from main actor after modifying activeRecords).
    private func syncTaskRecordMap() {
        let snapshot = activeRecords
        taskRecordLock.lock()
        taskRecordMap = snapshot
        taskRecordLock.unlock()
    }

    /// Thread-safe read of a download record by task identifier.
    private nonisolated func readTaskRecord(for taskId: Int) -> DownloadRecord? {
        taskRecordLock.lock()
        let record = taskRecordMap[taskId]
        taskRecordLock.unlock()
        return record
    }

    /// Download queue for models waiting to start.
    @ObservationIgnored
    private var downloadQueue: [QueuedDownload] = []

    /// Speed calculation samples for rolling average.
    @ObservationIgnored
    private var speedSamples: [String: [(timestamp: Date, bytes: Int64)]] = [:]

    /// The documents directory where models are stored.
    let documentsDirectory: URL

    /// Queued download item.
    private struct QueuedDownload {
        let modelFile: String
        let downloadURL: URL
        let isCommunityModel: Bool
    }

    // MARK: - Persistence Keys

    private let recordsKey = "active_download_records"
    private let concurrencyKey = "maxConcurrentDownloads"

    // MARK: - Init

    override init() {
        self.documentsDirectory = GalleryModelDiscovery.getAppModelsDirectory()
        super.init()

        // Restore user preference for concurrent downloads
        let saved = UserDefaults.standard.integer(forKey: concurrencyKey)
        if saved > 0 {
            maxConcurrentDownloads = saved
        }

        // Reconnect to any in-flight background downloads
        reconnectToBackgroundSession()
    }

    // MARK: - Background Session Reconnection

    /// Reconnect to the background session to pick up any downloads that completed
    /// while the app was terminated. This triggers delegate callbacks for pending events.
    private func reconnectToBackgroundSession() {
        // Accessing backgroundSession triggers lazy initialization, which
        // re-attaches to the existing background session (matching identifier).
        backgroundSession.getTasksWithCompletionHandler { [weak self] _, _, downloadTasks in
            Task { @MainActor [weak self] in
                guard let self else { return }

                // Load persisted records
                let records = self.loadRecords()

                // Match running tasks to persisted records
                for task in downloadTasks {
                    if let record = records.first(where: { $0.taskIdentifier == task.taskIdentifier }) {
                        self.activeRecords[task.taskIdentifier] = record
                        self.fileToTaskId[record.modelFile] = task.taskIdentifier
                        self.downloadStates[record.modelFile] = .downloading(progress: record.progress)
                    }
                }

                // Restore queued items
                for record in records where record.queuePosition != nil {
                    if self.downloadStates[record.modelFile] == nil {
                        self.downloadStates[record.modelFile] = .queued(position: record.queuePosition ?? 0)
                        if let url = URL(string: record.downloadURLString) {
                            self.downloadQueue.append(QueuedDownload(
                                modelFile: record.modelFile,
                                downloadURL: url,
                                isCommunityModel: record.isCommunityModel
                            ))
                        }
                    }
                }

                // Restore paused items
                for record in records where record.resumeData != nil {
                    if self.downloadStates[record.modelFile] == nil {
                        self.downloadStates[record.modelFile] = .paused(
                            resumeData: record.resumeData!,
                            progress: record.progress
                        )
                    }
                }

                // Sync thread-safe record map for delegate callbacks
                self.syncTaskRecordMap()
            }
        }
    }

    // MARK: - State Queries

    /// Check the download state for a model by scanning the filesystem.
    func checkState(for model: ModelMetadata) -> DownloadState {
        // Preserve active download/queue/pause states
        if let existing = downloadStates[model.modelFile] {
            switch existing {
            case .downloading, .queued, .paused:
                return existing
            default:
                break
            }
        }

        let fileURL = documentsDirectory.appendingPathComponent(model.modelFile)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let state = DownloadState.downloaded(fileURL)
            downloadStates[model.modelFile] = state
            return state
        } else if let discovered = GalleryModelDiscovery.discoverModels().first(where: { $0.filename == model.modelFile }) {
            let state = DownloadState.downloaded(discovered.url)
            downloadStates[model.modelFile] = state
            return state
        } else {
            if let cached = downloadStates[model.modelFile], case .downloaded = cached {
                downloadStates[model.modelFile] = .notDownloaded
            }
        }

        return downloadStates[model.modelFile] ?? .notDownloaded
    }

    /// Refresh download states for all registry models.
    func refreshStates() {
        for model in ModelRegistry.knownModels {
            let _ = checkState(for: model)
        }
    }

    // MARK: - Storage Validation

    /// Check available storage before downloading a model.
    func checkStorage(for model: ModelMetadata) -> StorageCheck {
        let modelSize = model.sizeInBytes
        let available = availableStorageBytes()
        let buffer: Int64 = 500_000_000 // 500 MB safety buffer
        return StorageCheck(
            modelSize: modelSize,
            availableSpace: available,
            hasEnoughSpace: available > modelSize + buffer
        )
    }

    /// Get available storage in bytes.
    func availableStorageBytes() -> Int64 {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let url,
              let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let capacity = values.volumeAvailableCapacityForImportantUsage else {
            return 0
        }
        return capacity
    }

    // MARK: - Download

    /// Start downloading a model file from HuggingFace.
    ///
    /// If the maximum concurrent download limit is reached, the model is queued.
    /// Call this AFTER the user confirms the pre-download storage dialog.
    ///
    /// - Parameter model: The model metadata with download URL.
    func download(_ model: ModelMetadata) {
        guard let downloadURL = model.downloadURL else {
            downloadStates[model.modelFile] = .failed("No download URL configured for this model.")
            return
        }

        // Don't start a duplicate download
        if fileToTaskId[model.modelFile] != nil { return }
        if downloadQueue.contains(where: { $0.modelFile == model.modelFile }) { return }

        let activeCount = currentActiveDownloadCount()
        if activeCount < maxConcurrentDownloads {
            startDownloadTask(modelFile: model.modelFile, downloadURL: downloadURL, isCommunityModel: false)
        } else {
            // Queue the download
            downloadQueue.append(QueuedDownload(
                modelFile: model.modelFile,
                downloadURL: downloadURL,
                isCommunityModel: false
            ))
            updateQueuePositions()
        }
    }

    /// Pause an active download, capturing resume data.
    func pauseDownload(_ model: ModelMetadata) {
        pauseDownload(filename: model.modelFile)
    }

    /// Pause by filename (works for community models too).
    func pauseDownload(filename: String) {
        guard let taskId = fileToTaskId[filename],
              let task = getDownloadTask(for: taskId) else { return }

        task.cancel(byProducingResumeData: { [weak self] resumeData in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let currentProgress: Double
                if case .downloading(let p) = self.downloadStates[filename] {
                    currentProgress = p
                } else {
                    currentProgress = 0
                }

                if let resumeData {
                    self.downloadStates[filename] = .paused(resumeData: resumeData, progress: currentProgress)
                    // Persist resume data
                    if var record = self.activeRecords[taskId] {
                        record.resumeData = resumeData
                        record.progress = currentProgress
                        self.activeRecords[taskId] = record
                    }
                } else {
                    self.downloadStates[filename] = .failed("Could not save download progress for resume.")
                }

                // Clean up task references
                self.activeRecords.removeValue(forKey: taskId)
                self.fileToTaskId.removeValue(forKey: filename)
                self.speedSamples.removeValue(forKey: filename)
                self.downloadProgress.removeValue(forKey: filename)
                self.saveRecords()
                self.processQueue()
            }
        })
    }

    /// Resume a paused download using saved resume data.
    func resumeDownload(_ model: ModelMetadata) {
        resumeDownload(filename: model.modelFile)
    }

    /// Resume by filename.
    func resumeDownload(filename: String) {
        guard case .paused(let resumeData, _) = downloadStates[filename] else { return }

        downloadStates[filename] = .downloading(progress: 0)

        let task = backgroundSession.downloadTask(withResumeData: resumeData)
        let taskId = task.taskIdentifier

        var record = DownloadRecord(
            modelFile: filename,
            downloadURLString: "",
            destinationPath: documentsDirectory.appendingPathComponent(filename).path,
            taskIdentifier: taskId,
            progress: 0,
            bytesWritten: 0,
            totalBytes: 0,
            startedAt: Date(),
            resumeData: nil,
            queuePosition: nil,
            isCommunityModel: false
        )
        // Try to restore from any existing record
        if let existingRecord = loadRecords().first(where: { $0.modelFile == filename }) {
            record = existingRecord
            record.taskIdentifier = taskId
            record.resumeData = nil
            record.queuePosition = nil
        }

        activeRecords[taskId] = record
        fileToTaskId[filename] = taskId
        syncTaskRecordMap()
        saveRecords()

        task.resume()
    }

    /// Cancel an active download.
    func cancelDownload(_ model: ModelMetadata) {
        cancelDownload(filename: model.modelFile)
    }

    /// Cancel by filename (works for both registry and community downloads).
    func cancelDownload(filename: String) {
        // Cancel active task
        if let taskId = fileToTaskId[filename] {
            getDownloadTask(for: taskId)?.cancel()
            activeRecords.removeValue(forKey: taskId)
            fileToTaskId.removeValue(forKey: filename)
        }

        // Remove from queue
        downloadQueue.removeAll { $0.modelFile == filename }
        updateQueuePositions()

        // Clean up
        speedSamples.removeValue(forKey: filename)
        downloadProgress.removeValue(forKey: filename)
        downloadStates[filename] = .notDownloaded
        saveRecords()
        processQueue()
    }

    /// Retry a download that requires authentication.
    func retryWithToken(_ model: ModelMetadata) {
        downloadStates[model.modelFile] = .notDownloaded
        download(model)
    }

    /// Delete a downloaded model file.
    func deleteModel(_ model: ModelMetadata) {
        deleteModel(filename: model.modelFile)
    }

    /// Delete a downloaded model by filename.
    func deleteModel(filename: String) {
        let fileURL = documentsDirectory.appendingPathComponent(filename)
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            logger.warning("Failed to delete model file: \(error.localizedDescription)")
        }
        downloadStates[filename] = .notDownloaded
        downloadProgress.removeValue(forKey: filename)
    }

    // MARK: - Community Model Download

    /// Callback invoked after a community model download completes.
    /// The parameter is the filename of the downloaded model.
    var postDownloadCallback: ((String, URL) -> Void)?

    /// Download an arbitrary LiteRT model from HuggingFace using dynamic URL construction.
    ///
    /// Unlike `download(_:)` which requires a pre-registered `ModelMetadata`, this method
    /// works with any `HFModelInfo` by finding the `.litertlm` sibling file and constructing
    /// the download URL dynamically.
    ///
    /// - Parameters:
    ///   - model: The HuggingFace model info from the community browser.
    ///   - sibling: The specific `.litertlm` file to download from the repo.
    func downloadCommunityModel(model: HFModelInfo, sibling: HFSibling) {
        let filename = sibling.rfilename

        // Don't start a duplicate download
        if fileToTaskId[filename] != nil { return }
        if downloadQueue.contains(where: { $0.modelFile == filename }) { return }

        let downloadURL = HFModelBrowser.downloadURL(
            repoId: model.id,
            filename: filename
        )

        let activeCount = currentActiveDownloadCount()
        if activeCount < maxConcurrentDownloads {
            startDownloadTask(modelFile: filename, downloadURL: downloadURL, isCommunityModel: true)
        } else {
            downloadQueue.append(QueuedDownload(
                modelFile: filename,
                downloadURL: downloadURL,
                isCommunityModel: true
            ))
            updateQueuePositions()
        }
    }

    // MARK: - Private — Download Task Management

    /// Start a new download task with the background session.
    private func startDownloadTask(modelFile: String, downloadURL: URL, isCommunityModel: Bool) {
        downloadStates[modelFile] = .downloading(progress: 0)

        var request = URLRequest(url: downloadURL)
        request.timeoutInterval = 7200 // 2 hours

        // Attach HF token if available
        if let token = HFTokenStorage.retrieve() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let task = backgroundSession.downloadTask(with: request)
        let taskId = task.taskIdentifier

        let record = DownloadRecord(
            modelFile: modelFile,
            downloadURLString: downloadURL.absoluteString,
            destinationPath: documentsDirectory.appendingPathComponent(modelFile).path,
            taskIdentifier: taskId,
            progress: 0,
            bytesWritten: 0,
            totalBytes: 0,
            startedAt: Date(),
            resumeData: nil,
            queuePosition: nil,
            isCommunityModel: isCommunityModel
        )

        activeRecords[taskId] = record
        fileToTaskId[modelFile] = taskId
        syncTaskRecordMap()
        saveRecords()

        task.resume()
    }

    /// Get the URLSessionDownloadTask for a given task identifier.
    private func getDownloadTask(for taskId: Int) -> URLSessionDownloadTask? {
        var result: URLSessionDownloadTask?
        let semaphore = DispatchSemaphore(value: 0)
        backgroundSession.getTasksWithCompletionHandler { _, _, downloadTasks in
            result = downloadTasks.first { $0.taskIdentifier == taskId }
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    /// Count currently active (non-queued, non-paused) downloads.
    private func currentActiveDownloadCount() -> Int {
        return downloadStates.values.filter {
            if case .downloading = $0 { return true }
            return false
        }.count
    }

    // MARK: - Private — Queue Management

    /// Process the queue: start downloads up to the concurrency limit.
    private func processQueue() {
        let activeCount = currentActiveDownloadCount()
        var slotsAvailable = maxConcurrentDownloads - activeCount

        while slotsAvailable > 0, !downloadQueue.isEmpty {
            let next = downloadQueue.removeFirst()
            startDownloadTask(
                modelFile: next.modelFile,
                downloadURL: next.downloadURL,
                isCommunityModel: next.isCommunityModel
            )
            slotsAvailable -= 1
        }

        updateQueuePositions()
    }

    /// Update queue position numbers in download states.
    private func updateQueuePositions() {
        for (index, item) in downloadQueue.enumerated() {
            downloadStates[item.modelFile] = .queued(position: index + 1)
        }
    }

    // MARK: - Private — Speed & ETA Calculation

    /// Calculate download speed using a rolling 5-second window.
    private func calculateSpeed(for modelFile: String, currentBytes: Int64) -> Double {
        let now = Date()
        speedSamples[modelFile, default: []].append((now, currentBytes))

        // Keep last 5 seconds of samples
        speedSamples[modelFile] = speedSamples[modelFile]?.filter {
            now.timeIntervalSince($0.timestamp) < 5
        } ?? []

        guard let first = speedSamples[modelFile]?.first,
              now.timeIntervalSince(first.timestamp) > 0.5 else {
            return 0
        }

        return Double(currentBytes - first.bytes) / now.timeIntervalSince(first.timestamp)
    }

    // MARK: - Private — Persistence

    /// Save active download records to UserDefaults.
    private func saveRecords() {
        var allRecords = Array(activeRecords.values)

        // Also save queued items
        for item in downloadQueue {
            let position = downloadQueue.firstIndex(where: { $0.modelFile == item.modelFile }).map { $0 + 1 }
            allRecords.append(DownloadRecord(
                modelFile: item.modelFile,
                downloadURLString: item.downloadURL.absoluteString,
                destinationPath: documentsDirectory.appendingPathComponent(item.modelFile).path,
                taskIdentifier: nil,
                progress: 0,
                bytesWritten: 0,
                totalBytes: 0,
                startedAt: Date(),
                resumeData: nil,
                queuePosition: position,
                isCommunityModel: item.isCommunityModel
            ))

        }

        // Save paused items (not in activeRecords)
        for (filename, state) in downloadStates {
            if case .paused(let data, let progress) = state {
                if !allRecords.contains(where: { $0.modelFile == filename }) {
                    allRecords.append(DownloadRecord(
                        modelFile: filename,
                        downloadURLString: "",
                        destinationPath: documentsDirectory.appendingPathComponent(filename).path,
                        taskIdentifier: nil,
                        progress: progress,
                        bytesWritten: 0,
                        totalBytes: 0,
                        startedAt: Date(),
                        resumeData: data,
                        queuePosition: nil,
                        isCommunityModel: false
                    ))
                }
            }
        }

        if let data = try? JSONEncoder().encode(allRecords) {
            UserDefaults.standard.set(data, forKey: recordsKey)
        }
    }

    /// Load persisted download records.
    private func loadRecords() -> [DownloadRecord] {
        guard let data = UserDefaults.standard.data(forKey: recordsKey),
              let records = try? JSONDecoder().decode([DownloadRecord].self, from: data) else {
            return []
        }
        return records
    }

    // MARK: - Private — iCloud Backup Exclusion

    /// Mark a file as excluded from iCloud backup.
    private func excludeFromBackup(_ url: URL) {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(resourceValues)
    }

    // MARK: - Private — Local Notifications

    #if os(iOS)
    /// Request notification permission (call early in app lifecycle).
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Send a local notification when a background download completes.
    private func sendDownloadCompleteNotification(modelFile: String) {
        // Try to find a display name from the registry
        let displayName = ModelRegistry.knownModels.first(where: { $0.modelFile == modelFile })?.name ?? modelFile

        let content = UNMutableNotificationContent()
        content.title = "\(displayName) is ready"
        content.body = "Model downloaded successfully. Tap to load it."
        content.sound = .default
        content.userInfo = ["modelFile": modelFile]

        let request = UNNotificationRequest(
            identifier: "download-complete-\(modelFile)",
            content: content,
            trigger: nil // Deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }
    #endif

    // MARK: - URLSessionDownloadDelegate

    /// Progress tracking — called on background queue.
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let taskId = downloadTask.taskIdentifier
        Task { @MainActor [weak self] in
            guard let self,
                  let record = self.activeRecords[taskId] else { return }

            let modelFile = record.modelFile
            let progress: Double
            if totalBytesExpectedToWrite != NSURLSessionTransferSizeUnknown {
                progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            } else {
                progress = 0
            }

            // Update state
            self.downloadStates[modelFile] = .downloading(progress: progress)

            // Calculate speed and ETA
            let speed = self.calculateSpeed(for: modelFile, currentBytes: totalBytesWritten)
            let eta: Double?
            if speed > 0, totalBytesExpectedToWrite != NSURLSessionTransferSizeUnknown {
                eta = Double(totalBytesExpectedToWrite - totalBytesWritten) / speed
            } else {
                eta = nil
            }

            self.downloadProgress[modelFile] = DownloadProgress(
                progress: progress,
                bytesWritten: totalBytesWritten,
                totalBytes: totalBytesExpectedToWrite,
                speedBytesPerSecond: speed,
                estimatedSecondsRemaining: eta
            )

            // Update persisted record
            var updatedRecord = record
            updatedRecord.progress = progress
            updatedRecord.bytesWritten = totalBytesWritten
            updatedRecord.totalBytes = totalBytesExpectedToWrite
            self.activeRecords[taskId] = updatedRecord
        }
    }

    /// Download completion — MUST move file before method returns.
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let taskId = downloadTask.taskIdentifier

        // We must access the record and move the file synchronously (before this method returns,
        // iOS deletes the temporary file). Read record from persisted storage as a fallback.
        let modelFile: String
        let destinationPath: String
        let isCommunityModel: Bool

        // Try thread-safe record map first, then persisted storage as fallback
        if let record = readTaskRecord(for: taskId) {
            modelFile = record.modelFile
            destinationPath = record.destinationPath
            isCommunityModel = record.isCommunityModel
        } else if let records = try? JSONDecoder().decode(
            [DownloadRecord].self,
            from: UserDefaults.standard.data(forKey: recordsKey) ?? Data()
        ), let record = records.first(where: { $0.taskIdentifier == taskId }) {
            modelFile = record.modelFile
            destinationPath = record.destinationPath
            isCommunityModel = record.isCommunityModel
        } else {
            // Unknown task — can't process
            return
        }

        let destinationURL = URL(fileURLWithPath: destinationPath)
        let fileManager = FileManager.default

        do {
            // Ensure destination directory exists
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            // Remove existing file if present
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }

            // Move from temp to permanent location
            try fileManager.moveItem(at: location, to: destinationURL)

            // Exclude from iCloud backup
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableURL = destinationURL
            try mutableURL.setResourceValues(resourceValues)

            // Update state on main actor
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.downloadStates[modelFile] = .downloaded(destinationURL)
                self.downloadProgress.removeValue(forKey: modelFile)
                self.speedSamples.removeValue(forKey: modelFile)
                self.activeRecords.removeValue(forKey: taskId)
                self.fileToTaskId.removeValue(forKey: modelFile)
                self.saveRecords()
                self.processQueue()

                // Fire community model callback
                if isCommunityModel {
                    self.postDownloadCallback?(modelFile, destinationURL)
                }

                // Send local notification (iOS only)
                #if os(iOS)
                self.sendDownloadCompleteNotification(modelFile: modelFile)
                #endif
            }
        } catch {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.downloadStates[modelFile] = .failed("Failed to save model: \(error.localizedDescription)")
                self.activeRecords.removeValue(forKey: taskId)
                self.fileToTaskId.removeValue(forKey: modelFile)
                self.saveRecords()
                self.processQueue()
            }
        }
    }

    /// Task completion/error handler — captures resumeData for pause/resume.
    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else { return } // Success is handled in didFinishDownloadingTo

        let taskId = task.taskIdentifier
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let record = self.activeRecords[taskId] else { return }
            let modelFile = record.modelFile

            let nsError = error as NSError

            if nsError.code == NSURLErrorCancelled {
                // Check for resume data (pause scenario)
                if let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                    let currentProgress: Double
                    if case .downloading(let p) = self.downloadStates[modelFile] {
                        currentProgress = p
                    } else {
                        currentProgress = record.progress
                    }
                    // Only set paused if not already cancelled by user
                    if case .paused = self.downloadStates[modelFile] {
                        // Already set by pauseDownload() — keep it
                    } else if self.downloadStates[modelFile] != nil,
                              case .notDownloaded = self.downloadStates[modelFile]! {
                        // User explicitly cancelled — keep notDownloaded
                    } else {
                        self.downloadStates[modelFile] = .paused(
                            resumeData: resumeData,
                            progress: currentProgress
                        )
                    }
                }
                // If no resume data and state is .notDownloaded, user cancelled — no action needed
            } else {
                // Check HTTP status for auth errors
                if let httpResponse = task.response as? HTTPURLResponse {
                    if httpResponse.statusCode == 401 {
                        self.downloadStates[modelFile] = .authRequired
                        if let model = ModelRegistry.knownModels.first(where: { $0.modelFile == modelFile }) {
                            self.pendingAuthModel = model
                        }
                        self.showTokenPrompt = true
                    } else if httpResponse.statusCode != 200 {
                        self.downloadStates[modelFile] = .failed(
                            "HTTP \(httpResponse.statusCode): Download failed."
                        )
                    }
                } else {
                    self.downloadStates[modelFile] = .failed(error.localizedDescription)
                }
            }

            // Clean up
            self.activeRecords.removeValue(forKey: taskId)
            self.fileToTaskId.removeValue(forKey: modelFile)
            self.speedSamples.removeValue(forKey: modelFile)
            self.downloadProgress.removeValue(forKey: modelFile)
            self.saveRecords()
            self.processQueue()
        }
    }

    /// Session-level completion — all background events processed.
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let handler = self.backgroundSessionCompletionHandler {
                self.backgroundSessionCompletionHandler = nil
                handler()
            }
        }
    }
}
