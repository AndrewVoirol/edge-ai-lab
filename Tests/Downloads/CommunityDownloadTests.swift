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

/// Tests for community model download pipeline and HuggingFace API integration.
final class CommunityDownloadTests: XCTestCase {

    // MARK: - Download URL Construction

    func testDownloadURLConstruction() {
        let url = HFModelBrowser.downloadURL(
            repoId: "litert-community/gemma-4-E2B-it-litert-lm",
            filename: "gemma-4-E2B-it.litertlm"
        )
        XCTAssertTrue(url.absoluteString.contains("litert-community/gemma-4-E2B-it-litert-lm"))
        XCTAssertTrue(url.absoluteString.contains("gemma-4-E2B-it.litertlm"))
        XCTAssertTrue(url.absoluteString.contains("resolve/main"))
    }

    func testDownloadURLCustomRevision() {
        let url = HFModelBrowser.downloadURL(
            repoId: "test/model",
            filename: "model.litertlm",
            revision: "v2"
        )
        XCTAssertTrue(url.absoluteString.contains("resolve/v2"))
    }

    // MARK: - LiteRT Sibling Detection

    func testLitertlmSiblingDetection() {
        let model = makeTestHFModel(siblings: [
            HFSibling(rfilename: "README.md", size: 100, lfs: nil),
            HFSibling(rfilename: "config.json", size: 200, lfs: nil),
            HFSibling(rfilename: "gemma-4-E2B-it.litertlm", size: 2_000_000_000, lfs: nil)
        ])

        let sibling = model.siblings?.first(where: { $0.rfilename.hasSuffix(".litertlm") })
        XCTAssertNotNil(sibling)
        XCTAssertEqual(sibling?.rfilename, "gemma-4-E2B-it.litertlm")
    }

    func testNoLitertlmSibling() {
        let model = makeTestHFModel(siblings: [
            HFSibling(rfilename: "README.md", size: 100, lfs: nil),
            HFSibling(rfilename: "model.safetensors", size: 5_000_000_000, lfs: nil)
        ])

        let sibling = model.siblings?.first(where: { $0.rfilename.hasSuffix(".litertlm") })
        XCTAssertNil(sibling)
    }

    // MARK: - Download State Transitions

    @MainActor
    func testDownloadStateNotDownloadedByDefault() {
        let manager = ModelDownloadManager()
        let state = manager.downloadStates["nonexistent.litertlm"] ?? .notDownloaded
        if case .notDownloaded = state {
            // Expected
        } else {
            XCTFail("Expected .notDownloaded state")
        }
    }

    @MainActor
    func testCancelDownloadResetsState() async {
        let manager = ModelDownloadManager()
        manager.downloadStates["test.litertlm"] = .downloading(progress: 0.5)
        await manager.cancelDownload(filename: "test.litertlm")
        
        let state = manager.downloadStates["test.litertlm"] ?? .notDownloaded
        if case .notDownloaded = state {
            // Expected
        } else {
            XCTFail("Expected .notDownloaded after cancel, got \(state)")
        }
    }

    @MainActor
    func testDeleteModelResetsState() {
        let manager = ModelDownloadManager()
        // Simulate a downloaded state
        manager.downloadStates["test.litertlm"] = .downloaded(URL(fileURLWithPath: "/tmp/test.litertlm"))
        manager.deleteModel(filename: "test.litertlm")

        let state = manager.downloadStates["test.litertlm"] ?? .notDownloaded
        if case .notDownloaded = state {
            // Expected
        } else {
            XCTFail("Expected .notDownloaded after delete")
        }
    }

    // MARK: - Post-Download Callback

    @MainActor
    func testPostDownloadCallbackConfigurable() {
        let manager = ModelDownloadManager()
        var callbackFired = false
        manager.postDownloadCallback = { filename, url in
            callbackFired = true
            XCTAssertEqual(filename, "test.litertlm")
        }

        // Simulate callback
        manager.postDownloadCallback?("test.litertlm", URL(fileURLWithPath: "/tmp/test.litertlm"))
        XCTAssertTrue(callbackFired)
    }

    // MARK: - HFModelFormat Detection

    func testDetectLitertlmFormat() {
        let model = makeTestHFModel(
            tags: ["litert"],
            libraryName: "litert",
            siblings: [
                HFSibling(rfilename: "model.litertlm", size: 1000, lfs: nil)
            ]
        )
        let browser = HFModelBrowser()
        let format = browser.detectFormat(model)
        XCTAssertEqual(format, .litertlm)
    }

    func testDetectMLXFormat() {
        let model = makeTestHFModel(
            tags: ["mlx"],
            libraryName: "mlx",
            siblings: [
                HFSibling(rfilename: "config.json", size: 500, lfs: nil),
                HFSibling(rfilename: "model.safetensors", size: 5_000_000_000, lfs: nil)
            ]
        )
        let browser = HFModelBrowser()
        let format = browser.detectFormat(model)
        XCTAssertEqual(format, .mlx)
    }

    func testDetectUnknownFormat() {
        let model = makeTestHFModel(
            tags: [],
            libraryName: nil,
            siblings: [
                HFSibling(rfilename: "model.bin", size: 1000, lfs: nil)
            ]
        )
        let browser = HFModelBrowser()
        let format = browser.detectFormat(model)
        XCTAssertEqual(format, .unknown)
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
