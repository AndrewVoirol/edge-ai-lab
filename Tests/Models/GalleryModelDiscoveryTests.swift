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

import XCTest
import LiteRTLM

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
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

    // MARK: - MLX Directory Discovery

    /// Create a fake MLX model directory with required files.
    private func createFakeMLXDirectory(
        named dirName: String,
        includeConfig: Bool = true,
        includeSafetensors: Bool = true,
        safetensorsCount: Int = 1
    ) throws -> URL {
        let modelDir = tempDirectory.appendingPathComponent(dirName)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        if includeConfig {
            let configData = Data("""
            {"model_type": "gemma2", "hidden_size": 2048}
            """.utf8)
            try configData.write(to: modelDir.appendingPathComponent("config.json"))
        }

        if includeSafetensors {
            for i in 1...safetensorsCount {
                let filename = safetensorsCount == 1
                    ? "model.safetensors"
                    : "model-\(String(format: "%05d", i))-of-\(String(format: "%05d", safetensorsCount)).safetensors"
                let data = Data(repeating: UInt8(i), count: 1024)
                try data.write(to: modelDir.appendingPathComponent(filename))
            }
        }

        // Add tokenizer files
        let tokenizerData = Data("{}".utf8)
        try tokenizerData.write(to: modelDir.appendingPathComponent("tokenizer.json"))

        return modelDir
    }

    /// Scan the temp directory for MLX model directories.
    /// Replicates GalleryModelDiscovery.scanForMLXModels logic.
    private func scanTestDirectoryForMLX() -> [DiscoveredModel] {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: tempDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.compactMap { url -> DiscoveredModel? in
            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard resourceValues?.isDirectory == true else { return nil }

            let configURL = url.appendingPathComponent("config.json")
            guard fileManager.fileExists(atPath: configURL.path) else { return nil }

            guard let dirContents = try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { return nil }

            let safetensorsFiles = dirContents.filter { $0.pathExtension == "safetensors" }
            guard !safetensorsFiles.isEmpty else { return nil }

            let totalSize = dirContents.reduce(Int64(0)) { sum, fileURL in
                let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                return sum + Int64(fileSize)
            }

            return DiscoveredModel(
                url: url,
                sizeInBytes: totalSize,
                source: .local,
                metadata: nil
            )
        }
    }

    /// A valid MLX model directory (config.json + .safetensors) should be discovered.
    func testScanDirectoryFindsMLXModelDirectories() throws {
        _ = try createFakeMLXDirectory(named: "mlx-community--gemma-test-4bit")

        let models = scanTestDirectoryForMLX()
        XCTAssertEqual(models.count, 1, "Should discover 1 MLX model directory")
        XCTAssertTrue(models.first!.url.lastPathComponent.contains("gemma-test"))
    }

    /// A directory missing config.json should NOT be discovered as an MLX model.
    func testMLXDirectoryMissingConfigIsIgnored() throws {
        _ = try createFakeMLXDirectory(
            named: "mlx-community--no-config",
            includeConfig: false
        )

        let models = scanTestDirectoryForMLX()
        XCTAssertTrue(models.isEmpty, "Directory without config.json should not be discovered")
    }

    /// A directory missing .safetensors files should NOT be discovered as an MLX model.
    func testMLXDirectoryMissingSafetensorsIsIgnored() throws {
        _ = try createFakeMLXDirectory(
            named: "mlx-community--no-tensors",
            includeSafetensors: false
        )

        let models = scanTestDirectoryForMLX()
        XCTAssertTrue(models.isEmpty, "Directory without .safetensors should not be discovered")
    }

    /// MLX and LiteRT models should coexist in the same directory.
    func testMLXAndLiteRTModelsCoexist() throws {
        // Create a LiteRT model
        try createFakeModelFile(named: "test-litert.litertlm")

        // Create an MLX model directory
        _ = try createFakeMLXDirectory(named: "mlx-community--test-model")

        let liteRTModels = scanTestDirectory()
        let mlxModels = scanTestDirectoryForMLX()

        XCTAssertEqual(liteRTModels.count, 1, "Should find 1 LiteRT model")
        XCTAssertEqual(mlxModels.count, 1, "Should find 1 MLX model")

        // Combined they should be 2 distinct models
        let allFilenames = Set(liteRTModels.map(\.filename) + mlxModels.map(\.filename))
        XCTAssertEqual(allFilenames.count, 2, "LiteRT and MLX models should have distinct filenames")
    }

    /// MLX model with multiple safetensors shards should report aggregate size.
    func testMLXMultiShardModelReportsAggregateSize() throws {
        _ = try createFakeMLXDirectory(
            named: "mlx-community--multi-shard",
            safetensorsCount: 3
        )

        let models = scanTestDirectoryForMLX()
        XCTAssertEqual(models.count, 1)

        // Should have size > 0 (aggregate of all files)
        let model = models.first!
        XCTAssertGreaterThan(model.sizeInBytes, 0, "Multi-shard model should have positive aggregate size")
    }

    /// Regular files (not directories) should be ignored by MLX scanner.
    func testMLXScannerIgnoresRegularFiles() throws {
        try createFakeFile(named: "not-a-model.txt", content: "Hello")
        try createFakeModelFile(named: "model.litertlm")

        let models = scanTestDirectoryForMLX()
        XCTAssertTrue(models.isEmpty, "MLX scanner should ignore regular files")
    }
}
