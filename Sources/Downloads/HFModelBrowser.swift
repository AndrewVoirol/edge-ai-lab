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
import Observation
import os

// MARK: - HuggingFace API Enrichment Types

// MARK: - Config Sub-Objects

/// Text (language model) configuration from a model's `config.json` → `text_config`.
///
/// Contains the core transformer architecture parameters. The `maxPositionEmbeddings` field
/// is the **authoritative** source for the model's maximum context window — more reliable
/// than any heuristic or API metadata.
///
/// Per AGENTS.md: all fields MUST be optional — external APIs change without notice.
struct HFTextConfig: Codable, Sendable, Hashable {
    /// Hidden dimension size (e.g., 2304 for Gemma 4 E2B).
    let hiddenSize: Int?
    /// Number of transformer layers (e.g., 34 for Gemma 4 E2B).
    let numHiddenLayers: Int?
    /// Number of attention heads (e.g., 8).
    let numAttentionHeads: Int?
    /// Number of key-value heads for GQA (e.g., 4).
    let numKeyValueHeads: Int?
    /// FFN intermediate dimension (e.g., 9216).
    let intermediateSize: Int?
    /// Vocabulary size (e.g., 262144 for Gemma 4).
    let vocabSize: Int?
    /// Maximum position embeddings — the authoritative context window size.
    let maxPositionEmbeddings: Int?
    /// Sliding window attention size, if applicable.
    let slidingWindow: Int?
    /// Per-head dimension (e.g., 256).
    let headDim: Int?
    /// PyTorch dtype used for weights (e.g., "bfloat16").
    let torchDtype: String?
    /// Whether MoE (Mixture of Experts) blocks are enabled.
    let enableMoeBlock: Bool?
    /// Model type for the text sub-model (e.g., "gemma4_text").
    let modelType: String?

    enum CodingKeys: String, CodingKey {
        case hiddenSize = "hidden_size"
        case numHiddenLayers = "num_hidden_layers"
        case numAttentionHeads = "num_attention_heads"
        case numKeyValueHeads = "num_key_value_heads"
        case intermediateSize = "intermediate_size"
        case vocabSize = "vocab_size"
        case maxPositionEmbeddings = "max_position_embeddings"
        case slidingWindow = "sliding_window"
        case headDim = "head_dim"
        case torchDtype = "torch_dtype"
        case enableMoeBlock = "enable_moe_block"
        case modelType = "model_type"
    }
}

/// Vision encoder configuration from a model's `config.json` → `vision_config`.
///
/// Presence of this sub-object is a strong signal that the model supports image input.
/// The `imageSize` field indicates the maximum input image resolution the model was
/// trained on.
struct HFVisionConfig: Codable, Sendable, Hashable {
    /// Hidden dimension size for the vision encoder.
    let hiddenSize: Int?
    /// Number of vision transformer layers.
    let numHiddenLayers: Int?
    /// Maximum input image resolution (e.g., 896 for SigLIP).
    let imageSize: Int?
    /// Patch size for the ViT backbone (e.g., 14).
    let patchSize: Int?
    /// Number of attention heads in the vision encoder.
    let numAttentionHeads: Int?
    /// Vision model type (e.g., "siglip_vision_model").
    let modelType: String?

    enum CodingKeys: String, CodingKey {
        case hiddenSize = "hidden_size"
        case numHiddenLayers = "num_hidden_layers"
        case imageSize = "image_size"
        case patchSize = "patch_size"
        case numAttentionHeads = "num_attention_heads"
        case modelType = "model_type"
    }
}

/// Audio encoder configuration from a model's `config.json` → `audio_config`.
///
/// Presence of this sub-object is a strong signal that the model supports audio input.
struct HFAudioConfig: Codable, Sendable, Hashable {
    /// Hidden dimension size for the audio encoder.
    let hiddenSize: Int?
    /// Number of audio transformer layers.
    let numHiddenLayers: Int?
    /// Number of attention heads in the audio encoder.
    let numAttentionHeads: Int?
    /// Audio model type (e.g., "gemma4_audio").
    let modelType: String?

    enum CodingKeys: String, CodingKey {
        case hiddenSize = "hidden_size"
        case numHiddenLayers = "num_hidden_layers"
        case numAttentionHeads = "num_attention_heads"
        case modelType = "model_type"
    }
}

// MARK: - HFModelConfig

/// Inline model configuration from the HuggingFace API.
///
/// When a model repository contains a `config.json`, the HuggingFace API inlines its contents
/// in the `/api/models/{id}` response. This is the full model architecture configuration.
///
/// **Not all repos have this.** LiteRT-LM repos typically omit `config.json` entirely, so
/// `HFModelInfo.config` will be `nil` for those. MLX and GGUF repos reliably include it.
///
/// The sub-config objects (`textConfig`, `visionConfig`, `audioConfig`) provide authoritative
/// architecture details and capability signals that are more reliable than tag-based heuristics.
///
/// Per AGENTS.md: all fields MUST be optional — external APIs change without notice.
struct HFModelConfig: Codable, Sendable, Hashable {
    /// Model architecture classes (e.g., `["Gemma4ForConditionalGeneration"]`).
    let architectures: [String]?
    /// Model type identifier (e.g., `"gemma4"`, `"llama"`).
    let modelType: String?
    /// Quantization configuration, present for quantized models (e.g., MLX 4-bit).
    let quantizationConfig: HFQuantizationConfig?
    /// Tokenizer configuration with special token definitions.
    let tokenizerConfig: HFTokenizerConfig?

    // MARK: - Architecture Sub-Configs (from config.json)

    /// Text (language model) architecture configuration.
    /// Contains hidden size, attention heads, vocab size, and critically,
    /// `maxPositionEmbeddings` — the authoritative context window.
    let textConfig: HFTextConfig?

    /// Vision encoder configuration. Presence indicates image input support.
    let visionConfig: HFVisionConfig?

    /// Audio encoder configuration. Presence indicates audio input support.
    let audioConfig: HFAudioConfig?

    // MARK: - Top-Level Config Fields

    /// Image token ID — presence is a strong signal for vision support.
    let imageTokenId: Int?

    /// Audio token ID — presence is a strong signal for audio support.
    let audioTokenId: Int?

    /// PyTorch dtype for model weights (e.g., "bfloat16", "float16").
    let torchDtype: String?

    /// Maximum position embeddings at the top level (some models put it here
    /// instead of in text_config).
    let maxPositionEmbeddings: Int?

    enum CodingKeys: String, CodingKey {
        case architectures
        case modelType = "model_type"
        case quantizationConfig = "quantization_config"
        case tokenizerConfig = "tokenizer_config"
        case textConfig = "text_config"
        case visionConfig = "vision_config"
        case audioConfig = "audio_config"
        case imageTokenId = "image_token_id"
        case audioTokenId = "audio_token_id"
        case torchDtype = "torch_dtype"
        case maxPositionEmbeddings = "max_position_embeddings"
    }

    /// Memberwise init with backward-compatible defaults for new fields.
    init(architectures: [String]? = nil, modelType: String? = nil,
         quantizationConfig: HFQuantizationConfig? = nil,
         tokenizerConfig: HFTokenizerConfig? = nil,
         textConfig: HFTextConfig? = nil,
         visionConfig: HFVisionConfig? = nil,
         audioConfig: HFAudioConfig? = nil,
         imageTokenId: Int? = nil, audioTokenId: Int? = nil,
         torchDtype: String? = nil, maxPositionEmbeddings: Int? = nil) {
        self.architectures = architectures
        self.modelType = modelType
        self.quantizationConfig = quantizationConfig
        self.tokenizerConfig = tokenizerConfig
        self.textConfig = textConfig
        self.visionConfig = visionConfig
        self.audioConfig = audioConfig
        self.imageTokenId = imageTokenId
        self.audioTokenId = audioTokenId
        self.torchDtype = torchDtype
        self.maxPositionEmbeddings = maxPositionEmbeddings
    }
}

/// Quantization configuration from a model's `config.json`.
///
/// Present for quantized models (e.g., MLX 4-bit models include `{"bits": 4}`).
struct HFQuantizationConfig: Codable, Sendable, Hashable {
    /// Number of bits used for quantization (e.g., 4 for 4-bit).
    let bits: Int?
    /// Quantization method identifier (e.g., `"awq"`, `"gptq"`).
    let quantMethod: String?

    enum CodingKeys: String, CodingKey {
        case bits
        case quantMethod = "quant_method"
    }
}

/// Tokenizer configuration from a model's `config.json`.
struct HFTokenizerConfig: Codable, Sendable, Hashable {
    /// Beginning-of-sequence token.
    let bosToken: String?
    /// End-of-sequence token.
    let eosToken: String?

    enum CodingKeys: String, CodingKey {
        case bosToken = "bos_token"
        case eosToken = "eos_token"
    }
}

/// Safetensors metadata from the HuggingFace API.
///
/// Only present for repos containing `.safetensors` files (MLX, transformers).
/// Provides the most reliable source for exact parameter counts.
///
/// Example API response:
/// ```json
/// {
///   "parameters": {"BF16": 617219651, "U32": 578977792},
///   "total": 1196197443
/// }
/// ```
struct HFSafetensorsInfo: Codable, Sendable, Hashable {
    /// Parameter counts by dtype (e.g., `{"BF16": 617219651, "U32": 578977792}`).
    let parameters: [String: Int64]?
    /// Total parameters across all dtypes.
    let total: Int64?
}

/// GGUF metadata from the HuggingFace API.
///
/// Only present for GGUF repositories. Provides architecture, context length,
/// and total file size — data that would otherwise require parsing the GGUF header.
///
/// Example API response:
/// ```json
/// {
///   "total": 4647450147,
///   "architecture": "gemma4",
///   "context_length": 131072
/// }
/// ```
struct HFGGUFInfo: Codable, Sendable, Hashable {
    /// Total size across all GGUF files in the repository, in bytes.
    let total: Int64?
    /// Architecture identifier (e.g., `"gemma4"`, `"llama"`).
    let architecture: String?
    /// Maximum context length in tokens (e.g., `131072`).
    let contextLength: Int?

    enum CodingKeys: String, CodingKey {
        case total, architecture
        case contextLength = "context_length"
    }
}

/// Parsed YAML frontmatter from a model's README.md.
///
/// The HuggingFace API parses the YAML frontmatter and returns it as structured JSON.
/// Contains license, base model, tags, and other metadata declared by the model author.
struct HFCardData: Codable, Sendable, Hashable {
    /// License identifier (e.g., `"apache-2.0"`, `"gemma"`).
    let license: String?
    /// URL to the full license text.
    let licenseLink: String?
    /// Base model(s) this model was derived from.
    /// Can be a single string or array of strings in the HF API — decoded via `HFFlexibleStringArray`.
    let baseModel: HFFlexibleStringArray?
    /// Tags declared in the model card frontmatter.
    let tags: [String]?
    /// Pipeline tag from the model card (e.g., `"image-text-to-text"`).
    let pipelineTag: String?
    /// Training datasets used.
    let datasets: HFFlexibleStringArray?
    /// Languages the model supports.
    let language: HFFlexibleStringArray?
    /// Library name from card metadata.
    let libraryName: String?

    enum CodingKeys: String, CodingKey {
        case license
        case licenseLink = "license_link"
        case baseModel = "base_model"
        case tags
        case pipelineTag = "pipeline_tag"
        case datasets
        case language
        case libraryName = "library_name"
    }
}

/// A flexible decoder for HuggingFace fields that can be either a single string or an array of strings.
///
/// The HuggingFace API is inconsistent: `base_model`, `language`, and `datasets` may appear as
/// `"value"` (a single string) or `["value1", "value2"]` (an array). This type normalizes both
/// shapes to `[String]` for uniform downstream access.
///
/// Usage:
/// ```swift
/// let languages = cardData.language?.values ?? []  // Always [String]
/// let baseModel = cardData.baseModel?.first        // First value or nil
/// ```
struct HFFlexibleStringArray: Codable, Sendable, Hashable {
    /// The normalized array of values.
    let values: [String]

    /// The first value, or nil if empty.
    var first: String? { values.first }

    init(values: [String]) {
        self.values = values
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Try array first, then single string
        if let array = try? container.decode([String].self) {
            values = array
        } else if let single = try? container.decode(String.self) {
            values = [single]
        } else {
            values = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}

/// Flexible decoder for the HuggingFace `gated` field.
///
/// The HuggingFace API returns `gated` as:
/// - `false` (Bool) — model is not gated
/// - `"auto"` (String) — auto-gated, requires token
/// - `"manual"` (String) — manually gated, requires approval
///
/// This type normalizes the polymorphic JSON to a consistent Swift type.
enum HFGatedStatus: Codable, Sendable, Hashable {
    case notGated
    case auto
    case manual
    case unknown(String)

    /// Whether the model requires any form of gating/authentication.
    var isGated: Bool {
        switch self {
        case .notGated: return false
        case .auto, .manual, .unknown: return true
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let boolValue = try? container.decode(Bool.self) {
            self = boolValue ? .unknown("true") : .notGated
        } else if let stringValue = try? container.decode(String.self) {
            switch stringValue.lowercased() {
            case "auto": self = .auto
            case "manual": self = .manual
            case "false": self = .notGated
            default: self = .unknown(stringValue)
            }
        } else {
            self = .notGated
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .notGated: try container.encode(false)
        case .auto: try container.encode("auto")
        case .manual: try container.encode("manual")
        case .unknown(let value): try container.encode(value)
        }
    }
}

// MARK: - HuggingFace API Response Models

/// Metadata for a single model returned by the HuggingFace API.
///
/// Maps to the JSON response from `GET /api/models/{id}` and `GET /api/models?author=...`.
/// Uses `CodingKeys` to bridge between the API's snake_case field names and Swift conventions.
///
/// Example API response fields:
/// ```json
/// {
///   "id": "litert-community/gemma-4-E2B-it-litert-lm",
///   "author": "litert-community",
///   "lastModified": "2026-06-01T12:00:00.000Z",
///   "downloads": 12345,
///   "likes": 42,
///   "tags": ["gemma-4", "litert", "text-generation"],
///   "pipeline_tag": "text-generation",
///   "library_name": "litert",
///   "siblings": [...]
/// }
/// ```
struct HFModelInfo: Codable, Sendable, Identifiable, Hashable {

    // MARK: - Hashable / Equatable (identity = repo ID only)

    static func == (lhs: HFModelInfo, rhs: HFModelInfo) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// The full repository ID (e.g., "litert-community/gemma-4-E2B-it-litert-lm").
    let id: String

    /// The organization or user that owns the repository.
    /// May be absent from the list endpoint — falls back to parsing from `id`.
    let author: String

    /// ISO-8601 timestamp of the last modification.
    /// May be absent from the list endpoint.
    let lastModified: String

    /// Total download count reported by HuggingFace.
    let downloads: Int

    /// Number of likes on the model page.
    let likes: Int

    /// Tags attached to the model (e.g., "gemma-4", "litert", "text-generation").
    let tags: [String]

    /// The pipeline tag (e.g., "text-generation", "image-classification").
    let pipelineTag: String?

    /// The library name (e.g., "litert", "transformers", "mlx").
    let libraryName: String?

    /// File listing for the repository. Only populated on detail endpoint responses.
    let siblings: [HFSibling]?

    /// Inline model configuration (from the repo's config.json).
    /// Only present for repos that contain a config.json (MLX, GGUF — NOT LiteRT-LM).
    let config: HFModelConfig?

    /// Safetensors metadata with exact parameter counts.
    /// Only present for repos containing .safetensors files.
    let safetensors: HFSafetensorsInfo?

    /// GGUF metadata including architecture, context length, and total size.
    /// Only present for GGUF repositories.
    let gguf: HFGGUFInfo?

    /// Parsed YAML frontmatter from the model's README.md.
    let cardData: HFCardData?

    /// Gating status — whether the model requires authentication or approval.
    let gated: HFGatedStatus?

    /// Total storage used by all files in the repository, in bytes.
    let usedStorage: Int64?

    // MARK: - Expanded API Fields (via expand[] parameters)

    /// ISO-8601 timestamp when the model was first created on HuggingFace.
    let createdAt: String?

    /// Git commit SHA of the latest revision.
    let sha: String?

    /// Trending score — measures recent popularity velocity.
    let trendingScore: Double?

    /// Cumulative all-time download count.
    let downloadsAllTime: Int?

    /// Whether the model has been disabled by HuggingFace.
    let disabled: Bool?

    enum CodingKeys: String, CodingKey {
        case id, author, lastModified, downloads, likes, tags, siblings
        case pipelineTag = "pipeline_tag"
        case libraryName = "library_name"
        case createdAt, sha
        case trendingScore, downloadsAllTime, disabled
        case config, safetensors, gguf, cardData, gated, usedStorage
    }

    /// Custom decoder to handle missing fields from the HF list endpoint.
    /// The list endpoint omits `author`, `lastModified`, and sometimes other fields.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        // author may be missing from list endpoint — parse from id ("org/repo" → "org")
        author = (try? container.decode(String.self, forKey: .author))
            ?? String(id.split(separator: "/").first ?? Substring(id))
        // lastModified may be missing — fall back to createdAt or empty
        lastModified = (try? container.decode(String.self, forKey: .lastModified))
            ?? (try? container.decode(String.self, forKey: .createdAt))
            ?? ""
        downloads = (try? container.decode(Int.self, forKey: .downloads)) ?? 0
        likes = (try? container.decode(Int.self, forKey: .likes)) ?? 0
        tags = (try? container.decode([String].self, forKey: .tags)) ?? []
        pipelineTag = try? container.decode(String.self, forKey: .pipelineTag)
        libraryName = try? container.decode(String.self, forKey: .libraryName)
        siblings = try? container.decode([HFSibling].self, forKey: .siblings)
        config = try? container.decode(HFModelConfig.self, forKey: .config)
        safetensors = try? container.decode(HFSafetensorsInfo.self, forKey: .safetensors)
        gguf = try? container.decode(HFGGUFInfo.self, forKey: .gguf)
        cardData = try? container.decode(HFCardData.self, forKey: .cardData)
        gated = try? container.decode(HFGatedStatus.self, forKey: .gated)
        usedStorage = try? container.decode(Int64.self, forKey: .usedStorage)
        // Expanded fields — may not be present without expand[] parameters
        createdAt = try? container.decode(String.self, forKey: .createdAt)
        sha = try? container.decode(String.self, forKey: .sha)
        trendingScore = try? container.decode(Double.self, forKey: .trendingScore)
        downloadsAllTime = try? container.decode(Int.self, forKey: .downloadsAllTime)
        disabled = try? container.decode(Bool.self, forKey: .disabled)
    }

    /// Custom encoder — only encodes stored properties (skips `createdAt` decode-only key).
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(author, forKey: .author)
        try container.encode(lastModified, forKey: .lastModified)
        try container.encode(downloads, forKey: .downloads)
        try container.encode(likes, forKey: .likes)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(pipelineTag, forKey: .pipelineTag)
        try container.encodeIfPresent(libraryName, forKey: .libraryName)
        try container.encodeIfPresent(siblings, forKey: .siblings)
        try container.encodeIfPresent(config, forKey: .config)
        try container.encodeIfPresent(safetensors, forKey: .safetensors)
        try container.encodeIfPresent(gguf, forKey: .gguf)
        try container.encodeIfPresent(cardData, forKey: .cardData)
        try container.encodeIfPresent(gated, forKey: .gated)
        try container.encodeIfPresent(usedStorage, forKey: .usedStorage)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(sha, forKey: .sha)
        try container.encodeIfPresent(trendingScore, forKey: .trendingScore)
        try container.encodeIfPresent(downloadsAllTime, forKey: .downloadsAllTime)
        try container.encodeIfPresent(disabled, forKey: .disabled)
    }

    /// Memberwise init for tests and previews.
    init(id: String, author: String, lastModified: String = "",
         downloads: Int = 0, likes: Int = 0, tags: [String] = [],
         pipelineTag: String? = nil, libraryName: String? = nil,
         siblings: [HFSibling]? = nil,
         config: HFModelConfig? = nil, safetensors: HFSafetensorsInfo? = nil,
         gguf: HFGGUFInfo? = nil, cardData: HFCardData? = nil,
         gated: HFGatedStatus? = nil, usedStorage: Int64? = nil,
         createdAt: String? = nil, sha: String? = nil,
         trendingScore: Double? = nil, downloadsAllTime: Int? = nil,
         disabled: Bool? = nil) {
        self.id = id
        self.author = author
        self.lastModified = lastModified
        self.downloads = downloads
        self.likes = likes
        self.tags = tags
        self.pipelineTag = pipelineTag
        self.libraryName = libraryName
        self.siblings = siblings
        self.config = config
        self.safetensors = safetensors
        self.gguf = gguf
        self.cardData = cardData
        self.gated = gated
        self.usedStorage = usedStorage
        self.createdAt = createdAt
        self.sha = sha
        self.trendingScore = trendingScore
        self.downloadsAllTime = downloadsAllTime
        self.disabled = disabled
    }
}


// MARK: - HFSibling

/// A single file entry within a HuggingFace repository.
///
/// Returned as part of the `siblings` array on `HFModelInfo`.
/// The `lfs` field is present when the file is stored via Git LFS (large files).
struct HFSibling: Codable, Sendable {

    /// Relative filename within the repository (e.g., "gemma-4-E2B-it.litertlm").
    let rfilename: String

    /// File size in bytes. May be nil for non-LFS files in list responses.
    let size: Int64?

    /// Git LFS metadata, present only for LFS-tracked files.
    let lfs: HFLFSInfo?
}

// MARK: - HFLFSInfo

/// Git LFS metadata for a file in a HuggingFace repository.
///
/// When a file is tracked by Git LFS, the actual content is stored externally.
/// The `size` here is the real file size, while `pointerSize` is the size of the
/// LFS pointer file in the Git repository.
struct HFLFSInfo: Codable, Sendable {

    /// The LFS object ID (SHA-256 hash of the file content).
    let oid: String

    /// Actual file size in bytes (the real content, not the pointer).
    let size: Int64

    /// Size of the LFS pointer file in bytes.
    /// Not always present in the HuggingFace API response.
    let pointerSize: Int?

    enum CodingKeys: String, CodingKey {
        case oid, size
        case pointerSize = "pointer_size"
    }
}

// MARK: - HFTreeEntry

/// A file entry from the HuggingFace repository tree API.
///
/// Returned by `GET /api/models/{id}/tree/{revision}`. Unlike `HFSibling` (from the
/// model detail endpoint), this includes the entry `type` (file vs directory) and
/// the `oid` directly on the entry for non-LFS files.
///
/// Example API response entry:
/// ```json
/// {
///   "type": "file",
///   "oid": "abc123...",
///   "size": 4200000000,
///   "path": "model-00001-of-00003.safetensors",
///   "lfs": {
///     "oid": "sha256:abc123...",
///     "size": 4200000000,
///     "pointerSize": 135
///   }
/// }
/// ```
struct HFTreeEntry: Codable, Sendable {

    /// Entry type: "file" or "directory".
    let type: String

    /// Object ID (Git blob hash for regular files, LFS OID for LFS files).
    let oid: String?

    /// File size in bytes. For LFS files, this is the pointer file size.
    let size: Int64?

    /// Relative path within the repository (e.g., "model-00001-of-00003.safetensors").
    let path: String

    /// Git LFS metadata, present only for LFS-tracked files.
    /// When present, `lfs.size` is the actual file size and `lfs.oid` is the SHA-256 hash.
    let lfs: HFTreeLFSInfo?
}

// MARK: - HFTreeLFSInfo

/// Git LFS metadata from the tree API response.
///
/// Similar to `HFLFSInfo` but uses a slightly different field naming convention
/// in the tree endpoint response.
struct HFTreeLFSInfo: Codable, Sendable {

    /// The SHA-256 hash of the file content (the LFS object identifier).
    let oid: String

    /// Actual file size in bytes.
    let size: Int64

    /// Size of the LFS pointer file in the Git repository.
    /// Not always present in the HuggingFace API response.
    let pointerSize: Int?

    enum CodingKeys: String, CodingKey {
        case oid, size
        case pointerSize = "pointer_size"
    }
}

// MARK: - Model Format Detection

/// Detected model format based on file contents of a HuggingFace repository.
///
/// Used to determine which runtime engine a discovered model requires:
/// - `.litertlm`: Google's LiteRT-LM format — runs via the LiteRT engine.
/// - `.mlx`: Apple MLX format — requires the MLX Swift runtime.
/// - `.unknown`: Format could not be determined from the file listing.
enum HFModelFormat: String, Sendable {
    /// LiteRT-LM packaged model (single `.litertlm` archive).
    case litertlm
    /// MLX model directory (contains `config.json` + `*.safetensors` weight shards).
    case mlx
    /// GGUF quantized model file (llama.cpp compatible).
    case gguf
    /// Format could not be determined from the repository file listing.
    case unknown
}

// MARK: - HFModelBrowser Errors

/// Errors specific to HuggingFace API operations.
enum HFModelBrowserError: LocalizedError {
    case invalidURL(String)
    case httpError(statusCode: Int, repoId: String)
    case httpStatusError(statusCode: Int)
    case invalidResponse
    case decodingFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid HuggingFace API URL: \(url)"
        case .httpError(let statusCode, let repoId):
            return "HuggingFace API returned HTTP \(statusCode) for \(repoId)."
        case .httpStatusError(let statusCode):
            return "HuggingFace API returned HTTP \(statusCode)."
        case .invalidResponse:
            return "HuggingFace API returned an invalid response."
        case .decodingFailed(let underlying):
            return "Failed to decode HuggingFace API response: \(underlying.localizedDescription)"
        }
    }
}

// MARK: - HFModelBrowser

/// Client for the HuggingFace Models API, used to discover and inspect models.
///
/// **Usage:**
/// ```swift
/// let browser = HFModelBrowser()
/// await browser.refreshGemmaModels()
/// for model in browser.discoveredModels {
///     print("\(model.displayName) — \(browser.detectFormat(model))")
/// }
/// ```
///
/// **Authentication:** If a HuggingFace token is stored via `HFTokenStorage`,
/// all API requests include a Bearer token header. This is required for gated
/// models (e.g., `google/*` repos) but optional for public repos like
/// `litert-community`.
///
/// **Caching:** List results are cached in-memory by organization name to avoid
/// redundant API calls during a session. The cache is cleared when the browser
/// is deallocated.
@Observable
final class HFModelBrowser: @unchecked Sendable {

    // MARK: - Constants

    /// Base URL for the HuggingFace models API.
    private static let apiBaseURL = "https://huggingface.co/api/models"

    /// Base URL for file downloads (resolve endpoint).
    private static let resolveBaseURL = "https://huggingface.co"

    /// Logger for network retry diagnostics.
    private static let logger = Logger(
        subsystem: "com.andrewvoirol.EdgeAILab",
        category: "hfModelBrowser"
    )

    // MARK: - Published State

    /// Models discovered by the most recent `refreshGemmaModels()` call.
    /// Updated on the MainActor.
    var discoveredModels: [HFModelInfo] = []

    /// Whether a fetch operation is currently in progress.
    var isLoading: Bool = false

    /// Human-readable description of the last error, or nil if the last operation succeeded.
    var lastError: String?

    // MARK: - Private State

    /// In-memory cache of list results, keyed by organization/author name.
    /// Protected by `cacheLock` to prevent data races between async network
    /// callbacks and SwiftUI's MainActor observation.
    private var _cache: [String: [HFModelInfo]] = [:]
    private let cacheLock = NSLock()

    /// Thread-safe cache read.
    private func cacheRead(_ key: String) -> [HFModelInfo]? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return _cache[key]
    }

    /// Thread-safe cache write.
    private func cacheWrite(_ key: String, _ value: [HFModelInfo]) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        _cache[key] = value
    }

    /// Thread-safe cache clear.
    private func cacheClear() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        _cache.removeAll()
    }

    /// Shared JSON decoder configured for HuggingFace API responses.
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        // Note: We use explicit CodingKeys for snake_case fields (pipeline_tag, library_name,
        // pointer_size) rather than .convertFromSnakeCase, because lastModified arrives as
        // camelCase from the API and would be broken by the blanket conversion strategy.
        return decoder
    }()

    // MARK: - Retry Logic

    /// Execute a URL request with retry and exponential backoff.
    /// Retries on 429 (rate limit) and 5xx (server error) responses.
    /// - Parameters:
    ///   - request: The URL request to execute.
    ///   - maxRetries: Maximum number of retry attempts (default: 3).
    ///   - baseDelay: Base delay in seconds before first retry (default: 1.0).
    /// - Returns: The response data and HTTP response.
    /// - Throws: The last error if all retries fail.
    private func performWithRetry(
        _ request: URLRequest,
        maxRetries: Int = 3,
        baseDelay: TimeInterval = 1.0
    ) async throws -> (Data, HTTPURLResponse) {
        var lastError: Error?

        for attempt in 0...maxRetries {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw HFModelBrowserError.invalidResponse
                }

                // Success
                if (200...299).contains(httpResponse.statusCode) {
                    return (data, httpResponse)
                }

                // Rate limit or server error — retry
                if httpResponse.statusCode == 429 || (500...599).contains(httpResponse.statusCode) {
                    if attempt < maxRetries {
                        let delay = baseDelay * pow(2.0, Double(attempt))
                        Self.logger.info("⏳ HTTP \(httpResponse.statusCode) — retrying in \(delay, privacy: .public)s (attempt \(attempt + 1)/\(maxRetries))")
                        try await Task.sleep(for: .seconds(delay))
                        continue
                    }
                }

                // Non-retryable error
                throw HFModelBrowserError.httpStatusError(statusCode: httpResponse.statusCode)
            } catch let error as HFModelBrowserError {
                lastError = error
                if attempt == maxRetries { throw error }
            } catch {
                lastError = error
                if attempt == maxRetries { throw error }
                // Network errors are retryable
                if attempt < maxRetries {
                    let delay = baseDelay * pow(2.0, Double(attempt))
                    Self.logger.info("⏳ Network error — retrying in \(delay, privacy: .public)s (attempt \(attempt + 1)/\(maxRetries))")
                    try await Task.sleep(for: .seconds(delay))
                }
            }
        }

        throw lastError ?? HFModelBrowserError.invalidResponse
    }

    // MARK: - List Models

    /// Fetch a list of models from a specific HuggingFace author/organization.
    ///
    /// Results are sorted by download count (descending) and cached in-memory
    /// by author name for the lifetime of this browser instance.
    ///
    /// - Parameters:
    ///   - author: The HuggingFace username or organization (e.g., "litert-community").
    ///   - search: Optional search query to filter model names.
    ///   - limit: Maximum number of results to return (default: 20).
    /// - Returns: An array of `HFModelInfo` matching the query.
    /// - Throws: `HFModelBrowserError` on network or decoding failures.
    func listModels(author: String, search: String? = nil, limit: Int = 20) async throws -> [HFModelInfo] {
        // Build cache key incorporating search to avoid stale results
        let cacheKey = search != nil ? "\(author):\(search!)" : author
        if let cached = cacheRead(cacheKey) {
            return cached
        }

        // Build URL with query parameters
        var components = URLComponents(string: Self.apiBaseURL)!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "author", value: author),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
        ]
        if let search = search {
            queryItems.append(URLQueryItem(name: "search", value: search))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw HFModelBrowserError.invalidURL(components.string ?? "nil")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        // Attach HF token if available (required for gated repos)
        if let token = HFTokenStorage.retrieve() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, _) = try await performWithRetry(request)

        do {
            let models = try decoder.decode([HFModelInfo].self, from: data)
            cacheWrite(cacheKey, models)
            return models
        } catch {
            throw HFModelBrowserError.decodingFailed(underlying: error)
        }
    }

    // MARK: - Model Detail

    /// Fetch full details for a specific model, including the file listing with sizes.
    ///
    /// Unlike `listModels`, the detail endpoint always returns the `siblings` array
    /// with LFS metadata, enabling file size inspection and format detection.
    ///
    /// - Parameter repoId: The full repository ID (e.g., "litert-community/gemma-4-E2B-it-litert-lm").
    /// - Returns: The full `HFModelInfo` with populated `siblings`.
    /// - Throws: `HFModelBrowserError` on network or decoding failures.
    func modelDetail(repoId: String) async throws -> HFModelInfo {
        let urlString = "\(Self.apiBaseURL)/\(repoId)"
        guard let url = URL(string: urlString) else {
            throw HFModelBrowserError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        // Attach HF token if available
        if let token = HFTokenStorage.retrieve() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, _) = try await performWithRetry(request)

        do {
            return try decoder.decode(HFModelInfo.self, from: data)
        } catch {
            throw HFModelBrowserError.decodingFailed(underlying: error)
        }
    }

    // MARK: - Full Config Fetch

    /// Fetch the complete `config.json` from a repository's files.
    ///
    /// The HuggingFace API inlines a subset of config.json in the model detail response,
    /// but it may be incomplete (especially for gated models). This method fetches the
    /// full config.json directly from the repository.
    ///
    /// Handles authentication gracefully:
    /// 1. Attempts fetch with stored HF token (if available)
    /// 2. Returns nil on 401/403 (gated model without valid token)
    /// 3. Returns nil on 404 (repo has no config.json — typical for LiteRT-LM)
    ///
    /// - Parameter repoId: The full repository ID.
    /// - Returns: The decoded `HFModelConfig`, or nil if unavailable.
    func fetchFullConfig(repoId: String) async -> HFModelConfig? {
        let urlString = "https://huggingface.co/\(repoId)/resolve/main/config.json"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        // Use existing Keychain-stored token for gated repos
        if let token = HFTokenStorage.retrieve() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            // Graceful degradation for auth/missing files
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200:
                    break  // Success — decode below
                case 401, 403:
                    Self.logger.info("⚠️ config.json fetch requires auth for \(repoId, privacy: .public)")
                    return nil
                case 404:
                    Self.logger.debug("ℹ️ No config.json in \(repoId, privacy: .public)")
                    return nil
                default:
                    Self.logger.warning("⚠️ config.json fetch HTTP \(httpResponse.statusCode) for \(repoId, privacy: .public)")
                    return nil
                }
            }

            return try decoder.decode(HFModelConfig.self, from: data)
        } catch {
            Self.logger.debug("ℹ️ config.json decode failed for \(repoId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Refresh Gemma Models

    /// Discover Gemma 4 models from known community organizations.
    ///
    /// Fetches from both `litert-community` (LiteRT-LM format) and `mlx-community`
    /// (MLX format), searching for the specified query. Results are merged, deduplicated
    /// by repo ID, and stored in `discoveredModels`.
    ///
    /// This method updates `isLoading` and `lastError` on the MainActor for UI binding.
    ///
    /// - Parameter searchQuery: Optional search query to broaden discovery beyond "gemma-4".
    ///   Defaults to "gemma-4" for backward compatibility.
    func refreshGemmaModels(searchQuery: String = "gemma-4") async {
        await MainActor.run {
            isLoading = true
            lastError = nil
        }

        do {
            async let litertModels = listModels(author: "litert-community", search: searchQuery)
            async let mlxModels = listModels(author: "mlx-community", search: searchQuery)

            let litert = try await litertModels
            let mlx = try await mlxModels

            // Merge results, litert-community first (primary format for this app)
            var merged: [HFModelInfo] = []
            var seenIds: Set<String> = []
            for model in litert + mlx {
                if seenIds.insert(model.id).inserted {
                    merged.append(model)
                }
            }

            let finalModels = merged
            await MainActor.run {
                discoveredModels = finalModels
                isLoading = false
            }
        } catch {
            await MainActor.run {
                lastError = error.localizedDescription
                isLoading = false
            }
        }
    }

    // MARK: - Freeform Search

    /// Search for models across all of HuggingFace (not limited to a specific author).
    ///
    /// Unlike `listModels(author:)`, this method searches globally. Results are sorted
    /// by download count (descending) and not cached (search results are inherently
    /// transient).
    ///
    /// - Parameters:
    ///   - query: The search query string.
    ///   - limit: Maximum number of results to return (default: 20).
    /// - Returns: An array of `HFModelInfo` matching the query.
    /// - Throws: `HFModelBrowserError` on network or decoding failures.
    func searchModels(query: String, limit: Int = 20) async throws -> [HFModelInfo] {
        var components = URLComponents(string: Self.apiBaseURL)!
        components.queryItems = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
        ]

        guard let url = components.url else {
            throw HFModelBrowserError.invalidURL(components.string ?? "nil")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        // Attach HF token if available
        if let token = HFTokenStorage.retrieve() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, _) = try await performWithRetry(request)

        do {
            return try decoder.decode([HFModelInfo].self, from: data)
        } catch {
            throw HFModelBrowserError.decodingFailed(underlying: error)
        }
    }

    // MARK: - Model Card (README)

    /// Fetch the README.md content for a HuggingFace model repository.
    ///
    /// Downloads the raw README content from the repository's `resolve/main/README.md`
    /// endpoint. This is used by `ModelCardParser` for deeper metadata inference.
    ///
    /// - Parameter repoId: The full repository ID (e.g., "litert-community/gemma-4-E2B-it-litert-lm").
    /// - Returns: The raw README.md content as a string.
    /// - Throws: `HFModelBrowserError` on network failures or if the README doesn't exist.
    func fetchModelCard(repoId: String) async throws -> String {
        let urlString = "\(Self.resolveBaseURL)/\(repoId)/resolve/main/README.md"
        guard let url = URL(string: urlString) else {
            throw HFModelBrowserError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        // Attach HF token if available
        if let token = HFTokenStorage.retrieve() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, _) = try await performWithRetry(request)

        guard let content = String(data: data, encoding: .utf8) else {
            throw HFModelBrowserError.decodingFailed(
                underlying: NSError(domain: "HFModelBrowser", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "README.md content is not valid UTF-8"])
            )
        }

        return content
    }

    /// Detect the model format from file listing, metadata, or naming conventions.
    ///
    /// Priority:
    /// 1. If `siblings` is populated, inspect filenames (.litertlm, .gguf, .safetensors)
    /// 2. Otherwise, infer from `libraryName` and `tags` metadata
    /// 3. Fall back to model ID pattern matching
    ///
    /// **MLX disambiguation:** `config.json + *.safetensors` alone does NOT indicate
    /// an MLX model — every raw transformers repo has the same layout. We require
    /// additional MLX signals (author, tags, library_name) to classify as MLX.
    func detectFormat(_ model: HFModelInfo) -> HFModelFormat {
        // 1. Check siblings if available (detail endpoint)
        if let siblings = model.siblings {
            let filenames = siblings.map(\.rfilename)

            if filenames.contains(where: { $0.hasSuffix(".litertlm") }) {
                return .litertlm
            }

            // Check for GGUF files
            if filenames.contains(where: { $0.hasSuffix(".gguf") }) {
                return .gguf
            }

            // config.json + safetensors requires positive MLX signal
            let hasConfig = filenames.contains("config.json")
            let hasSafetensors = filenames.contains(where: { $0.hasSuffix(".safetensors") })
            if hasConfig && hasSafetensors {
                let hasMLXSignal = model.author.lowercased() == "mlx-community"
                    || model.tags.contains(where: { $0.lowercased() == "mlx" })
                    || model.libraryName?.lowercased() == "mlx"
                    || model.id.lowercased().contains("-mlx")
                    || model.id.lowercased().contains("mlx-")
                if hasMLXSignal {
                    return .mlx
                }
                // No MLX signal — don't classify as MLX, fall through to metadata checks.
            }
        }

        // 2. Infer from library_name metadata (returned by list endpoint)
        if let lib = model.libraryName?.lowercased() {
            if lib.contains("litert") {
                return .litertlm
            }
            if lib == "mlx" {
                return .mlx
            }
            if lib == "gguf" || lib.contains("llama.cpp") {
                return .gguf
            }
        }

        // 3. Infer from tags
        if model.tags.contains(where: { $0.lowercased().contains("litert") }) {
            return .litertlm
        }
        if model.tags.contains(where: { $0.lowercased() == "mlx" }) {
            return .mlx
        }
        if model.tags.contains(where: { $0.lowercased() == "gguf" }) {
            return .gguf
        }

        // 4. Infer from model ID naming convention
        if model.id.lowercased().contains("litert-lm") || model.id.lowercased().contains("litert_lm") {
            return .litertlm
        }
        if model.author.lowercased() == "mlx-community"
            || model.id.lowercased().contains("-mlx")
            || model.id.lowercased().contains("mlx-") {
            return .mlx
        }
        if model.id.lowercased().contains("-gguf") || model.id.lowercased().hasSuffix(".gguf") {
            return .gguf
        }

        return .unknown
    }

    // MARK: - File Manifest (MLX Multi-File Downloads)

    /// Fetch the complete file listing for a model repository using the HF tree API.
    ///
    /// Endpoint: `GET https://huggingface.co/api/models/{id}/tree/main`
    ///
    /// This returns per-file metadata including sizes and LFS hashes, enabling
    /// manifest-first downloads where total size is known before downloading.
    ///
    /// - Parameter repoId: The full repository ID (e.g., "mlx-community/gemma-4-E2B-it-4bit").
    /// - Returns: An array of `HFTreeEntry` with file metadata.
    /// - Throws: `HFModelBrowserError` on network or decoding failures.
    func fetchFileManifest(for repoId: String) async throws -> [HFTreeEntry] {
        let urlString = "\(Self.apiBaseURL)/\(repoId)/tree/main"
        guard let url = URL(string: urlString) else {
            throw HFModelBrowserError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        // Attach HF token if available
        if let token = HFTokenStorage.retrieve() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, _) = try await performWithRetry(request)

        do {
            return try decoder.decode([HFTreeEntry].self, from: data)
        } catch {
            throw HFModelBrowserError.decodingFailed(underlying: error)
        }
    }

    /// Filter a file manifest to only the files required for an MLX model.
    ///
    /// Keeps: `config.json`, `tokenizer*.json`, `special_tokens_map.json`,
    /// `*.safetensors`, `*.safetensors.index.json`, `chat_template.jinja`,
    /// `processor_config.json`.
    /// Excludes: `*.gguf`, `*.bin`, `README.md`, `.gitattributes`, etc.
    ///
    /// - Parameter manifest: The full file listing from `fetchFileManifest`.
    /// - Returns: Only the files needed to run the MLX model.
    static func filterRequiredMLXFiles(_ manifest: [HFTreeEntry]) -> [HFTreeEntry] {
        let requiredPatterns: [(String) -> Bool] = [
            { $0 == "config.json" },
            { $0.hasPrefix("tokenizer") && $0.hasSuffix(".json") },
            { $0 == "special_tokens_map.json" },
            { $0 == "generation_config.json" },
            { $0.hasSuffix(".safetensors") },
            { $0.hasSuffix(".safetensors.index.json") },
            // Chat template — required for Gemma 4 and other models that store
            // their chat template in a standalone .jinja file rather than inline
            // in tokenizer_config.json.
            { $0 == "chat_template.jinja" || $0 == "chat_template.json" },
            // Processor config — required for VLM models (Gemma4, Paligemma, etc.)
            // that use a dedicated processor for input formatting.
            { $0 == "processor_config.json" || $0 == "preprocessor_config.json" },
        ]

        return manifest.filter { entry in
            // Only include regular files (not directories)
            guard entry.type == "file" else { return false }
            let filename = entry.path
            return requiredPatterns.contains { $0(filename) }
        }
    }

    /// Build download metadata for all required files in an MLX model.
    ///
    /// Returns tuples of (filename, downloadURL, expectedSize, sha256Hash) for each
    /// required file. The SHA-256 hash comes from the LFS `oid` field if present.
    ///
    /// - Parameters:
    ///   - repoId: The full repository ID.
    ///   - requiredFiles: The filtered manifest from `filterRequiredMLXFiles`.
    /// - Returns: Array of download descriptors.
    static func downloadDescriptors(
        repoId: String,
        requiredFiles: [HFTreeEntry]
    ) -> [(filename: String, url: URL, size: Int64, sha256: String?)] {
        return requiredFiles.map { entry in
            let url = downloadURL(repoId: repoId, filename: entry.path)
            let size = entry.lfs?.size ?? entry.size ?? 0
            let hash = entry.lfs?.oid  // LFS oid IS the SHA-256 hash
            return (filename: entry.path, url: url, size: size, sha256: hash)
        }
    }

    // MARK: - Model Size

    /// Extract the size of the largest model file from the repository's file listing.
    ///
    /// Prefers LFS sizes (actual content size) over regular file sizes. This gives
    /// the best estimate for download size of the primary model artifact.
    ///
    /// - Parameter model: The model info with populated `siblings`.
    /// - Returns: The size in bytes of the largest file, or nil if no file sizes are available.
    func modelSize(_ model: HFModelInfo) -> Int64? {
        guard let siblings = model.siblings else {
            return nil
        }

        let sizes: [Int64] = siblings.compactMap { sibling in
            // Prefer LFS size (actual content size) over the regular size field
            if let lfs = sibling.lfs {
                return lfs.size
            }
            return sibling.size
        }

        return sizes.max()
    }

    /// Calculate the total download size for all required files in an MLX model.
    ///
    /// Unlike `modelSize()` which returns the largest file, this sums all required
    /// files for MLX models which need multiple files downloaded.
    ///
    /// - Parameter model: The model info with populated `siblings`.
    /// - Returns: The total size in bytes of all required MLX files, or nil if not an MLX model.
    func totalMLXModelSize(_ model: HFModelInfo) -> Int64? {
        guard let siblings = model.siblings else { return nil }

        let requiredFilenames: [(String) -> Bool] = [
            { $0 == "config.json" },
            { $0.hasPrefix("tokenizer") && $0.hasSuffix(".json") },
            { $0 == "special_tokens_map.json" },
            { $0 == "generation_config.json" },
            { $0.hasSuffix(".safetensors") },
            { $0.hasSuffix(".safetensors.index.json") },
            { $0 == "chat_template.jinja" || $0 == "chat_template.json" },
            { $0 == "processor_config.json" || $0 == "preprocessor_config.json" },
        ]

        let requiredSiblings = siblings.filter { sibling in
            requiredFilenames.contains { $0(sibling.rfilename) }
        }

        guard !requiredSiblings.isEmpty else { return nil }

        return requiredSiblings.reduce(Int64(0)) { sum, sibling in
            let size = sibling.lfs?.size ?? sibling.size ?? 0
            return sum + size
        }
    }

    // MARK: - Download URL Construction

    /// Construct a direct download URL for a file in a HuggingFace repository.
    ///
    /// Uses the `/resolve/{revision}/{filename}` endpoint which serves the raw file
    /// content, following LFS redirects automatically.
    ///
    /// - Parameters:
    ///   - repoId: The full repository ID (e.g., "litert-community/gemma-4-E2B-it-litert-lm").
    ///   - filename: The file to download (e.g., "gemma-4-E2B-it.litertlm").
    ///   - revision: The Git revision to download from (default: "main").
    /// - Returns: The fully qualified download URL.
    static func downloadURL(repoId: String, filename: String, revision: String = "main") -> URL {
        // Force-unwrap is safe here: all components are URL-safe strings from the HF API
        URL(string: "\(resolveBaseURL)/\(repoId)/resolve/\(revision)/\(filename)")!
    }

    // MARK: - Cache Management

    /// Clear the in-memory model cache, forcing fresh API requests on next fetch.
    func clearCache() {
        cacheClear()
    }
}

// MARK: - HFModelInfo Convenience Extensions

extension HFModelInfo {

    /// Human-readable model name extracted from the full repository ID.
    ///
    /// Strips the organization prefix and returns just the model name portion.
    /// For example, `"litert-community/gemma-4-E2B-it-litert-lm"` → `"gemma-4-E2B-it-litert-lm"`.
    var displayName: String {
        if let slashIndex = id.firstIndex(of: "/") {
            return String(id[id.index(after: slashIndex)...])
        }
        return id
    }

    /// Organization or user name extracted from the full repository ID.
    ///
    /// For example, `"litert-community/gemma-4-E2B-it-litert-lm"` → `"litert-community"`.
    var orgName: String {
        if let slashIndex = id.firstIndex(of: "/") {
            return String(id[..<slashIndex])
        }
        return id
    }

    /// Whether this model is a Gemma 4 variant, detected from tags or the repository ID.
    var isGemma4: Bool {
        tags.contains(where: { $0.lowercased().contains("gemma-4") || $0.lowercased().contains("gemma4") })
            || id.lowercased().contains("gemma-4")
            || id.lowercased().contains("gemma4")
    }

    /// Quantization information extracted from the model name or tags.
    ///
    /// Looks for common quantization indicators such as "4bit", "8bit", "bf16", "fp16",
    /// "int4", "int8", "q4", "q8", etc. Returns nil if no quantization info is detected.
    ///
    /// Examples:
    /// - `"mlx-community/gemma-4-4bit"` → `"4bit"`
    /// - `"mlx-community/gemma-4-E2B-it-bf16"` → `"bf16"`
    var quantizationInfo: String? {
        // Prefer API-provided quantization config (e.g., MLX models with quantization_config.bits)
        if let bits = config?.quantizationConfig?.bits {
            return "\(bits)bit"
        }

        // Known quantization patterns to search for, ordered by specificity
        let patterns = [
            "bf16", "fp16", "fp32",
            "int4", "int8",
            "4bit", "8bit",
            "q4_0", "q4_1", "q4_k_m", "q4_k_s",
            "q5_0", "q5_1", "q5_k_m", "q5_k_s",
            "q6_k",
            "q8_0",
        ]

        let lowerId = id.lowercased()

        // Check the repo ID first (most reliable source)
        for pattern in patterns {
            if lowerId.contains(pattern) {
                return pattern
            }
        }

        // Fall back to tags
        for tag in tags {
            let lowerTag = tag.lowercased()
            for pattern in patterns {
                if lowerTag.contains(pattern) {
                    return pattern
                }
            }
        }

        return nil
    }

    // MARK: - Rich Metadata Accessors

    /// Exact parameter count from safetensors metadata.
    ///
    /// This is the most reliable source for parameter counts — directly from the
    /// model's safetensors file headers. Only available for repos with `.safetensors` files.
    var totalParameters: Int64? {
        safetensors?.total
    }

    /// Maximum context length, cascading through all available data sources.
    ///
    /// Priority: text_config.max_position_embeddings → top-level max_position_embeddings
    /// → gguf.context_length → nil.
    var contextLength: Int? {
        maxContextLength
    }

    /// Primary architecture class (e.g., `"Gemma4ForConditionalGeneration"`).
    var architecture: String? {
        config?.architectures?.first
    }

    /// Model type identifier from config (e.g., `"gemma4"`).
    var modelType: String? {
        config?.modelType
    }

    /// License identifier from the model card frontmatter.
    var license: String? {
        cardData?.license
    }

    /// Base model ID that this model was derived from.
    var baseModelId: String? {
        cardData?.baseModel?.first
    }

    /// Quantization bit depth from config (e.g., 4 for MLX 4-bit models).
    var quantizationBits: Int? {
        config?.quantizationConfig?.bits
    }

    /// Whether the repository requires authentication to access.
    ///
    /// Uses the API-provided `gated` field instead of guessing from the author name.
    var isGated: Bool {
        gated?.isGated ?? false
    }

    /// Human-readable parameter count string.
    ///
    /// Formats the exact parameter count from safetensors into a compact label.
    /// Examples: `"617M"`, `"1.2B"`, `"12B"`.
    /// Returns nil if no parameter count is available.
    var parameterCountLabel: String? {
        guard let total = totalParameters else { return nil }
        if total >= 1_000_000_000 {
            let billions = Double(total) / 1_000_000_000
            if billions >= 10 {
                return "\(Int(billions))B"
            }
            return String(format: "%.1fB", billions)
        }
        if total >= 1_000_000 {
            return "\(total / 1_000_000)M"
        }
        return "\(total)"
    }

    /// Best estimate of total download size in bytes.
    ///
    /// Prefers GGUF total (most accurate for GGUF repos), then falls back to
    /// `usedStorage` (total repo size from HuggingFace).
    var estimatedDownloadSize: Int64? {
        gguf?.total ?? usedStorage
    }

    /// GGUF architecture identifier (e.g., `"gemma4"`).
    var ggufArchitecture: String? {
        gguf?.architecture
    }

    /// Languages the model supports, from card metadata.
    var supportedLanguages: [String] {
        cardData?.language?.values ?? []
    }

    /// Training datasets used, from card metadata.
    var trainingDatasets: [String] {
        cardData?.datasets?.values ?? []
    }

    // MARK: - Config-Derived Capability Signals

    /// Authoritative maximum context length, cascading through data sources.
    ///
    /// Priority:
    /// 1. `text_config.max_position_embeddings` (from config.json — most authoritative)
    /// 2. Top-level `max_position_embeddings` (some models put it here instead)
    /// 3. `gguf.context_length` (from GGUF metadata in API response)
    /// 4. `nil` — no data available, caller should use heuristics
    var maxContextLength: Int? {
        config?.textConfig?.maxPositionEmbeddings
            ?? config?.maxPositionEmbeddings
            ?? gguf?.contextLength
    }

    /// Whether this model supports image/vision input, derived from config.json signals.
    ///
    /// Uses authoritative signals from the model's configuration:
    /// 1. `vision_config` sub-object exists → vision encoder present
    /// 2. `image_token_id` exists → model has a special image token
    /// 3. Architecture contains "ConditionalGeneration" → multimodal architecture
    var hasVisionSupport: Bool {
        config?.visionConfig != nil
            || config?.imageTokenId != nil
            || (config?.architectures?.first?.contains("ConditionalGeneration") == true)
    }

    /// Whether this model supports audio input, derived from config.json signals.
    ///
    /// Uses authoritative signals from the model's configuration:
    /// 1. `audio_config` sub-object exists → audio encoder present
    /// 2. `audio_token_id` exists → model has a special audio token
    var hasAudioSupport: Bool {
        config?.audioConfig != nil
            || config?.audioTokenId != nil
    }

    /// Maximum input image resolution from vision config (e.g., 896 for SigLIP).
    var maxImageResolution: Int? {
        config?.visionConfig?.imageSize
    }

    /// Number of transformer layers in the text model.
    var numLayers: Int? {
        config?.textConfig?.numHiddenLayers
    }

    /// Hidden dimension size of the text model.
    var hiddenSize: Int? {
        config?.textConfig?.hiddenSize
    }

    /// Number of attention heads in the text model.
    var numAttentionHeads: Int? {
        config?.textConfig?.numAttentionHeads
    }

    /// Vocabulary size from text config.
    var vocabSize: Int? {
        config?.textConfig?.vocabSize
    }

    /// PyTorch dtype for model weights, from config or text_config.
    var dtype: String? {
        config?.torchDtype ?? config?.textConfig?.torchDtype
    }

    /// Whether the model uses Mixture of Experts architecture.
    var isMoE: Bool {
        config?.textConfig?.enableMoeBlock == true
    }

    /// License link URL from model card frontmatter.
    var licenseLink: String? {
        cardData?.licenseLink
    }
}
