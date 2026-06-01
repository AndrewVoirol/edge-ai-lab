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

/// Discovers .litertlm model files from the app's Documents directory and
/// the AI Edge Gallery's shared folder (accessible via Files.app on iOS).
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

        // 1. Check our own Documents directory
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let localModels = scanDirectory(docs, source: .local)
            for model in localModels where !seenFilenames.contains(model.filename) {
                seenFilenames.insert(model.filename)
                models.append(model)
            }
        }

        #if os(macOS) || targetEnvironment(simulator)
        // On macOS/simulator, also check the project's models/ directory
        // (used for development, not available on device)
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

    // MARK: - Directory Scanning

    /// Scan a directory for .litertlm model files.
    private static func scanDirectory(_ directory: URL, source: DiscoveredModel.DiscoverySource) -> [DiscoveredModel] {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.compactMap { url -> DiscoveredModel? in
            guard url.pathExtension == "litertlm" else { return nil }

            let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
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

            let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard resourceValues?.isRegularFile == true else { return nil }

            let size = Int64(resourceValues?.fileSize ?? 0)
            let metadata = ModelRegistry.lookup(filename: url.lastPathComponent)

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
}
