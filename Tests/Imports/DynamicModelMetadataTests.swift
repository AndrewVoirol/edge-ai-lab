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
import XCTest

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

final class DynamicModelMetadataTests: XCTestCase {

  // MARK: - Helpers

  private func makeTestModelMetadata(
    modelFile: String = "test-model.litertlm"
  ) -> ModelMetadata {
    ModelMetadata(
      name: "Test Model",
      modelId: "test-org/test-model",
      modelFile: modelFile,
      description: "A test model",
      sizeInBytes: 1_000_000,
      minDeviceMemoryGB: 4,
      contextWindowSize: 128_000,
      architectureType: "Test Arch",
      recommendedFor: "Testing",
      supportsImage: false,
      supportsAudio: false,
      capabilities: ["llm_thinking"],
      defaultConfig: ModelDefaultConfig(
        topK: 64,
        topP: 0.95,
        temperature: 1.0,
        maxContextLength: 128_000,
        maxTokens: 2048,
        accelerators: "gpu,cpu",
        visionAccelerator: nil
      ),
      platformSupport: PlatformSupport(
        macOS: .gpuAndCpu,
        iOSDevice: .gpuAndCpu,
        iOSSimulator: .cpuOnly
      ),
      runtimeType: .litertlm
    )
  }

  // MARK: - MetadataSource — Raw Values

  func testMetadataSource_rawValues() {
    XCTAssertEqual(MetadataSource.knownRegistry.rawValue, "knownRegistry")
    XCTAssertEqual(MetadataSource.huggingFaceInferred.rawValue, "huggingFaceInferred")
    XCTAssertEqual(MetadataSource.userProvided.rawValue, "userProvided")
  }

  func testMetadataSource_initFromRawValue() {
    XCTAssertEqual(MetadataSource(rawValue: "knownRegistry"), .knownRegistry)
    XCTAssertEqual(MetadataSource(rawValue: "huggingFaceInferred"), .huggingFaceInferred)
    XCTAssertEqual(MetadataSource(rawValue: "userProvided"), .userProvided)
    XCTAssertNil(MetadataSource(rawValue: "invalid"))
  }

  // MARK: - MetadataSource — Codable

  func testMetadataSource_codableRoundTrip() throws {
    let allCases: [MetadataSource] = [
      .knownRegistry, .huggingFaceInferred, .userProvided,
    ]
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    for source in allCases {
      let data = try encoder.encode(source)
      let decoded = try decoder.decode(MetadataSource.self, from: data)
      XCTAssertEqual(decoded, source, "Round-trip failed for \(source)")
    }
  }

  // MARK: - MetadataConfidence — Symbol Name

  func testMetadataConfidence_symbolName() {
    XCTAssertEqual(MetadataConfidence.verified.symbolName, "checkmark.seal.fill")
    XCTAssertEqual(MetadataConfidence.high.symbolName, "checkmark.circle.fill")
    XCTAssertEqual(MetadataConfidence.medium.symbolName, "questionmark.circle.fill")
    XCTAssertEqual(MetadataConfidence.low.symbolName, "exclamationmark.triangle.fill")
  }

  // MARK: - MetadataConfidence — Label

  func testMetadataConfidence_label() {
    XCTAssertEqual(MetadataConfidence.verified.label, "Verified Compatible")
    XCTAssertEqual(MetadataConfidence.high.label, "Likely Compatible")
    XCTAssertEqual(MetadataConfidence.medium.label, "Review Recommended")
    XCTAssertEqual(MetadataConfidence.low.label, "Compatibility Unknown")
  }

  // MARK: - MetadataConfidence — Comparable

  func testMetadataConfidence_verifiedGreaterThanHigh() {
    XCTAssertGreaterThan(MetadataConfidence.verified, .high)
  }

  func testMetadataConfidence_verifiedGreaterThanMedium() {
    XCTAssertGreaterThan(MetadataConfidence.verified, .medium)
  }

  func testMetadataConfidence_verifiedGreaterThanLow() {
    XCTAssertGreaterThan(MetadataConfidence.verified, .low)
  }

  func testMetadataConfidence_highGreaterThanMedium() {
    XCTAssertGreaterThan(MetadataConfidence.high, .medium)
  }

  func testMetadataConfidence_highGreaterThanLow() {
    XCTAssertGreaterThan(MetadataConfidence.high, .low)
  }

  func testMetadataConfidence_mediumGreaterThanLow() {
    XCTAssertGreaterThan(MetadataConfidence.medium, .low)
  }

  // MARK: - MetadataConfidence — Codable

  func testMetadataConfidence_codableRoundTrip() throws {
    let allCases: [MetadataConfidence] = [.verified, .high, .medium, .low]
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    for confidence in allCases {
      let data = try encoder.encode(confidence)
      let decoded = try decoder.decode(MetadataConfidence.self, from: data)
      XCTAssertEqual(decoded, confidence, "Round-trip failed for \(confidence)")
    }
  }

  func testMetadataConfidence_rawValues() {
    XCTAssertEqual(MetadataConfidence.verified.rawValue, "verified")
    XCTAssertEqual(MetadataConfidence.high.rawValue, "high")
    XCTAssertEqual(MetadataConfidence.medium.rawValue, "medium")
    XCTAssertEqual(MetadataConfidence.low.rawValue, "low")
  }

  // MARK: - DynamicModelMetadata — fromKnownModel

  func testFromKnownModel_setsSourceToKnownRegistry() {
    let model = makeTestModelMetadata()
    let entry = DynamicModelMetadata.fromKnownModel(model)
    XCTAssertEqual(entry.source, .knownRegistry)
  }

  func testFromKnownModel_setsConfidenceToVerified() {
    let model = makeTestModelMetadata()
    let entry = DynamicModelMetadata.fromKnownModel(model)
    XCTAssertEqual(entry.confidence, .verified)
  }

  func testFromKnownModel_setsIdFromModelFile() {
    let model = makeTestModelMetadata(modelFile: "custom-model.litertlm")
    let entry = DynamicModelMetadata.fromKnownModel(model)
    XCTAssertEqual(entry.id, "custom-model.litertlm")
  }

  func testFromKnownModel_setsLastVerifiedAt() {
    let model = makeTestModelMetadata()
    let entry = DynamicModelMetadata.fromKnownModel(model)
    XCTAssertNotNil(entry.lastVerifiedAt)
    XCTAssertEqual(entry.lastVerifiedAt, Date.distantPast)
  }

  func testFromKnownModel_userNotesAreNil() {
    let model = makeTestModelMetadata()
    let entry = DynamicModelMetadata.fromKnownModel(model)
    XCTAssertNil(entry.userNotes)
  }

  // MARK: - DynamicModelMetadata — fromHuggingFace

  func testFromHuggingFace_setsSourceToHuggingFaceInferred() {
    let model = makeTestModelMetadata()
    let entry = DynamicModelMetadata.fromHuggingFace(
      repoId: "org/repo", metadata: model, confidence: .high
    )
    XCTAssertEqual(entry.source, .huggingFaceInferred)
  }

  func testFromHuggingFace_setsConfidenceFromParameter() {
    let model = makeTestModelMetadata()
    let entryHigh = DynamicModelMetadata.fromHuggingFace(
      repoId: "org/repo", metadata: model, confidence: .high
    )
    XCTAssertEqual(entryHigh.confidence, .high)

    let entryLow = DynamicModelMetadata.fromHuggingFace(
      repoId: "org/repo-low", metadata: model, confidence: .low
    )
    XCTAssertEqual(entryLow.confidence, .low)
  }

  func testFromHuggingFace_setsIdFromRepoId() {
    let model = makeTestModelMetadata()
    let entry = DynamicModelMetadata.fromHuggingFace(
      repoId: "litert-community/gemma-model", metadata: model, confidence: .medium
    )
    XCTAssertEqual(entry.id, "litert-community/gemma-model")
  }

  func testFromHuggingFace_lastVerifiedAtIsNil() {
    let model = makeTestModelMetadata()
    let entry = DynamicModelMetadata.fromHuggingFace(
      repoId: "org/repo", metadata: model, confidence: .high
    )
    XCTAssertNil(entry.lastVerifiedAt)
  }

  // MARK: - DynamicModelMetadata — Codable Round-Trip

  func testDynamicModelMetadata_codableRoundTrip_knownModel() throws {
    let model = makeTestModelMetadata()
    let entry = DynamicModelMetadata.fromKnownModel(model)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let data = try encoder.encode(entry)
    let decoded = try decoder.decode(DynamicModelMetadata.self, from: data)

    XCTAssertEqual(decoded.id, entry.id)
    XCTAssertEqual(decoded.source, entry.source)
    XCTAssertEqual(decoded.confidence, entry.confidence)
    XCTAssertEqual(decoded.metadata.name, entry.metadata.name)
    XCTAssertEqual(decoded.metadata.modelFile, entry.metadata.modelFile)
    XCTAssertEqual(decoded.metadata.modelId, entry.metadata.modelId)
    XCTAssertNil(decoded.userNotes)
  }

  func testDynamicModelMetadata_codableRoundTrip_huggingFace() throws {
    let model = makeTestModelMetadata()
    var entry = DynamicModelMetadata.fromHuggingFace(
      repoId: "org/hf-model", metadata: model, confidence: .high
    )
    entry.userNotes = "Imported for testing"

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let data = try encoder.encode(entry)
    let decoded = try decoder.decode(DynamicModelMetadata.self, from: data)

    XCTAssertEqual(decoded.id, "org/hf-model")
    XCTAssertEqual(decoded.source, .huggingFaceInferred)
    XCTAssertEqual(decoded.confidence, .high)
    XCTAssertEqual(decoded.userNotes, "Imported for testing")
    XCTAssertNil(decoded.lastVerifiedAt)
  }

  func testDynamicModelMetadata_codableRoundTrip_userProvided() throws {
    let model = makeTestModelMetadata()
    let entry = DynamicModelMetadata(
      id: "user-model",
      source: .userProvided,
      metadata: model,
      confidence: .medium,
      importedAt: Date(),
      lastVerifiedAt: nil,
      userNotes: nil
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let data = try encoder.encode(entry)
    let decoded = try decoder.decode(DynamicModelMetadata.self, from: data)

    XCTAssertEqual(decoded.id, "user-model")
    XCTAssertEqual(decoded.source, .userProvided)
    XCTAssertEqual(decoded.confidence, .medium)
  }

  // MARK: - DynamicModelMetadata — Metadata Preservation

  func testFromKnownModel_preservesMetadataFields() {
    let model = makeTestModelMetadata(modelFile: "preserve-test.litertlm")
    let entry = DynamicModelMetadata.fromKnownModel(model)

    XCTAssertEqual(entry.metadata.name, "Test Model")
    XCTAssertEqual(entry.metadata.modelId, "test-org/test-model")
    XCTAssertEqual(entry.metadata.modelFile, "preserve-test.litertlm")
    XCTAssertEqual(entry.metadata.sizeInBytes, 1_000_000)
    XCTAssertEqual(entry.metadata.contextWindowSize, 128_000)
    XCTAssertFalse(entry.metadata.supportsImage)
    XCTAssertFalse(entry.metadata.supportsAudio)
    XCTAssertEqual(entry.metadata.capabilities, ["llm_thinking"])
    XCTAssertEqual(entry.metadata.runtimeType, .litertlm)
  }
}
