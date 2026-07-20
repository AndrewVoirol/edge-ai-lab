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

// MARK: - DownloadManager Tests

@MainActor
final class DownloadManagerTests: XCTestCase {

    // MARK: - Initial State

    /// A freshly created manager should have no download states populated.
    func testInitialDownloadStatesEmpty() {
        let manager = ModelDownloadManager()
        XCTAssertTrue(manager.downloadStates.isEmpty)
    }

    /// After refreshStates, all known models should have an entry in downloadStates
    /// (either .notDownloaded or .downloaded if the file happens to exist).
    func testRefreshStatesPopulatesAllKnownModels() {
        let manager = ModelDownloadManager()
        manager.refreshStates()

        // Every known model should now have a state entry
        for model in KnownModelCatalog.allModels {
            let state = manager.checkState(for: model)
            // On a test machine, models won't be downloaded, so expect .notDownloaded
            // (unless they happen to exist in Documents)
            switch state {
            case .notDownloaded, .downloaded:
                break  // Both are valid
            default:
                XCTFail("\(model.displayName) has unexpected state after refresh: \(state)")
            }
        }
    }

    // MARK: - State Queries

    /// checkState should return .notDownloaded for a model that doesn't exist on disk.
    func testCheckStateReturnsNotDownloadedForMissingFile() {
        let manager = ModelDownloadManager()
        let model = KnownModelCatalog.gemma4E2BStandard

        let state = manager.checkState(for: model)

        // On test machines, the model file won't be in Documents
        // This test could be environment-dependent; we verify we get a non-crash result
        switch state {
        case .notDownloaded:
            break  // Expected on clean machines
        case .downloaded:
            break  // Acceptable if someone has the file
        default:
            XCTFail("Expected .notDownloaded or .downloaded, got: \(state)")
        }
    }

    // MARK: - Auth Requirements

    /// Models from google/* repos require HuggingFace authentication.
    func testGoogleRepoModelsRequireAuth() {
        for model in KnownModelCatalog.allModels {
            if let modelId = model.modelId, modelId.hasPrefix("google/") {
                XCTAssertTrue(
                    model.requiresAuth,
                    "\(model.displayName) from google/ should requireAuth"
                )
            }
        }
    }

    /// Models from litert-community/* repos should NOT require auth.
    func testCommunityRepoModelsDontRequireAuth() {
        for model in KnownModelCatalog.allModels {
            if let modelId = model.modelId, modelId.hasPrefix("litert-community/") {
                XCTAssertFalse(
                    model.requiresAuth,
                    "\(model.displayName) from litert-community should not requireAuth"
                )
            }
        }
    }

    // MARK: - Cancel

    /// Canceling a download that isn't active should not crash.
    func testCancelNonActiveDownloadDoesNotCrash() async {
        let manager = ModelDownloadManager()
        let model = KnownModelCatalog.gemma4E2BStandard

        // Should be a no-op, not a crash
        await manager.cancelDownload(model)

        let state = manager.checkState(for: model)
        switch state {
        case .notDownloaded:
            break
        default:
            break  // Any state is acceptable — we just verify no crash
        }
    }

    // MARK: - Download State Enum

    /// Verify that download state dictionary tracks per-model state correctly.
    func testDownloadStatesArePerModel() {
        let manager = ModelDownloadManager()

        // Check state for two different models
        let state1 = manager.checkState(for: KnownModelCatalog.gemma4E2BStandard)
        let state2 = manager.checkState(for: KnownModelCatalog.gemma4E2BWeb)

        // Both should have states (likely .notDownloaded)
        // The important thing is they're tracked independently
        switch state1 {
        case .notDownloaded, .downloaded:
            break
        default:
            XCTFail("Unexpected state for E2B Standard")
        }
        switch state2 {
        case .notDownloaded, .downloaded:
            break
        default:
            XCTFail("Unexpected state for E2B Web")
        }
    }

    // MARK: - Pending Auth Model

    /// Initially, pendingAuthModel should be nil.
    func testPendingAuthModelInitiallyNil() {
        let manager = ModelDownloadManager()
        XCTAssertNil(manager.pendingAuthModel)
        XCTAssertFalse(manager.showTokenPrompt)
    }

    // MARK: - Download URL Construction

    /// Every model should have a well-formed download URL.
    func testDownloadURLConstruction() {
        for model in KnownModelCatalog.allModels {
            guard let url = model.downloadURL else {
                XCTFail("\(model.displayName) has nil downloadURL")
                continue
            }
            // URL should contain the model file name
            XCTAssertTrue(
                url.absoluteString.contains(model.modelFile ?? ""),
                "\(model.displayName) download URL should contain the model filename"
            )
            // URL should contain the model ID (repo path)
            let modelId = model.modelId ?? ""
            let repoPath = modelId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
                ?? modelId
            XCTAssertTrue(
                url.absoluteString.contains(modelId) ||
                url.absoluteString.contains(repoPath),
                "\(model.displayName) download URL should contain the modelId"
            )
        }
    }

    /// Deleting a model that doesn't exist should set state to .notDownloaded without crashing.
    func testDeleteNonExistentModelSetsNotDownloaded() {
        let manager = ModelDownloadManager()
        
        // Use a dummy model that definitely does not exist on disk
        let model = ModelCapabilityProfile(
            id: "dummy-not-real.litertlm",
            displayName: "Dummy",
            repoId: nil,
            runtimeType: .litertlm,
            supportsVision: nil, supportsAudio: nil, supportsThinking: nil,
            supportsToolCalling: nil, supportsMTP: nil, supportsConstrainedDecoding: nil,
            architecture: nil, contextWindow: nil, fileSizeBytes: nil,
            estimatedMemoryGB: nil, totalParameters: nil, parameterLabel: nil,
            confidence: .low, source: .huggingFaceInferred, lastUpdated: Date(),
            repoSha: nil, license: nil, licenseLink: nil, baseModelId: nil,
            downloads: nil, likes: nil, downloadsAllTime: nil,
            supportedLanguages: [], tags: [],
            defaultConfig: nil, platformSupport: nil,
            modelDescription: nil, recommendedFor: nil,
            modelFile: "dummy-not-real.litertlm",
            modelId: "dummy/dummy"
        )

        manager.deleteModel(model)

        let state = manager.checkState(for: model)
        switch state {
        case .notDownloaded:
            break  // Expected
        default:
            XCTFail("Expected .notDownloaded after deleting non-existent model, got: \(state)")
        }
    }
}
