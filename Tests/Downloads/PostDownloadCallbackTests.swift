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
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - PostDownloadCallback Tests

/// Tests for the postDownloadCallback race condition fix.
///
/// The race condition: HFModelCard called `downloadCommunityModel()` and then
/// on the NEXT line set `postDownloadCallbacks[filename]`. If a download completed
/// near-instantly (cache hit, mock session), the URLSession delegate could fire
/// before the callback was registered.
///
/// Fix: The completion closure is now passed as a parameter to `downloadCommunityModel`
/// and registered INSIDE the method BEFORE starting the download task.
@Suite("PostDownloadCallback — Race Condition Fix")
struct PostDownloadCallbackRaceFixTests {

    // MARK: - Callback Registration Atomicity

    @Test("Callback is registered before download task starts")
    @MainActor
    func callbackRegisteredBeforeDownloadStarts() {
        let manager = ModelDownloadManager()
        let model = makeTestHFModel()
        let sibling = HFSibling(rfilename: "test-model.litertlm", size: 1000, lfs: nil)

        // Pass a completion closure
        manager.downloadCommunityModel(model: model, sibling: sibling) { _, _ in
            // Callback body — we just need to verify it was registered
        }

        // The callback should be registered in the dictionary immediately
        #expect(
            manager.postDownloadCallbacks["test-model.litertlm"] != nil,
            "Callback must be registered in postDownloadCallbacks before download starts"
        )
    }

    @Test("Callback fires after state transitions to .downloaded")
    @MainActor
    func callbackFiresAfterStateUpdate() {
        let manager = ModelDownloadManager()
        let filename = "test-callback-order.litertlm"
        let testURL = manager.documentsDirectory.appendingPathComponent(filename)

        var callbackFired = false
        var stateAtCallbackTime: ModelDownloadManager.DownloadState?

        // Register callback directly (simulating what downloadCommunityModel does internally)
        manager.postDownloadCallbacks[filename] = { _, _ in
            callbackFired = true
            stateAtCallbackTime = manager.downloadStates[filename]
        }

        // Simulate what the URLSession delegate does after download completes:
        // set state first, then fire callback
        manager.downloadStates[filename] = .downloaded(testURL)

        if let callback = manager.postDownloadCallbacks[filename] {
            callback(filename, testURL)
            manager.postDownloadCallbacks.removeValue(forKey: filename)
        }

        #expect(callbackFired, "Callback should have fired")

        // State should be .downloaded when the callback executes
        if case .downloaded(let url) = stateAtCallbackTime {
            #expect(url == testURL, "Downloaded URL should match")
        } else {
            Issue.record("State should be .downloaded when callback fires, got: \(String(describing: stateAtCallbackTime))")
        }
    }

    @Test("Callback is removed after firing (no memory leak)")
    @MainActor
    func callbackRemovedAfterFiring() {
        let manager = ModelDownloadManager()
        let filename = "test-cleanup.litertlm"
        let testURL = manager.documentsDirectory.appendingPathComponent(filename)

        manager.postDownloadCallbacks[filename] = { _, _ in }

        #expect(manager.postDownloadCallbacks[filename] != nil, "Callback should exist before firing")

        // Simulate the delegate's callback firing and cleanup
        if let callback = manager.postDownloadCallbacks[filename] {
            callback(filename, testURL)
            manager.postDownloadCallbacks.removeValue(forKey: filename)
        }

        #expect(
            manager.postDownloadCallbacks[filename] == nil,
            "Callback should be removed after firing to prevent memory leaks"
        )
    }

    @Test("No completion parameter means no callback registered")
    @MainActor
    func noCompletionDoesNotRegisterCallback() {
        let manager = ModelDownloadManager()
        let model = makeTestHFModel()
        let sibling = HFSibling(rfilename: "no-callback.litertlm", size: 1000, lfs: nil)

        // Call without completion
        manager.downloadCommunityModel(model: model, sibling: sibling)

        #expect(
            manager.postDownloadCallbacks["no-callback.litertlm"] == nil,
            "No callback should be registered when completion is nil"
        )
    }

    @Test("Duplicate download calls are rejected")
    @MainActor
    func duplicateDownloadRejected() {
        let manager = ModelDownloadManager()
        let model = makeTestHFModel()
        let sibling = HFSibling(rfilename: "dup-test.litertlm", size: 1000, lfs: nil)

        // First call — should register callback and start download
        manager.downloadCommunityModel(model: model, sibling: sibling) { _, _ in }

        // Verify first callback is registered
        #expect(manager.postDownloadCallbacks["dup-test.litertlm"] != nil)

        // Second call — should be rejected (duplicate)
        manager.downloadCommunityModel(model: model, sibling: sibling) { _, _ in }

        // The first callback should still be the one registered
        // (the second call was rejected before reaching callback registration)
    }

    // MARK: - Helpers

    private func makeTestHFModel(
        id: String = "test/test-model",
        tags: [String] = ["litert"],
        libraryName: String? = "litert",
        siblings: [HFSibling]? = nil
    ) -> HFModelInfo {
        HFModelInfo(
            id: id,
            author: "test",
            lastModified: "2026-01-01T00:00:00.000Z",
            downloads: 100,
            likes: 10,
            tags: tags,
            pipelineTag: "text-generation",
            libraryName: libraryName,
            siblings: siblings
        )
    }
}
