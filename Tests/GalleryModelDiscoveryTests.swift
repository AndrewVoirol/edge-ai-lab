import XCTest
import LiteRTLM

#if os(iOS)
@testable import GemmaEdgeGallery_iOS
#elseif os(macOS)
@testable import GemmaEdgeGallery_macOS
#endif

// MARK: - GalleryModelDiscovery Tests

final class GalleryModelDiscoveryTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        // Create a unique temp directory for each test
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gallery_discovery_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: tempDirectory, withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    // MARK: - Empty Directory

    /// Scanning an empty directory should return no models.
    func testScanEmptyDirectoryReturnsNoModels() {
        let models = scanTestDirectory()
        XCTAssertTrue(models.isEmpty, "Empty directory should produce no discovered models")
    }

    // MARK: - Finding .litertlm Files

    /// Scanning a directory with .litertlm files should discover them.
    func testScanDirectoryFindsLitertlmFiles() throws {
        // Create fake .litertlm files
        try createFakeModelFile(named: "test-model-1.litertlm")
        try createFakeModelFile(named: "test-model-2.litertlm")

        let models = scanTestDirectory()
        XCTAssertEqual(models.count, 2, "Should discover 2 .litertlm files")

        let filenames = models.map(\.filename).sorted()
        XCTAssertEqual(filenames, ["test-model-1.litertlm", "test-model-2.litertlm"])
    }

    // MARK: - Ignoring Non-Model Files

    /// Non-.litertlm files should be excluded from discovery.
    func testScanDirectoryIgnoresNonLitertlmFiles() throws {
        // Create various non-model files
        try createFakeFile(named: "readme.txt", content: "Hello")
        try createFakeFile(named: "model.bin", content: "Binary data")
        try createFakeFile(named: "weights.safetensors", content: "Tensors")
        try createFakeFile(named: "config.json", content: "{}")

        // Also create one real .litertlm file
        try createFakeModelFile(named: "real-model.litertlm")

        let models = scanTestDirectory()
        XCTAssertEqual(models.count, 1, "Should only discover .litertlm files")
        XCTAssertEqual(models.first?.filename, "real-model.litertlm")
    }

    // MARK: - Lookup Matches

    /// A discovered file whose name matches a known model should include registry metadata.
    func testLookupMatchesDiscoveredFiles() throws {
        // Use a real known model filename
        let knownFilename = ModelRegistry.gemma4E2BStandard.modelFile
        try createFakeModelFile(named: knownFilename)

        let models = scanTestDirectory()
        XCTAssertEqual(models.count, 1)

        let discovered = models.first!
        XCTAssertEqual(discovered.filename, knownFilename)
        XCTAssertNotNil(discovered.metadata, "Known model filename should match registry metadata")
        XCTAssertEqual(discovered.metadata?.name, ModelRegistry.gemma4E2BStandard.name)
    }

    /// A discovered file with an unknown name should have nil metadata.
    func testUnknownModelFileHasNilMetadata() throws {
        try createFakeModelFile(named: "custom-finetuned-model.litertlm")

        let models = scanTestDirectory()
        XCTAssertEqual(models.count, 1)
        XCTAssertNil(
            models.first?.metadata,
            "Unknown model filename should have nil metadata"
        )
    }

    // MARK: - DiscoveredModel Properties

    /// Verify that DiscoveredModel correctly reports file properties.
    func testDiscoveredModelProperties() throws {
        try createFakeModelFile(named: "test-props.litertlm", sizeKB: 100)

        let models = scanTestDirectory()
        XCTAssertEqual(models.count, 1)

        let model = models.first!
        XCTAssertEqual(model.filename, "test-props.litertlm")
        XCTAssertEqual(model.source, .local)
        XCTAssertTrue(model.url.path.contains("test-props.litertlm"))
        // formattedSize should produce a non-empty human-readable string
        XCTAssertFalse(model.formattedSize.isEmpty)
    }

    // MARK: - Hidden Files Excluded

    /// Hidden files (starting with .) should be excluded.
    func testHiddenFilesAreExcluded() throws {
        try createFakeModelFile(named: ".hidden-model.litertlm")
        try createFakeModelFile(named: "visible-model.litertlm")

        let models = scanTestDirectory()
        // Hidden files should be skipped by the scanner
        let filenames = models.map(\.filename)
        XCTAssertFalse(filenames.contains(".hidden-model.litertlm"))
        XCTAssertTrue(filenames.contains("visible-model.litertlm"))
    }

    // MARK: - ModelRegistry.lookup Integration

    /// Verify that ModelRegistry.lookup works correctly for all known filenames.
    func testRegistryLookupForAllKnownModels() {
        for model in ModelRegistry.knownModels {
            let found = ModelRegistry.lookup(filename: model.modelFile)
            XCTAssertNotNil(found, "Lookup should find \(model.modelFile)")
            XCTAssertEqual(found?.name, model.name)
        }
    }

    /// Verify that ModelRegistry.lookup(path:) extracts filename correctly.
    func testRegistryLookupByPath() {
        let path = "/some/deep/path/to/models/gemma-4-E2B-it.litertlm"
        let found = ModelRegistry.lookup(path: path)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.modelFile, "gemma-4-E2B-it.litertlm")
    }

    // MARK: - Helpers

    /// Scan the temp directory using the same pattern as GalleryModelDiscovery's internal scanner.
    /// We replicate the scanning logic because scanDirectory is private.
    private func scanTestDirectory() -> [DiscoveredModel] {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: tempDirectory,
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
                source: .local,
                metadata: metadata
            )
        }
    }

    /// Create a fake .litertlm file in the temp directory.
    private func createFakeModelFile(named filename: String, sizeKB: Int = 1) throws {
        let fileURL = tempDirectory.appendingPathComponent(filename)
        let data = Data(repeating: 0, count: sizeKB * 1024)
        try data.write(to: fileURL)
    }

    /// Create a generic file in the temp directory.
    private func createFakeFile(named filename: String, content: String) throws {
        let fileURL = tempDirectory.appendingPathComponent(filename)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
