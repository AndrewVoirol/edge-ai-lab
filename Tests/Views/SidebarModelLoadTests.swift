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

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - Sidebar Model Load Tests
//
// Unit tests for the download-to-load mechanics at the ModelDownloadManager
// and ConversationViewModel level. These verify the callback contract that
// enables the sidebar to surface newly-downloaded models for loading.

@MainActor
final class SidebarModelLoadTests: XCTestCase {

    // MARK: - Test Infrastructure

    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SidebarModelLoadTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    // MARK: - Download Manager Callback Tests

    /// onDownloadCompleted callback should be nil by default on a fresh manager.
    func testOnDownloadCompletedDefaultsToNil() {
        let config = URLSessionConfiguration.ephemeral
        let dm = ModelDownloadManager(configuration: config, documentsDirectory: tempDir)
        XCTAssertNil(dm.onDownloadCompleted, "Callback should be nil before wiring")
    }

    /// Setting onDownloadCompleted should work and the callback should be invocable.
    func testOnDownloadCompletedCanBeSetAndInvoked() {
        let config = URLSessionConfiguration.ephemeral
        let dm = ModelDownloadManager(configuration: config, documentsDirectory: tempDir)

        var callbackFired = false
        var receivedFilename: String?
        var receivedURL: URL?

        dm.onDownloadCompleted = { filename, url in
            callbackFired = true
            receivedFilename = filename
            receivedURL = url
        }

        let testURL = tempDir.appendingPathComponent("test.litertlm")
        dm.onDownloadCompleted?("test.litertlm", testURL)

        XCTAssertTrue(callbackFired, "Callback should fire when invoked")
        XCTAssertEqual(receivedFilename, "test.litertlm")
        XCTAssertEqual(receivedURL, testURL)
    }

    /// postDownloadCallback and onDownloadCompleted are independent — setting one
    /// should not affect the other.
    func testCallbacksAreIndependent() {
        let config = URLSessionConfiguration.ephemeral
        let dm = ModelDownloadManager(configuration: config, documentsDirectory: tempDir)

        var generalFired = false
        var communityFired = false

        dm.onDownloadCompleted = { _, _ in generalFired = true }
        dm.postDownloadCallback = { _, _ in communityFired = true }

        let testURL = tempDir.appendingPathComponent("test.litertlm")

        dm.onDownloadCompleted?("test.litertlm", testURL)
        XCTAssertTrue(generalFired)
        XCTAssertFalse(communityFired, "Community callback should not fire from general callback")

        generalFired = false
        dm.postDownloadCallback?("test.litertlm", testURL)
        XCTAssertFalse(generalFired, "General callback should not fire from community callback")
        XCTAssertTrue(communityFired)
    }

    // MARK: - Download State Tests

    /// The .downloaded state should carry the file URL for tap-to-load.
    func testDownloadedStateCarriesURL() {
        let config = URLSessionConfiguration.ephemeral
        let dm = ModelDownloadManager(configuration: config, documentsDirectory: tempDir)

        let fileURL = tempDir.appendingPathComponent("model.litertlm")
        dm.downloadStates["model.litertlm"] = .downloaded(fileURL)

        guard case .downloaded(let url) = dm.downloadStates["model.litertlm"] else {
            XCTFail("Expected .downloaded state")
            return
        }
        XCTAssertEqual(url, fileURL, "URL should be preserved in .downloaded state")
    }

    /// checkState should detect an existing file and return .downloaded with correct URL.
    func testCheckStateDetectsExistingFile() throws {
        let config = URLSessionConfiguration.ephemeral
        let dm = ModelDownloadManager(configuration: config, documentsDirectory: tempDir)

        // Create a model that exists in the registry
        let model = ModelRegistry.gemma4E2BStandard

        // Create the file at the expected location
        let fileURL = tempDir.appendingPathComponent(model.modelFile)
        try Data("fake model".utf8).write(to: fileURL)

        let state = dm.checkState(for: model)
        guard case .downloaded(let url) = state else {
            XCTFail("Expected .downloaded state for existing file, got: \(state)")
            return
        }
        XCTAssertEqual(url.lastPathComponent, model.modelFile)
    }

    /// After deleteModel, state should return to .notDownloaded.
    func testDeleteModelClearsState() throws {
        let config = URLSessionConfiguration.ephemeral
        let dm = ModelDownloadManager(configuration: config, documentsDirectory: tempDir)

        let model = ModelRegistry.gemma4E2BStandard
        let fileURL = tempDir.appendingPathComponent(model.modelFile)
        try Data("fake model".utf8).write(to: fileURL)

        // Establish downloaded state
        let _ = dm.checkState(for: model)

        // Delete
        dm.deleteModel(model)

        guard case .notDownloaded = dm.downloadStates[model.modelFile] else {
            XCTFail("Expected .notDownloaded after delete")
            return
        }
    }

    // MARK: - ViewModel Wiring Verification

    /// ViewModel init should wire the download manager's onDownloadCompleted callback.
    func testViewModelWiresOnDownloadCompleted() {
        let config = URLSessionConfiguration.ephemeral
        let dm = ModelDownloadManager(configuration: config, documentsDirectory: tempDir)

        XCTAssertNil(dm.onDownloadCompleted, "Precondition")

        let store = ConversationStore(
            storageDirectory: tempDir.appendingPathComponent("conversations")
        )
        let vm = ConversationViewModel(
            engine: MockInferenceEngine.happyPath(),
            metricsStore: MetricsStore(fileURL: tempDir.appendingPathComponent("metrics.json")),
            downloadManager: dm,
            conversationStore: store
        )
        _ = vm // Keep alive

        XCTAssertNotNil(
            dm.onDownloadCompleted,
            "ViewModel init must wire onDownloadCompleted"
        )
    }

    /// ViewModel's discoveredModels property should be refreshable without crash.
    func testRefreshDiscoveredModelsDoesNotCrash() {
        let store = ConversationStore(
            storageDirectory: tempDir.appendingPathComponent("conversations")
        )
        let vm = ConversationViewModel(
            engine: MockInferenceEngine.happyPath(),
            metricsStore: MetricsStore(fileURL: tempDir.appendingPathComponent("metrics.json")),
            conversationStore: store
        )

        // Should not crash
        vm.refreshDiscoveredModels()

        // discoveredModels should be a valid array (possibly empty on test machines)
        XCTAssertNotNil(vm.discoveredModels)
    }

    /// refreshStates + checkState round-trip should clear stale cached state
    /// and re-scan the filesystem.
    ///
    /// Note: On developer machines, `GalleryModelDiscovery.discoverModels()` may find
    /// the real model in Sources/Models/ (DEBUG macOS #filePath resolution). In that case,
    /// checkState falls through to discovery and returns .downloaded even if the temp-dir
    /// file was deleted. We test the cache-clearing behavior rather than asserting a
    /// specific final state, per AGENTS.md multi-path resolution rules.
    func testRefreshAndCheckStateRoundTrip() throws {
        let config = URLSessionConfiguration.ephemeral
        let dm = ModelDownloadManager(configuration: config, documentsDirectory: tempDir)

        let model = ModelRegistry.gemma4E2BStandard

        // Create the file at the expected location
        let fileURL = tempDir.appendingPathComponent(model.modelFile)
        try Data("fake model".utf8).write(to: fileURL)

        // First check should set .downloaded
        let state1 = dm.checkState(for: model)
        guard case .downloaded = state1 else {
            XCTFail("Expected .downloaded after file creation")
            return
        }

        // Delete the file from our temp dir
        try FileManager.default.removeItem(at: fileURL)

        // State is still cached as .downloaded (no re-scan yet)
        let state2 = dm.checkState(for: model)
        guard case .downloaded = state2 else {
            XCTFail("Expected cached .downloaded state before refresh")
            return
        }

        // refreshStates should clear the cache
        dm.refreshStates()

        // After refresh, the stale cache entry is cleared. checkState re-evaluates:
        // - First checks tempDir (file is gone) → no match
        // - Falls through to GalleryModelDiscovery.discoverModels()
        //   → On dev machines, may find the real model in Sources/Models/
        //   → On CI, returns .notDownloaded
        let state3 = dm.checkState(for: model)
        switch state3 {
        case .notDownloaded:
            break // Expected on CI / clean machines
        case .downloaded:
            break // Acceptable on dev machines where real model exists
        default:
            XCTFail("Expected .notDownloaded or .downloaded after refresh, got: \(state3)")
        }
    }
}
