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

// MARK: - ConversationViewModel + URL Import

/// URL import pipeline: HuggingFace model import via paste-and-go or ⌘I shortcut.
extension ConversationViewModel {

    // MARK: - URL Import

    /// Start importing a model from a HuggingFace URL.
    ///
    /// This opens the import sheet and begins the pipeline. Both the inline
    /// quick-paste field and the ⌘I shortcut call this method.
    ///
    /// - Parameter urlString: The HuggingFace URL to import from.
    func startURLImport(_ urlString: String) {
        pendingImportURL = urlString
        showURLImportSheet = true
    }

    /// Load a model that was imported via URL Import.
    ///
    /// Discovers the downloaded file on disk, then loads it into the engine.
    /// Called from the import sheet's "Load Model" button after download completes.
    ///
    /// - Parameter metadata: The imported model's `DynamicModelMetadata`.
    func loadImportedModel(_ metadata: DynamicModelMetadata) {
        // Refresh to pick up newly downloaded file
        refreshDiscoveredModels()

        // Find the downloaded file among discovered models
        // Check both known and community discovered models
        let filename = metadata.metadata.modelFile

        // Search discovered models for a matching file
        if let match = discoveredModels.first(where: { $0.filename.contains(filename) || filename.contains($0.filename) }) {
            Task {
                await handleModelSelection(match.url)
            }
        } else {
            // If not found in standard discovery, check community models
            statusMessage = "Model downloaded. Select it from the sidebar to load."
        }
    }
}
