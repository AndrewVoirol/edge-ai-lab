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

// MARK: - CapabilitySource Tests

@Suite("CapabilitySource")
struct CapabilitySourceTests {

    @Test("Display labels are human-readable")
    func displayLabels() {
        #expect(CapabilitySource.configJSON.displayLabel == "from config.json")
        #expect(CapabilitySource.apiMetadata.displayLabel == "from API")
        #expect(CapabilitySource.heuristic.displayLabel == "estimated")
        #expect(CapabilitySource.engineRuntime.displayLabel == "verified at runtime")
        #expect(CapabilitySource.registry.displayLabel == "known model")
    }

    @Test("Codable roundtrip")
    func codableRoundtrip() throws {
        let original = CapabilitySource.configJSON
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CapabilitySource.self, from: data)
        #expect(decoded == original)
    }
}

// MARK: - SourcedValue Tests

@Suite("SourcedValue")
struct SourcedValueTests {

    @Test("Stores value and source")
    func storesValueAndSource() {
        let sv = SourcedValue(true, source: .configJSON)
        #expect(sv.value == true)
        #expect(sv.source == .configJSON)
    }

    @Test("Codable roundtrip for Bool")
    func codableRoundtrip_bool() throws {
        let original = SourcedValue(false, source: .heuristic)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SourcedValue<Bool>.self, from: data)
        #expect(decoded.value == false)
        #expect(decoded.source == .heuristic)
    }

    @Test("Codable roundtrip for Int")
    func codableRoundtrip_int() throws {
        let original = SourcedValue(131072, source: .configJSON)
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(SourcedValue<Int>.self, from: data)
        #expect(decoded.value == 131072)
        #expect(decoded.source == .configJSON)
    }

    @Test("Hashable: same value and source are equal")
    func hashable_equal() {
        let a = SourcedValue(true, source: .configJSON)
        let b = SourcedValue(true, source: .configJSON)
        #expect(a == b)
    }

    @Test("Hashable: different source makes unequal")
    func hashable_differentSource() {
        let a = SourcedValue(true, source: .configJSON)
        let b = SourcedValue(true, source: .heuristic)
        #expect(a != b)
    }
}

// MARK: - Profile Builder from HFModelInfo

@Suite("ModelCapabilityProfileBuilder — from HFModelInfo")
struct ProfileBuilderHFModelInfoTests {

    @Test("Vision detected from vision_config (source: config_json)")
    func vision_fromVisionConfig() {
        let config = HFModelConfig(
            architectures: ["Gemma4ForConditionalGeneration"],
            visionConfig: HFVisionConfig(
                hiddenSize: 1152, numHiddenLayers: 27,
                imageSize: 896, patchSize: 14,
                numAttentionHeads: 16, modelType: "siglip_vision_model"
            )
        )
        let model = HFModelInfo(id: "test/model-it", author: "test", config: config)
        let profile = ModelCapabilityProfileBuilder.fromHFModelInfo(model, runtimeType: .mlx)

        #expect(profile.hasVision)
        #expect(profile.supportsVision?.source == .configJSON)
    }

    @Test("Vision detected from image_token_id (source: config_json)")
    func vision_fromImageTokenId() {
        let config = HFModelConfig(imageTokenId: 262145)
        let model = HFModelInfo(id: "test/model-it", author: "test", config: config)
        let profile = ModelCapabilityProfileBuilder.fromHFModelInfo(model, runtimeType: .mlx)

        #expect(profile.hasVision)
        #expect(profile.supportsVision?.source == .configJSON)
    }

    @Test("Vision detected from ConditionalGeneration architecture")
    func vision_fromArchitecture() {
        let config = HFModelConfig(
            architectures: ["Gemma4ForConditionalGeneration"]
        )
        let model = HFModelInfo(id: "test/model-it", author: "test", config: config)
        let profile = ModelCapabilityProfileBuilder.fromHFModelInfo(model, runtimeType: .mlx)

        #expect(profile.hasVision)
        #expect(profile.supportsVision?.source == .configJSON)
    }

    @Test("Vision false for CausalLM architecture with config present")
    func vision_falseForCausalLM() {
        let config = HFModelConfig(
            architectures: ["Gemma4ForCausalLM"],
            modelType: "gemma4"
        )
        let model = HFModelInfo(id: "test/model-it", author: "test", config: config)
        let profile = ModelCapabilityProfileBuilder.fromHFModelInfo(model, runtimeType: .mlx)

        #expect(!profile.hasVision)
        #expect(profile.supportsVision?.source == .configJSON)
    }

    @Test("Vision nil when no config at all")
    func vision_nilWhenNoConfig() {
        let model = HFModelInfo(id: "test/model", author: "test")
        let profile = ModelCapabilityProfileBuilder.fromHFModelInfo(model, runtimeType: .litertlm)

        #expect(profile.supportsVision == nil)
    }

    @Test("Vision detected from tags when no config")
    func vision_fromTags() {
        let model = HFModelInfo(
            id: "test/model-it", author: "test",
            tags: ["image-text-to-text", "multimodal"]
        )
        let profile = ModelCapabilityProfileBuilder.fromHFModelInfo(model, runtimeType: .litertlm)

        #expect(profile.hasVision)
        #expect(profile.supportsVision?.source == .apiMetadata)
    }

    @Test("Audio detected from audio_config")
    func audio_fromAudioConfig() {
        let config = HFModelConfig(
            audioConfig: HFAudioConfig(
                hiddenSize: 1536, numHiddenLayers: 32,
                numAttentionHeads: 24, modelType: "gemma4_audio"
            )
        )
        let model = HFModelInfo(id: "test/model-it", author: "test", config: config)
        let profile = ModelCapabilityProfileBuilder.fromHFModelInfo(model, runtimeType: .mlx)

        #expect(profile.hasAudio)
        #expect(profile.supportsAudio?.source == .configJSON)
    }

    @Test("Audio detected from audio_token_id")
    func audio_fromAudioTokenId() {
        let config = HFModelConfig(audioTokenId: 262146)
        let model = HFModelInfo(id: "test/model-it", author: "test", config: config)
        let profile = ModelCapabilityProfileBuilder.fromHFModelInfo(model, runtimeType: .mlx)

        #expect(profile.hasAudio)
        #expect(profile.supportsAudio?.source == .configJSON)
    }

    @Test("Thinking supported for Gemma 4 models")
    func thinking_gemma4() {
        let config = HFModelConfig(modelType: "gemma4")
        let model = HFModelInfo(id: "test/gemma-4-model-it", author: "test", config: config)
        let profile = ModelCapabilityProfileBuilder.fromHFModelInfo(model, runtimeType: .mlx)

        #expect(profile.hasThinking)
    }

    @Test("Thinking nil for non-Gemma models")
    func thinking_nonGemma() {
        let config = HFModelConfig(modelType: "llama")
        let model = HFModelInfo(id: "test/llama-model", author: "test", config: config)
        let profile = ModelCapabilityProfileBuilder.fromHFModelInfo(model, runtimeType: .gguf)

        #expect(profile.supportsThinking == nil)
    }

    @Test("Tool calling from instruction-tuned model name (-it-)")
    func toolCalling_instructionTuned() {
        let model = HFModelInfo(id: "test/gemma-4-E2B-it-4bit", author: "test")
        let profile = ModelCapabilityProfileBuilder.fromHFModelInfo(model, runtimeType: .mlx)

        #expect(profile.hasToolCalling)
        #expect(profile.supportsToolCalling?.source == .heuristic)
    }

    @Test("Tool calling false for base model")
    func toolCalling_baseModel() {
        let model = HFModelInfo(id: "test/gemma-4-E2B-base", author: "test")
        let profile = ModelCapabilityProfileBuilder.fromHFModelInfo(model, runtimeType: .mlx)

        #expect(!profile.hasToolCalling)
    }

    @Test("Context window from text_config (source: config_json)")
    func contextWindow_fromTextConfig() {
        let config = HFModelConfig(
            textConfig: HFTextConfig(
                hiddenSize: nil, numHiddenLayers: nil,
                numAttentionHeads: nil, numKeyValueHeads: nil,
                intermediateSize: nil, vocabSize: nil,
                maxPositionEmbeddings: 131072, slidingWindow: nil,
                headDim: nil, torchDtype: nil,
                enableMoeBlock: nil, modelType: nil
            )
        )
        let model = HFModelInfo(id: "test/model", author: "test", config: config)
        let profile = ModelCapabilityProfileBuilder.fromHFModelInfo(model, runtimeType: .mlx)

        #expect(profile.contextWindowSize == 131072)
        #expect(profile.contextWindow?.source == .configJSON)
    }

    @Test("Context window from GGUF when no config")
    func contextWindow_fromGGUF() {
        let model = HFModelInfo(
            id: "test/model", author: "test",
            gguf: HFGGUFInfo(total: 4_000_000, architecture: "gemma4", contextLength: 8192)
        )
        let profile = ModelCapabilityProfileBuilder.fromHFModelInfo(model, runtimeType: .gguf)

        #expect(profile.contextWindowSize == 8192)
        #expect(profile.contextWindow?.source == .apiMetadata)
    }

    @Test("Architecture info populated from config")
    func architecture_fromConfig() {
        let config = HFModelConfig(
            architectures: ["Gemma4ForConditionalGeneration"],
            modelType: "gemma4",
            textConfig: HFTextConfig(
                hiddenSize: 2304, numHiddenLayers: 34,
                numAttentionHeads: 8, numKeyValueHeads: 4,
                intermediateSize: 9216, vocabSize: 262144,
                maxPositionEmbeddings: 131072, slidingWindow: nil,
                headDim: 256, torchDtype: "bfloat16",
                enableMoeBlock: true, modelType: "gemma4_text"
            ),
            visionConfig: HFVisionConfig(
                hiddenSize: 1152, numHiddenLayers: 27,
                imageSize: 896, patchSize: 14,
                numAttentionHeads: 16, modelType: "siglip_vision_model"
            ),
            torchDtype: "bfloat16"
        )
        let model = HFModelInfo(id: "test/model-it", author: "test", config: config)
        let profile = ModelCapabilityProfileBuilder.fromHFModelInfo(model, runtimeType: .mlx)

        let arch = profile.architecture
        #expect(arch != nil)
        #expect(arch?.architectureClass == "Gemma4ForConditionalGeneration")
        #expect(arch?.modelType == "gemma4")
        #expect(arch?.isMoE == true)
        #expect(arch?.hiddenSize == 2304)
        #expect(arch?.numLayers == 34)
        #expect(arch?.maxImageResolution == 896)
        #expect(arch?.dtype == "bfloat16")
    }

    @Test("Memory estimation from safetensors")
    func memoryEstimation() {
        let model = HFModelInfo(
            id: "test/model-it", author: "test",
            safetensors: HFSafetensorsInfo(parameters: nil, total: 1_196_197_443)
        )
        let profile = ModelCapabilityProfileBuilder.fromHFModelInfo(model, runtimeType: .mlx)

        #expect(profile.memoryGB != nil)
        // 1.2B params × 2 bytes = ~2.4GB → ceil → 4 (clamped min)
        #expect(profile.memoryGB == 4)
        #expect(profile.estimatedMemoryGB?.source == .apiMetadata)
    }

    @Test("Constrained decoding true for LiteRT-LM")
    func constrainedDecoding_litertlm() {
        let model = HFModelInfo(id: "test/model-it", author: "test")
        let profile = ModelCapabilityProfileBuilder.fromHFModelInfo(model, runtimeType: .litertlm)

        #expect(profile.hasConstrainedDecoding)
    }

    @Test("Constrained decoding false for MLX")
    func constrainedDecoding_mlx() {
        let model = HFModelInfo(id: "test/model-it", author: "test")
        let profile = ModelCapabilityProfileBuilder.fromHFModelInfo(model, runtimeType: .mlx)

        #expect(!profile.hasConstrainedDecoding)
    }

    @Test("isMultimodal true when vision supported")
    func isMultimodal_vision() {
        let config = HFModelConfig(
            visionConfig: HFVisionConfig(
                hiddenSize: 1152, numHiddenLayers: nil,
                imageSize: nil, patchSize: nil,
                numAttentionHeads: nil, modelType: nil
            )
        )
        let model = HFModelInfo(id: "test/model-it", author: "test", config: config)
        let profile = ModelCapabilityProfileBuilder.fromHFModelInfo(model, runtimeType: .mlx)

        #expect(profile.isMultimodal)
    }
}

// MARK: - Profile Builder from ModelMetadata

@Suite("ModelCapabilityProfileBuilder — from ModelMetadata")
struct ProfileBuilderModelMetadataTests {

    @Test("Builds profile from known registry model")
    func fromKnownRegistry() {
        // Use the first known model in the registry
        let knownModels = ModelRegistry.knownModels
        guard let metadata = knownModels.first else {
            Issue.record("No known models in registry")
            return
        }

        let profile = ModelCapabilityProfileBuilder.fromModelMetadata(metadata)

        #expect(profile.id == metadata.modelFile)
        #expect(profile.displayName == metadata.name)
        #expect(profile.runtimeType == metadata.runtimeType)
        #expect(profile.confidence == .verified)
        #expect(profile.source == .knownRegistry)
        #expect(profile.supportsVision?.value == metadata.supportsImage)
        #expect(profile.supportsAudio?.value == metadata.supportsAudio)
        #expect(profile.contextWindowSize == metadata.contextWindowSize)
        #expect(profile.memoryGB == metadata.minDeviceMemoryGB)
    }

    @Test("Source is .registry for known models")
    func sourceIsRegistry() {
        let knownModels = ModelRegistry.knownModels
        guard let metadata = knownModels.first else {
            Issue.record("No known models in registry")
            return
        }

        let profile = ModelCapabilityProfileBuilder.fromModelMetadata(metadata)
        #expect(profile.supportsVision?.source == .registry)
    }
}

// MARK: - Profile Codable Tests

@Suite("ModelCapabilityProfile — Codable")
struct ProfileCodableTests {

    @Test("Full profile roundtrip encode/decode")
    func fullRoundtrip() throws {
        let config = HFModelConfig(
            architectures: ["Gemma4ForConditionalGeneration"],
            modelType: "gemma4",
            visionConfig: HFVisionConfig(
                hiddenSize: 1152, numHiddenLayers: 27,
                imageSize: 896, patchSize: 14,
                numAttentionHeads: 16, modelType: "siglip_vision_model"
            ),
            audioConfig: HFAudioConfig(
                hiddenSize: 1536, numHiddenLayers: 32,
                numAttentionHeads: 24, modelType: "gemma4_audio"
            ),
            imageTokenId: 262145,
            audioTokenId: 262146,
            torchDtype: "bfloat16"
        )
        let model = HFModelInfo(
            id: "mlx-community/gemma-4-E2B-it-4bit",
            author: "mlx-community",
            tags: ["gemma-4", "mlx"],
            config: config,
            safetensors: HFSafetensorsInfo(parameters: nil, total: 1_196_197_443)
        )
        let profile = ModelCapabilityProfileBuilder.fromHFModelInfo(model, runtimeType: .mlx)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(profile)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ModelCapabilityProfile.self, from: data)

        #expect(decoded.id == profile.id)
        #expect(decoded.hasVision == profile.hasVision)
        #expect(decoded.hasAudio == profile.hasAudio)
        #expect(decoded.contextWindowSize == profile.contextWindowSize)
        #expect(decoded.supportsVision?.source == profile.supportsVision?.source)
    }

    @Test("Profile JSON is human-readable")
    func jsonIsHumanReadable() throws {
        let config = HFModelConfig(
            architectures: ["Gemma4ForConditionalGeneration"],
            modelType: "gemma4",
            visionConfig: HFVisionConfig(
                hiddenSize: 1152, numHiddenLayers: nil,
                imageSize: 896, patchSize: nil,
                numAttentionHeads: nil, modelType: nil
            )
        )
        let model = HFModelInfo(
            id: "test/model-it", author: "test",
            config: config
        )
        let profile = ModelCapabilityProfileBuilder.fromHFModelInfo(model, runtimeType: .mlx)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(profile)
        let json = String(data: data, encoding: .utf8) ?? ""

        // Verify key fields are present in the JSON
        #expect(json.contains("\"supportsVision\""))
        #expect(json.contains("\"source\""))
        #expect(json.contains("config_json"))
    }
}
