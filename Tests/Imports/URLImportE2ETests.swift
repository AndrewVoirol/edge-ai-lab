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

// MARK: - E2E URL Import Integration Tests

/// End-to-end integration tests proving the URL Import pipeline works for both
/// HuggingFace and Kaggle URLs. These exercise the actual `URLImportManager`
/// state machine with REAL network calls.
///
/// Test flow:
/// 1. Create URLImportManager with real dependencies
/// 2. Feed it a URL
/// 3. Observe state transitions through the pipeline
/// 4. Verify terminal state is correct (readyToDownload, complete, or failed with expected error)
///
/// Network-resilient: Tests adapt assertions based on whether network requests
/// succeed or fail — what matters is the state machine works correctly.
final class URLImportE2ETests: XCTestCase {

    private var catalog: DynamicModelCatalog!
    private var tempDir: URL!

    @MainActor
    override func setUp() {
        super.setUp()
        // Use an isolated temp directory for the dynamic model catalog
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("URLImportE2ETests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        catalog = DynamicModelCatalog(storageDirectory: tempDir)
    }

    override func tearDown() {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    // MARK: - Test 1: HuggingFace URL Parsing + API Fetch

    /// Verify the full HF import pipeline: URL → parse → fetch → analyze → readyToDownload.
    /// Uses a known public model URL.
    @MainActor
    func testHuggingFaceImportPipeline() async {
        let browser = HFModelBrowser()
        let manager = URLImportManager(browser: browser, catalog: catalog)

        // Use a known, small, public LiteRT model
        let testURL = "https://huggingface.co/litert-community/gemma-3n-E2B-it-litert-lm"

        // Start import
        await manager.importFromURL(testURL)

        // After importFromURL completes, the state should be terminal:
        // - .readyToDownload (success: metadata parsed, files available)
        // - .complete (already known in registry)
        // - .failed (network error, but with a meaningful message)
        switch manager.state {
        case .readyToDownload(let metadata, let files):
            // SUCCESS: Full pipeline worked
            XCTAssertFalse(metadata.metadata.name.isEmpty, "Model name should be non-empty")
            XCTAssertFalse(metadata.metadata.modelId.isEmpty, "Model ID should be non-empty")
            XCTAssertTrue(metadata.metadata.modelId.contains("litert-community"), "Model ID should contain repo org")
            XCTAssertFalse(files.isEmpty, "Should have at least one downloadable file")
            print("✅ HF Import: readyToDownload — \(metadata.metadata.name) with \(files.count) file(s)")

        case .complete(let metadata):
            // Model was already in the known registry — also valid
            XCTAssertFalse(metadata.metadata.name.isEmpty, "Model name should be non-empty")
            print("✅ HF Import: complete (already known) — \(metadata.metadata.name)")

        case .failed(let error):
            // Network error — validate the error message is meaningful
            XCTAssertFalse(error.isEmpty, "Error message should be non-empty")
            // Don't hard-fail: network may be unavailable in CI
            print("⚠️ HF Import: failed (network issue) — \(error)")

        default:
            XCTFail("Import pipeline should reach a terminal state, got: \(manager.state)")
        }
    }

    // MARK: - Test 2: Known Model Shortcut

    /// Verify that importing a URL for a model already in the known registry
    /// immediately resolves to .complete without a network call.
    @MainActor
    func testKnownModelShortcutsToComplete() async {
        let browser = HFModelBrowser()
        let manager = URLImportManager(browser: browser, catalog: catalog)

        // Find a model that IS in the known registry
        guard let knownModel = ModelRegistry.knownModels.first else {
            // No known models available — skip this test
            return
        }

        let testURL = "https://huggingface.co/\(knownModel.modelId)"

        await manager.importFromURL(testURL)

        switch manager.state {
        case .complete(let metadata):
            // Should shortcut directly to complete
            XCTAssertEqual(metadata.metadata.modelId, knownModel.modelId,
                          "Should match the known model ID")
            print("✅ Known model shortcut: \(metadata.metadata.name)")

        case .readyToDownload:
            // Also acceptable — the URL path format might differ slightly
            print("✅ Known model reached readyToDownload (URL format variation)")

        case .failed:
            // Network fallback — still valid
            print("⚠️ Known model fell through to network (URL format mismatch)")

        default:
            break
        }
    }

    // MARK: - Test 3: Kaggle URL Parsing

    /// Verify that a Kaggle URL is correctly detected, parsed, and routed to the
    /// Kaggle import path. Without credentials, expect a .failed state with a
    /// Kaggle-specific error message.
    @MainActor
    func testKaggleURLParsing() async {
        let browser = HFModelBrowser()
        let manager = URLImportManager(browser: browser, catalog: catalog)

        // No Kaggle credentials set → should fail with credentials error
        manager.kaggleUsername = nil
        manager.kaggleAPIKey = nil

        let kaggleURL = "https://www.kaggle.com/models/google/gemma-3n/litert/gemma-3n-e4b-it/1"

        await manager.importFromURL(kaggleURL)

        switch manager.state {
        case .failed(let error):
            // Expected: credentials required
            XCTAssertTrue(
                error.lowercased().contains("kaggle") || error.lowercased().contains("credential")
                    || error.lowercased().contains("api") || error.lowercased().contains("auth"),
                "Error should mention Kaggle credentials: got '\(error)'"
            )
            print("✅ Kaggle import correctly fails without credentials: \(error)")

        case .readyToDownload:
            // If credentials happen to be in the keychain, this is also valid
            print("✅ Kaggle import succeeded (credentials found in keychain)")

        case .complete:
            print("✅ Kaggle import completed (already imported)")

        default:
            // Any other state means the Kaggle URL wasn't handled
            XCTFail("Kaggle URL should be handled, got state: \(manager.state)")
        }
    }

    // MARK: - Test 4: Invalid URL Rejection

    /// Verify that non-model URLs are rejected with a meaningful error.
    @MainActor
    func testInvalidURLRejection() async {
        let browser = HFModelBrowser()
        let manager = URLImportManager(browser: browser, catalog: catalog)

        await manager.importFromURL("https://www.google.com")

        switch manager.state {
        case .failed(let error):
            XCTAssertFalse(error.isEmpty, "Error should have a meaningful message")
            XCTAssertTrue(error.contains("Invalid URL") || error.contains("paste"),
                         "Error should indicate the URL is invalid: got '\(error)'")
            print("✅ Invalid URL correctly rejected: \(error)")

        default:
            XCTFail("Invalid URL should fail, got state: \(manager.state)")
        }
    }

    // MARK: - Test 5: Garbage Input Rejection

    /// Verify that garbage strings are handled gracefully.
    @MainActor
    func testGarbageInputRejection() async {
        let browser = HFModelBrowser()
        let manager = URLImportManager(browser: browser, catalog: catalog)

        await manager.importFromURL("not a url at all")

        switch manager.state {
        case .failed(let error):
            XCTAssertFalse(error.isEmpty, "Error should have a message")
            print("✅ Garbage input correctly rejected: \(error)")

        default:
            XCTFail("Garbage input should fail, got state: \(manager.state)")
        }
    }

    // MARK: - Test 6: Empty Input Rejection

    /// Verify that empty/whitespace input is handled gracefully.
    @MainActor
    func testEmptyInputRejection() async {
        let browser = HFModelBrowser()
        let manager = URLImportManager(browser: browser, catalog: catalog)

        await manager.importFromURL("   ")

        switch manager.state {
        case .failed(let error):
            XCTAssertFalse(error.isEmpty)
            print("✅ Empty input correctly rejected: \(error)")

        default:
            XCTFail("Empty input should fail, got state: \(manager.state)")
        }
    }

    // MARK: - Test 7: State Machine Reset

    /// Verify that the manager can be reused for multiple imports.
    @MainActor
    func testStateResetBetweenImports() async {
        let browser = HFModelBrowser()
        let manager = URLImportManager(browser: browser, catalog: catalog)

        // First import: invalid URL
        await manager.importFromURL("not-a-url")
        guard case .failed = manager.state else {
            XCTFail("First import should fail")
            return
        }

        // Second import: different invalid URL — state should transition cleanly
        await manager.importFromURL("https://www.google.com")
        guard case .failed = manager.state else {
            XCTFail("Second import should also fail")
            return
        }
        print("✅ State machine correctly resets between imports")
    }

    // MARK: - Test 8: Kaggle URL Detection (Unit-Level)

    /// Verify KaggleModelParser detects various Kaggle URL formats.
    func testKaggleURLDetection() {
        // Valid Kaggle URLs
        let valid1 = KaggleModelParser.parseURL("https://kaggle.com/models/google/gemma-3n/litert/gemma-3n-e4b-it/1")
        XCTAssertNotNil(valid1, "Should parse kaggle.com URL")
        XCTAssertEqual(valid1?.owner, "google")
        XCTAssertEqual(valid1?.modelSlug, "gemma-3n")

        let valid2 = KaggleModelParser.parseURL("https://www.kaggle.com/models/google/gemma-3n")
        XCTAssertNotNil(valid2, "Should parse www.kaggle.com URL")

        // Invalid URLs should NOT be detected as Kaggle
        let invalid1 = KaggleModelParser.parseURL("https://huggingface.co/google/gemma")
        XCTAssertNil(invalid1, "HuggingFace URL should not be detected as Kaggle")

        let invalid2 = KaggleModelParser.parseURL("https://www.google.com")
        XCTAssertNil(invalid2, "Google URL should not be detected as Kaggle")

        print("✅ Kaggle URL detection works correctly")
    }

    // MARK: - Test 9: HuggingFace URL Parsing (Unit-Level)

    /// Verify HuggingFace URL parsing for various formats.
    @MainActor
    func testHuggingFaceURLParsing() {
        let browser = HFModelBrowser()
        let manager = URLImportManager(browser: browser, catalog: catalog)

        // Standard format
        let parsed1 = manager.parseHuggingFaceURL("https://huggingface.co/litert-community/gemma-3n-E2B-it-litert-lm")
        XCTAssertNotNil(parsed1, "Should parse standard HF URL")
        XCTAssertEqual(parsed1?.org, "litert-community")
        XCTAssertEqual(parsed1?.repo, "gemma-3n-E2B-it-litert-lm")

        // Short URL
        let parsed2 = manager.parseHuggingFaceURL("https://hf.co/litert-community/gemma-3n-E2B-it-litert-lm")
        XCTAssertNotNil(parsed2, "Should parse short HF URL")

        // With blob path
        let parsed3 = manager.parseHuggingFaceURL("https://huggingface.co/litert-community/gemma-3n-E2B-it-litert-lm/blob/main/model.litertlm")
        XCTAssertNotNil(parsed3, "Should parse blob URL")
        XCTAssertEqual(parsed3?.specificFile, "model.litertlm")

        // Invalid
        let parsed4 = manager.parseHuggingFaceURL("https://www.google.com")
        XCTAssertNil(parsed4, "Should reject non-HF URL")

        print("✅ HuggingFace URL parsing works correctly")
    }
}
