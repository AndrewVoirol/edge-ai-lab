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

    /// Matched profile from KnownModelCatalog, if available.
    let metadata: ModelCapabilityProfile?

    /// Path to a companion multimodal projector file (mmproj-*.gguf), if found.
    /// Populated during discovery by scanning the same directory for mmproj files.
    let mmProjPath: String?

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

    /// Returns catalog profile if available, otherwise synthesizes a reasonable
    /// profile from the filename, file size, and extension. This ensures the
    /// detail panel, load/unload buttons, and model card always render —
    /// even for user-imported GGUF or community models with no catalog entry.
    ///
    /// Note: For GGUF models, the profile reflects the model family's inherent
    /// capabilities (e.g., Gemma 4 supports vision). Whether the engine can
    /// actually USE those capabilities at runtime depends on the mmproj companion
    /// file — this is checked by the engine after loading (engine.supportsVision),
    /// not by the profile. This separation keeps discovery and runtime concerns clean.
    var resolvedMetadata: ModelCapabilityProfile {
        if let metadata {
            return metadata
        }
        return ModelCapabilityProfileBuilder.synthesized(
            filename: filename,
            sizeInBytes: sizeInBytes,
            hasMMProj: mmProjPath != nil
        )
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

    /// Convert a HuggingFace-style directory name to a human-readable model name.
    ///
    /// Examples:
    /// - `"lmstudio-community--gemma-4-E2B-it-MLX-4bit"` → `"gemma-4-E2B-it-MLX-4bit"`
    /// - `"mlx-community--phi-4-4bit"` → `"phi-4-4bit"`
    /// - `"gemma-4-E2B-it.litertlm"` → `"gemma-4-E2B-it.litertlm"` (no change)
    static func cleanModelDirectoryName(_ dirName: String) -> String {
        if dirName.contains("--") {
            return String(dirName.split(separator: "--", maxSplits: 1).last ?? Substring(dirName))
        }
        return dirName
    }

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
    ///
    /// On macOS, prefers the project-root `models/` directory (detected via `#filePath`
    /// at compile time) for development builds — this works in both Debug and Release
    /// configurations. Falls back to `~/Library/Application Support/<bundleId>/models/`
    /// when the project root doesn't exist (e.g., distributed app bundles).
    ///
    /// On iOS, uses the Documents directory so models are visible in Files.app.
    ///
    /// The eval pipeline can override this with `-EvalModelsDir <path>`.
    static func getAppModelsDirectory() -> URL {
        // CLI override: -EvalModelsDir /path/to/models
        if let idx = CommandLine.arguments.firstIndex(of: "-EvalModelsDir"),
           idx + 1 < CommandLine.arguments.count {
            return URL(fileURLWithPath: CommandLine.arguments[idx + 1])
        }

        #if os(macOS)
        // Try project-root/models/ first (works in both Debug and Release via #filePath).
        // #filePath is a compile-time literal — it resolves to the source file's absolute
        // path at build time, regardless of optimization level.
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = sourceFileURL
            .deletingLastPathComponent() // removes GalleryModelDiscovery.swift → .../Sources/Models/
            .deletingLastPathComponent() // removes Models/                      → .../Sources/
            .deletingLastPathComponent() // removes Sources/                     → .../  (project root)
        let projectModels = projectRoot.appendingPathComponent("models")

        if FileManager.default.fileExists(atPath: projectModels.path) {
            return projectModels
        }

        // Fallback: Application Support (for distributed app bundles)
        let appSupport = DirectoryHelper.applicationSupport
        let appDir = appSupport.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.andrewvoirol.EdgeAILab")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("models")
        #else
        // Use Documents on iOS so it shows up in the Files app
        return DirectoryHelper.documents
        #endif
    }

    // MARK: - Directory Scanning

    /// Scan a directory for single-file models (.litertlm, .gguf).
    /// Resolves symlinks so linked models are correctly discovered.
    private static func scanDirectory(_ directory: URL, source: DiscoveredModel.DiscoverySource) -> [DiscoveredModel] {
        let fileManager = FileManager.default
        let supportedExtensions: Set<String> = ["litertlm", "gguf"]
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        // Scan for mmproj companion files in the same directory.
        // Two naming patterns exist in the wild:
        //   1. Prefix: "mmproj-model-f16.gguf" (llama.cpp convention)
        //   2. Infix:  "gemma-4-E2B-mmproj-f16.gguf" (HuggingFace convention)
        let mmprojFiles = contents.filter { url in
            let name = url.lastPathComponent.lowercased()
            return name.hasSuffix(".gguf") && name.contains("mmproj")
        }
        // Pick the first mmproj file (prefer F16 over others if multiple exist)
        let mmprojURL = mmprojFiles.first(where: { $0.lastPathComponent.lowercased().contains("f16") })
            ?? mmprojFiles.first

        return contents.compactMap { url -> DiscoveredModel? in
            guard supportedExtensions.contains(url.pathExtension.lowercased()) else { return nil }
            // Skip mmproj files — they are companion files, not loadable models.
            // Matches both prefix ("mmproj-model.gguf") and infix ("model-mmproj-f16.gguf") patterns.
            let lowerName = url.lastPathComponent.lowercased()
            guard !(lowerName.hasSuffix(".gguf") && lowerName.contains("mmproj")) else { return nil }

            // Resolve symlinks so we check the actual target file
            let resolvedURL = url.resolvingSymlinksInPath()
            let resourceValues = try? resolvedURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard resourceValues?.isRegularFile == true else { return nil }

            let size = Int64(resourceValues?.fileSize ?? 0)
            let metadata = KnownModelCatalog.lookup(filename: url.lastPathComponent)

            // Only attach mmproj path to GGUF models
            let projPath: String? = url.pathExtension.lowercased() == "gguf" ? mmprojURL?.path : nil

            return DiscoveredModel(
                url: url,
                sizeInBytes: size,
                source: source,
                metadata: metadata,
                mmProjPath: projPath
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

            // Parse model profile from config.json if possible
            let metadata = parseMLXConfig(configURL)

            return DiscoveredModel(
                url: url,
                sizeInBytes: totalSize,
                source: source,
                metadata: metadata,
                mmProjPath: nil
            )
        }
    }

    /// Parse model profile from an MLX model's config.json and directory name.
    ///
    /// Extracts model_type from config.json and derives a human-readable name
    /// from the directory name. If the directory name matches a KnownModelCatalog entry,
    /// returns that entry's full profile instead.
    private static func parseMLXConfig(_ configURL: URL) -> ModelCapabilityProfile? {
        // First check if this directory matches a known catalog model
        let dirName = configURL.deletingLastPathComponent().lastPathComponent
        if let registryMatch = KnownModelCatalog.lookup(filename: dirName) {
            return registryMatch
        }

        // No registry match — construct minimal metadata from the directory name
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let modelType = config["model_type"] as? String ?? "unknown"
        // Convert directory name to human-readable: "mlx-community--gemma-4-E2B-it-4bit" → "gemma-4-E2B-it-4bit"
        let rawName: String
        if dirName.contains("--") {
            rawName = String(dirName.split(separator: "--", maxSplits: 1).last ?? Substring(dirName))
        } else {
            rawName = dirName
        }
        // Normalize MLX directory names using the shared formatter
        let humanName = ModelDetailFormatters.normalizeDisplayName(rawName)
        // Reconstruct model ID from directory name: "mlx-community--gemma-4-E2B-it-4bit" → "mlx-community/gemma-4-E2B-it-4bit"
        let modelId = dirName.replacingOccurrences(of: "--", with: "/")

        // Detect multimodal capability from model config.
        // VLMs (Gemma 4, Qwen-VL, PaliGemma) include vision_config in config.json
        // and ship with processor_config.json alongside their weights.
        let hasVisionConfig = config["vision_config"] != nil
        let modelDir = configURL.deletingLastPathComponent()
        let hasProcessorConfig = FileManager.default.fileExists(
            atPath: modelDir.appendingPathComponent("processor_config.json").path
        )
        let supportsImage = hasVisionConfig || hasProcessorConfig
        // Audio: detect from audio_config in config.json. mlx-swift-lm's Swift API
        // supports audio via UserInput.Audio (AVFoundation-based processing) and
        // Chat.Message's audios parameter. Gemma 4 Standard variants include
        // audio_config in their model configs.
        let hasAudioConfig = config["audio_config"] != nil
        let supportsAudio = hasAudioConfig

        // Infer context window from model name
        let contextWindow: Int
        let lowerName = rawName.lowercased()
        if lowerName.contains("gemma") && lowerName.contains("4") {
            if lowerName.contains("12b") {
                contextWindow = 256_000
            } else {
                contextWindow = 128_000
            }
        } else if lowerName.contains("gemma") {
            contextWindow = 32_000
        } else if lowerName.contains("llama") {
            contextWindow = 128_000
        } else {
            contextWindow = 32_000
        }

        // Construct a ModelCapabilityProfile directly.
        // Uses .configJSON source for config.json-derived data (vision, audio),
        // which is more reliable than filename heuristics.
        return ModelCapabilityProfile(
            id: dirName,
            displayName: humanName,
            repoId: modelId,
            runtimeType: .mlx,
            supportsVision: SourcedValue(supportsImage, source: hasVisionConfig ? .configJSON : .heuristic),
            supportsAudio: SourcedValue(supportsAudio, source: hasAudioConfig ? .configJSON : .heuristic),
            supportsThinking: SourcedValue(lowerName.contains("it") && (lowerName.contains("gemma") || lowerName.contains("llama") || lowerName.contains("mistral") || lowerName.contains("phi") || lowerName.contains("qwen")), source: .heuristic),
            supportsToolCalling: SourcedValue(lowerName.contains("it"), source: .heuristic),
            supportsMTP: SourcedValue(false, source: .heuristic),
            supportsConstrainedDecoding: SourcedValue(false, source: .heuristic),
            architecture: ArchitectureInfo(
                architectureClass: nil, modelType: modelType, isMoE: false,
                hiddenSize: nil, numLayers: nil, numAttentionHeads: nil,
                numKeyValueHeads: nil, vocabSize: nil, headDim: nil,
                maxImageResolution: nil, dtype: nil,
                quantizationBits: nil, quantizationMethod: nil
            ),
            contextWindow: SourcedValue(contextWindow, source: .heuristic),
            fileSizeBytes: 0,  // Size will be computed from actual directory contents by the caller
            estimatedMemoryGB: SourcedValue(8, source: .heuristic),
            totalParameters: nil,
            parameterLabel: nil,
            confidence: .medium,
            source: .huggingFaceInferred,
            lastUpdated: Date(),
            repoSha: nil,
            license: nil, licenseLink: nil, baseModelId: nil,
            downloads: nil, likes: nil, downloadsAllTime: nil,
            supportedLanguages: [],
            tags: [],
            defaultConfig: ModelDefaultConfig(
                topK: 40, topP: 0.9, temperature: 0.6,
                maxContextLength: contextWindow, maxTokens: 4_000,
                accelerators: "gpu",
                visionAccelerator: supportsImage ? "gpu" : nil
            ),
            platformSupport: PlatformSupport(
                macOS: .gpuOnly, iOSDevice: .gpuOnly, iOSSimulator: .unknown
            ),
            modelDescription: "MLX \(modelType) model",
            recommendedFor: "Apple Silicon inference",
            modelFile: dirName,
            modelId: modelId
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

            let metadata = KnownModelCatalog.lookup(filename: url.lastPathComponent)

            // MLX directory models: validate it's a real directory with config.json + safetensors,
            // not a stub file left from a failed download attempt.
            if metadata?.isMLXDirectoryModel == true {
                guard ModelFormatDetector.detectMLXDirectory(at: url) else { return nil }
                let totalSize = directorySize(at: url)
                return DiscoveredModel(
                    url: url,
                    sizeInBytes: totalSize,
                    source: .edgeGallery,
                    metadata: metadata,
                    mmProjPath: nil
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
                metadata: metadata,
                mmProjPath: nil
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
