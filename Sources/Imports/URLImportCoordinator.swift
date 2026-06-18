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
import Observation
import os

// MARK: - URL Import Coordinator

/// Shared coordinator that owns the import-manager lifecycle and download-observation
/// polling loop. Both `iOSURLImportSheet` and `macOSURLImportSheet` delegate to this
/// coordinator so the behavioral logic lives in one place.
///
/// Platform-specific behavior (e.g. auto-dismiss on iOS) is injected via closures
/// passed to `observeDownloadCompletion(…)`.
@Observable
@MainActor
final class URLImportCoordinator {

    private static let logger = Logger(
        subsystem: "com.andrewvoirol.EdgeAILab",
        category: "URLImportCoordinator"
    )

    // MARK: - State

    /// The active import manager for the current import session.
    private(set) var importManager: URLImportManager?

    /// Tracks the download completion observation task so it can be cancelled on dismiss.
    private var downloadObservationTask: Task<Void, Never>?

    // MARK: - Computed Properties

    /// Whether the import is in a terminal state (downloading, complete, or failed)
    /// where the user should see a "Done" button instead of "Cancel".
    var isTerminalState: Bool {
        guard let manager = importManager else { return false }
        switch manager.state {
        case .downloading, .complete, .failed:
            return true
        default:
            return false
        }
    }

    // MARK: - Actions

    /// Start a new import session from the given URL text.
    ///
    /// Creates a fresh `HFModelBrowser` and `URLImportManager`, then kicks off
    /// the import pipeline.
    ///
    /// - Parameters:
    ///   - urlText: The raw URL string pasted by the user.
    ///   - catalog: The `DynamicModelCatalog` to register imported models in.
    func startImport(urlText: String, catalog: DynamicModelCatalog) {
        // NOTE: Creates a fresh HFModelBrowser per import. This is fine for a modal
        // sheet, but could be optimized to reuse viewModel.browser if one is added.
        let browser = HFModelBrowser()
        let manager = URLImportManager(browser: browser, catalog: catalog)
        self.importManager = manager
        Task {
            await manager.importFromURL(urlText)
        }
    }

    /// Observe download completion by polling `ModelDownloadManager.downloadStates`.
    ///
    /// When the download state for `filename` transitions to `.downloaded`, calls
    /// `markComplete()` on the import manager and invokes the `onComplete` closure.
    /// On `.failed`, transitions the import state and invokes the `onFail` closure.
    ///
    /// - Parameters:
    ///   - filename: The filename being downloaded.
    ///   - metadata: The model metadata for marking completion.
    ///   - downloadManager: The download manager whose `downloadStates` to poll.
    ///   - onComplete: Optional closure invoked after a successful download (e.g. auto-dismiss on iOS).
    ///   - onFail: Optional closure invoked after a failed download.
    func observeDownloadCompletion(
        filename: String,
        metadata: DynamicModelMetadata,
        downloadManager: ModelDownloadManager,
        onComplete: (() -> Void)?,
        onFail: (() -> Void)?
    ) {
        downloadObservationTask?.cancel()
        downloadObservationTask = Task { @MainActor [weak importManager] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                if let dlState = downloadManager.downloadStates[filename] {
                    switch dlState {
                    case .downloaded:
                        importManager?.markComplete(metadata: metadata)
                        Self.logger.info("✅ Download completed for \(filename, privacy: .public)")
                        if let onComplete {
                            // Brief delay so the user sees the success state
                            try? await Task.sleep(for: .milliseconds(1500))
                            if !Task.isCancelled {
                                onComplete()
                            }
                        }
                        return
                    case .failed(let message):
                        importManager?.state = .failed(error: "Download failed: \(message)")
                        Self.logger.error("❌ Download failed for \(filename, privacy: .public): \(message, privacy: .public)")
                        onFail?()
                        return
                    default:
                        continue
                    }
                }
            }
        }
    }

    /// Cancel the download observation task.
    ///
    /// Call this when the sheet is being dismissed to prevent dangling observation loops.
    func cancelObservation() {
        downloadObservationTask?.cancel()
        downloadObservationTask = nil
    }
}
