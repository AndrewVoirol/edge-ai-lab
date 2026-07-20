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

final class ModelCardParserTests: XCTestCase {

  // MARK: - Runtime type inference

  @MainActor
  func testInferRuntimeType_litert() {
    let model = HFModelInfo(
      id: "org/model", author: "org", libraryName: "litert"
    )
    let (metadata, _) = ModelCardParser.inferMetadata(from: model)
    XCTAssertTrue(metadata.runtimeType == .litertlm)
  }

  @MainActor
  func testInferRuntimeType_mlx() {
    let model = HFModelInfo(
      id: "org/model", author: "org", libraryName: "mlx"
    )
    let (metadata, _) = ModelCardParser.inferMetadata(from: model)
    XCTAssertTrue(metadata.runtimeType == .mlx)
  }

  @MainActor
  func testInferRuntimeType_gguf() {
    let model = HFModelInfo(
      id: "org/model", author: "org", libraryName: "gguf"
    )
    let (metadata, _) = ModelCardParser.inferMetadata(from: model)
    XCTAssertTrue(metadata.runtimeType == .gguf)
  }

  @MainActor
  func testInferRuntimeType_fromTags() {
    let model = HFModelInfo(
      id: "org/model", author: "org", tags: ["litert"]
    )
    let (metadata, _) = ModelCardParser.inferMetadata(from: model)
    XCTAssertTrue(metadata.runtimeType == .litertlm)
  }

  @MainActor
  func testInferRuntimeType_fromSiblings() {
    let siblings = [
      HFSibling(rfilename: "model.litertlm", size: 1_000_000, lfs: nil)
    ]
    let model = HFModelInfo(
      id: "org/model", author: "org", siblings: siblings
    )
    let (metadata, _) = ModelCardParser.inferMetadata(from: model, siblings: siblings)
    XCTAssertTrue(metadata.runtimeType == .litertlm)
  }

  @MainActor
  func testInferRuntimeType_default() {
    let model = HFModelInfo(
      id: "org/model", author: "org"
    )
    let (metadata, _) = ModelCardParser.inferMetadata(from: model)
    XCTAssertTrue(metadata.runtimeType == .litertlm)
  }

  // MARK: - Parameter info inference

  @MainActor
  func testInferParameterInfo_E2B() {
    let model = HFModelInfo(
      id: "org/gemma-4-E2B-it-litert-lm", author: "org"
    )
    let (metadata, _) = ModelCardParser.inferMetadata(from: model)
    let nameContainsMoEEdge = metadata.displayName.contains("MoE Edge") || metadata.displayName.contains("2B")
    XCTAssertTrue(nameContainsMoEEdge, "Expected name to contain 'MoE Edge' or '2B', got: \(metadata.displayName)")
  }

  @MainActor
  func testInferParameterInfo_12B() {
    let model = HFModelInfo(
      id: "org/gemma-4-12B-it-litert-lm", author: "org"
    )
    let (metadata, _) = ModelCardParser.inferMetadata(from: model)
    let nameContains12B = metadata.displayName.contains("Dense 12B") || metadata.displayName.contains("12B")
    XCTAssertTrue(nameContains12B, "Expected name to contain 'Dense 12B' or '12B', got: \(metadata.displayName)")
  }

  @MainActor
  func testInferParameterInfo_unknown() {
    let model = HFModelInfo(
      id: "org/some-model", author: "org"
    )
    let (metadata, _) = ModelCardParser.inferMetadata(from: model)
    XCTAssertEqual(metadata.memoryGB ?? 0, 8)
  }

  // MARK: - Capability inference

  @MainActor
  func testInferImageSupport_fromTags() {
    let model = HFModelInfo(
      id: "org/model", author: "org", tags: ["vision"]
    )
    let (metadata, _) = ModelCardParser.inferMetadata(from: model)
    XCTAssertTrue(metadata.hasVision)
  }

  @MainActor
  func testInferImageSupport_fromPipeline() {
    let model = HFModelInfo(
      id: "org/model", author: "org", pipelineTag: "image-text-to-text"
    )
    let (metadata, _) = ModelCardParser.inferMetadata(from: model)
    XCTAssertTrue(metadata.hasVision)
  }

  @MainActor
  func testInferImageSupport_none() {
    let model = HFModelInfo(
      id: "org/model", author: "org"
    )
    let (metadata, _) = ModelCardParser.inferMetadata(from: model)
    XCTAssertFalse(metadata.hasVision)
  }

  @MainActor
  func testInferAudioSupport_fromTags() {
    let model = HFModelInfo(
      id: "org/model", author: "org", tags: ["audio"]
    )
    let (metadata, _) = ModelCardParser.inferMetadata(from: model)
    XCTAssertTrue(metadata.hasAudio)
  }

  @MainActor
  func testInferMTPSupport_fromReadme() {
    let readme = """
      This model supports speculative decoding for faster inference.
      """
    let model = HFModelInfo(
      id: "org/model", author: "org"
    )
    let (metadata, _) = ModelCardParser.inferMetadata(from: model, readmeContent: readme)
    XCTAssertTrue(
      metadata.hasMTP,
      "Expected hasMTP to be true"
    )
  }

  // MARK: - Context window inference

  @MainActor
  func testInferContextWindow_gemma() {
    let model = HFModelInfo(
      id: "org/gemma-model", author: "org"
    )
    let (metadata, _) = ModelCardParser.inferMetadata(from: model)
    XCTAssertEqual(metadata.contextWindowSize, 128_000)
  }

  @MainActor
  func testInferContextWindow_fromReadme_256k() {
    let readme = """
      This model supports a context window of 256k tokens.
      """
    let model = HFModelInfo(
      id: "org/model", author: "org"
    )
    let (metadata, _) = ModelCardParser.inferMetadata(from: model, readmeContent: readme)
    XCTAssertEqual(metadata.contextWindowSize, 256_000)
  }

  @MainActor
  func testInferContextWindow_default() {
    let model = HFModelInfo(
      id: "org/some-other-model", author: "org"
    )
    let (metadata, _) = ModelCardParser.inferMetadata(from: model)
    XCTAssertEqual(metadata.contextWindowSize, 32_000)
  }

  // MARK: - Confidence scoring

  @MainActor
  func testConfidence_high() {
    let siblings = [
      HFSibling(
        rfilename: "model.litertlm",
        size: nil,
        lfs: HFLFSInfo(oid: "abc123", size: 2_000_000_000, pointerSize: 132)
      )
    ]
    let readme = "Full model card with details about gemma."
    let model = HFModelInfo(
      id: "org/model", author: "org", libraryName: "litert", siblings: siblings
    )
    let (_, confidence) = ModelCardParser.inferMetadata(
      from: model, siblings: siblings, readmeContent: readme
    )
    XCTAssertTrue(
      confidence >= .medium,
      "Expected confidence >= .medium, got: \(confidence)"
    )
  }

  @MainActor
  func testConfidence_low() {
    let model = HFModelInfo(
      id: "org/model", author: "org"
    )
    let (_, confidence) = ModelCardParser.inferMetadata(from: model)
    XCTAssertEqual(confidence, .low)
  }

  // MARK: - Web variant detection

  @MainActor
  func testWebVariantDetection() {
    let siblings = [
      HFSibling(rfilename: "model-web.litertlm", size: 1_000_000, lfs: nil)
    ]
    let model = HFModelInfo(
      id: "org/model", author: "org", siblings: siblings
    )
    let (metadata, _) = ModelCardParser.inferMetadata(from: model, siblings: siblings)
    XCTAssertTrue(metadata.platformSupport?.macOS == .gpuOnly)
  }

  // MARK: - File size inference

  @MainActor
  func testFileSizeFromLFS() {
    let lfsSize: Int64 = 3_500_000_000
    let siblings = [
      HFSibling(
        rfilename: "model.litertlm",
        size: nil,
        lfs: HFLFSInfo(oid: "sha256abc", size: lfsSize, pointerSize: 132)
      )
    ]
    let model = HFModelInfo(
      id: "org/model", author: "org", siblings: siblings
    )
    let (metadata, _) = ModelCardParser.inferMetadata(from: model, siblings: siblings)
    XCTAssertEqual(metadata.fileSizeBytes, lfsSize)
  }

  @MainActor
  func testFileSizeFromRegular() {
    let regularSize: Int64 = 2_000_000_000
    let siblings = [
      HFSibling(rfilename: "model.litertlm", size: regularSize, lfs: nil)
    ]
    let model = HFModelInfo(
      id: "org/model", author: "org", siblings: siblings
    )
    let (metadata, _) = ModelCardParser.inferMetadata(from: model, siblings: siblings)
    XCTAssertEqual(metadata.fileSizeBytes, regularSize)
  }
}
