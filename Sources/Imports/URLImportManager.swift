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

// MARK: - URL Import Manager

/// Orchestrates the full paste-URL-to-download pipeline for importing models
/// from HuggingFace and Kaggle.
///
/// **Workflow:**
/// 1. User pastes a HuggingFace or Kaggle model URL
/// 2. Manager detects the source and parses the URL accordingly:
///    - **Kaggle:** Extracts the model handle via `KaggleModelParser`
///    - **HuggingFace:** Extracts org/repo (and optionally a specific file)
/// 3. Fetches model details from the appropriate API
/// 4. Runs `ModelCardParser` to infer metadata (HuggingFace) or builds
///    metadata from the Kaggle handle directly
/// 5. Presents the inferred metadata for user confirmation
/// 6. On confirmation, starts the download via `ModelDownloadManager`
/// 7. Adds the completed model to `DynamicModelCatalog`
///
/// **Supported URL Formats:**
///
/// *HuggingFace:*
/// - `https://huggingface.co/{org}/{repo}`
/// - `https://huggingface.co/{org}/{repo}/blob/main/{file}`
/// - `https://huggingface.co/{org}/{repo}/tree/main`
/// - `https://hf.co/{org}/{repo}` (short URL)
///
/// *Kaggle:*
/// - `https://www.kaggle.com/models/{owner}/{model}`
/// - `https://www.kaggle.com/models/{owner}/{model}/{framework}/{variation}/{version}`
///
/// **State Machine:**
/// ```
/// idle → parsing → fetching → analyzing → readyToDownload
///                                              ↓
///                                         downloading → complete
///                                              ↓
///                                           failed
/// ```
@Observable
@MainActor
final class URLImportManager {

    private static let logger = Logger(
        subsystem: "com.andrewvoirol.EdgeAILab",
        category: "urlImportManager"
    )

    // MARK: - Import State

    /// The current state of the import pipeline.
    enum ImportState: Sendable {
        /// No import in progress.
        case idle
        /// Parsing the pasted URL to extract repository information.
        case parsing(url: String)
        /// Fetching model details from the HuggingFace API.
        case fetching(repoId: String)
        /// Analyzing the model to infer metadata.
        case analyzing(model: HFModelInfo)
        /// Metadata inferred; waiting for user confirmation to download.
        case readyToDownload(metadata: DynamicModelMetadata, files: [HFSibling])
        /// Download in progress (progress tracked by ModelDownloadManager).
        case downloading(filename: String)
        /// Import completed successfully.
        case complete(metadata: DynamicModelMetadata)
        /// Import failed with an error message.
        case failed(error: String)
    }

    /// Parsed URL components extracted from a HuggingFace URL.
    struct ParsedHFURL: Sendable {
        /// The organization/user name.
        let org: String
        /// The repository name.
        let repo: String
        /// The full repo ID (org/repo).
        var repoId: String { "\(org)/\(repo)" }
        /// An optional specific file path within the repo.
        let specificFile: String?
    }

    // MARK: - State

    /// Current import state, observed by the UI.
    var state: ImportState = .idle

    /// The most recently imported model, available after `.complete`.
    var lastImportedModel: DynamicModelMetadata?

    // MARK: - Kaggle Credentials

    /// Kaggle username for API authentication. Set via Settings.
    var kaggleUsername: String?

    /// Kaggle API key for authentication. Set via Settings.
    var kaggleAPIKey: String?

    // MARK: - Dependencies

    /// HuggingFace API client for fetching model details.
    private let browser: HFModelBrowser

    /// Persistent model catalog for storing imported models.
    private let catalog: DynamicModelCatalog

    // MARK: - Init

    /// Create a new URL import manager.
    ///
    /// - Parameters:
    ///   - browser: The HuggingFace API client to use for fetching model info.
    ///   - catalog: The persistent catalog to store imported models.
    init(browser: HFModelBrowser, catalog: DynamicModelCatalog) {
        self.browser = browser
        self.catalog = catalog
    }

    // MARK: - Import Pipeline

    /// Start the import pipeline from a pasted URL string.
    ///
    /// This method drives the full state machine from parsing through to
    /// `readyToDownload`. The actual download is triggered separately via
    /// `confirmDownload(metadata:file:downloadManager:)`.
    ///
    /// Supports both Kaggle and HuggingFace URLs. Kaggle URLs are detected
    /// first; if the URL isn't a Kaggle model URL, it falls through to the
    /// existing HuggingFace import flow.
    ///
    /// - Parameter urlString: The model URL to import from (Kaggle or HuggingFace).
    func importFromURL(_ urlString: String) async {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        state = .parsing(url: trimmed)

        Self.logger.info("🔗 Importing from URL: \(trimmed, privacy: .public)")

        // Load Kaggle credentials from Keychain
        kaggleUsername = KaggleTokenStorage.retrieveUsername()
        kaggleAPIKey = KaggleTokenStorage.retrieveAPIKey()

        // Step 0: Check for Kaggle URL first
        if let kaggleHandle = KaggleModelParser.parseURL(trimmed) {
            await importFromKaggle(handle: kaggleHandle)
            return
        }

        // Step 1: Parse URL (HuggingFace)
        guard let parsed = parseHuggingFaceURL(trimmed) else {
            state = .failed(error: "Invalid URL. Please paste a HuggingFace or Kaggle model URL (e.g., https://huggingface.co/org/model or https://www.kaggle.com/models/owner/model).")
            Self.logger.error("❌ Failed to parse URL: \(trimmed, privacy: .public)")
            return
        }

        // Step 2: Check if already in known registry
        if let known = ModelRegistry.knownModels.first(where: { $0.modelId == parsed.repoId }) {
            let dynamicMeta = DynamicModelMetadata.fromKnownModel(known)
            // Verify the model file actually exists on disk
            let localModels = GalleryModelDiscovery.discoverModels()
            if localModels.contains(where: { $0.filename == known.modelFile }) {
                state = .complete(metadata: dynamicMeta)
                lastImportedModel = dynamicMeta
                Self.logger.info("✅ Model already in known registry and on disk: \(parsed.repoId, privacy: .public)")
                return
            } else {
                Self.logger.info("📦 Model in known registry but not on disk — offering download: \(parsed.repoId, privacy: .public)")
                // Fall through to the HF API fetch to get file listing for download
            }
        }

        // Step 2b: Check if already in dynamic catalog
        if let existing = catalog.find(id: parsed.repoId) {
            // Verify the model file actually exists on disk
            let localModels = GalleryModelDiscovery.discoverModels()
            if localModels.contains(where: { $0.filename == existing.metadata.modelFile }) {
                state = .complete(metadata: existing)
                lastImportedModel = existing
                Self.logger.info("✅ Model already imported: \(parsed.repoId, privacy: .public)")
                return
            } else {
                // Stale catalog entry — model file was deleted. Remove and continue import.
                try? catalog.remove(id: existing.id)
                Self.logger.info("🔄 Stale catalog entry removed for \(parsed.repoId, privacy: .public) — model file not on disk")
            }
        }

        // Step 3: Fetch model details
        state = .fetching(repoId: parsed.repoId)

        let modelDetail: HFModelInfo
        do {
            modelDetail = try await browser.modelDetail(repoId: parsed.repoId)
        } catch {
            state = .failed(error: "Failed to fetch model details: \(error.localizedDescription)")
            Self.logger.error("❌ API fetch failed for \(parsed.repoId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }

        // Step 4: Analyze model
        state = .analyzing(model: modelDetail)

        // Fetch README for deeper analysis (non-fatal if it fails)
        var readmeContent: String?
        do {
            readmeContent = try await browser.fetchModelCard(repoId: parsed.repoId)
        } catch {
            Self.logger.info("ℹ️ No README available for \(parsed.repoId, privacy: .public)")
        }

        // Step 5: Infer metadata
        let (metadata, confidence) = ModelCardParser.inferMetadata(
            from: modelDetail,
            siblings: modelDetail.siblings,
            readmeContent: readmeContent
        )

        let dynamicMeta = DynamicModelMetadata.fromHuggingFace(
            repoId: parsed.repoId,
            metadata: metadata,
            confidence: confidence
        )

        // Step 6: Collect downloadable files
        let downloadableFiles: [HFSibling]
        if let specificFile = parsed.specificFile,
           let sibling = modelDetail.siblings?.first(where: { $0.rfilename == specificFile }) {
            downloadableFiles = [sibling]
        } else {
            downloadableFiles = modelDetail.siblings?.filter { sibling in
                sibling.rfilename.hasSuffix(".\(metadata.runtimeType.fileExtension)")
            } ?? []
        }

        state = .readyToDownload(metadata: dynamicMeta, files: downloadableFiles)
        Self.logger.info(
            "📦 Ready to download \(parsed.repoId, privacy: .public): \(downloadableFiles.count) file(s), confidence=\(confidence.label, privacy: .public)"
        )
    }

    /// Confirm and start downloading a specific model file.
    ///
    /// Call this after the user reviews the inferred metadata in the `.readyToDownload` state
    /// and selects a file to download.
    ///
    /// - Parameters:
    ///   - metadata: The `DynamicModelMetadata` for the model being imported.
    ///   - file: The specific `HFSibling` file to download.
    ///   - downloadManager: The download manager to use for the actual download.
    func confirmDownload(
        metadata: DynamicModelMetadata,
        file: HFSibling,
        downloadManager: ModelDownloadManager
    ) {
        state = .downloading(filename: file.rfilename)

        // Add to catalog
        do {
            try catalog.add(metadata)
        } catch {
            Self.logger.error("⚠️ Failed to add to catalog (continuing with download): \(error.localizedDescription, privacy: .public)")
        }

        // Build HFModelInfo for the download manager
        let modelInfo = HFModelInfo(
            id: metadata.id,
            author: String(metadata.id.split(separator: "/").first ?? Substring(metadata.id))
        )

        // Start download
        downloadManager.downloadCommunityModel(model: modelInfo, sibling: file)

        // Set up completion tracking
        lastImportedModel = metadata

        Self.logger.info("⬇️ Download started for \(file.rfilename, privacy: .public)")
    }

    /// Mark the current import as complete.
    ///
    /// Call this when the download finishes (observed via `ModelDownloadManager.downloadStates`).
    ///
    /// - Parameter metadata: The completed model's metadata.
    func markComplete(metadata: DynamicModelMetadata) {
        state = .complete(metadata: metadata)
        lastImportedModel = metadata

        // Update verification timestamp
        var updated = metadata
        updated.lastVerifiedAt = Date()
        try? catalog.update(updated)

        Self.logger.info("✅ Import complete: \(metadata.id, privacy: .public)")
    }

    /// Reset the import manager to the idle state.
    ///
    /// Call this when the user dismisses the import sheet or wants to start over.
    func reset() {
        state = .idle
        Self.logger.info("🔄 Import manager reset to idle")
    }

    // MARK: - Kaggle Import

    /// Handle a Kaggle model URL import.
    ///
    /// Validates credentials, constructs the download URL, and transitions
    /// to `.readyToDownload` or `.failed` state.
    ///
    /// - Parameter handle: The parsed `KaggleModelHandle` from the URL.
    private func importFromKaggle(handle: KaggleModelHandle) async {
        Self.logger.info(
            "🔗 Kaggle import: \(handle.owner, privacy: .public)/\(handle.modelSlug, privacy: .public)"
        )

        // Verify Kaggle credentials are configured
        guard let username = kaggleUsername, !username.isEmpty,
              let apiKey = kaggleAPIKey, !apiKey.isEmpty else {
            state = .failed(
                error: "Kaggle API credentials required. Add your Kaggle username and API key in Settings."
            )
            Self.logger.error("❌ Kaggle credentials not configured")
            return
        }

        // Build download URL — requires full handle (framework/variation/version)
        guard let downloadURL = KaggleModelParser.buildDownloadURL(handle: handle) else {
            state = .failed(
                error: "Incomplete Kaggle URL. Please use a full model URL including framework, variation, and version "
                + "(e.g., https://www.kaggle.com/models/google/gemma/litert/gemma-3n-e4b-it/1)."
            )
            Self.logger.error(
                "❌ Cannot build download URL for basic Kaggle URL: \(handle.owner, privacy: .public)/\(handle.modelSlug, privacy: .public)"
            )
            return
        }

        // Build model ID for catalog lookup
        let modelId = "kaggle/\(handle.owner)/\(handle.modelSlug)"

        // Check if already imported
        if let existing = catalog.find(id: modelId) {
            state = .complete(metadata: existing)
            lastImportedModel = existing
            Self.logger.info("✅ Kaggle model already imported: \(modelId, privacy: .public)")
            return
        }

        // Build metadata for the Kaggle model
        let metadata = DynamicModelMetadata.fromKaggle(
            handle: handle,
            downloadURL: downloadURL
        )

        // Transition to ready (no file listing from Kaggle, so empty siblings)
        state = .readyToDownload(metadata: metadata, files: [])
        Self.logger.info(
            "📦 Ready to download Kaggle model: \(metadata.id, privacy: .public) from \(downloadURL.absoluteString, privacy: .public)"
        )
    }

    // MARK: - URL Parsing

    /// Parse a HuggingFace URL into its components.
    ///
    /// Handles the following formats:
    /// - `https://huggingface.co/{org}/{repo}`
    /// - `https://huggingface.co/{org}/{repo}/blob/main/{file}`
    /// - `https://huggingface.co/{org}/{repo}/tree/main`
    /// - `https://hf.co/{org}/{repo}` (short URL)
    ///
    /// - Parameter urlString: The URL string to parse.
    /// - Returns: Parsed URL components, or nil if the URL is invalid.
    func parseHuggingFaceURL(_ urlString: String) -> ParsedHFURL? {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased() else {
            return nil
        }

        // Validate host
        guard host == "huggingface.co" || host == "hf.co" || host == "www.huggingface.co" else {
            return nil
        }

        // Extract path components, filtering empty strings
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        // Need at least org and repo
        guard pathComponents.count >= 2 else {
            return nil
        }

        let org = pathComponents[0]
        let repo = pathComponents[1]

        // Validate org/repo aren't reserved paths
        let reservedPaths = ["api", "docs", "spaces", "datasets", "settings", "login", "join"]
        guard !reservedPaths.contains(org.lowercased()) else {
            return nil
        }

        // Check for specific file reference (e.g., /blob/main/filename.litertlm)
        var specificFile: String?
        if pathComponents.count >= 4,
           pathComponents[2] == "blob" || pathComponents[2] == "resolve" {
            // Join remaining components after "blob/main/" or "resolve/main/"
            let fileComponents = pathComponents.dropFirst(4) // Skip org, repo, blob/resolve, branch
            if !fileComponents.isEmpty {
                specificFile = fileComponents.joined(separator: "/")
            }
        }

        return ParsedHFURL(org: org, repo: repo, specificFile: specificFile)
    }
}
