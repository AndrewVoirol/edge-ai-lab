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

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Integration tests for DownloadManager ↔ ModelRegistry ↔ DynamicModelCatalog.
///
/// Validates that the model registry exposes the expected known models,
/// the dynamic catalog correctly merges imported models with the registry,
/// and the download manager tracks progress state correctly.
@MainActor
final class DownloadModelRegistryTests: XCTestCase {

    // MARK: - Properties

    /// Temporary directory for catalog persistence during tests.
    private var tempDirectory: URL!

    /// Temporary directory for simulated downloads.
    private var tempDownloadDirectory: URL!

    /// DynamicModelCatalog backed by the temp directory (no interference with real data).
    private var catalog: DynamicModelCatalog!

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadModelRegistryTests-\(UUID().uuidString)", isDirectory: true)
        tempDownloadDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadModelRegistryTests-dl-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: tempDownloadDirectory, withIntermediateDirectories: true)
        catalog = DynamicModelCatalog(storageDirectory: tempDirectory)
    }

    override func tearDown() {
        catalog = nil
        try? FileManager.default.removeItem(at: tempDirectory)
        try? FileManager.default.removeItem(at: tempDownloadDirectory)
        tempDirectory = nil
        tempDownloadDirectory = nil
        super.tearDown()
    }

    // MARK: - ModelRegistry Tests

    /// Verify that ModelRegistry.knownModels contains the expected models on fresh access.
    func testModelRegistryStartsEmpty() {
        // ModelRegistry.knownModels is a static constant — it always has models.
        // A fresh DynamicModelCatalog with no imports should have zero `entries`.
        XCTAssertTrue(
            catalog.entries.isEmpty,
            "Fresh DynamicModelCatalog should have no imported entries. Got \(catalog.entries.count)."
        )

        // allModels() includes the known registry models even with no imports.
        XCTAssertFalse(
            catalog.allModels().isEmpty,
            "allModels() should include known registry models even when catalog entries is empty."
        )

        // Verify known registry count matches
        XCTAssertEqual(
            catalog.allModels().count,
            ModelRegistry.knownModels.count,
            "allModels() should equal the known model count when no imports exist."
        )
    }

    /// Add a model entry to the DynamicModelCatalog, verify it appears in allModels().
    func testAddModelToRegistry() throws {
        let testModel = makeTestModelMetadata(filename: "test-model-add.litertlm")
        let entry = DynamicModelMetadata.fromHuggingFace(
            repoId: "test-org/test-model-add",
            metadata: testModel,
            confidence: .medium
        )

        try catalog.add(entry)

        XCTAssertEqual(
            catalog.entries.count, 1,
            "Catalog should have exactly 1 imported entry after add. Got \(catalog.entries.count)."
        )

        let all = catalog.allModels()
        let found = all.first(where: { $0.id == "test-org/test-model-add" })
        XCTAssertNotNil(found, "Added model should appear in allModels().")
        XCTAssertEqual(found?.metadata.name, "Test Model Add")
    }

    /// Adding the same model twice should throw a `duplicateEntry` error.
    func testDuplicateModelRejected() throws {
        let testModel = makeTestModelMetadata(filename: "test-model-dup.litertlm")
        let entry = DynamicModelMetadata.fromHuggingFace(
            repoId: "test-org/test-model-dup",
            metadata: testModel,
            confidence: .high
        )

        try catalog.add(entry)

        XCTAssertThrowsError(try catalog.add(entry), "Adding duplicate should throw") { error in
            guard let catalogError = error as? DynamicModelCatalogError else {
                XCTFail("Expected DynamicModelCatalogError, got \(type(of: error))")
                return
            }
            if case .duplicateEntry(let id) = catalogError {
                XCTAssertEqual(id, "test-org/test-model-dup",
                    "Duplicate error should reference the correct model ID.")
            } else {
                XCTFail("Expected .duplicateEntry, got \(catalogError)")
            }
        }

        XCTAssertEqual(catalog.entries.count, 1,
            "Catalog should still have exactly 1 entry after rejected duplicate.")
    }

    /// Add a model, then remove it, verify it's gone.
    func testModelDeletion() throws {
        let testModel = makeTestModelMetadata(filename: "test-model-del.litertlm")
        let entry = DynamicModelMetadata.fromHuggingFace(
            repoId: "test-org/test-model-del",
            metadata: testModel,
            confidence: .medium
        )

        try catalog.add(entry)
        XCTAssertEqual(catalog.entries.count, 1)

        try catalog.remove(id: "test-org/test-model-del")
        XCTAssertEqual(catalog.entries.count, 0,
            "Catalog should have 0 entries after removal.")

        let all = catalog.allModels()
        let found = all.first(where: { $0.id == "test-org/test-model-del" })
        XCTAssertNil(found, "Removed model should not appear in allModels().")
    }

    /// Adding an imported model should be reflected in allModels() alongside known models.
    func testDynamicCatalogReflectsRegistry() throws {
        let knownCount = ModelRegistry.knownModels.count
        let initialAll = catalog.allModels()
        XCTAssertEqual(initialAll.count, knownCount,
            "Initial allModels() count should equal known model count.")

        // Add an imported model with a unique filename (no overlap with registry)
        let testModel = makeTestModelMetadata(filename: "community-model-unique.litertlm")
        let entry = DynamicModelMetadata.fromHuggingFace(
            repoId: "community/unique-model",
            metadata: testModel,
            confidence: .medium
        )
        try catalog.add(entry)

        let updatedAll = catalog.allModels()
        XCTAssertEqual(updatedAll.count, knownCount + 1,
            "allModels() should include the new import plus all known models.")

        // Verify known models still take precedence — add an import that overlaps
        let overlappingModel = ModelRegistry.gemma4E2BStandard
        let overlappingEntry = DynamicModelMetadata.fromHuggingFace(
            repoId: "overlap/gemma-4-E2B-it",
            metadata: overlappingModel,
            confidence: .high
        )
        // The overlapping entry has the same modelFile as the registry entry,
        // so allModels() should deduplicate it.
        try catalog.add(overlappingEntry)
        let afterOverlapAll = catalog.allModels()
        XCTAssertEqual(afterOverlapAll.count, knownCount + 1,
            "Overlapping import should be deduplicated by allModels(). Known registry wins.")
    }

    /// Multiple concurrent async adds should not corrupt the catalog.
    func testConcurrentRegistryAccess() async throws {
        let iterations = 20

        // Perform concurrent adds using a TaskGroup
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<iterations {
                group.addTask { @MainActor in
                    let model = self.makeTestModelMetadata(filename: "concurrent-\(i).litertlm")
                    let entry = DynamicModelMetadata.fromHuggingFace(
                        repoId: "concurrent-test/model-\(i)",
                        metadata: model,
                        confidence: .low
                    )
                    // Each add is unique, so no duplicate errors expected.
                    try? self.catalog.add(entry)
                }
            }
        }

        XCTAssertEqual(catalog.entries.count, iterations,
            "After \(iterations) concurrent adds, catalog should have \(iterations) entries. Got \(catalog.entries.count).")

        // Verify no data corruption — all entries should be decodable
        let all = catalog.allModels()
        XCTAssertEqual(all.count, ModelRegistry.knownModels.count + iterations,
            "allModels() should include known + imported models.")

        // Verify uniqueness
        let ids = Set(catalog.entries.map(\.id))
        XCTAssertEqual(ids.count, iterations,
            "All entry IDs should be unique. Got \(ids.count) unique out of \(iterations).")
    }

    /// Verify ModelDownloadManager tracks download state and progress correctly.
    func testDownloadManagerTracksProgress() throws {
        // Create a download manager with an ephemeral config and temp directory
        let config = URLSessionConfiguration.ephemeral
        let manager = ModelDownloadManager(configuration: config, documentsDirectory: tempDownloadDirectory)

        // Initially, no download states should be set
        XCTAssertTrue(manager.downloadStates.isEmpty,
            "Fresh download manager should have no download states.")

        // Check state for a known model — should be .notDownloaded since file doesn't exist
        let testModel = ModelRegistry.gemma4E2BStandard
        let state = manager.checkState(for: testModel)

        switch state {
        case .notDownloaded:
            break // Expected
        case .downloaded:
            // Possible if the model file exists on disk (in the temp dir, unlikely)
            break
        default:
            XCTFail("Expected .notDownloaded or .downloaded, got unexpected state.")
        }

        // Verify state is now cached
        XCTAssertNotNil(manager.downloadStates[testModel.modelFile],
            "checkState should cache the state for the model.")

        // Simulate a download by creating a dummy file and re-checking state
        let dummyFile = tempDownloadDirectory.appendingPathComponent(testModel.modelFile)
        try Data("dummy model data".utf8).write(to: dummyFile)

        // Clear cached state to force re-scan
        manager.downloadStates.removeValue(forKey: testModel.modelFile)
        let refreshedState = manager.checkState(for: testModel)

        if case .downloaded(let url) = refreshedState {
            XCTAssertEqual(url.lastPathComponent, testModel.modelFile,
                "Downloaded state should reference the correct file.")
        } else {
            XCTFail("After creating file, checkState should return .downloaded. Got: \(refreshedState)")
        }

        // Verify deleteModel clears the state
        manager.deleteModel(filename: testModel.modelFile)
        if case .notDownloaded = manager.downloadStates[testModel.modelFile] {
            // Expected
        } else {
            XCTFail("After deletion, state should be .notDownloaded.")
        }

        // File should be removed from disk
        XCTAssertFalse(FileManager.default.fileExists(atPath: dummyFile.path),
            "Model file should be deleted from disk after deleteModel().")
    }

    // MARK: - Helpers

    /// Create a test `ModelMetadata` with the given filename.
    private func makeTestModelMetadata(filename: String) -> ModelMetadata {
        ModelMetadata(
            name: filename.replacingOccurrences(of: ".litertlm", with: "").replacingOccurrences(of: "-", with: " ").capitalized,
            modelId: "test-org/\(filename.replacingOccurrences(of: ".litertlm", with: ""))",
            modelFile: filename,
            description: "Test model for integration testing",
            sizeInBytes: 100_000_000,
            minDeviceMemoryGB: 4,
            contextWindowSize: 32_000,
            architectureType: "Test Architecture",
            recommendedFor: "Testing",
            supportsImage: false,
            supportsAudio: false,
            capabilities: ["llm_thinking"],
            defaultConfig: ModelDefaultConfig(
                topK: 64,
                topP: 0.95,
                temperature: 1.0,
                maxContextLength: 32_000,
                maxTokens: 4_000,
                accelerators: "gpu,cpu",
                visionAccelerator: nil
            ),
            platformSupport: PlatformSupport(
                macOS: .gpuAndCpu,
                iOSDevice: .gpuAndCpu,
                iOSSimulator: .cpuOnly
            ),
            runtimeType: .litertlm
        )
    }
}
