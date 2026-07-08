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
    private static let backgroundSessionIdentifier = "com.andrewvoirol.EdgeAILab.downloads"

    // MARK: - Download State

    /// The download state for a specific model.
    enum DownloadState: Sendable {
        /// Model file exists on disk.
        case downloaded(URL)
        /// Download is in progress (single file).
        case downloading(progress: Double)
        /// Multi-file download in progress (MLX models).
        case downloadingDirectory(progress: Double, completedFiles: Int, totalFiles: Int)
        /// Waiting in serial download queue.
        case queued(position: Int)
        /// Download paused by user — can resume from saved progress.
        case paused(resumeData: Data, progress: Double)
        /// Multi-file download paused.
        case pausedDirectory(progress: Double, completedFiles: Int, totalFiles: Int)
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

    // MARK: - Multi-File Download Types

    /// Tracks a multi-file model download (MLX directory models).
    ///
    /// MLX models consist of multiple files (config.json, tokenizer, safetensors shards)
    /// that must all be downloaded and verified before the model is usable.
    struct DirectoryDownload: Sendable {
        /// HuggingFace repo ID (e.g., "mlx-community/gemma-4-E2B-it-4bit").
        let modelId: String
        /// Runtime type for this model.
        let runtimeType: RuntimeType
        /// Individual file downloads within this model.
        var files: [FileDownload]
        /// Total expected size across all files.
        var totalBytes: Int64
        /// Sum of bytes downloaded across all files.
        var downloadedBytes: Int64 { files.reduce(0) { $0 + $1.downloadedBytes } }
        /// Whether all files are complete and verified.
        var isComplete: Bool { files.allSatisfy(\.isComplete) }
        /// Aggregate progress (0.0–1.0).
        var progress: Double { totalBytes > 0 ? Double(downloadedBytes) / Double(totalBytes) : 0 }
        /// Number of files that have completed download.
        var completedFileCount: Int { files.filter(\.isComplete).count }
        /// Local directory where files are stored.
        let localDirectory: URL
    }

    /// Tracks an individual file within a multi-file download.
    struct FileDownload: Sendable {
        /// Filename within the model directory (e.g., "model-00001-of-00003.safetensors").
        let filename: String
        /// HuggingFace download URL for this file.
        let url: URL
        /// Expected file size in bytes.
        let expectedSize: Int64
        /// Expected SHA-256 hash from HuggingFace manifest (nil if not available).
        let expectedHash: String?
        /// Bytes downloaded so far.
        var downloadedBytes: Int64
        /// Saved resume data for pausing/resuming.
        var resumeData: Data?
        /// Whether this file's download is complete.
        var isComplete: Bool
        /// Whether the SHA-256 hash has been verified after download.
        var hashVerified: Bool
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

    /// Custom URLSession configuration injected for testing.
    /// When set, `backgroundSession` uses this config instead of the default background config.
    @ObservationIgnored
    private var _testSessionConfiguration: URLSessionConfiguration?

    /// The URLSession used for downloads — background by default, or a test-injected config.
    /// Marked @ObservationIgnored because `lazy` is incompatible with @Observable's
    /// property transformation, and this is internal state not observed by views.
    @ObservationIgnored
    private lazy var backgroundSession: URLSession = {
        if let testConfig = _testSessionConfiguration {
            return URLSession(configuration: testConfig, delegate: self, delegateQueue: nil)
        }
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

    /// Testable initializer: inject a custom URLSession configuration and documents directory.
    ///
    /// Use this in tests to provide an ephemeral `URLSessionConfiguration` with `URLProtocol`
    /// registered, avoiding the background session infrastructure. Production code should
    /// continue using the default `init()`.
    ///
    /// - Parameters:
    ///   - configuration: The URLSession configuration to use (e.g., `.ephemeral` with test protocols).
    ///   - documentsDirectory: The directory where downloaded model files are stored.
    init(configuration: URLSessionConfiguration, documentsDirectory: URL) {
        self.documentsDirectory = documentsDirectory
        self._testSessionConfiguration = configuration
        super.init()
        // Don't reconnect to background session or restore UserDefaults in test mode
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
        // If we already know the state, return it immediately.
        // This prevents the infinite re-render loop: SwiftUI body evaluation calls
        // checkState() → mutation → view invalidation → body re-evaluation → checkState() ...
        // By returning the cached value, we avoid mutating @Observable state during render.
        if let existing = downloadStates[model.modelFile] {
            return existing
        }

        // For MLX directory models, delegate to the directory-aware checker
        // which validates config.json + .safetensors presence.
        if model.isMLXDirectoryModel {
            return checkMLXModelState(modelId: model.modelId)
        }

        // First-time check: scan filesystem to determine initial state.
        let fileURL = documentsDirectory.appendingPathComponent(model.modelFile)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let state = DownloadState.downloaded(fileURL)
            downloadStates[model.modelFile] = state
            return state
        } else if let discovered = GalleryModelDiscovery.discoverModels().first(where: { $0.filename == model.modelFile }) {
            let state = DownloadState.downloaded(discovered.url)
            downloadStates[model.modelFile] = state
            return state
        }

        // Mark as not downloaded — this is the initial state.
        downloadStates[model.modelFile] = .notDownloaded
        return .notDownloaded
    }

    /// Refresh download states for all registry models.
    ///
    /// Clears stale cached entries (downloaded, notDownloaded, failed, authRequired)
    /// so `checkState()` re-scans the filesystem. In-flight states (downloading,
    /// queued, paused) are preserved to avoid interrupting active downloads.
    func refreshStates() {
        // Preserve only in-flight states — clear everything else so checkState()
        // re-scans the filesystem for each model.
        downloadStates = downloadStates.filter { _, state in
            switch state {
            case .downloading, .downloadingDirectory, .queued, .paused, .pausedDirectory: return true
            default: return false
            }
        }
        // Re-check all registry models against the filesystem
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
    func pauseDownload(_ model: ModelMetadata) async {
        await pauseDownload(filename: model.modelFile)
    }

    /// Pause by filename (works for community models too).
    func pauseDownload(filename: String) async {
        guard let taskId = fileToTaskId[filename],
              let task = await getDownloadTask(for: taskId) else { return }

        let resumeData = await task.cancelByProducingResumeData()
        let currentProgress: Double
        if case .downloading(let p) = self.downloadStates[filename] {
            currentProgress = p
        } else {
            currentProgress = 0
        }

        if let resumeData, !resumeData.isEmpty {
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
    func cancelDownload(_ model: ModelMetadata) async {
        await cancelDownload(filename: model.modelFile)
    }

    /// Cancel by filename (works for both registry and community downloads).
    func cancelDownload(filename: String) async {
        // Cancel active task
        if let taskId = fileToTaskId[filename] {
            await getDownloadTask(for: taskId)?.cancel()
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

    /// Callbacks invoked after community model downloads complete, keyed by filename.
    /// Each callback fires once for its specific file, then is removed.
    var postDownloadCallbacks: [String: (String, URL) -> Void] = [:]

    /// Callback invoked after ANY model download completes (registry or community).
    /// Used by ConversationViewModel to auto-refresh discoveredModels.
    var onDownloadCompleted: ((String, URL) -> Void)?

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

    // MARK: - Multi-File Download (MLX Models)

    /// Active directory downloads keyed by model ID.
    @ObservationIgnored
    private var activeDirectoryDownloads: [String: DirectoryDownload] = [:]

    /// Maximum concurrent file downloads within a single model (parallel shard downloads).
    private let maxConcurrentShardDownloads = 3

    /// Download an MLX model's multi-file directory from HuggingFace.
    ///
    /// This method:
    /// 1. Fetches the file manifest from HuggingFace's tree API
    /// 2. Filters to required files (config, tokenizer, safetensors)
    /// 3. Downloads files in parallel (up to `maxConcurrentShardDownloads` at a time)
    /// 4. Verifies SHA-256 hash of each file after download
    /// 5. Marks the model as `.downloaded` only when ALL files are present and verified
    ///
    /// - Parameters:
    ///   - model: The HuggingFace model info.
    ///   - descriptors: Pre-computed download descriptors from `HFModelBrowser.downloadDescriptors`.
    func downloadMLXModel(
        modelId: String,
        descriptors: [(filename: String, url: URL, size: Int64, sha256: String?)]
    ) {
        // Use model ID with slashes replaced as the directory name
        let dirName = modelId.replacingOccurrences(of: "/", with: "--")

        // Don't start a duplicate download
        if activeDirectoryDownloads[modelId] != nil { return }

        let modelDir = documentsDirectory.appendingPathComponent(dirName)

        // If a regular file (e.g., a failed download stub) exists at the directory path,
        // remove it so we can create the directory. Without this, createDirectory silently
        // fails and all subsequent file writes go to the wrong location.
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: modelDir.path, isDirectory: &isDir), !isDir.boolValue {
            try? FileManager.default.removeItem(at: modelDir)
        }

        // Create the directory
        try? FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        // Build file downloads
        let fileDownloads = descriptors.map { desc in
            FileDownload(
                filename: desc.filename,
                url: desc.url,
                expectedSize: desc.size,
                expectedHash: desc.sha256,
                downloadedBytes: 0,
                resumeData: nil,
                isComplete: false,
                hashVerified: false
            )
        }

        let totalBytes = descriptors.reduce(Int64(0)) { $0 + $1.size }

        let dirDownload = DirectoryDownload(
            modelId: modelId,
            runtimeType: .mlx,
            files: fileDownloads,
            totalBytes: totalBytes,
            localDirectory: modelDir
        )

        activeDirectoryDownloads[modelId] = dirDownload
        downloadStates[dirName] = .downloadingDirectory(
            progress: 0,
            completedFiles: 0,
            totalFiles: fileDownloads.count
        )

        // Start the parallel download
        Task { @MainActor in
            await performDirectoryDownload(modelId: modelId, dirName: dirName)
        }
    }

    /// Perform the actual multi-file download with parallel shard downloads.
    private func performDirectoryDownload(modelId: String, dirName: String) async {
        guard var dirDownload = activeDirectoryDownloads[modelId] else { return }
        let modelDir = dirDownload.localDirectory

        do {
            // Download files in parallel batches
            try await withThrowingTaskGroup(of: (Int, URL).self) { group in
                var pendingIndices = Array(dirDownload.files.indices)
                var activeTasks = 0

                // Seed initial batch
                while activeTasks < maxConcurrentShardDownloads, !pendingIndices.isEmpty {
                    let index = pendingIndices.removeFirst()
                    let file = dirDownload.files[index]
                    activeTasks += 1

                    group.addTask { [weak self] in
                        guard let self else { throw CancellationError() }
                        let destURL = modelDir.appendingPathComponent(file.filename)
                        try await self.downloadSingleFile(from: file.url, to: destURL)
                        return (index, destURL)
                    }
                }

                // Process completed files and start new ones
                for try await (completedIndex, destURL) in group {
                    activeTasks -= 1

                    // Verify hash if available
                    let file = dirDownload.files[completedIndex]
                    if let expectedHash = file.expectedHash {
                        let verified = try await FileIntegrityChecker.verify(
                            file: destURL,
                            expectedHash: expectedHash
                        )
                        if !verified {
                            // Re-download on hash mismatch
                            logger.warning("⚠️ Hash mismatch for \(file.filename) — re-downloading")
                            try FileManager.default.removeItem(at: destURL)
                            try await self.downloadSingleFile(from: file.url, to: destURL)
                            let retryVerified = try await FileIntegrityChecker.verify(
                                file: destURL,
                                expectedHash: expectedHash
                            )
                            dirDownload.files[completedIndex].hashVerified = retryVerified
                        } else {
                            dirDownload.files[completedIndex].hashVerified = true
                        }
                    } else {
                        dirDownload.files[completedIndex].hashVerified = true
                    }

                    dirDownload.files[completedIndex].isComplete = true
                    dirDownload.files[completedIndex].downloadedBytes = file.expectedSize
                    activeDirectoryDownloads[modelId] = dirDownload

                    // Update UI state
                    downloadStates[dirName] = .downloadingDirectory(
                        progress: dirDownload.progress,
                        completedFiles: dirDownload.completedFileCount,
                        totalFiles: dirDownload.files.count
                    )

                    // Start next file if available
                    if !pendingIndices.isEmpty {
                        let nextIndex = pendingIndices.removeFirst()
                        let nextFile = dirDownload.files[nextIndex]
                        activeTasks += 1

                        group.addTask { [weak self] in
                            guard let self else { throw CancellationError() }
                            let nextDest = modelDir.appendingPathComponent(nextFile.filename)
                            try await self.downloadSingleFile(from: nextFile.url, to: nextDest)
                            return (nextIndex, nextDest)
                        }
                    }
                }
            }

            // All files complete — mark as downloaded
            excludeFromBackup(modelDir)
            downloadStates[dirName] = .downloaded(modelDir)
            downloadProgress.removeValue(forKey: dirName)
            activeDirectoryDownloads.removeValue(forKey: modelId)

            // Fire callbacks
            onDownloadCompleted?(dirName, modelDir)

            #if os(iOS)
            sendDownloadCompleteNotification(modelFile: dirName)
            #endif

        } catch {
            if error is CancellationError {
                // User cancelled — state already handled
            } else {
                downloadStates[dirName] = .failed("Download failed: \(error.localizedDescription)")
            }
            activeDirectoryDownloads.removeValue(forKey: modelId)
        }
    }

    /// Download a single file using URLSession (non-background, for multi-file orchestration).
    private func downloadSingleFile(from url: URL, to destination: URL) async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = 7200

        // Attach HF token if available
        if let token = HFTokenStorage.retrieve() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (tempURL, response) = try await URLSession.shared.download(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HFModelBrowserError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw HFModelBrowserError.httpError(statusCode: 401, repoId: url.absoluteString)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw HFModelBrowserError.httpStatusError(statusCode: httpResponse.statusCode)
        }

        // Ensure parent directory exists
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Remove existing file if present
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        // Move from temp to permanent location
        try FileManager.default.moveItem(at: tempURL, to: destination)

        // Exclude from iCloud backup
        excludeFromBackup(destination)
    }

    /// Cancel an active multi-file download.
    func cancelDirectoryDownload(modelId: String) {
        let dirName = modelId.replacingOccurrences(of: "/", with: "--")
        activeDirectoryDownloads.removeValue(forKey: modelId)
        downloadStates[dirName] = .notDownloaded
        downloadProgress.removeValue(forKey: dirName)

        // Clean up partially downloaded directory
        let modelDir = documentsDirectory.appendingPathComponent(dirName)
        try? FileManager.default.removeItem(at: modelDir)
    }

    /// Delete a downloaded MLX model directory.
    func deleteMLXModel(modelId: String) {
        let dirName = modelId.replacingOccurrences(of: "/", with: "--")
        let modelDir = documentsDirectory.appendingPathComponent(dirName)
        do {
            if FileManager.default.fileExists(atPath: modelDir.path) {
                try FileManager.default.removeItem(at: modelDir)
            }
        } catch {
            logger.warning("Failed to delete MLX model directory: \(error.localizedDescription)")
        }
        downloadStates[dirName] = .notDownloaded
        downloadProgress.removeValue(forKey: dirName)
    }

    /// Check whether an MLX model directory is fully downloaded and valid.
    ///
    /// A valid MLX model directory must contain `config.json` and at least one
    /// `.safetensors` file.
    func checkMLXModelState(modelId: String) -> DownloadState {
        let dirName = modelId.replacingOccurrences(of: "/", with: "--")

        // Return cached state if in-flight
        if let existing = downloadStates[dirName] {
            switch existing {
            case .downloading, .downloadingDirectory, .queued, .paused, .pausedDirectory:
                return existing
            case .downloaded:
                return existing
            default:
                break
            }
        }

        let modelDir = documentsDirectory.appendingPathComponent(dirName)
        let fm = FileManager.default

        guard fm.fileExists(atPath: modelDir.path) else {
            return .notDownloaded
        }

        let configPath = modelDir.appendingPathComponent("config.json").path
        guard fm.fileExists(atPath: configPath) else {
            return .notDownloaded
        }

        // Check for at least one safetensors file
        if let contents = try? fm.contentsOfDirectory(atPath: modelDir.path),
           contents.contains(where: { $0.hasSuffix(".safetensors") }) {
            // Cache the result so future reads don't hit filesystem
            let state = DownloadState.downloaded(modelDir)
            downloadStates[dirName] = state
            return state
        }

        return .notDownloaded
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
    private func getDownloadTask(for taskId: Int) async -> URLSessionDownloadTask? {
        let tasks = await backgroundSession.allTasks
        return tasks.compactMap { $0 as? URLSessionDownloadTask }
            .first { $0.taskIdentifier == taskId }
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

                // Fire general download-completed callback (refreshes discoveredModels)
                self.onDownloadCompleted?(modelFile, destinationURL)

                // Fire community model callback
                if isCommunityModel, let callback = self.postDownloadCallbacks[modelFile] {
                    callback(modelFile, destinationURL)
                    self.postDownloadCallbacks.removeValue(forKey: modelFile)
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
