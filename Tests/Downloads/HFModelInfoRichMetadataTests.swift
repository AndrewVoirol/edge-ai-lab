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
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - HFModelInfo Rich Metadata Tests

/// Tests for the enriched HuggingFace API response types added in Phase 1.
///
/// These tests verify:
/// 1. New Codable types decode real API JSON shapes correctly
/// 2. Polymorphic decoders (HFFlexibleStringArray, HFGatedStatus) handle all variants
/// 3. Computed properties on HFModelInfo surface the right data
/// 4. Backward compatibility: minimal JSON (list endpoint) still decodes fine
@Suite("HFModelInfo Rich Metadata")
struct HFModelInfoRichMetadataTests {

    // MARK: - HFFlexibleStringArray

    @Test("Decodes single string into array")
    func flexibleStringArray_singleString() throws {
        let json = #""google/gemma-4-E2B-it""#
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode(HFFlexibleStringArray.self, from: data)
        #expect(result.values == ["google/gemma-4-E2B-it"])
        #expect(result.first == "google/gemma-4-E2B-it")
    }

    @Test("Decodes array of strings")
    func flexibleStringArray_array() throws {
        let json = #"["google/gemma-4-E2B-it", "google/gemma-4-12b-it"]"#
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode(HFFlexibleStringArray.self, from: data)
        #expect(result.values == ["google/gemma-4-E2B-it", "google/gemma-4-12b-it"])
        #expect(result.first == "google/gemma-4-E2B-it")
    }

    @Test("Decodes empty array")
    func flexibleStringArray_emptyArray() throws {
        let json = #"[]"#
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode(HFFlexibleStringArray.self, from: data)
        #expect(result.values.isEmpty)
        #expect(result.first == nil)
    }

    @Test("Roundtrip encoding preserves array")
    func flexibleStringArray_roundtrip() throws {
        let original = HFFlexibleStringArray(values: ["en", "fr", "de"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HFFlexibleStringArray.self, from: data)
        #expect(decoded.values == original.values)
    }

    // MARK: - HFGatedStatus

    @Test("Decodes false as notGated")
    func gatedStatus_false() throws {
        let json = #"false"#
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode(HFGatedStatus.self, from: data)
        #expect(result == .notGated)
        #expect(!result.isGated)
    }

    @Test("Decodes 'auto' as auto-gated")
    func gatedStatus_auto() throws {
        let json = #""auto""#
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode(HFGatedStatus.self, from: data)
        #expect(result == .auto)
        #expect(result.isGated)
    }

    @Test("Decodes 'manual' as manual-gated")
    func gatedStatus_manual() throws {
        let json = #""manual""#
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode(HFGatedStatus.self, from: data)
        #expect(result == .manual)
        #expect(result.isGated)
    }

    @Test("Decodes true as unknown gated")
    func gatedStatus_true() throws {
        let json = #"true"#
        let data = Data(json.utf8)
        let result = try JSONDecoder().decode(HFGatedStatus.self, from: data)
        #expect(result.isGated)
    }

    @Test("Roundtrip encoding for notGated")
    func gatedStatus_roundtrip_notGated() throws {
        let data = try JSONEncoder().encode(HFGatedStatus.notGated)
        let decoded = try JSONDecoder().decode(HFGatedStatus.self, from: data)
        #expect(decoded == .notGated)
    }

    @Test("Roundtrip encoding for auto")
    func gatedStatus_roundtrip_auto() throws {
        let data = try JSONEncoder().encode(HFGatedStatus.auto)
        let decoded = try JSONDecoder().decode(HFGatedStatus.self, from: data)
        #expect(decoded == .auto)
    }

    // MARK: - HFModelConfig

    @Test("Decodes config with architectures and model type")
    func modelConfig_basic() throws {
        let json = """
        {
            "architectures": ["Gemma4ForConditionalGeneration"],
            "model_type": "gemma4"
        }
        """
        let data = Data(json.utf8)
        let config = try JSONDecoder().decode(HFModelConfig.self, from: data)
        #expect(config.architectures == ["Gemma4ForConditionalGeneration"])
        #expect(config.modelType == "gemma4")
        #expect(config.quantizationConfig == nil)
    }

    @Test("Decodes config with quantization")
    func modelConfig_withQuantization() throws {
        let json = """
        {
            "architectures": ["Gemma4ForConditionalGeneration"],
            "model_type": "gemma4",
            "quantization_config": {
                "bits": 4,
                "quant_method": "mlx"
            }
        }
        """
        let data = Data(json.utf8)
        let config = try JSONDecoder().decode(HFModelConfig.self, from: data)
        #expect(config.quantizationConfig?.bits == 4)
        #expect(config.quantizationConfig?.quantMethod == "mlx")
    }

    @Test("Decodes minimal empty config")
    func modelConfig_minimal() throws {
        let json = "{}"
        let data = Data(json.utf8)
        let config = try JSONDecoder().decode(HFModelConfig.self, from: data)
        #expect(config.architectures == nil)
        #expect(config.modelType == nil)
    }

    // MARK: - HFSafetensorsInfo

    @Test("Decodes safetensors with parameters and total")
    func safetensorsInfo_full() throws {
        let json = """
        {
            "parameters": {"BF16": 617219651, "U32": 578977792},
            "total": 1196197443
        }
        """
        let data = Data(json.utf8)
        let info = try JSONDecoder().decode(HFSafetensorsInfo.self, from: data)
        #expect(info.total == 1196197443)
        #expect(info.parameters?["BF16"] == 617219651)
    }

    // MARK: - HFGGUFInfo

    @Test("Decodes GGUF with architecture and context length")
    func ggufInfo_full() throws {
        let json = """
        {
            "total": 4647450147,
            "architecture": "gemma4",
            "context_length": 131072
        }
        """
        let data = Data(json.utf8)
        let info = try JSONDecoder().decode(HFGGUFInfo.self, from: data)
        #expect(info.total == 4647450147)
        #expect(info.architecture == "gemma4")
        #expect(info.contextLength == 131072)
    }

    // MARK: - HFCardData

    @Test("Decodes card data with polymorphic base_model")
    func cardData_withStringBaseModel() throws {
        let json = """
        {
            "license": "gemma",
            "base_model": "google/gemma-4-E2B-it",
            "pipeline_tag": "text-generation",
            "language": ["en", "fr"]
        }
        """
        let data = Data(json.utf8)
        let card = try JSONDecoder().decode(HFCardData.self, from: data)
        #expect(card.license == "gemma")
        #expect(card.baseModel?.first == "google/gemma-4-E2B-it")
        #expect(card.pipelineTag == "text-generation")
        #expect(card.language?.values == ["en", "fr"])
    }

    @Test("Decodes card data with array base_model")
    func cardData_withArrayBaseModel() throws {
        let json = """
        {
            "license": "apache-2.0",
            "base_model": ["google/gemma-4-E2B-it", "google/gemma-4-12b-it"]
        }
        """
        let data = Data(json.utf8)
        let card = try JSONDecoder().decode(HFCardData.self, from: data)
        #expect(card.baseModel?.values.count == 2)
    }

    // MARK: - HFModelInfo Computed Properties

    @Test("parameterCountLabel formats billions correctly")
    func parameterCountLabel_billions() {
        let model = HFModelInfo(
            id: "test/model", author: "test",
            safetensors: HFSafetensorsInfo(parameters: nil, total: 12_000_000_000)
        )
        #expect(model.parameterCountLabel == "12B")
    }

    @Test("parameterCountLabel formats sub-10B with decimal")
    func parameterCountLabel_subTenBillions() {
        let model = HFModelInfo(
            id: "test/model", author: "test",
            safetensors: HFSafetensorsInfo(parameters: nil, total: 1_196_197_443)
        )
        #expect(model.parameterCountLabel == "1.2B")
    }

    @Test("parameterCountLabel formats millions")
    func parameterCountLabel_millions() {
        let model = HFModelInfo(
            id: "test/model", author: "test",
            safetensors: HFSafetensorsInfo(parameters: nil, total: 617_219_651)
        )
        #expect(model.parameterCountLabel == "617M")
    }

    @Test("parameterCountLabel nil when no safetensors")
    func parameterCountLabel_nil() {
        let model = HFModelInfo(id: "test/model", author: "test")
        #expect(model.parameterCountLabel == nil)
    }

    @Test("contextLength from GGUF")
    func contextLength_fromGGUF() {
        let model = HFModelInfo(
            id: "test/model", author: "test",
            gguf: HFGGUFInfo(total: 4_000_000, architecture: "gemma4", contextLength: 131072)
        )
        #expect(model.contextLength == 131072)
    }

    @Test("architecture from config")
    func architecture_fromConfig() {
        let config = HFModelConfig(
            architectures: ["Gemma4ForConditionalGeneration"],
            modelType: "gemma4",
            quantizationConfig: nil,
            tokenizerConfig: nil
        )
        let model = HFModelInfo(id: "test/model", author: "test", config: config)
        #expect(model.architecture == "Gemma4ForConditionalGeneration")
        #expect(model.modelType == "gemma4")
    }

    @Test("isGated from gated status")
    func isGated_fromStatus() {
        let gatedModel = HFModelInfo(id: "test/model", author: "test", gated: .auto)
        #expect(gatedModel.isGated)

        let ungatedModel = HFModelInfo(id: "test/model", author: "test", gated: .notGated)
        #expect(!ungatedModel.isGated)

        let noGatedField = HFModelInfo(id: "test/model", author: "test")
        #expect(!noGatedField.isGated)
    }

    @Test("license from cardData")
    func license_fromCardData() {
        let cardData = HFCardData(
            license: "apache-2.0", licenseLink: nil, baseModel: nil,
            tags: nil, pipelineTag: nil, datasets: nil, language: nil,
            libraryName: nil
        )
        let model = HFModelInfo(id: "test/model", author: "test", cardData: cardData)
        #expect(model.license == "apache-2.0")
    }

    @Test("quantizationInfo prefers config over ID pattern")
    func quantizationInfo_prefersConfig() {
        let config = HFModelConfig(
            architectures: nil, modelType: nil,
            quantizationConfig: HFQuantizationConfig(bits: 4, quantMethod: "mlx"),
            tokenizerConfig: nil
        )
        // Even though ID contains "bf16", config should take priority
        let model = HFModelInfo(id: "test/model-bf16", author: "test", config: config)
        #expect(model.quantizationInfo == "4bit")
    }

    @Test("quantizationInfo falls back to ID pattern when no config")
    func quantizationInfo_fallsBackToID() {
        let model = HFModelInfo(id: "mlx-community/gemma-4-E2B-it-bf16", author: "mlx-community")
        #expect(model.quantizationInfo == "bf16")
    }

    @Test("estimatedDownloadSize prefers GGUF total")
    func estimatedDownloadSize_prefersGGUF() {
        let model = HFModelInfo(
            id: "test/model", author: "test",
            gguf: HFGGUFInfo(total: 4_647_450_147, architecture: nil, contextLength: nil),
            usedStorage: 5_000_000_000
        )
        #expect(model.estimatedDownloadSize == 4_647_450_147)
    }

    @Test("estimatedDownloadSize falls back to usedStorage")
    func estimatedDownloadSize_fallsBackToStorage() {
        let model = HFModelInfo(
            id: "test/model", author: "test",
            usedStorage: 5_000_000_000
        )
        #expect(model.estimatedDownloadSize == 5_000_000_000)
    }

    @Test("supportedLanguages from cardData")
    func supportedLanguages_fromCardData() {
        let cardData = HFCardData(
            license: nil, licenseLink: nil, baseModel: nil,
            tags: nil, pipelineTag: nil, datasets: nil,
            language: HFFlexibleStringArray(values: ["en", "fr", "de"]),
            libraryName: nil
        )
        let model = HFModelInfo(id: "test/model", author: "test", cardData: cardData)
        #expect(model.supportedLanguages == ["en", "fr", "de"])
    }

    // MARK: - Full API Response Decoding

    @Test("Decodes enriched API response with all new fields")
    func fullAPIResponse_decoding() throws {
        let json = """
        {
            "id": "mlx-community/gemma-4-E2B-it-4bit",
            "author": "mlx-community",
            "lastModified": "2026-06-15T10:30:00.000Z",
            "downloads": 5000,
            "likes": 25,
            "tags": ["gemma-4", "mlx", "text-generation"],
            "pipeline_tag": "text-generation",
            "library_name": "mlx",
            "config": {
                "architectures": ["Gemma4ForConditionalGeneration"],
                "model_type": "gemma4",
                "quantization_config": {
                    "bits": 4
                }
            },
            "safetensors": {
                "parameters": {"BF16": 617219651},
                "total": 1196197443
            },
            "cardData": {
                "license": "gemma",
                "base_model": "google/gemma-4-E2B-it",
                "language": ["en"]
            },
            "gated": false,
            "usedStorage": 2000000000
        }
        """
        let data = Data(json.utf8)
        let model = try JSONDecoder().decode(HFModelInfo.self, from: data)

        // Core fields
        #expect(model.id == "mlx-community/gemma-4-E2B-it-4bit")
        #expect(model.author == "mlx-community")

        // Enriched fields
        #expect(model.architecture == "Gemma4ForConditionalGeneration")
        #expect(model.modelType == "gemma4")
        #expect(model.quantizationBits == 4)
        #expect(model.totalParameters == 1196197443)
        #expect(model.license == "gemma")
        #expect(model.baseModelId == "google/gemma-4-E2B-it")
        #expect(!model.isGated)
        #expect(model.usedStorage == 2000000000)
    }

    @Test("Backward compatible: minimal JSON still decodes")
    func minimalJSON_backwardCompatible() throws {
        let json = """
        {
            "id": "litert-community/gemma-4-E2B-it-litert-lm"
        }
        """
        let data = Data(json.utf8)
        let model = try JSONDecoder().decode(HFModelInfo.self, from: data)

        #expect(model.id == "litert-community/gemma-4-E2B-it-litert-lm")
        #expect(model.author == "litert-community")
        #expect(model.config == nil)
        #expect(model.safetensors == nil)
        #expect(model.gguf == nil)
        #expect(model.cardData == nil)
        #expect(model.gated == nil)
        #expect(model.usedStorage == nil)
        #expect(model.totalParameters == nil)
        #expect(model.parameterCountLabel == nil)
    }

    @Test("GGUF API response decodes correctly")
    func ggufAPIResponse_decoding() throws {
        let json = """
        {
            "id": "unsloth/gemma-4-E2B-it-GGUF",
            "author": "unsloth",
            "downloads": 10000,
            "likes": 50,
            "tags": ["gguf", "gemma-4"],
            "gguf": {
                "total": 4647450147,
                "architecture": "gemma4",
                "context_length": 131072
            },
            "cardData": {
                "license": "gemma",
                "base_model": ["google/gemma-4-E2B-it"]
            },
            "gated": "auto"
        }
        """
        let data = Data(json.utf8)
        let model = try JSONDecoder().decode(HFModelInfo.self, from: data)

        #expect(model.contextLength == 131072)
        #expect(model.ggufArchitecture == "gemma4")
        #expect(model.estimatedDownloadSize == 4647450147)
        #expect(model.isGated)
        #expect(model.baseModelId == "google/gemma-4-E2B-it")
    }
}

// MARK: - ModelCardParser API-Data-Preferred Path Tests

/// Tests that verify ModelCardParser prefers API-provided data from enriched HFModelInfo
/// over heuristic inference from repo IDs and READMEs.
@Suite("ModelCardParser API-Data Paths")
struct ModelCardParserAPIDataTests {

    @MainActor
    @Test("inferMetadata uses API parameter count over ID heuristic")
    func inferMetadata_prefersAPIParameterCount() {
        let model = HFModelInfo(
            id: "custom-org/my-model",  // No param hint in ID
            author: "custom-org",
            safetensors: HFSafetensorsInfo(parameters: nil, total: 12_000_000_000)
        )
        let (metadata, _) = ModelCardParser.inferMetadata(from: model)
        // Should pick up 12B from API, not "Unknown" from ID heuristic
        #expect(metadata.modelDescription?.contains("12B") == true)
    }

    @MainActor
    @Test("inferMetadata uses API context window from GGUF")
    func inferMetadata_prefersAPIContextWindow() {
        let model = HFModelInfo(
            id: "org/model",
            author: "org",
            gguf: HFGGUFInfo(total: 4_000_000, architecture: "gemma4", contextLength: 131072)
        )
        let (metadata, _) = ModelCardParser.inferMetadata(from: model)
        #expect(metadata.contextWindowSize == 131072)
    }

    @MainActor
    @Test("inferMetadata detects image support from architecture name")
    func inferMetadata_imageFromArchitecture() {
        let config = HFModelConfig(
            architectures: ["Gemma4ForConditionalGeneration"],
            modelType: "gemma4",
            quantizationConfig: nil,
            tokenizerConfig: nil
        )
        let model = HFModelInfo(
            id: "org/model",
            author: "org",
            config: config
        )
        let (metadata, _) = ModelCardParser.inferMetadata(from: model)
        #expect(metadata.hasVision == true)
    }

    @MainActor
    @Test("inferMetadata detects GGUF runtime from gguf metadata")
    func inferMetadata_ggufFromMetadata() {
        let model = HFModelInfo(
            id: "org/some-model",  // No GGUF hint in ID
            author: "org",
            tags: [],  // No GGUF tags
            gguf: HFGGUFInfo(total: 4_000_000, architecture: "gemma4", contextLength: nil)
        )
        let (metadata, _) = ModelCardParser.inferMetadata(from: model)
        #expect(metadata.runtimeType == .gguf)
    }

    @MainActor
    @Test("inferMetadata uses API architecture description")
    func inferMetadata_usesAPIArchitecture() {
        let config = HFModelConfig(
            architectures: ["Gemma4ForCausalLM"],
            modelType: "gemma4",
            quantizationConfig: nil,
            tokenizerConfig: nil
        )
        let model = HFModelInfo(
            id: "org/model",
            author: "org",
            config: config
        )
        let (metadata, _) = ModelCardParser.inferMetadata(from: model)
        // Architecture should contain cleaned-up name with "(Text)" suffix
        let archClass = metadata.architecture?.architectureClass ?? ""
        #expect(archClass.contains("Gemma4"))
    }

    @MainActor
    @Test("inferMetadata higher confidence with API data")
    func inferMetadata_higherConfidenceWithAPIData() {
        let modelWithAPI = HFModelInfo(
            id: "org/model",
            author: "org",
            safetensors: HFSafetensorsInfo(parameters: nil, total: 1_000_000_000),
            gguf: HFGGUFInfo(total: 4_000_000, architecture: "gemma4", contextLength: 8192)
        )
        let modelWithoutAPI = HFModelInfo(
            id: "org/model",
            author: "org"
        )

        let (_, confWith) = ModelCardParser.inferMetadata(from: modelWithAPI)
        let (_, confWithout) = ModelCardParser.inferMetadata(from: modelWithoutAPI)
        #expect(confWith > confWithout)
    }
}
