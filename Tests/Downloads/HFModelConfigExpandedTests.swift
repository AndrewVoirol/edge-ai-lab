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

// MARK: - HFModelConfig Expanded Tests

/// Tests for the expanded HFModelConfig with sub-config objects (text_config, vision_config,
/// audio_config) and new top-level fields. These fields provide authoritative model
/// architecture data from config.json, replacing tag-based heuristics.
@Suite("HFModelConfig Expanded")
struct HFModelConfigExpandedTests {

    // MARK: - HFTextConfig

    @Test("Decodes text_config with all fields from Gemma 4 E2B config.json")
    func textConfig_fullGemma4E2B() throws {
        let json = """
        {
            "hidden_size": 2304,
            "num_hidden_layers": 34,
            "num_attention_heads": 8,
            "num_key_value_heads": 4,
            "intermediate_size": 9216,
            "vocab_size": 262144,
            "max_position_embeddings": 131072,
            "sliding_window": 512,
            "head_dim": 256,
            "torch_dtype": "bfloat16",
            "enable_moe_block": true,
            "model_type": "gemma4_text"
        }
        """
        let data = Data(json.utf8)
        let config = try JSONDecoder().decode(HFTextConfig.self, from: data)
        #expect(config.hiddenSize == 2304)
        #expect(config.numHiddenLayers == 34)
        #expect(config.numAttentionHeads == 8)
        #expect(config.numKeyValueHeads == 4)
        #expect(config.intermediateSize == 9216)
        #expect(config.vocabSize == 262144)
        #expect(config.maxPositionEmbeddings == 131072)
        #expect(config.slidingWindow == 512)
        #expect(config.headDim == 256)
        #expect(config.torchDtype == "bfloat16")
        #expect(config.enableMoeBlock == true)
        #expect(config.modelType == "gemma4_text")
    }

    @Test("Decodes minimal text_config — all fields optional")
    func textConfig_minimal() throws {
        let json = "{}"
        let data = Data(json.utf8)
        let config = try JSONDecoder().decode(HFTextConfig.self, from: data)
        #expect(config.hiddenSize == nil)
        #expect(config.maxPositionEmbeddings == nil)
        #expect(config.enableMoeBlock == nil)
    }

    @Test("Decodes text_config for dense model (no MoE)")
    func textConfig_denseModel() throws {
        let json = """
        {
            "hidden_size": 3840,
            "num_hidden_layers": 48,
            "num_attention_heads": 16,
            "num_key_value_heads": 8,
            "vocab_size": 262144,
            "max_position_embeddings": 262144,
            "model_type": "gemma4_text"
        }
        """
        let data = Data(json.utf8)
        let config = try JSONDecoder().decode(HFTextConfig.self, from: data)
        #expect(config.hiddenSize == 3840)
        #expect(config.numHiddenLayers == 48)
        #expect(config.maxPositionEmbeddings == 262144)
        #expect(config.enableMoeBlock == nil)  // Dense model has no MoE field
    }

    // MARK: - HFVisionConfig

    @Test("Decodes vision_config from SigLIP encoder")
    func visionConfig_siglip() throws {
        let json = """
        {
            "hidden_size": 1152,
            "num_hidden_layers": 27,
            "image_size": 896,
            "patch_size": 14,
            "num_attention_heads": 16,
            "model_type": "siglip_vision_model"
        }
        """
        let data = Data(json.utf8)
        let config = try JSONDecoder().decode(HFVisionConfig.self, from: data)
        #expect(config.hiddenSize == 1152)
        #expect(config.numHiddenLayers == 27)
        #expect(config.imageSize == 896)
        #expect(config.patchSize == 14)
        #expect(config.numAttentionHeads == 16)
        #expect(config.modelType == "siglip_vision_model")
    }

    @Test("Decodes minimal vision_config")
    func visionConfig_minimal() throws {
        let json = "{}"
        let data = Data(json.utf8)
        let config = try JSONDecoder().decode(HFVisionConfig.self, from: data)
        #expect(config.imageSize == nil)
    }

    // MARK: - HFAudioConfig

    @Test("Decodes audio_config")
    func audioConfig_basic() throws {
        let json = """
        {
            "hidden_size": 1536,
            "num_hidden_layers": 32,
            "num_attention_heads": 24,
            "model_type": "gemma4_audio"
        }
        """
        let data = Data(json.utf8)
        let config = try JSONDecoder().decode(HFAudioConfig.self, from: data)
        #expect(config.hiddenSize == 1536)
        #expect(config.numHiddenLayers == 32)
        #expect(config.numAttentionHeads == 24)
        #expect(config.modelType == "gemma4_audio")
    }

    // MARK: - HFModelConfig with Sub-Configs

    @Test("Decodes full config.json with text, vision, and audio sub-configs")
    func modelConfig_fullSubConfigs() throws {
        let json = """
        {
            "architectures": ["Gemma4ForConditionalGeneration"],
            "model_type": "gemma4",
            "torch_dtype": "bfloat16",
            "image_token_id": 262145,
            "audio_token_id": 262146,
            "max_position_embeddings": 131072,
            "text_config": {
                "hidden_size": 2304,
                "num_hidden_layers": 34,
                "max_position_embeddings": 131072,
                "enable_moe_block": true
            },
            "vision_config": {
                "hidden_size": 1152,
                "image_size": 896,
                "patch_size": 14,
                "model_type": "siglip_vision_model"
            },
            "audio_config": {
                "hidden_size": 1536,
                "num_hidden_layers": 32,
                "model_type": "gemma4_audio"
            }
        }
        """
        let data = Data(json.utf8)
        let config = try JSONDecoder().decode(HFModelConfig.self, from: data)

        // Top-level
        #expect(config.architectures == ["Gemma4ForConditionalGeneration"])
        #expect(config.modelType == "gemma4")
        #expect(config.torchDtype == "bfloat16")
        #expect(config.imageTokenId == 262145)
        #expect(config.audioTokenId == 262146)
        #expect(config.maxPositionEmbeddings == 131072)

        // Text sub-config
        #expect(config.textConfig?.hiddenSize == 2304)
        #expect(config.textConfig?.numHiddenLayers == 34)
        #expect(config.textConfig?.maxPositionEmbeddings == 131072)
        #expect(config.textConfig?.enableMoeBlock == true)

        // Vision sub-config
        #expect(config.visionConfig?.hiddenSize == 1152)
        #expect(config.visionConfig?.imageSize == 896)
        #expect(config.visionConfig?.patchSize == 14)
        #expect(config.visionConfig?.modelType == "siglip_vision_model")

        // Audio sub-config
        #expect(config.audioConfig?.hiddenSize == 1536)
        #expect(config.audioConfig?.modelType == "gemma4_audio")
    }

    @Test("Config with text-only model — no vision or audio sub-configs")
    func modelConfig_textOnly() throws {
        let json = """
        {
            "architectures": ["Gemma4ForCausalLM"],
            "model_type": "gemma4",
            "text_config": {
                "hidden_size": 2304,
                "max_position_embeddings": 131072
            }
        }
        """
        let data = Data(json.utf8)
        let config = try JSONDecoder().decode(HFModelConfig.self, from: data)
        #expect(config.textConfig?.hiddenSize == 2304)
        #expect(config.visionConfig == nil)
        #expect(config.audioConfig == nil)
        #expect(config.imageTokenId == nil)
        #expect(config.audioTokenId == nil)
    }

    @Test("Backward compat: old-style config without sub-configs decodes fine")
    func modelConfig_backwardCompat() throws {
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
        #expect(config.architectures == ["Gemma4ForConditionalGeneration"])
        #expect(config.quantizationConfig?.bits == 4)
        // New fields default to nil
        #expect(config.textConfig == nil)
        #expect(config.visionConfig == nil)
        #expect(config.audioConfig == nil)
    }

    @Test("Memberwise init backward compat — old call style still works")
    func modelConfig_memberwiseInitBackwardCompat() {
        let config = HFModelConfig(
            architectures: ["TestArch"],
            modelType: "test",
            quantizationConfig: nil,
            tokenizerConfig: nil
        )
        #expect(config.architectures == ["TestArch"])
        #expect(config.textConfig == nil)
        #expect(config.visionConfig == nil)
        #expect(config.audioConfig == nil)
        #expect(config.imageTokenId == nil)
    }

    @Test("Memberwise init with new fields")
    func modelConfig_memberwiseInitNewFields() {
        let textConfig = HFTextConfig(
            hiddenSize: 2304, numHiddenLayers: 34,
            numAttentionHeads: 8, numKeyValueHeads: 4,
            intermediateSize: 9216, vocabSize: 262144,
            maxPositionEmbeddings: 131072, slidingWindow: 512,
            headDim: 256, torchDtype: "bfloat16",
            enableMoeBlock: true, modelType: "gemma4_text"
        )
        let visionConfig = HFVisionConfig(
            hiddenSize: 1152, numHiddenLayers: 27,
            imageSize: 896, patchSize: 14,
            numAttentionHeads: 16, modelType: "siglip_vision_model"
        )
        let config = HFModelConfig(
            architectures: ["Gemma4ForConditionalGeneration"],
            modelType: "gemma4",
            textConfig: textConfig,
            visionConfig: visionConfig,
            imageTokenId: 262145,
            torchDtype: "bfloat16"
        )
        #expect(config.textConfig?.maxPositionEmbeddings == 131072)
        #expect(config.visionConfig?.imageSize == 896)
        #expect(config.imageTokenId == 262145)
        #expect(config.audioConfig == nil)
    }

    // MARK: - HFModelInfo Capability Signals

    @Test("hasVisionSupport from vision_config")
    func hasVisionSupport_fromVisionConfig() {
        let config = HFModelConfig(
            visionConfig: HFVisionConfig(
                hiddenSize: 1152, numHiddenLayers: 27,
                imageSize: 896, patchSize: 14,
                numAttentionHeads: 16, modelType: "siglip_vision_model"
            )
        )
        let model = HFModelInfo(id: "test/model", author: "test", config: config)
        #expect(model.hasVisionSupport)
    }

    @Test("hasVisionSupport from image_token_id")
    func hasVisionSupport_fromImageTokenId() {
        let config = HFModelConfig(imageTokenId: 262145)
        let model = HFModelInfo(id: "test/model", author: "test", config: config)
        #expect(model.hasVisionSupport)
    }

    @Test("hasVisionSupport from ConditionalGeneration architecture")
    func hasVisionSupport_fromArchitecture() {
        let config = HFModelConfig(
            architectures: ["Gemma4ForConditionalGeneration"]
        )
        let model = HFModelInfo(id: "test/model", author: "test", config: config)
        #expect(model.hasVisionSupport)
    }

    @Test("hasVisionSupport false for text-only model")
    func hasVisionSupport_falseForTextOnly() {
        let config = HFModelConfig(
            architectures: ["Gemma4ForCausalLM"],
            modelType: "gemma4"
        )
        let model = HFModelInfo(id: "test/model", author: "test", config: config)
        #expect(!model.hasVisionSupport)
    }

    @Test("hasVisionSupport false when no config")
    func hasVisionSupport_falseNoConfig() {
        let model = HFModelInfo(id: "test/model", author: "test")
        #expect(!model.hasVisionSupport)
    }

    @Test("hasAudioSupport from audio_config")
    func hasAudioSupport_fromAudioConfig() {
        let config = HFModelConfig(
            audioConfig: HFAudioConfig(
                hiddenSize: 1536, numHiddenLayers: 32,
                numAttentionHeads: 24, modelType: "gemma4_audio"
            )
        )
        let model = HFModelInfo(id: "test/model", author: "test", config: config)
        #expect(model.hasAudioSupport)
    }

    @Test("hasAudioSupport from audio_token_id")
    func hasAudioSupport_fromAudioTokenId() {
        let config = HFModelConfig(audioTokenId: 262146)
        let model = HFModelInfo(id: "test/model", author: "test", config: config)
        #expect(model.hasAudioSupport)
    }

    @Test("hasAudioSupport false when no audio indicators")
    func hasAudioSupport_falseNoAudio() {
        let config = HFModelConfig(
            architectures: ["Gemma4ForConditionalGeneration"],
            visionConfig: HFVisionConfig(
                hiddenSize: 1152, numHiddenLayers: nil,
                imageSize: nil, patchSize: nil,
                numAttentionHeads: nil, modelType: nil
            )
        )
        let model = HFModelInfo(id: "test/model", author: "test", config: config)
        #expect(!model.hasAudioSupport)
    }

    // MARK: - Context Length Cascade

    @Test("maxContextLength from text_config.max_position_embeddings (highest priority)")
    func maxContextLength_fromTextConfig() {
        let config = HFModelConfig(
            textConfig: HFTextConfig(
                hiddenSize: nil, numHiddenLayers: nil,
                numAttentionHeads: nil, numKeyValueHeads: nil,
                intermediateSize: nil, vocabSize: nil,
                maxPositionEmbeddings: 131072, slidingWindow: nil,
                headDim: nil, torchDtype: nil,
                enableMoeBlock: nil, modelType: nil
            ),
            maxPositionEmbeddings: 65536  // Lower priority — should be ignored
        )
        let model = HFModelInfo(
            id: "test/model", author: "test",
            config: config,
            gguf: HFGGUFInfo(total: nil, architecture: nil, contextLength: 32768)  // Lowest
        )
        #expect(model.maxContextLength == 131072)
        #expect(model.contextLength == 131072)
    }

    @Test("maxContextLength falls back to top-level max_position_embeddings")
    func maxContextLength_fromTopLevel() {
        let config = HFModelConfig(maxPositionEmbeddings: 65536)
        let model = HFModelInfo(id: "test/model", author: "test", config: config)
        #expect(model.maxContextLength == 65536)
    }

    @Test("maxContextLength falls back to GGUF context_length")
    func maxContextLength_fromGGUF() {
        let model = HFModelInfo(
            id: "test/model", author: "test",
            gguf: HFGGUFInfo(total: nil, architecture: nil, contextLength: 8192)
        )
        #expect(model.maxContextLength == 8192)
    }

    @Test("maxContextLength nil when no data available")
    func maxContextLength_nil() {
        let model = HFModelInfo(id: "test/model", author: "test")
        #expect(model.maxContextLength == nil)
    }

    // MARK: - Architecture Properties

    @Test("isMoE true when enable_moe_block is true")
    func isMoE_true() {
        let config = HFModelConfig(
            textConfig: HFTextConfig(
                hiddenSize: nil, numHiddenLayers: nil,
                numAttentionHeads: nil, numKeyValueHeads: nil,
                intermediateSize: nil, vocabSize: nil,
                maxPositionEmbeddings: nil, slidingWindow: nil,
                headDim: nil, torchDtype: nil,
                enableMoeBlock: true, modelType: nil
            )
        )
        let model = HFModelInfo(id: "test/model", author: "test", config: config)
        #expect(model.isMoE)
    }

    @Test("isMoE false when enable_moe_block is nil")
    func isMoE_falseNil() {
        let config = HFModelConfig(
            textConfig: HFTextConfig(
                hiddenSize: 2304, numHiddenLayers: nil,
                numAttentionHeads: nil, numKeyValueHeads: nil,
                intermediateSize: nil, vocabSize: nil,
                maxPositionEmbeddings: nil, slidingWindow: nil,
                headDim: nil, torchDtype: nil,
                enableMoeBlock: nil, modelType: nil
            )
        )
        let model = HFModelInfo(id: "test/model", author: "test", config: config)
        #expect(!model.isMoE)
    }

    @Test("dtype from torch_dtype")
    func dtype_fromTorchDtype() {
        let config = HFModelConfig(torchDtype: "bfloat16")
        let model = HFModelInfo(id: "test/model", author: "test", config: config)
        #expect(model.dtype == "bfloat16")
    }

    @Test("dtype falls back to text_config.torch_dtype")
    func dtype_fromTextConfig() {
        let config = HFModelConfig(
            textConfig: HFTextConfig(
                hiddenSize: nil, numHiddenLayers: nil,
                numAttentionHeads: nil, numKeyValueHeads: nil,
                intermediateSize: nil, vocabSize: nil,
                maxPositionEmbeddings: nil, slidingWindow: nil,
                headDim: nil, torchDtype: "float16",
                enableMoeBlock: nil, modelType: nil
            )
        )
        let model = HFModelInfo(id: "test/model", author: "test", config: config)
        #expect(model.dtype == "float16")
    }

    // MARK: - Expanded API Fields

    @Test("Decodes expanded API fields (sha, trendingScore, downloadsAllTime)")
    func expandedFields_decode() throws {
        let json = """
        {
            "id": "test/model",
            "sha": "abc123def456",
            "trendingScore": 42.5,
            "downloadsAllTime": 1000000,
            "disabled": false,
            "createdAt": "2026-01-15T10:00:00.000Z"
        }
        """
        let data = Data(json.utf8)
        let model = try JSONDecoder().decode(HFModelInfo.self, from: data)
        #expect(model.sha == "abc123def456")
        #expect(model.trendingScore == 42.5)
        #expect(model.downloadsAllTime == 1000000)
        #expect(model.disabled == false)
        #expect(model.createdAt == "2026-01-15T10:00:00.000Z")
    }

    @Test("Expanded fields nil when not present (backward compat)")
    func expandedFields_nilWhenMissing() throws {
        let json = """
        {
            "id": "test/model"
        }
        """
        let data = Data(json.utf8)
        let model = try JSONDecoder().decode(HFModelInfo.self, from: data)
        #expect(model.sha == nil)
        #expect(model.trendingScore == nil)
        #expect(model.downloadsAllTime == nil)
        #expect(model.disabled == nil)
    }

    @Test("Roundtrip encode/decode preserves expanded fields")
    func expandedFields_roundtrip() throws {
        let original = HFModelInfo(
            id: "test/model", author: "test",
            sha: "abc123", trendingScore: 99.9,
            downloadsAllTime: 5_000_000, disabled: false
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HFModelInfo.self, from: data)
        #expect(decoded.sha == "abc123")
        #expect(decoded.trendingScore == 99.9)
        #expect(decoded.downloadsAllTime == 5_000_000)
        #expect(decoded.disabled == false)
    }

    // MARK: - Full Integration: Gemma 4 E2B Standard Config

    @Test("Full Gemma 4 E2B Standard config.json decodes and exposes all capabilities")
    func fullGemma4E2B_integration() throws {
        // Realistic config.json structure based on real Gemma 4 E2B models
        let json = """
        {
            "architectures": ["Gemma4ForConditionalGeneration"],
            "model_type": "gemma4",
            "torch_dtype": "bfloat16",
            "image_token_id": 262145,
            "audio_token_id": 262146,
            "text_config": {
                "hidden_size": 2304,
                "num_hidden_layers": 34,
                "num_attention_heads": 8,
                "num_key_value_heads": 4,
                "intermediate_size": 9216,
                "vocab_size": 262144,
                "max_position_embeddings": 131072,
                "sliding_window": 512,
                "head_dim": 256,
                "torch_dtype": "bfloat16",
                "enable_moe_block": true,
                "model_type": "gemma4_text"
            },
            "vision_config": {
                "hidden_size": 1152,
                "num_hidden_layers": 27,
                "image_size": 896,
                "patch_size": 14,
                "num_attention_heads": 16,
                "model_type": "siglip_vision_model"
            },
            "audio_config": {
                "hidden_size": 1536,
                "num_hidden_layers": 32,
                "num_attention_heads": 24,
                "model_type": "gemma4_audio"
            }
        }
        """
        let data = Data(json.utf8)
        let config = try JSONDecoder().decode(HFModelConfig.self, from: data)

        let model = HFModelInfo(
            id: "mlx-community/gemma-4-E2B-it-4bit",
            author: "mlx-community",
            tags: ["gemma-4", "mlx"],
            config: config,
            safetensors: HFSafetensorsInfo(parameters: ["BF16": 617219651], total: 1196197443)
        )

        // Capability signals
        #expect(model.hasVisionSupport)
        #expect(model.hasAudioSupport)
        #expect(model.isMoE)
        #expect(model.maxContextLength == 131072)
        #expect(model.maxImageResolution == 896)
        #expect(model.dtype == "bfloat16")
        #expect(model.numLayers == 34)
        #expect(model.hiddenSize == 2304)
        #expect(model.numAttentionHeads == 8)
        #expect(model.vocabSize == 262144)
        #expect(model.totalParameters == 1196197443)
    }

    @Test("Web variant: text-only Gemma 4 E2B — no vision or audio")
    func webVariant_textOnly() throws {
        let json = """
        {
            "architectures": ["Gemma4ForCausalLM"],
            "model_type": "gemma4",
            "text_config": {
                "hidden_size": 2304,
                "max_position_embeddings": 131072,
                "enable_moe_block": true
            }
        }
        """
        let data = Data(json.utf8)
        let config = try JSONDecoder().decode(HFModelConfig.self, from: data)

        let model = HFModelInfo(
            id: "litert-community/gemma-4-E2B-it-web-litert-lm",
            author: "litert-community",
            config: config
        )

        // Web variant — no multimodal
        #expect(!model.hasVisionSupport)
        #expect(!model.hasAudioSupport)
        #expect(model.isMoE)
        #expect(model.maxContextLength == 131072)
        #expect(model.maxImageResolution == nil)
    }
}
