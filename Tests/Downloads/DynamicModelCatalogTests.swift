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
import Foundation

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

final class DynamicModelCatalogTests: XCTestCase {

  private var tempDir: URL!
  private var catalog: DynamicModelCatalog!

  @MainActor
  override func setUp() {
    super.setUp()
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("DynamicModelCatalogTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    catalog = DynamicModelCatalog(storageDirectory: tempDir)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: tempDir)
    super.tearDown()
  }

  // MARK: - Helpers

  private func makeTestDynamicMetadata(
    id: String = "test-org/test-model"
  ) -> DynamicModelMetadata {
    let profile = ModelCapabilityProfile(
      id: "test-model-\(UUID().uuidString).litertlm",
      displayName: "Test Model",
      repoId: id,
      runtimeType: .litertlm,
      supportsVision: SourcedValue(false, source: .heuristic),
      supportsAudio: SourcedValue(false, source: .heuristic),
      supportsThinking: SourcedValue(true, source: .heuristic),
      supportsToolCalling: nil,
      supportsMTP: nil,
      supportsConstrainedDecoding: nil,
      architecture: ArchitectureInfo(
        architectureClass: nil, modelType: nil, isMoE: true,
        hiddenSize: nil, numLayers: nil, numAttentionHeads: nil,
        numKeyValueHeads: nil, vocabSize: nil, headDim: nil,
        maxImageResolution: nil, dtype: nil,
        quantizationBits: nil, quantizationMethod: nil
      ),
      contextWindow: SourcedValue(128_000, source: .heuristic),
      fileSizeBytes: 1_000_000_000,
      estimatedMemoryGB: SourcedValue(8, source: .heuristic),
      totalParameters: nil,
      parameterLabel: nil,
      confidence: .medium,
      source: .huggingFaceInferred,
      lastUpdated: Date(),
      repoSha: nil,
      license: nil, licenseLink: nil, baseModelId: nil,
      downloads: nil, likes: nil, downloadsAllTime: nil,
      supportedLanguages: [],
      tags: ["llm_thinking"],
      defaultConfig: ModelDefaultConfig(
        topK: 64, topP: 0.95, temperature: 1.0,
        maxContextLength: 32_000, maxTokens: 4_000,
        accelerators: "gpu,cpu", visionAccelerator: nil
      ),
      platformSupport: PlatformSupport(
        macOS: .gpuAndCpu, iOSDevice: .gpuAndCpu, iOSSimulator: .cpuOnly
      ),
      modelDescription: "A test model",
      recommendedFor: "Testing",
      modelFile: "test-model-\(UUID().uuidString).litertlm",
      modelId: id
    )
    return DynamicModelMetadata.fromHuggingFace(
      repoId: id, metadata: profile, confidence: .medium
    )
  }

  // MARK: - CRUD

  @MainActor
  func testAddModel() throws {
    let entry = makeTestDynamicMetadata()
    try catalog.add(entry)
    XCTAssertEqual(catalog.entries.count, 1)
  }

  @MainActor
  func testAddDuplicate_throws() throws {
    let entry = makeTestDynamicMetadata()
    try catalog.add(entry)
    XCTAssertThrowsError(try catalog.add(entry)) { error in
      guard let catalogError = error as? DynamicModelCatalogError else {
        XCTFail("Expected DynamicModelCatalogError, got \(error)")
        return
      }
      if case .duplicateEntry = catalogError {
        // Expected
      } else {
        XCTFail("Expected .duplicateEntry, got \(catalogError)")
      }
    }
  }

  @MainActor
  func testRemoveModel() throws {
    let entry = makeTestDynamicMetadata()
    try catalog.add(entry)
    XCTAssertEqual(catalog.entries.count, 1)
    try catalog.remove(id: entry.id)
    XCTAssertEqual(catalog.entries.count, 0)
  }

  @MainActor
  func testRemoveNonexistent_throws() {
    XCTAssertThrowsError(try catalog.remove(id: UUID().uuidString)) { error in
      guard let catalogError = error as? DynamicModelCatalogError else {
        XCTFail("Expected DynamicModelCatalogError, got \(error)")
        return
      }
      if case .notFound = catalogError {
        // Expected
      } else {
        XCTFail("Expected .notFound, got \(catalogError)")
      }
    }
  }

  @MainActor
  func testUpdateModel() throws {
    var entry = makeTestDynamicMetadata()
    try catalog.add(entry)
    entry.userNotes = "Updated notes"
    try catalog.update(entry)
    let updated = catalog.entries.first
    XCTAssertEqual(updated?.userNotes, "Updated notes")
  }

  @MainActor
  func testUpdateNonexistent_throws() {
    let entry = makeTestDynamicMetadata(id: "nonexistent/model")
    XCTAssertThrowsError(try catalog.update(entry)) { error in
      guard let catalogError = error as? DynamicModelCatalogError else {
        XCTFail("Expected DynamicModelCatalogError, got \(error)")
        return
      }
      if case .notFound = catalogError {
        // Expected
      } else {
        XCTFail("Expected .notFound, got \(catalogError)")
      }
    }
  }

  // MARK: - Merge

  @MainActor
  func testAllModels_includesKnownRegistry() {
    let allModels = catalog.allModels()
    let knownModels = KnownModelCatalog.allModels
    for known in knownModels {
      let found = allModels.contains { $0.metadata.modelFile == known.modelFile }
      XCTAssertTrue(found, "Expected allModels to include known model: \(known.displayName)")
    }
  }

  @MainActor
  func testAllModels_includesImported() throws {
    let entry = makeTestDynamicMetadata(id: "imported/unique-model")
    try catalog.add(entry)
    let allModels = catalog.allModels()
    XCTAssertTrue(
      allModels.count > KnownModelCatalog.allModels.count,
      "Expected allModels count (\(allModels.count)) > knownModels count (\(KnownModelCatalog.allModels.count))"
    )
  }

  @MainActor
  func testAllModels_deduplicates() throws {
    guard let knownModel = KnownModelCatalog.allModels.first else {
      XCTFail("KnownModelCatalog.allModels is empty")
      return
    }
    let duplicateProfile = ModelCapabilityProfile(
      id: "dup-model",
      displayName: knownModel.displayName,
      repoId: "dup/model",
      runtimeType: knownModel.runtimeType,
      supportsVision: knownModel.supportsVision,
      supportsAudio: knownModel.supportsAudio,
      supportsThinking: knownModel.supportsThinking,
      supportsToolCalling: knownModel.supportsToolCalling,
      supportsMTP: knownModel.supportsMTP,
      supportsConstrainedDecoding: knownModel.supportsConstrainedDecoding,
      architecture: knownModel.architecture,
      contextWindow: knownModel.contextWindow,
      fileSizeBytes: knownModel.fileSizeBytes,
      estimatedMemoryGB: knownModel.estimatedMemoryGB,
      totalParameters: knownModel.totalParameters,
      parameterLabel: knownModel.parameterLabel,
      confidence: knownModel.confidence,
      source: knownModel.source,
      lastUpdated: Date(),
      repoSha: nil,
      license: nil, licenseLink: nil, baseModelId: nil,
      downloads: nil, likes: nil, downloadsAllTime: nil,
      supportedLanguages: [],
      tags: [],
      defaultConfig: knownModel.defaultConfig,
      platformSupport: knownModel.platformSupport,
      modelDescription: "Duplicate",
      recommendedFor: knownModel.recommendedFor,
      modelFile: knownModel.modelFile,
      modelId: "dup/model"
    )
    let entry = DynamicModelMetadata.fromHuggingFace(
      repoId: "dup/model", metadata: duplicateProfile, confidence: .medium
    )
    try catalog.add(entry)
    let allModels = catalog.allModels()
    let matchingFiles = allModels.filter { $0.metadata.modelFile == knownModel.modelFile }
    XCTAssertEqual(
      matchingFiles.count, 1,
      "Expected no duplicates for modelFile '\(knownModel.modelFile ?? "")', found \(matchingFiles.count)"
    )
  }

  // MARK: - Search

  @MainActor
  func testSearch_byName() throws {
    let entry = makeTestDynamicMetadata()
    try catalog.add(entry)
    let results = catalog.search(query: "test")
    XCTAssertFalse(results.isEmpty, "Expected search for 'test' to find the model")
  }

  @MainActor
  func testSearch_caseInsensitive() throws {
    let entry = makeTestDynamicMetadata()
    try catalog.add(entry)
    let results = catalog.search(query: "TEST")
    XCTAssertFalse(results.isEmpty, "Expected case-insensitive search for 'TEST' to find the model")
  }

  @MainActor
  func testSearch_noMatch() throws {
    let entry = makeTestDynamicMetadata()
    try catalog.add(entry)
    let results = catalog.search(query: "zzzzz")
    XCTAssertTrue(results.isEmpty, "Expected no results for 'zzzzz'")
  }

  // MARK: - Filter

  @MainActor
  func testFilterByRuntime() throws {
    let entry = makeTestDynamicMetadata()
    try catalog.add(entry)
    let filtered = catalog.filter(by: .litertlm)
    for model in filtered {
      XCTAssertTrue(
        model.metadata.runtimeType == .litertlm,
        "Expected all filtered models to be .litertlm, got \(model.metadata.runtimeType)"
      )
    }
  }

  @MainActor
  func testFilterByCapability_vision() {
    let filtered = catalog.filter(by: "vision")
    for model in filtered {
      XCTAssertTrue(
        model.metadata.hasVision,
        "Expected all vision-filtered models to have hasVision == true"
      )
    }
  }

  // MARK: - Persistence

  @MainActor
  func testPersistenceAndReload() throws {
    let entry = makeTestDynamicMetadata()
    try catalog.add(entry)
    XCTAssertEqual(catalog.entries.count, 1)

    let reloadedCatalog = DynamicModelCatalog(storageDirectory: tempDir)
    XCTAssertEqual(
      reloadedCatalog.entries.count, 1,
      "Expected reloaded catalog to have 1 entry, got \(reloadedCatalog.entries.count)"
    )
  }
}
