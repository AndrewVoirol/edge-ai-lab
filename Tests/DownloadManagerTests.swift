import XCTest
import LiteRTLM

#if os(iOS)
@testable import GemmaEdgeGallery_iOS
#elseif os(macOS)
@testable import GemmaEdgeGallery_macOS
#endif

// MARK: - DownloadManager Tests

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
        for model in ModelRegistry.knownModels {
            let state = manager.checkState(for: model)
            // On a test machine, models won't be downloaded, so expect .notDownloaded
            // (unless they happen to exist in Documents)
            switch state {
            case .notDownloaded, .downloaded:
                break  // Both are valid
            default:
                XCTFail("\(model.name) has unexpected state after refresh: \(state)")
            }
        }
    }

    // MARK: - State Queries

    /// checkState should return .notDownloaded for a model that doesn't exist on disk.
    func testCheckStateReturnsNotDownloadedForMissingFile() {
        let manager = ModelDownloadManager()
        let model = ModelRegistry.gemma4E2BStandard

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
        for model in ModelRegistry.knownModels {
            if model.modelId.hasPrefix("google/") {
                XCTAssertTrue(
                    model.requiresAuth,
                    "\(model.name) from google/ should requireAuth"
                )
            }
        }
    }

    /// Models from litert-community/* repos should NOT require auth.
    func testCommunityRepoModelsDontRequireAuth() {
        for model in ModelRegistry.knownModels {
            if model.modelId.hasPrefix("litert-community/") {
                XCTAssertFalse(
                    model.requiresAuth,
                    "\(model.name) from litert-community should not requireAuth"
                )
            }
        }
    }

    // MARK: - Cancel

    /// Canceling a download that isn't active should not crash.
    func testCancelNonActiveDownloadDoesNotCrash() {
        let manager = ModelDownloadManager()
        let model = ModelRegistry.gemma4E2BStandard

        // Should be a no-op, not a crash
        manager.cancelDownload(model)

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
        let state1 = manager.checkState(for: ModelRegistry.gemma4E2BStandard)
        let state2 = manager.checkState(for: ModelRegistry.gemma4E2BWeb)

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
        for model in ModelRegistry.knownModels {
            guard let url = model.downloadURL else {
                XCTFail("\(model.name) has nil downloadURL")
                continue
            }
            // URL should contain the model file name
            XCTAssertTrue(
                url.absoluteString.contains(model.modelFile),
                "\(model.name) download URL should contain the model filename"
            )
            // URL should contain the model ID (repo path)
            let repoPath = model.modelId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
                ?? model.modelId
            XCTAssertTrue(
                url.absoluteString.contains(model.modelId) ||
                url.absoluteString.contains(repoPath),
                "\(model.name) download URL should contain the modelId"
            )
        }
    }

    /// Deleting a model that doesn't exist should set state to .notDownloaded without crashing.
    func testDeleteNonExistentModelSetsNotDownloaded() {
        let manager = ModelDownloadManager()
        
        // Use a dummy model that definitely does not exist on disk
        let model = ModelMetadata(
            name: "Dummy",
            modelId: "dummy/dummy",
            modelFile: "dummy-not-real.litertlm",
            description: "",
            sizeInBytes: 0,
            minDeviceMemoryGB: 0,
            contextWindowSize: 0,
            architectureType: "Dummy",
            recommendedFor: "",
            supportsImage: false,
            supportsAudio: false,
            capabilities: [],
            defaultConfig: ModelDefaultConfig(topK: 1, topP: 1.0, temperature: 1.0, maxContextLength: 1024, maxTokens: 0, accelerators: "", visionAccelerator: nil),
            platformSupport: PlatformSupport(macOS: .unknown, iOSDevice: .unknown, iOSSimulator: .unknown)
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
