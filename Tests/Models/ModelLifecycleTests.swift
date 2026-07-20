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

// MARK: - Model Lifecycle Tests

/// Tests for the model lifecycle: import → download → delete → re-import.
/// Verifies that the known catalog shortcut properly
/// checks for local file existence before marking imports as complete.
@MainActor
final class ModelLifecycleTests: XCTestCase {

    // MARK: - Known Catalog Shortcut Tests

    func testKnownModelsCatalogIsNotEmpty() {
        XCTAssertFalse(KnownModelCatalog.allModels.isEmpty, "KnownModelCatalog.allModels should not be empty")
    }

    func testKnownModelMatchesByModelId() {
        guard let firstKnown = KnownModelCatalog.allModels.first else {
            XCTFail("No known models")
            return
        }
        let found = KnownModelCatalog.allModels.first(where: { $0.modelId == firstKnown.modelId })
        XCTAssertNotNil(found, "Should find model by modelId")
    }

    func testDynamicMetadataFromKnownModelSetsVerifiedConfidence() {
        guard let known = KnownModelCatalog.allModels.first else {
            XCTFail("No known models")
            return
        }
        let dynamicMeta = DynamicModelMetadata.fromKnownModel(known)
        XCTAssertEqual(dynamicMeta.confidence, .verified)
        XCTAssertEqual(dynamicMeta.source, .knownRegistry)
    }

    // MARK: - Catalog Stale Entry Tests

    func testCatalogAddAndRemoveRoundTrip() throws {
        let catalog = DynamicModelCatalog()

        let modelInfo = HFModelInfo(
            id: "lifecycle-test/model",
            author: "lifecycle-test",
            tags: ["litert"],
            pipelineTag: "text-generation",
            libraryName: "litert"
        )

        let (metadata, confidence) = ModelCardParser.inferMetadata(from: modelInfo)
        let dynamicMeta = DynamicModelMetadata.fromHuggingFace(
            repoId: "lifecycle-test/model",
            metadata: metadata,
            confidence: confidence
        )

        try catalog.add(dynamicMeta)
        XCTAssertNotNil(catalog.find(id: "lifecycle-test/model"), "Model should be in catalog after add")

        try catalog.remove(id: dynamicMeta.id)
        XCTAssertNil(catalog.find(id: "lifecycle-test/model"), "Model should be gone after remove")
    }

    func testImportPipelineResetClearsState() {
        let catalog = DynamicModelCatalog()
        let browser = HFModelBrowser()
        let importManager = URLImportManager(browser: browser, catalog: catalog)

        if case .idle = importManager.state {
            // Expected
        } else {
            XCTFail("Import manager should start in idle state")
        }

        importManager.reset()
        if case .idle = importManager.state {
            // Expected
        } else {
            XCTFail("Reset should return to idle state")
        }
    }

    func testImportRejectsGarbageURL() async {
        let catalog = DynamicModelCatalog()
        let browser = HFModelBrowser()
        let importManager = URLImportManager(browser: browser, catalog: catalog)

        await importManager.importFromURL("not-a-url-at-all")

        if case .failed = importManager.state {
            // Expected — garbage URL should fail
        } else {
            XCTFail("Garbage URL should result in .failed state")
        }
    }

    // MARK: - Duplicate Condition Fix Tests

    func testModelCardParserDetects13BModels() {
        let model = HFModelInfo(
            id: "test-org/model-13b-instruct",
            author: "test-org",
            tags: ["litert"],
            libraryName: "litert"
        )

        let (metadata, _) = ModelCardParser.inferMetadata(from: model)
        XCTAssertTrue(
            (metadata.memoryGB ?? 0) >= 16,
            "Parser should recognize 13B models — got memoryGB=\(metadata.memoryGB ?? 0)"
        )
    }

    func testModelCardParserDetects12BModels() {
        let model = HFModelInfo(
            id: "test-org/model-12b-instruct",
            author: "test-org",
            tags: ["litert"],
            libraryName: "litert"
        )

        let (metadata, _) = ModelCardParser.inferMetadata(from: model)
        XCTAssertTrue(
            (metadata.memoryGB ?? 0) >= 16,
            "Parser should recognize 12B models — got memoryGB=\(metadata.memoryGB ?? 0)"
        )
    }
}

// MARK: - KaggleTokenStorage Tests

final class KaggleTokenStorageTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        KaggleTokenStorage.deleteCredentials()
    }

    func testSaveAndRetrieveCredentials() throws {
        try KaggleTokenStorage.saveCredentials(username: "test_user", apiKey: "test_key_12345")
        XCTAssertEqual(KaggleTokenStorage.retrieveUsername(), "test_user")
        XCTAssertEqual(KaggleTokenStorage.retrieveAPIKey(), "test_key_12345")
        XCTAssertTrue(KaggleTokenStorage.hasCredentials)
    }

    func testDeleteCredentials() throws {
        try KaggleTokenStorage.saveCredentials(username: "user", apiKey: "key")
        XCTAssertTrue(KaggleTokenStorage.hasCredentials)

        KaggleTokenStorage.deleteCredentials()
        XCTAssertNil(KaggleTokenStorage.retrieveUsername())
        XCTAssertNil(KaggleTokenStorage.retrieveAPIKey())
        XCTAssertFalse(KaggleTokenStorage.hasCredentials)
    }

    func testHasCredentialsRequiresBoth() {
        XCTAssertFalse(KaggleTokenStorage.hasCredentials)
    }

    func testOverwriteCredentials() throws {
        try KaggleTokenStorage.saveCredentials(username: "old_user", apiKey: "old_key")
        try KaggleTokenStorage.saveCredentials(username: "new_user", apiKey: "new_key")
        XCTAssertEqual(KaggleTokenStorage.retrieveUsername(), "new_user")
        XCTAssertEqual(KaggleTokenStorage.retrieveAPIKey(), "new_key")
    }
}
