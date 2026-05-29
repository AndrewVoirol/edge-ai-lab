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
@testable import GemmaEdgeGallery_iOS
#elseif os(macOS)
@testable import GemmaEdgeGallery_macOS
#endif

// MARK: - ModelRegistry Tests

final class ModelRegistryTests: XCTestCase {

    // MARK: - Known Models Count

    /// Validates that the registry contains the expected number of models.
    /// Update this count when adding new models to ModelRegistry.
    func testKnownModelCount() {
        XCTAssertEqual(ModelRegistry.knownModels.count, 5)
    }

    // MARK: - Uniqueness (Issue #16)

    /// All modelFile values must be unique — they serve as SwiftUI Identifiable IDs.
    /// Duplicate filenames would cause SwiftUI list rendering bugs (Issue #16).
    func testAllModelFilenamesAreUnique() {
        let filenames = ModelRegistry.knownModels.map(\.modelFile)
        let uniqueFilenames = Set(filenames)
        XCTAssertEqual(
            filenames.count, uniqueFilenames.count,
            "Duplicate modelFile found: \(filenames.filter { name in filenames.filter { $0 == name }.count > 1 })"
        )
    }

    // MARK: - URL Validity

    /// Every model must have a syntactically valid download URL.
    func testAllModelURLsAreValid() {
        for model in ModelRegistry.knownModels {
            let url = model.downloadURL
            XCTAssertNotNil(url, "\(model.name) has no valid downloadURL")
            if let url = url {
                XCTAssertTrue(
                    url.scheme == "https",
                    "\(model.name) downloadURL should use HTTPS, got: \(url.scheme ?? "nil")"
                )
                XCTAssertTrue(
                    url.host?.contains("huggingface.co") == true,
                    "\(model.name) downloadURL host should be huggingface.co"
                )
            }
        }
    }

    // MARK: - Size Bounds

    /// File sizes should be reasonable: between 100 MB and 20 GB.
    func testAllModelSizesAreReasonable() {
        let minSize: Int64 = 100_000_000       // 100 MB
        let maxSize: Int64 = 20_000_000_000    // 20 GB

        for model in ModelRegistry.knownModels {
            XCTAssertGreaterThan(
                model.sizeInBytes, minSize,
                "\(model.name) size \(model.sizeInBytes) is below 100 MB minimum"
            )
            XCTAssertLessThan(
                model.sizeInBytes, maxSize,
                "\(model.name) size \(model.sizeInBytes) exceeds 20 GB maximum"
            )
        }
    }

    // MARK: - Platform Support

    /// No model should have .unknown for ALL three platforms — at least one must be known.
    func testPlatformSupportMatrixCompleteness() {
        for model in ModelRegistry.knownModels {
            let support = model.platformSupport
            let allUnknown = (support.macOS == .unknown
                && support.iOSDevice == .unknown
                && support.iOSSimulator == .unknown)
            XCTAssertFalse(
                allUnknown,
                "\(model.name) has .unknown for ALL platforms — at least one must be specified"
            )
        }
    }

    // MARK: - Lookup

    /// Looking up a filename that doesn't exist in the registry should return nil.
    func testLookupUnknownFilenameReturnsNil() {
        XCTAssertNil(ModelRegistry.lookup(filename: "nonexistent-model.litertlm"))
        XCTAssertNil(ModelRegistry.lookup(filename: ""))
        XCTAssertNil(ModelRegistry.lookup(filename: "gemma-4-E2B-it"))  // Missing extension
    }

    // MARK: - Required Fields

    /// Every model must have a non-empty name, modelId, modelFile, and description.
    func testAllModelsHaveRequiredFields() {
        for model in ModelRegistry.knownModels {
            XCTAssertFalse(model.name.isEmpty, "Model has empty name")
            XCTAssertFalse(model.modelId.isEmpty, "Model \(model.name) has empty modelId")
            XCTAssertFalse(model.modelFile.isEmpty, "Model \(model.name) has empty modelFile")
            XCTAssertFalse(model.description.isEmpty, "Model \(model.name) has empty description")
            XCTAssertGreaterThan(
                model.minDeviceMemoryGB, 0,
                "Model \(model.name) has non-positive minDeviceMemoryGB"
            )
        }
    }

    // MARK: - E2B Variants

    /// Standard and Web E2B variants share the same modelId but must have different modelFile values.
    func testE2BVariantsShareModelIdButDifferentFile() {
        let standard = ModelRegistry.gemma4E2BStandard
        let web = ModelRegistry.gemma4E2BWeb

        // Same repo
        XCTAssertEqual(standard.modelId, web.modelId)

        // Different filenames (essential for disambiguation)
        XCTAssertNotEqual(standard.modelFile, web.modelFile)

        // Both should be named differently for UI clarity
        XCTAssertNotEqual(standard.name, web.name)
    }

    /// Standard and Web E4B variants should follow the same pattern.
    func testE4BVariantsShareModelIdButDifferentFile() {
        let standard = ModelRegistry.gemma4E4BStandard
        let web = ModelRegistry.gemma4E4BWeb

        XCTAssertEqual(standard.modelId, web.modelId)
        XCTAssertNotEqual(standard.modelFile, web.modelFile)
        XCTAssertNotEqual(standard.name, web.name)
    }

    // MARK: - Multimodal + Platform Support

    /// All models claiming image support should also have at least one non-unknown platform.
    func testMultimodalModelsHavePlatformSupport() {
        let multimodalModels = ModelRegistry.knownModels.filter { $0.supportsImage }

        XCTAssertFalse(multimodalModels.isEmpty, "Expected at least one multimodal model")

        for model in multimodalModels {
            let support = model.platformSupport
            let hasKnownPlatform = (support.macOS != .unknown
                || support.iOSDevice != .unknown
                || support.iOSSimulator != .unknown)
            XCTAssertTrue(
                hasKnownPlatform,
                "\(model.name) supports image but has no known platform support"
            )
        }
    }

    // MARK: - Auth Requirement

    /// litert-community models should NOT require auth; google/ models should.
    func testRequiresAuthMatchesModelIdPrefix() {
        for model in ModelRegistry.knownModels {
            if model.modelId.hasPrefix("litert-community/") {
                XCTAssertFalse(
                    model.requiresAuth,
                    "\(model.name) is litert-community but requiresAuth is true"
                )
            } else if model.modelId.hasPrefix("google/") {
                XCTAssertTrue(
                    model.requiresAuth,
                    "\(model.name) is google/ but requiresAuth is false"
                )
            }
        }
    }

    // MARK: - All Models Have .litertlm Extension

    /// Every model file should have the .litertlm extension.
    func testAllModelFilesHaveLitertlmExtension() {
        for model in ModelRegistry.knownModels {
            XCTAssertTrue(
                model.modelFile.hasSuffix(".litertlm"),
                "\(model.name) modelFile doesn't end with .litertlm: \(model.modelFile)"
            )
        }
    }
}
