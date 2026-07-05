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

// MARK: - Discovered Model

/// A model discovered from an external source (e.g., AI Edge Gallery's shared folder).
struct DiscoveredModel: Identifiable, Sendable {
    var id: String { url.absoluteString }

    /// The file URL to the model.
    let url: URL

    /// The filename (e.g., "gemma-4-E2B-it.litertlm").
    var filename: String { url.lastPathComponent }

    /// The file size in bytes.
    let sizeInBytes: Int64

    /// Where this model was discovered.
    let source: DiscoverySource

    /// Matched metadata from ModelRegistry, if available.
    let metadata: ModelMetadata?

    enum DiscoverySource: String, Sendable {
        /// Found in the app's own Documents directory.
        case local
        /// Found in the AI Edge Gallery's shared folder via Files.app.
        case edgeGallery
    }

    /// Human-readable size string.
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeInBytes, countStyle: .file)
    }
}

// MARK: - Gallery Model Discovery

/// Discovers .litertlm model files and MLX model directories from the app's
/// Documents directory and the AI Edge Gallery's shared folder (accessible via Files.app on iOS).
///
/// On iOS, apps with `UIFileSharingEnabled` expose their Documents folder
/// via the "On My iPhone" section of Files.app. The Gallery app appears as
/// "Edge Gallery" and stores downloaded models there.
enum GalleryModelDiscovery {

    /// Discover all available models from local and external sources.
    /// - Returns: Array of discovered models, deduplicated by filename.
    static func discoverModels() -> [DiscoveredModel] {
        var models: [DiscoveredModel] = []
        var seenFilenames = Set<String>()

        // 1. Check the app's designated models directory
        let modelsDir = getAppModelsDirectory()
        let localModels = scanDirectory(modelsDir, source: .local)
        for model in localModels where !seenFilenames.contains(model.filename) {
            seenFilenames.insert(model.filename)
            models.append(model)
        }

        // Also scan for MLX model directories
        let mlxModels = scanForMLXModels(modelsDir, source: .local)
        for model in mlxModels where !seenFilenames.contains(model.filename) {
            seenFilenames.insert(model.filename)
            models.append(model)
        }

        #if os(macOS) || targetEnvironment(simulator)
        // On macOS/simulator, also check Caches
        let additionalDirs: [URL] = [
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
        ].compactMap { $0 }
        
        for dir in additionalDirs {
            let found = scanDirectory(dir, source: .local)
            for m in found where !seenFilenames.contains(m.filename) {
                seenFilenames.insert(m.filename)
                models.append(m)
            }

            // Also scan for MLX model directories
            let mlxFound = scanForMLXModels(dir, source: .local)
            for m in mlxFound where !seenFilenames.contains(m.filename) {
                seenFilenames.insert(m.filename)
                models.append(m)
            }
        }
        #endif

        // 2. Check for Gallery's shared folder
        // On iOS, the Gallery app's Documents folder is accessible when:
        //   - Gallery has UIFileSharingEnabled = true
        //   - User has browsed to it via Files.app (creating a security-scoped bookmark)
        //
        // We check common paths where Files.app exposes other apps' documents.
        // The actual path is:
        //   /var/mobile/Containers/Shared/AppGroup/
        //   OR accessed via UIDocumentPickerViewController
        //
        // Since we can't directly enumerate other apps' sandboxes, we rely on
        // the user having previously opened the Gallery folder via our file picker.
        // Models discovered this way will be accessible via security-scoped URLs.

        // 3. Check for previously bookmarked Gallery models
        let galleryModels = loadBookmarkedGalleryModels()
        for model in galleryModels where !seenFilenames.contains(model.filename) {
            seenFilenames.insert(model.filename)
            models.append(model)
        }

        return models.sorted { $0.filename < $1.filename }
    }

    /// Returns the primary directory where the app expects to read/write models.
    static func getAppModelsDirectory() -> URL {
        #if DEBUG && os(macOS)
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        // Path: .../Sources/Models/GalleryModelDiscovery.swift
        let projectRoot = sourceFileURL
            .deletingLastPathComponent() // removes GalleryModelDiscovery.swift → .../Sources/Models/
            .deletingLastPathComponent() // removes Models/                      → .../Sources/
            .deletingLastPathComponent() // removes Sources/                     → .../  (project root)
        return projectRoot.appendingPathComponent("models")
        #else
        #if os(macOS)
        // Use Application Support on macOS to avoid TCC prompts for Documents
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.andrewvoirol.EdgeAILab")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("models")
        #else
        // Use Documents on iOS so it shows up in the Files app
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        #endif
        #endif
    }

    // MARK: - Directory Scanning

    /// Scan a directory for .litertlm model files.
    /// Resolves symlinks so linked models are correctly discovered.
    private static func scanDirectory(_ directory: URL, source: DiscoveredModel.DiscoverySource) -> [DiscoveredModel] {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.compactMap { url -> DiscoveredModel? in
            guard url.pathExtension == "litertlm" else { return nil }

            // Resolve symlinks so we check the actual target file
            let resolvedURL = url.resolvingSymlinksInPath()
            let resourceValues = try? resolvedURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard resourceValues?.isRegularFile == true else { return nil }

            let size = Int64(resourceValues?.fileSize ?? 0)
            let metadata = ModelRegistry.lookup(filename: url.lastPathComponent)

            return DiscoveredModel(
                url: url,
                sizeInBytes: size,
                source: source,
                metadata: metadata
            )
        }
    }

    /// Scan a directory for MLX model directories.
    /// An MLX model directory must contain config.json AND at least one .safetensors file.
    /// Directory names follow the pattern: `mlx-community--model-name` (slashes replaced with --).
    private static func scanForMLXModels(_ directory: URL, source: DiscoveredModel.DiscoverySource) -> [DiscoveredModel] {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.compactMap { url -> DiscoveredModel? in
            // Must be a directory
            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard resourceValues?.isDirectory == true else { return nil }

            // Must contain config.json
            let configURL = url.appendingPathComponent("config.json")
            guard fileManager.fileExists(atPath: configURL.path) else { return nil }

            // Must contain at least one .safetensors file
            guard let dirContents = try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { return nil }

            let safetensorsFiles = dirContents.filter { $0.pathExtension == "safetensors" }
            guard !safetensorsFiles.isEmpty else { return nil }

            // Calculate total size across all files in the directory
            let totalSize = dirContents.reduce(Int64(0)) { sum, fileURL in
                let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                return sum + Int64(fileSize)
            }

            // Parse model metadata from config.json if possible
            let metadata = parseMLXConfig(configURL)

            return DiscoveredModel(
                url: url,
                sizeInBytes: totalSize,
                source: source,
                metadata: metadata
            )
        }
    }

    /// Parse model metadata from an MLX model's config.json and directory name.
    ///
    /// Extracts model_type from config.json and derives a human-readable name
    /// from the directory name. If the directory name matches a ModelRegistry entry,
    /// returns that entry's full metadata instead.
    private static func parseMLXConfig(_ configURL: URL) -> ModelMetadata? {
        // First check if this directory matches a known registry model
        let dirName = configURL.deletingLastPathComponent().lastPathComponent
        if let registryMatch = ModelRegistry.knownModels.first(where: { $0.modelFile == dirName }) {
            return registryMatch
        }

        // No registry match — construct minimal metadata from the directory name
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let modelType = config["model_type"] as? String ?? "unknown"
        // Convert directory name to human-readable: "mlx-community--gemma-4-E2B-it-4bit" → "gemma-4-E2B-it-4bit"
        let humanName: String
        if dirName.contains("--") {
            humanName = String(dirName.split(separator: "--", maxSplits: 1).last ?? Substring(dirName))
        } else {
            humanName = dirName
        }
        // Reconstruct model ID from directory name: "mlx-community--gemma-4-E2B-it-4bit" → "mlx-community/gemma-4-E2B-it-4bit"
        let modelId = dirName.replacingOccurrences(of: "--", with: "/")

        return ModelMetadata(
            name: humanName,
            modelId: modelId,
            modelFile: dirName,
            description: "MLX \(modelType) model",
            sizeInBytes: 0,  // Size will be computed from actual directory contents by the caller
            minDeviceMemoryGB: 8,
            contextWindowSize: 128_000,
            architectureType: modelType,
            recommendedFor: "Apple Silicon inference",
            supportsImage: false,
            supportsAudio: false,
            capabilities: [],
            defaultConfig: ModelDefaultConfig(
                topK: 40,
                topP: 0.9,
                temperature: 0.6,
                maxContextLength: 32_000,
                maxTokens: 4_000,
                accelerators: "gpu",
                visionAccelerator: nil
            ),
            platformSupport: PlatformSupport(
                macOS: .gpuOnly,
                iOSDevice: .gpuOnly,
                iOSSimulator: .unknown
            ),
            runtimeType: .mlx
        )
    }

    // MARK: - Gallery Model Bookmarking

    /// Key for persisting Gallery model bookmarks in UserDefaults.
    private static let bookmarksKey = "gallery_model_bookmarks"

    /// Save a security-scoped bookmark for a Gallery model URL.
    /// Call this when the user selects a model from the Gallery folder via the file picker.
    static func bookmarkGalleryModel(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let bookmarkData = try? url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }

        var bookmarks = loadBookmarkDataArray()
        // Deduplicate by filename
        let filename = url.lastPathComponent
        bookmarks.removeAll { entry in
            guard let (savedURL, _) = resolveBookmark(entry) else { return true }
            return savedURL.lastPathComponent == filename
        }
        bookmarks.append(bookmarkData)

        UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
    }

    /// Load previously bookmarked Gallery models.
    private static func loadBookmarkedGalleryModels() -> [DiscoveredModel] {
        let bookmarks = loadBookmarkDataArray()
        return bookmarks.compactMap { data -> DiscoveredModel? in
            guard let (url, isStale) = resolveBookmark(data) else { return nil }
            if isStale { return nil }

            // Verify the file still exists
            guard url.startAccessingSecurityScopedResource() else { return nil }
            defer { url.stopAccessingSecurityScopedResource() }

            let metadata = ModelRegistry.lookup(filename: url.lastPathComponent)

            // MLX directory models: validate it's a real directory with config.json + safetensors,
            // not a stub file left from a failed download attempt.
            if metadata?.isMLXDirectoryModel == true {
                guard ModelFormatDetector.detectMLXDirectory(at: url) else { return nil }
                let totalSize = directorySize(at: url)
                return DiscoveredModel(
                    url: url,
                    sizeInBytes: totalSize,
                    source: .edgeGallery,
                    metadata: metadata
                )
            }

            // Single-file models (LiteRT, etc.): must be a regular file
            let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard resourceValues?.isRegularFile == true else { return nil }

            let size = Int64(resourceValues?.fileSize ?? 0)

            return DiscoveredModel(
                url: url,
                sizeInBytes: size,
                source: .edgeGallery,
                metadata: metadata
            )
        }
    }

    private static func loadBookmarkDataArray() -> [Data] {
        UserDefaults.standard.array(forKey: bookmarksKey) as? [Data] ?? []
    }

    private static func resolveBookmark(_ data: Data) -> (URL, Bool)? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        return (url, isStale)
    }

    /// Compute total file size of a directory's contents (non-recursive, top-level files only).
    private static func directorySize(at url: URL) -> Int64 {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        return contents.reduce(Int64(0)) { sum, fileURL in
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return sum + Int64(size)
        }
    }
}
