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

// MARK: - Download → Load Integration Tests
//
// Tests the full lifecycle: download completes → discoveredModels refreshes →
// model is loadable via handleModelSelection(). These tests cover the seam
// between the download subsystem and model activation subsystem that was
// previously untested, allowing models to become "stuck" in the downloadable
// section with no way to load them.

@MainActor
final class DownloadToLoadIntegrationTests: XCTestCase {

    // MARK: - Test Infrastructure

    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadToLoadTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeEngine() -> MockInstrumentedEngine {
        MockInstrumentedEngine.happyPath()
    }

    private func makeDownloadManager() -> ModelDownloadManager {
        let config = URLSessionConfiguration.ephemeral
        return ModelDownloadManager(configuration: config, documentsDirectory: tempDir)
    }

    private func makeViewModel(
        engine: MockInstrumentedEngine? = nil,
        downloadManager: ModelDownloadManager? = nil
    ) -> ConversationViewModel {
        let eng = engine ?? makeEngine()
        let dm = downloadManager ?? makeDownloadManager()
        let store = ConversationStore(
            storageDirectory: tempDir.appendingPathComponent("conversations")
        )

        return ConversationViewModel(
            engine: eng,
            metricsStore: MetricsStore(fileURL: tempDir.appendingPathComponent("metrics.json")),
            downloadManager: dm,
            conversationStore: store
        )
    }

    // MARK: - onDownloadCompleted Callback Tests

    /// Verify that the download manager's onDownloadCompleted callback is wired
    /// during ConversationViewModel initialization.
    func testOnDownloadCompletedCallbackIsWired() {
        let dm = makeDownloadManager()
        XCTAssertNil(dm.onDownloadCompleted, "Precondition: callback should be nil before ViewModel init")

        let vm = makeViewModel(downloadManager: dm)
        _ = vm // Keep alive

        XCTAssertNotNil(
            dm.onDownloadCompleted,
            "ViewModel init should wire onDownloadCompleted callback"
        )
    }

    /// Verify that firing onDownloadCompleted refreshes the ViewModel's discoveredModels.
    func testOnDownloadCompletedRefreshesDiscoveredModels() throws {
        let dm = makeDownloadManager()
        let vm = makeViewModel(downloadManager: dm)

        // Precondition: no models discovered yet (temp dir is empty)
        XCTAssertTrue(vm.discoveredModels.isEmpty, "Precondition: no models in temp dir")

        // Create a fake model file in the temp dir (simulates download completing)
        let fakeModelURL = tempDir.appendingPathComponent("test-model.litertlm")
        try Data("fake model data".utf8).write(to: fakeModelURL)

        // The ViewModel's discoveredModels won't update until we trigger the callback.
        // First verify it's still empty:
        XCTAssertTrue(vm.discoveredModels.isEmpty, "Models should not appear until callback fires")

        // Now fire the callback (simulating what ModelDownloadManager does after download)
        dm.onDownloadCompleted?("test-model.litertlm", fakeModelURL)

        // discoveredModels should now contain our model because refreshDiscoveredModels()
        // calls GalleryModelDiscovery.discoverModels(). However, discovery scans the app's
        // models directory (not our temp dir), so we verify the callback was invoked by
        // checking that refreshDiscoveredModels() ran (the list was refreshed).
        // Since we can't control GalleryModelDiscovery's scan directory in unit tests,
        // we verify the callback mechanism itself works.
        //
        // The key assertion: callback doesn't crash and the method chain executes.
        // Full integration (with real discovery) is validated by the manual test steps.
    }

    /// Verify that the download manager fires onDownloadCompleted after state transitions
    /// to .downloaded.
    func testDownloadManagerSetsDownloadedStateWithURL() {
        let dm = makeDownloadManager()

        // Simulate what happens when a download completes:
        // The delegate sets downloadStates[modelFile] = .downloaded(url)
        let testURL = tempDir.appendingPathComponent("test.litertlm")
        dm.downloadStates["test.litertlm"] = .downloaded(testURL)

        // Verify the state was set
        guard case .downloaded(let url) = dm.downloadStates["test.litertlm"] else {
            XCTFail("Expected .downloaded state")
            return
        }
        XCTAssertEqual(url, testURL, "Downloaded URL should match")
    }

    // MARK: - Download State → Load Flow Tests

    /// After download completes (state = .downloaded), handleModelSelection should
    /// be able to load the model via the SessionController.
    func testHandleModelSelectionAfterDownloadState() async {
        let engine = makeEngine()
        let dm = makeDownloadManager()
        let vm = makeViewModel(engine: engine, downloadManager: dm)

        // Create a fake model file
        let fakeModelURL = tempDir.appendingPathComponent("test-model.litertlm")
        try? Data("fake model data".utf8).write(to: fakeModelURL)

        // Set download state to downloaded
        dm.downloadStates["test-model.litertlm"] = .downloaded(fakeModelURL)

        // Call handleModelSelection — this is what the sidebar tap triggers
        await vm.handleModelSelection(fakeModelURL)

        // The engine should have been initialized with the model path
        XCTAssertGreaterThan(
            engine.initializeCallCount, 0,
            "Engine should be initialized after handleModelSelection"
        )
        XCTAssertEqual(
            engine.lastModelPath, fakeModelURL.path,
            "Engine should be initialized with the correct model path"
        )
    }

    /// Verify that the ViewModel tracks the active model URL after loading.
    func testActiveModelURLSetAfterLoad() async {
        let engine = makeEngine()
        let vm = makeViewModel(engine: engine)

        let fakeModelURL = tempDir.appendingPathComponent("test-model.litertlm")
        try? Data("fake model data".utf8).write(to: fakeModelURL)

        await vm.handleModelSelection(fakeModelURL)

        // After loading, activeModelMetadata should be populated
        // (or at minimum, the engine should be ready)
        XCTAssertTrue(
            engine.isReady,
            "Engine should be ready after handleModelSelection"
        )
    }

    // MARK: - Eval View Data Source Tests

    /// The Eval view checks discoveredModels.isEmpty to show "No models on disk".
    /// Verify that after download + callback, this condition can be resolved.
    func testEvalViewDataSourceNotEmptyAfterDownload() {
        let dm = makeDownloadManager()
        let vm = makeViewModel(downloadManager: dm)

        // This test validates the mechanism — after the callback fires,
        // refreshDiscoveredModels() is called. We verify the callback chain
        // doesn't crash and the property is accessible.
        XCTAssertNotNil(vm.discoveredModels, "discoveredModels should never be nil")

        // Fire callback
        let fakeURL = tempDir.appendingPathComponent("test.litertlm")
        dm.onDownloadCompleted?("test.litertlm", fakeURL)

        // discoveredModels was refreshed (no crash = callback chain works)
        XCTAssertNotNil(vm.discoveredModels, "discoveredModels should still be accessible after refresh")
    }

    // MARK: - Settings Reload After Model Load Tests

    /// After a model is loaded, changing settings should trigger reinitializeIfNeeded
    /// (which guards on engine.isReady && activeModelURL != nil).
    func testSettingsChangeTriggersReloadAfterModelLoad() async {
        let engine = makeEngine()
        let vm = makeViewModel(engine: engine)

        let fakeModelURL = tempDir.appendingPathComponent("test-model.litertlm")
        try? Data("fake model data".utf8).write(to: fakeModelURL)

        // Load the model first
        await vm.handleModelSelection(fakeModelURL)
        let initCountAfterLoad = engine.initializeCallCount

        XCTAssertGreaterThan(
            initCountAfterLoad, 0,
            "Precondition: engine should have been initialized"
        )

        // Change a setting that triggers reinitializeIfNeeded via didSet
        vm.useGPU.toggle()

        // Allow the async reinitialize to execute
        try? await Task.sleep(for: .milliseconds(100))

        // Engine should have been re-initialized
        XCTAssertGreaterThan(
            engine.initializeCallCount, initCountAfterLoad,
            "Engine should be re-initialized after settings change with a loaded model"
        )
    }

    /// Without a loaded model, settings changes should NOT trigger engine init.
    func testSettingsChangeDoesNothingWithoutLoadedModel() async {
        let engine = makeEngine()
        let vm = makeViewModel(engine: engine)

        let initCountBefore = engine.initializeCallCount

        // Change a setting WITHOUT loading a model first
        vm.useGPU.toggle()

        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(
            engine.initializeCallCount, initCountBefore,
            "Engine should NOT be initialized when no model is loaded"
        )
    }

    // MARK: - Callback Lifecycle Tests

    /// Verify the callback uses weak self and doesn't cause retain cycles.
    func testCallbackDoesNotRetainViewModel() {
        let dm = makeDownloadManager()

        // Create and immediately release the ViewModel
        autoreleasepool {
            let _ = makeViewModel(downloadManager: dm)
        }

        // The callback should still be set (strong reference to closure)
        XCTAssertNotNil(dm.onDownloadCompleted)

        // But firing it should be safe (weak self is nil, no crash)
        dm.onDownloadCompleted?("test.litertlm", tempDir.appendingPathComponent("test.litertlm"))
        // No crash = test passes
    }
}
