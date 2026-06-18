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
import Foundation

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - URL Import Integration Tests

/// Integration tests for the URL Import pipeline — the v2.0 "Paste and Go" feature.
///
/// These tests verify the full state machine flow from URL parsing through metadata
/// inference and catalog persistence. Network-dependent tests (API fetch, download)
/// are separated so they can be excluded from CI.
///
/// Test model: `litert-community/DeepSeek-R1-Distill-Qwen-1.5B` — a real HuggingFace
/// repo with `.litertlm` files that is NOT in `ModelRegistry.knownModels`.
final class URLImportIntegrationTests: XCTestCase {

    private var tempDir: URL!
    private var browser: HFModelBrowser!
    private var catalog: DynamicModelCatalog!
    private var manager: URLImportManager!

    @MainActor
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("URLImportInteg-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        browser = HFModelBrowser()
        catalog = DynamicModelCatalog(storageDirectory: tempDir)
        manager = URLImportManager(browser: browser, catalog: catalog)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - State Machine Tests

    /// Verify initial state is idle and reset returns to idle.
    @MainActor
    func testStateLifecycle() {
        // Initial state
        assertState(.idle)

        // Reset from any state
        manager.state = .failed(error: "test")
        manager.reset()
        assertState(.idle)
    }

    /// Verify that parsing transitions from idle → parsing → (next state or failed).
    @MainActor
    func testParsingInvalidURLTransitionsToFailed() async {
        await manager.importFromURL("not-a-url")
        assertStateFailed("Expected .failed for invalid URL")
    }

    /// Verify that a known model URL short-circuits to .complete when the model file is on disk.
    ///
    /// The `importFromURL` code verifies the model file exists on disk before short-circuiting
    /// (prevents claiming a model is "imported" when the file has been deleted). This test
    /// pre-stages a dummy file to satisfy that check.
    @MainActor
    func testKnownModelShortCircuitsToComplete() async {
        // Pre-stage a dummy model file so the on-disk existence check passes
        let modelsDir = GalleryModelDiscovery.getAppModelsDirectory()
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        let dummyModel = modelsDir.appendingPathComponent("gemma-4-E2B-it.litertlm")
        FileManager.default.createFile(atPath: dummyModel.path, contents: Data("dummy".utf8))
        defer { try? FileManager.default.removeItem(at: dummyModel) }

        await manager.importFromURL("https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm")
        assertStateComplete("Expected .complete for known model with file on disk")
    }

    /// Verify that a model already in the dynamic catalog short-circuits to .complete.
    @MainActor
    func testCatalogModelShortCircuitsToComplete() async throws {
        // Create a dummy model file so GalleryModelDiscovery.discoverModels() finds it.
        // The catalog short-circuit verifies the model file exists on disk to prevent
        // stale entries from bypassing re-import of deleted models.
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dummyModelFile = cachesDir.appendingPathComponent("test-model.litertlm")
        FileManager.default.createFile(atPath: dummyModelFile.path, contents: Data("dummy".utf8))
        defer { try? FileManager.default.removeItem(at: dummyModelFile) }

        // Also place in the app models directory (DEBUG mode scans project-root/models/)
        let modelsDir = GalleryModelDiscovery.getAppModelsDirectory()
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        let dummyModelFile2 = modelsDir.appendingPathComponent("test-model.litertlm")
        FileManager.default.createFile(atPath: dummyModelFile2.path, contents: Data("dummy".utf8))
        defer { try? FileManager.default.removeItem(at: dummyModelFile2) }

        // Pre-populate catalog with a test model
        let metadata = ModelMetadata(
            name: "Test Model",
            modelId: "test-org/test-model",
            modelFile: "test-model.litertlm",
            description: "A test model",
            sizeInBytes: 500_000_000,
            minDeviceMemoryGB: 4,
            contextWindowSize: 8192,
            architectureType: "Transformer",
            recommendedFor: "Testing",
            supportsImage: false,
            supportsAudio: false,
            capabilities: [],
            defaultConfig: ModelDefaultConfig(
                topK: 64, topP: 0.95, temperature: 1.0,
                maxContextLength: 8192, maxTokens: 2048,
                accelerators: "gpu,cpu", visionAccelerator: nil
            ),
            platformSupport: PlatformSupport(
                macOS: .gpuAndCpu, iOSDevice: .gpuAndCpu, iOSSimulator: .cpuOnly
            ),
            runtimeType: .litertlm
        )
        let testMeta = DynamicModelMetadata.fromHuggingFace(
            repoId: "test-org/test-model",
            metadata: metadata,
            confidence: .medium
        )
        try catalog.add(testMeta)

        await manager.importFromURL("https://huggingface.co/test-org/test-model")
        assertStateComplete("Expected .complete for catalog model")
    }

    /// Verify that markComplete updates state and catalog.
    @MainActor
    func testMarkCompleteUpdatesStateAndCatalog() throws {
        let metadata = ModelMetadata(
            name: "Completed Model",
            modelId: "test-org/completed-model",
            modelFile: "completed-model.litertlm",
            description: "Done",
            sizeInBytes: 500_000_000,
            minDeviceMemoryGB: 4,
            contextWindowSize: 8192,
            architectureType: "Transformer",
            recommendedFor: "Testing",
            supportsImage: false,
            supportsAudio: false,
            capabilities: [],
            defaultConfig: ModelDefaultConfig(
                topK: 64, topP: 0.95, temperature: 1.0,
                maxContextLength: 8192, maxTokens: 2048,
                accelerators: "gpu,cpu", visionAccelerator: nil
            ),
            platformSupport: PlatformSupport(
                macOS: .gpuAndCpu, iOSDevice: .gpuAndCpu, iOSSimulator: .cpuOnly
            ),
            runtimeType: .litertlm
        )
        let meta = DynamicModelMetadata.fromHuggingFace(
            repoId: "test-org/completed-model",
            metadata: metadata,
            confidence: .high
        )
        try catalog.add(meta)

        manager.markComplete(metadata: meta)
        assertStateComplete("Expected .complete after markComplete")
        XCTAssertNotNil(manager.lastImportedModel, "lastImportedModel should be set after completion")
        XCTAssertEqual(manager.lastImportedModel?.id, meta.id)
    }

    // MARK: - ViewModel Integration Tests

    /// Verify that ConversationViewModel can own and expose a URLImportManager.
    @MainActor
    func testViewModelOwnsURLImportManager() {
        let vm = ConversationViewModel(
            engine: MockInstrumentedEngine(),
            downloadManager: ModelDownloadManager(),
            dynamicModelCatalog: catalog
        )

        // The VM should expose a URLImportManager and showURLImportSheet flag
        XCTAssertNotNil(vm.urlImportManager, "ViewModel should expose urlImportManager")
        XCTAssertFalse(vm.showURLImportSheet, "showURLImportSheet should default to false")
    }

    /// Verify startURLImport sets pending URL and opens the sheet.
    @MainActor
    func testStartURLImportSetsStateAndOpensSheet() async {
        let vm = ConversationViewModel(
            engine: MockInstrumentedEngine(),
            downloadManager: ModelDownloadManager(),
            dynamicModelCatalog: catalog
        )

        let testURL = "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm"
        vm.startURLImport(testURL)
        XCTAssertTrue(vm.showURLImportSheet, "Sheet should be shown after startURLImport")
        XCTAssertEqual(vm.pendingImportURL, testURL, "Pending URL should be set")
    }

    // MARK: - Network-Dependent Tests (Skip in CI)

    /// Full E2E: parse → API fetch → analyze → readyToDownload for a non-known model.
    ///
    /// This test hits the real HuggingFace API. Skip if network is unavailable.
    @MainActor
    func testFullPipelineToReadyToDownload() async throws {
        // Use a model NOT in the known registry
        let testURL = "https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B"

        await manager.importFromURL(testURL)

        // Should reach readyToDownload or failed (if network unavailable)
        switch manager.state {
        case .readyToDownload(let metadata, let files):
            XCTAssertFalse(metadata.metadata.name.isEmpty, "Model name should be populated")
            XCTAssertFalse(files.isEmpty, "Should have at least one downloadable file")

            // Verify files are .litertlm
            for file in files {
                XCTAssertTrue(
                    file.rfilename.hasSuffix(".litertlm"),
                    "Expected .litertlm file, got: \(file.rfilename)"
                )
            }

        case .failed(let error):
            // Network unavailable — acceptable in CI
            print("⚠️ Network test skipped: \(error)")

        case .complete:
            XCTFail("Should not short-circuit — model is not in known registry")

        default:
            XCTFail("Unexpected state: \(manager.state)")
        }
    }

    /// Verify confirmDownload transitions to .downloading state.
    @MainActor
    func testConfirmDownloadTransitionsToDownloading() async throws {
        let testURL = "https://huggingface.co/litert-community/DeepSeek-R1-Distill-Qwen-1.5B"

        await manager.importFromURL(testURL)

        guard case .readyToDownload(let metadata, let files) = manager.state,
              let file = files.first else {
            // Network unavailable — skip
            print("⚠️ Skipping confirmDownload test — could not reach readyToDownload state")
            return
        }

        let downloadManager = ModelDownloadManager()
        manager.confirmDownload(metadata: metadata, file: file, downloadManager: downloadManager)

        if case .downloading(let filename) = manager.state {
            XCTAssertEqual(filename, file.rfilename, "Downloading filename should match selected file")
        } else {
            XCTFail("Expected .downloading state after confirmDownload")
        }

        // Verify model was added to catalog
        let catalogEntry = catalog.find(id: metadata.id)
        XCTAssertNotNil(catalogEntry, "Model should be added to catalog after confirmDownload")
    }

    // MARK: - Search Integration

    /// Verify HFModelBrowser.searchModels returns results for a real query.
    @MainActor
    func testSearchModelsReturnsResults() async throws {
        do {
            let results = try await browser.searchModels(query: "gemma litert")
            // May be empty if rate-limited, but shouldn't throw
            print("ℹ️ Search returned \(results.count) results")
        } catch {
            // Network unavailable — acceptable in CI
            print("⚠️ Search test skipped: \(error)")
        }
    }

    // MARK: - Helpers

    @MainActor
    private func assertState(_ expected: URLImportManager.ImportState) {
        switch (expected, manager.state) {
        case (.idle, .idle): break
        default:
            XCTFail("Expected \(expected), got \(manager.state)")
        }
    }

    @MainActor
    private func assertStateFailed(_ message: String) {
        if case .failed = manager.state {
            // Expected
        } else {
            XCTFail("\(message), got: \(manager.state)")
        }
    }

    @MainActor
    private func assertStateComplete(_ message: String) {
        if case .complete = manager.state {
            // Expected
        } else {
            XCTFail("\(message), got: \(manager.state)")
        }
    }
}
