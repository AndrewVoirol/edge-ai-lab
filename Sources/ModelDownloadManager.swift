import Foundation
import Observation

/// Manages downloading model files from HuggingFace, integrated with the ModelRegistry.
///
/// **Download strategy:**
/// 1. Check if the model file already exists in the app's Documents directory.
/// 2. Attempt unauthenticated download via HuggingFace CDN.
/// 3. If the server returns 401, prompt for a HuggingFace API token and retry.
/// 4. Download uses URLSession for background-safe transfers with progress tracking.
///
/// **File placement:** Models are downloaded to the app's Documents directory,
/// the same location `GalleryModelDiscovery` scans for local models.
@Observable
final class ModelDownloadManager {

    // MARK: - Download State

    /// The download state for a specific model.
    enum DownloadState: Sendable {
        /// Model file exists on disk.
        case downloaded(URL)
        /// Download is in progress.
        case downloading(progress: Double)
        /// Not downloaded and not in progress.
        case notDownloaded
        /// Download failed.
        case failed(String)
        /// Server returned 401 — needs HuggingFace token.
        case authRequired
    }

    // MARK: - Published State

    /// Download state keyed by model file name.
    var downloadStates: [String: DownloadState] = [:]

    /// Whether a token prompt should be shown (set when a download returns 401).
    var showTokenPrompt = false

    /// The model that triggered the token prompt (to retry after token entry).
    var pendingAuthModel: ModelMetadata?

    // MARK: - Private State

    /// Active download tasks keyed by model file name.
    private var activeTasks: [String: URLSessionDownloadTask] = [:]

    /// Observation tokens for download progress.
    private var progressObservations: [String: NSKeyValueObservation] = [:]

    /// The documents directory where models are stored.
    let documentsDirectory: URL

    // MARK: - Init

    init() {
        self.documentsDirectory = GalleryModelDiscovery.getAppModelsDirectory()
    }

    // MARK: - State Queries

    /// Check the download state for a model by scanning the filesystem.
    func checkState(for model: ModelMetadata) -> DownloadState {
        if let existing = downloadStates[model.modelFile], case .downloading = existing {
            return existing
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

    // MARK: - Download

    /// Start downloading a model file from HuggingFace.
    /// - Parameter model: The model metadata with download URL.
    func download(_ model: ModelMetadata) {
        guard let downloadURL = model.downloadURL else {
            downloadStates[model.modelFile] = .failed("No download URL configured for this model.")
            return
        }

        // Don't start a duplicate download
        if activeTasks[model.modelFile] != nil {
            return
        }

        downloadStates[model.modelFile] = .downloading(progress: 0)

        var request = URLRequest(url: downloadURL)
        request.timeoutInterval = 3600  // 1 hour for large files

        // Attach HF token if available
        if let token = HFTokenStorage.retrieve() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let session = URLSession(
            configuration: .default,
            delegate: nil,
            delegateQueue: .main
        )

        let task = session.downloadTask(with: request) { [weak self] tempURL, response, error in
            Task { @MainActor in
                self?.handleDownloadCompletion(
                    model: model,
                    tempURL: tempURL,
                    response: response,
                    error: error
                )
            }
        }

        // Observe download progress
        let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            Task { @MainActor in
                self?.downloadStates[model.modelFile] = .downloading(progress: progress.fractionCompleted)
            }
        }
        progressObservations[model.modelFile] = observation

        activeTasks[model.modelFile] = task
        task.resume()
    }

    /// Cancel an active download.
    func cancelDownload(_ model: ModelMetadata) {
        activeTasks[model.modelFile]?.cancel()
        activeTasks.removeValue(forKey: model.modelFile)
        progressObservations.removeValue(forKey: model.modelFile)
        downloadStates[model.modelFile] = .notDownloaded
    }

    /// Retry a download that requires authentication.
    func retryWithToken(_ model: ModelMetadata) {
        downloadStates[model.modelFile] = .notDownloaded
        download(model)
    }

    /// Delete a downloaded model file.
    func deleteModel(_ model: ModelMetadata) {
        let fileURL = documentsDirectory.appendingPathComponent(model.modelFile)
        try? FileManager.default.removeItem(at: fileURL)
        downloadStates[model.modelFile] = .notDownloaded
    }

    // MARK: - Private

    private func handleDownloadCompletion(
        model: ModelMetadata,
        tempURL: URL?,
        response: URLResponse?,
        error: Error?
    ) {
        activeTasks.removeValue(forKey: model.modelFile)
        progressObservations.removeValue(forKey: model.modelFile)

        if let error = error {
            if (error as NSError).code == NSURLErrorCancelled {
                downloadStates[model.modelFile] = .notDownloaded
            } else {
                downloadStates[model.modelFile] = .failed(error.localizedDescription)
            }
            return
        }

        // Check for HTTP errors
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 401 {
                downloadStates[model.modelFile] = .authRequired
                pendingAuthModel = model
                showTokenPrompt = true
                return
            }

            if httpResponse.statusCode != 200 {
                downloadStates[model.modelFile] = .failed(
                    "HTTP \(httpResponse.statusCode): Download failed."
                )
                return
            }
        }

        guard let tempURL = tempURL else {
            downloadStates[model.modelFile] = .failed("No file received from server.")
            return
        }

        // Move the downloaded file to Documents
        let destinationURL = documentsDirectory.appendingPathComponent(model.modelFile)

        do {
            // Remove any existing file at the destination
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)
            downloadStates[model.modelFile] = .downloaded(destinationURL)
        } catch {
            downloadStates[model.modelFile] = .failed(
                "Failed to save model: \(error.localizedDescription)"
            )
        }
    }
}
