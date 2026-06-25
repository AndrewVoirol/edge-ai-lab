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

// MARK: - ModelDownloadManager refreshStates() Tests
//
// Verifies the refreshStates() fix: stale cached entries (.notDownloaded, .downloaded,
// .failed, .authRequired) are cleared before re-scanning the filesystem, while
// in-flight states (.downloading, .queued, .paused) are preserved to avoid
// interrupting active downloads.

@MainActor
final class ModelDownloadManagerRefreshTests: XCTestCase {

    // MARK: - Stale Entry Clearing

    /// refreshStates() should clear stale .notDownloaded entries so checkState()
    /// re-evaluates them from the filesystem.
    func test_refreshStates_clearsStaleNotDownloaded() {
        let manager = ModelDownloadManager()

        // Inject a stale .notDownloaded entry for a model key that isn't a real file
        let staleKey = "fake-stale-model.litertlm"
        manager.downloadStates[staleKey] = .notDownloaded

        XCTAssertNotNil(
            manager.downloadStates[staleKey],
            "Precondition: stale entry should exist before refresh"
        )

        manager.refreshStates()

        // After refresh, the stale entry should have been cleared.
        // refreshStates() only preserves .downloading, .queued, and .paused states.
        // Since "fake-stale-model.litertlm" isn't a known registry model, it won't
        // be re-added by the checkState() loop over ModelRegistry.knownModels.
        XCTAssertNil(
            manager.downloadStates[staleKey],
            "Stale .notDownloaded entry should be cleared after refreshStates()"
        )
    }

    // MARK: - In-Flight State Preservation

    /// refreshStates() should preserve .downloading states to avoid interrupting
    /// active downloads.
    func test_refreshStates_preservesActiveDownloads() {
        let manager = ModelDownloadManager()

        let modelKey = "active-download-model.litertlm"
        manager.downloadStates[modelKey] = .downloading(progress: 0.5)

        manager.refreshStates()

        guard let state = manager.downloadStates[modelKey] else {
            XCTFail("Active download state should survive refreshStates()")
            return
        }

        switch state {
        case .downloading(let progress):
            XCTAssertEqual(progress, 0.5, accuracy: 0.001,
                           "Download progress should be preserved exactly")
        default:
            XCTFail("Expected .downloading(0.5), got: \(state)")
        }
    }

    /// refreshStates() should preserve .queued states to maintain download queue order.
    func test_refreshStates_preservesQueuedState() {
        let manager = ModelDownloadManager()

        let modelKey = "queued-model.litertlm"
        manager.downloadStates[modelKey] = .queued(position: 1)

        manager.refreshStates()

        guard let state = manager.downloadStates[modelKey] else {
            XCTFail("Queued state should survive refreshStates()")
            return
        }

        switch state {
        case .queued(let position):
            XCTAssertEqual(position, 1, "Queue position should be preserved")
        default:
            XCTFail("Expected .queued(position: 1), got: \(state)")
        }
    }

    /// refreshStates() should preserve .paused states so users can resume downloads.
    func test_refreshStates_preservesPausedState() {
        let manager = ModelDownloadManager()

        let modelKey = "paused-model.litertlm"
        let resumeData = Data([0x01, 0x02, 0x03, 0x04])
        manager.downloadStates[modelKey] = .paused(resumeData: resumeData, progress: 0.3)

        manager.refreshStates()

        guard let state = manager.downloadStates[modelKey] else {
            XCTFail("Paused state should survive refreshStates()")
            return
        }

        switch state {
        case .paused(let data, let progress):
            XCTAssertEqual(data, resumeData, "Resume data should be preserved")
            XCTAssertEqual(progress, 0.3, accuracy: 0.001,
                           "Paused progress should be preserved")
        default:
            XCTFail("Expected .paused(resumeData:, progress: 0.3), got: \(state)")
        }
    }
}
