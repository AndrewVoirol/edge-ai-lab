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

// MARK: - Capability Source Tracking

/// Tracks where a capability determination came from.
///
/// This enables the UI to show users *why* a capability is reported as supported
/// or unsupported, building justified trust. For example, "Vision ✓ (from config.json)"
/// is more trustworthy than "Vision ✓ (inferred from model name)".
enum CapabilitySource: String, Codable, Sendable, Hashable {
    /// Derived from config.json fields (text_config, vision_config, audio_config,
    /// image_token_id, audio_token_id). The most authoritative source.
    case configJSON = "config_json"
    /// From HuggingFace API metadata (tags, pipeline_tag, library_name, gguf metadata).
    case apiMetadata = "api_metadata"
    /// From the model's README.md content analysis.
    case readme
    /// From model naming conventions (e.g., "-it" suffix → instruction-tuned).
    case heuristic
    /// From KnownModelCatalog hardcoded profiles — hand-verified metadata.
    case catalog = "registry"
    /// Verified at runtime by the inference engine after loading.
    case engineRuntime = "engine_runtime"
    /// Manually set or overridden by the user.
    case userOverride = "user_override"

    /// Human-readable label for UI display.
    var displayLabel: String {
        switch self {
        case .configJSON: return "from config.json"
        case .apiMetadata: return "from API"
        case .readme: return "from README"
        case .heuristic: return "estimated"
        case .catalog: return "known model"
        case .engineRuntime: return "verified at runtime"
        case .userOverride: return "user override"
        }
    }
}

// MARK: - Sourced Value

/// A value paired with its provenance source.
///
/// Used throughout `ModelCapabilityProfile` to track not just *what* a model can do,
/// but *how we know* it can do it.
struct SourcedValue<T: Codable & Sendable & Hashable>: Codable, Sendable, Hashable {
    /// The actual value.
    let value: T
    /// Where this value was determined from.
    let source: CapabilitySource

    init(_ value: T, source: CapabilitySource) {
        self.value = value
        self.source = source
    }
}

// MARK: - Architecture Info

/// Structural architecture information derived from config.json.
///
/// This data enables intelligent memory estimation, performance prediction,
/// and architecture-aware UI displays.
struct ArchitectureInfo: Codable, Sendable, Hashable {
    /// Primary architecture class (e.g., "Gemma4ForConditionalGeneration").
    let architectureClass: String?
    /// Model type identifier (e.g., "gemma4", "llama").
    let modelType: String?
    /// Whether the model uses Mixture of Experts.
    let isMoE: Bool
    /// Hidden dimension size.
    let hiddenSize: Int?
    /// Number of transformer layers.
    let numLayers: Int?
    /// Number of attention heads.
    let numAttentionHeads: Int?
    /// Number of key-value heads (for GQA).
    let numKeyValueHeads: Int?
    /// Vocabulary size.
    let vocabSize: Int?
    /// Per-head dimension.
    let headDim: Int?
    /// Maximum input image resolution (from vision encoder).
    let maxImageResolution: Int?
    /// PyTorch dtype for weights (e.g., "bfloat16").
    let dtype: String?
    /// Quantization bit depth, if quantized.
    let quantizationBits: Int?
    /// Quantization method (e.g., "mlx", "awq", "gptq").
    let quantizationMethod: String?
}

// MARK: - Model Capability Profile

/// The single source of truth for what a model can do, across all data sources.
///
/// Built progressively as information becomes available:
/// 1. **At browse time**: from HF API response (`HFModelInfo`)
/// 2. **At download/import**: from config.json parsing + `KnownModelCatalog`
/// 3. **At load time**: from engine runtime state
///
/// Persisted to disk for offline access. Lazily refreshed in background.
///
/// Every subsystem queries this instead of checking capabilities independently:
/// - **UI**: Shows/hides multimodal controls, capability badges
/// - **Settings**: Gates toggles (thinking, tool calling, MTP, etc.)
/// - **Eval**: Filters suites by required capabilities
/// - **Engine**: Configures load parameters
///
/// ## Design Principles
/// - Every capability field is a `SourcedValue<Bool>` — carries both the answer
///   AND provenance. "Vision: true (from config.json)" vs "Vision: true (estimated)".
/// - Fields with `?` are genuinely unknown. Fields with `value: false` are known-absent.
/// - The profile is Codable and Sendable — safe to persist, cache, and pass across actors.
struct ModelCapabilityProfile: Codable, Sendable, Hashable, Identifiable {
    /// Unique identifier — modelFile for local models, repoId for HF models.
    let id: String

    /// Human-readable model name.
    let displayName: String

    /// Repository ID on HuggingFace (e.g., "mlx-community/gemma-4-E2B-it-4bit").
    let repoId: String?

    /// Runtime type (LiteRT-LM, MLX, GGUF).
    let runtimeType: RuntimeType

    // MARK: - Capability Flags

    /// Whether the model supports image/vision input.
    let supportsVision: SourcedValue<Bool>?

    /// Whether the model supports audio input.
    let supportsAudio: SourcedValue<Bool>?

    /// Whether the model supports thinking/reasoning mode.
    let supportsThinking: SourcedValue<Bool>?

    /// Whether the model supports tool calling (function calling).
    let supportsToolCalling: SourcedValue<Bool>?

    /// Whether the model supports multi-token prediction (speculative decoding).
    let supportsMTP: SourcedValue<Bool>?

    /// Whether the model supports constrained decoding (JSON mode, grammars).
    let supportsConstrainedDecoding: SourcedValue<Bool>?

    // MARK: - Architecture & Size

    /// Detailed architecture information from config.json.
    let architecture: ArchitectureInfo?

    /// Maximum context window in tokens.
    let contextWindow: SourcedValue<Int>?

    /// Model file size on disk, in bytes.
    let fileSizeBytes: Int64?

    /// Estimated memory requirement in GB.
    let estimatedMemoryGB: SourcedValue<Int>?

    /// Total parameter count (from safetensors metadata).
    let totalParameters: Int64?

    /// Human-readable parameter label (e.g., "1.2B", "12B").
    let parameterLabel: String?

    // MARK: - Provenance

    /// Overall confidence in the profile's accuracy.
    let confidence: MetadataConfidence

    /// How this profile was constructed.
    let source: MetadataSource

    /// When this profile was last built or refreshed.
    let lastUpdated: Date

    /// Git SHA of the HF repo at time of profile creation (for staleness detection).
    let repoSha: String?

    // MARK: - HF Metadata (for UI display)

    /// License identifier.
    let license: String?

    /// License link URL.
    let licenseLink: String?

    /// Base model that this model was derived from.
    let baseModelId: String?

    /// HuggingFace download count.
    let downloads: Int?

    /// HuggingFace likes count.
    let likes: Int?

    /// All-time download count (from expand parameter).
    let downloadsAllTime: Int?

    /// Languages the model supports.
    let supportedLanguages: [String]

    /// Tags from the HuggingFace model card.
    let tags: [String]

    // MARK: - Operational Configuration

    /// Default sampler configuration for this model.
    let defaultConfig: ModelDefaultConfig?

    /// Platform-specific backend support matrix.
    let platformSupport: PlatformSupport?

    /// Human-readable description of the model.
    let modelDescription: String?

    /// Human-readable recommendation (e.g., "Mobile chat", "Desktop coding").
    let recommendedFor: String?

    /// Model file name on disk (e.g., "gemma-4-E2B-it.litertlm").
    let modelFile: String?

    /// HuggingFace model identifier (e.g., "litert-community/gemma-4-E2B-it-litert-lm").
    let modelId: String?
}

// MARK: - Convenience Accessors

extension ModelCapabilityProfile {

    /// Whether vision is supported — safe accessor that defaults to false.
    var hasVision: Bool {
        supportsVision?.value ?? false
    }

    /// Whether audio is supported — safe accessor that defaults to false.
    var hasAudio: Bool {
        supportsAudio?.value ?? false
    }

    /// Whether thinking mode is supported — safe accessor that defaults to false.
    var hasThinking: Bool {
        supportsThinking?.value ?? false
    }

    /// Whether tool calling is supported — safe accessor that defaults to false.
    var hasToolCalling: Bool {
        supportsToolCalling?.value ?? false
    }

    /// Whether MTP/speculative decoding is supported — safe accessor that defaults to false.
    var hasMTP: Bool {
        supportsMTP?.value ?? false
    }

    /// Whether constrained decoding is supported — safe accessor that defaults to false.
    var hasConstrainedDecoding: Bool {
        supportsConstrainedDecoding?.value ?? false
    }

    /// The context window size, or nil if unknown.
    var contextWindowSize: Int? {
        contextWindow?.value
    }

    /// Whether this model is multimodal (vision or audio).
    var isMultimodal: Bool {
        hasVision || hasAudio
    }

    /// The estimated memory requirement, or nil if unknown.
    var memoryGB: Int? {
        estimatedMemoryGB?.value
    }

    /// Maximum tokens for generation from the model's default config.
    var maxTokens: Int {
        defaultConfig?.maxTokens ?? 4000
    }

    /// The recommended backend for the current platform, or `.probeRequired` if unknown.
    var recommendedBackend: BackendRecommendation {
        platformSupport?.currentPlatform.recommendedBackend ?? .probeRequired
    }

    /// Whether this model requires HuggingFace authentication.
    var requiresAuth: Bool {
        guard let modelId else { return false }
        return modelId.hasPrefix("google/")
    }

    /// HuggingFace download URL.
    var downloadURL: URL? {
        guard let modelId, let modelFile else { return nil }
        return URL(string: "https://huggingface.co/\(modelId)/resolve/main/\(modelFile)")
    }

    /// Whether this model uses a multi-file directory format (MLX models).
    var isMLXDirectoryModel: Bool {
        runtimeType == .mlx
    }

    // MARK: - Runtime Enrichment

    /// Creates a new profile with engine-verified capability values.
    ///
    /// Called after an engine successfully loads a model. The engine's runtime
    /// state is the ground truth for what actually works — it supersedes all
    /// prior metadata sources.
    ///
    /// Only overrides capabilities the engine explicitly reports. Preserves
    /// all other fields from the original profile.
    ///
    /// - Parameters:
    ///   - supportsVision: Engine's runtime vision capability.
    ///   - supportsToolCalling: Engine's runtime tool calling capability.
    /// - Returns: A new profile with `.engineRuntime` sourced overrides.
    func enrichedWithEngineRuntime(
        supportsVision engineVision: Bool,
        supportsToolCalling engineToolCalling: Bool
    ) -> ModelCapabilityProfile {
        ModelCapabilityProfile(
            id: id,
            displayName: displayName,
            repoId: repoId,
            runtimeType: runtimeType,
            supportsVision: SourcedValue(engineVision, source: .engineRuntime),
            supportsAudio: supportsAudio,
            supportsThinking: supportsThinking,
            supportsToolCalling: SourcedValue(engineToolCalling, source: .engineRuntime),
            supportsMTP: supportsMTP,
            supportsConstrainedDecoding: supportsConstrainedDecoding,
            architecture: architecture,
            contextWindow: contextWindow,
            fileSizeBytes: fileSizeBytes,
            estimatedMemoryGB: estimatedMemoryGB,
            totalParameters: totalParameters,
            parameterLabel: parameterLabel,
            confidence: .verified,
            source: source,
            lastUpdated: Date(),
            repoSha: repoSha,
            license: license,
            licenseLink: licenseLink,
            baseModelId: baseModelId,
            downloads: downloads,
            likes: likes,
            downloadsAllTime: downloadsAllTime,
            supportedLanguages: supportedLanguages,
            tags: tags,
            defaultConfig: defaultConfig,
            platformSupport: platformSupport,
            modelDescription: modelDescription,
            recommendedFor: recommendedFor,
            modelFile: modelFile,
            modelId: modelId
        )
    }
}

// MARK: - Profile Builder

/// Builds a `ModelCapabilityProfile` from available data sources.
///
/// The builder follows a priority cascade:
/// 1. config.json data (most authoritative)
/// 2. HuggingFace API metadata
/// 3. KnownModelCatalog (hand-verified profiles)
/// 4. Heuristics (model name patterns)
///
/// Each field records its source via `SourcedValue`, enabling the UI
/// to show provenance (e.g., "Vision: ✓ (from config.json)").
enum ModelCapabilityProfileBuilder {

    /// Build a profile from an HFModelInfo (at browse/import time).
    ///
    /// This is the primary entry point for community models discovered through
    /// the HuggingFace API. Uses config.json-derived data where available,
    /// falling back to tag-based heuristics.
    static func fromHFModelInfo(
        _ model: HFModelInfo,
        runtimeType: RuntimeType,
        confidence: MetadataConfidence = .medium
    ) -> ModelCapabilityProfile {
        // Vision detection — cascade through config.json sources
        let vision: SourcedValue<Bool>?
        if model.config?.visionConfig != nil || model.config?.imageTokenId != nil {
            vision = SourcedValue(true, source: .configJSON)
        } else if model.config?.architectures?.first?.contains("ConditionalGeneration") == true {
            vision = SourcedValue(true, source: .configJSON)
        } else if inferVisionFromTags(model) {
            vision = SourcedValue(true, source: .apiMetadata)
        } else if model.config != nil {
            // Config exists but no vision indicators → known absent
            vision = SourcedValue(false, source: .configJSON)
        } else {
            vision = nil  // No config at all → genuinely unknown
        }

        // Audio detection
        let audio: SourcedValue<Bool>?
        if model.config?.audioConfig != nil || model.config?.audioTokenId != nil {
            audio = SourcedValue(true, source: .configJSON)
        } else if inferAudioFromTags(model) {
            audio = SourcedValue(true, source: .apiMetadata)
        } else if model.config != nil {
            audio = SourcedValue(false, source: .configJSON)
        } else {
            audio = nil
        }

        // Thinking detection — Gemma 4 models all support thinking
        let thinking: SourcedValue<Bool>?
        if model.modelType == "gemma4" || model.id.lowercased().contains("gemma-4") || model.id.lowercased().contains("gemma4") {
            thinking = SourcedValue(true, source: .apiMetadata)
        } else if model.tags.contains(where: { $0.lowercased().contains("thinking") || $0.lowercased().contains("reasoning") }) {
            thinking = SourcedValue(true, source: .apiMetadata)
        } else {
            thinking = nil  // Unknown for non-Gemma models
        }

        // Tool calling — instruction-tuned models support it
        let toolCalling: SourcedValue<Bool>?
        let lowerId = model.id.lowercased()
        if lowerId.contains("-it-") || lowerId.contains("-it.") || lowerId.hasSuffix("-it")
            || lowerId.contains("-instruct") || lowerId.contains("-chat") {
            toolCalling = SourcedValue(true, source: .heuristic)
        } else {
            toolCalling = SourcedValue(false, source: .heuristic)
        }

        // MTP detection
        let mtp: SourcedValue<Bool>?
        if model.tags.contains(where: { $0.lowercased().contains("mtp") || $0.lowercased().contains("speculative") }) {
            mtp = SourcedValue(true, source: .apiMetadata)
        } else {
            mtp = SourcedValue(false, source: .heuristic)
        }

        // Context window
        let contextWindow: SourcedValue<Int>?
        if let ctx = model.config?.textConfig?.maxPositionEmbeddings {
            contextWindow = SourcedValue(ctx, source: .configJSON)
        } else if let ctx = model.config?.maxPositionEmbeddings {
            contextWindow = SourcedValue(ctx, source: .configJSON)
        } else if let ctx = model.gguf?.contextLength {
            contextWindow = SourcedValue(ctx, source: .apiMetadata)
        } else {
            contextWindow = nil
        }

        // Architecture info
        let archInfo: ArchitectureInfo?
        if let config = model.config {
            archInfo = ArchitectureInfo(
                architectureClass: config.architectures?.first,
                modelType: config.modelType,
                isMoE: config.textConfig?.enableMoeBlock == true,
                hiddenSize: config.textConfig?.hiddenSize,
                numLayers: config.textConfig?.numHiddenLayers,
                numAttentionHeads: config.textConfig?.numAttentionHeads,
                numKeyValueHeads: config.textConfig?.numKeyValueHeads,
                vocabSize: config.textConfig?.vocabSize,
                headDim: config.textConfig?.headDim,
                maxImageResolution: config.visionConfig?.imageSize,
                dtype: config.torchDtype ?? config.textConfig?.torchDtype,
                quantizationBits: config.quantizationConfig?.bits,
                quantizationMethod: config.quantizationConfig?.quantMethod
            )
        } else {
            archInfo = nil
        }

        // Memory estimation
        let memoryGB: SourcedValue<Int>?
        if let total = model.safetensors?.total {
            // Exact: safetensors param count × bytes per param
            let bytesPerParam: Double
            if let bits = model.config?.quantizationConfig?.bits {
                bytesPerParam = Double(bits) / 8.0
            } else if let dtype = model.dtype {
                switch dtype {
                case "bfloat16", "float16": bytesPerParam = 2.0
                case "float32": bytesPerParam = 4.0
                case "int8": bytesPerParam = 1.0
                default: bytesPerParam = 2.0  // Default to fp16
                }
            } else {
                bytesPerParam = 2.0
            }
            let estimatedBytes = Double(total) * bytesPerParam
            let gb = max(4, Int(ceil(estimatedBytes / 1_073_741_824)))
            memoryGB = SourcedValue(gb, source: .apiMetadata)
        } else {
            memoryGB = nil
        }

        return ModelCapabilityProfile(
            id: model.id,
            displayName: model.displayName,
            repoId: model.id,
            runtimeType: runtimeType,
            supportsVision: vision,
            supportsAudio: audio,
            supportsThinking: thinking,
            supportsToolCalling: toolCalling,
            supportsMTP: mtp,
            supportsConstrainedDecoding: runtimeType == .litertlm
                ? SourcedValue(true, source: .apiMetadata)
                : SourcedValue(false, source: .heuristic),
            architecture: archInfo,
            contextWindow: contextWindow,
            fileSizeBytes: model.estimatedDownloadSize,
            estimatedMemoryGB: memoryGB,
            totalParameters: model.safetensors?.total,
            parameterLabel: model.parameterCountLabel,
            confidence: confidence,
            source: .huggingFaceInferred,
            lastUpdated: Date(),
            repoSha: model.sha,
            license: model.license,
            licenseLink: model.licenseLink,
            baseModelId: model.baseModelId,
            downloads: model.downloads,
            likes: model.likes,
            downloadsAllTime: model.downloadsAllTime,
            supportedLanguages: model.supportedLanguages,
            tags: model.tags,
            defaultConfig: nil,
            platformSupport: nil,
            modelDescription: nil,
            recommendedFor: nil,
            modelFile: nil,
            modelId: model.id
        )
    }


    /// Build a profile by synthesizing metadata from filename heuristics.
    ///
    /// Used for user-imported models with no HF API data and no catalog match.
    /// Parses quantization, runtime type, model family, and capabilities from the filename.
    static func synthesized(
        filename: String,
        sizeInBytes: Int64,
        hasMMProj: Bool = false
    ) -> ModelCapabilityProfile {
        let ext = (filename as NSString).pathExtension.lowercased()
        let stem = (filename as NSString).deletingPathExtension

        // Infer runtime from extension
        let runtime: RuntimeType = switch ext {
        case "gguf": .gguf
        case "litertlm": .litertlm
        default: .gguf
        }

        // Parse quantization from filename (e.g., "Q4_K_M", "Q8_0", "FP16")
        let quantPattern = stem.components(separatedBy: "-")
        let quantization = quantPattern.last(where: {
            $0.hasPrefix("Q") || $0.hasPrefix("F") || $0.hasPrefix("q") || $0.hasPrefix("f")
        })

        // Estimate RAM
        let ramMultiplier: Double
        if let q = quantization?.uppercased() {
            if q.hasPrefix("Q4") || q.hasPrefix("Q3") || q.contains("IQ4") || q.contains("IQ3") || q.contains("IQ2") || q.contains("4BIT") || q.contains("2BIT") {
                ramMultiplier = 1.6
            } else if q.hasPrefix("Q8") || q.hasPrefix("Q5") || q.hasPrefix("Q6") || q.contains("8BIT") {
                ramMultiplier = 1.4
            } else if q.contains("F16") || q.contains("FP16") || q.contains("BF16") {
                ramMultiplier = 1.2
            } else {
                ramMultiplier = 1.3
            }
        } else {
            ramMultiplier = 1.3
        }
        let estimatedRAM = max(2, Int(Double(sizeInBytes) / 1_000_000_000.0 * ramMultiplier))

        let displayName = ModelDetailFormatters.normalizeDisplayName(stem)

        // Detect multimodal support
        let lowerStem = stem.lowercased()
        let isGemma4Standard = lowerStem.contains("gemma") && lowerStem.contains("4")
            && !lowerStem.contains("web") && !lowerStem.contains("mobile")
        let hasMultimodal: Bool
        switch runtime {
        case .gguf:
            hasMultimodal = isGemma4Standard && hasMMProj
        case .litertlm:
            hasMultimodal = isGemma4Standard
        default:
            hasMultimodal = isGemma4Standard
        }

        // Infer context window
        let contextWindow: Int
        if lowerStem.contains("gemma") && lowerStem.contains("4") {
            if lowerStem.contains("12b") {
                contextWindow = 256_000
            } else {
                contextWindow = 128_000
            }
        } else if lowerStem.contains("gemma") {
            contextWindow = 32_000
        } else if lowerStem.contains("llama") {
            contextWindow = 128_000
        } else {
            contextWindow = 32_000
        }

        // Infer architecture
        let archClass: String?
        let isMoE: Bool
        if lowerStem.contains("gemma") && lowerStem.contains("4") {
            if lowerStem.contains("e2b") || lowerStem.contains("e4b") {
                archClass = "Mixture of Experts"
                isMoE = true
            } else if lowerStem.contains("12b") {
                archClass = "Dense Transformer"
                isMoE = false
            } else {
                archClass = "Transformer"
                isMoE = false
            }
        } else {
            archClass = "Transformer"
            isMoE = false
        }

        // Infer thinking support
        let hasThinking = lowerStem.contains("it") && (
            lowerStem.contains("gemma") || lowerStem.contains("llama") ||
            lowerStem.contains("mistral") || lowerStem.contains("phi") ||
            lowerStem.contains("qwen"))

        // MTP: Only LiteRT models have speculative decoding
        let hasMTP = runtime == .litertlm

        let capSource: CapabilitySource = .heuristic

        return ModelCapabilityProfile(
            id: filename,
            displayName: displayName,
            repoId: nil,
            runtimeType: runtime,
            supportsVision: SourcedValue(hasMultimodal, source: capSource),
            supportsAudio: SourcedValue(hasMultimodal, source: capSource),
            supportsThinking: SourcedValue(hasThinking, source: capSource),
            supportsToolCalling: SourcedValue(hasThinking, source: capSource),
            supportsMTP: SourcedValue(hasMTP, source: capSource),
            supportsConstrainedDecoding: SourcedValue(runtime == .litertlm, source: capSource),
            architecture: ArchitectureInfo(
                architectureClass: archClass,
                modelType: nil,
                isMoE: isMoE,
                hiddenSize: nil,
                numLayers: nil,
                numAttentionHeads: nil,
                numKeyValueHeads: nil,
                vocabSize: nil,
                headDim: nil,
                maxImageResolution: nil,
                dtype: nil,
                quantizationBits: nil,
                quantizationMethod: nil
            ),
            contextWindow: SourcedValue(contextWindow, source: capSource),
            fileSizeBytes: sizeInBytes,
            estimatedMemoryGB: SourcedValue(estimatedRAM, source: capSource),
            totalParameters: nil,
            parameterLabel: nil,
            confidence: .low,
            source: .huggingFaceInferred,
            lastUpdated: Date(),
            repoSha: nil,
            license: nil,
            licenseLink: nil,
            baseModelId: nil,
            downloads: nil,
            likes: nil,
            downloadsAllTime: nil,
            supportedLanguages: [],
            tags: [],
            defaultConfig: ModelDefaultConfig(
                topK: 40,
                topP: 0.95,
                temperature: 0.7,
                maxContextLength: contextWindow,
                maxTokens: 2048,
                accelerators: "gpu",
                visionAccelerator: hasMultimodal ? "gpu" : nil
            ),
            platformSupport: PlatformSupport(
                macOS: .gpuAndCpu,
                iOSDevice: .gpuAndCpu,
                iOSSimulator: .cpuOnly
            ),
            modelDescription: "Locally imported \(runtime.displayName) model"
                + (quantization.map { " (\($0) quantization)" } ?? ""),
            recommendedFor: "Local inference",
            modelFile: filename,
            modelId: "local/\(filename)"
        )
    }

    // MARK: - Private Helpers

    /// Infer vision support from HF tags/pipeline (when config.json is unavailable).
    private static func inferVisionFromTags(_ model: HFModelInfo) -> Bool {
        let visionTags = ["vision", "image-text-to-text", "visual-question-answering", "multimodal"]
        if model.tags.contains(where: { tag in
            visionTags.contains(where: { tag.lowercased().contains($0) })
        }) {
            return true
        }
        if let pipeline = model.pipelineTag?.lowercased() {
            return visionTags.contains(where: { pipeline.contains($0) })
        }
        return false
    }

    /// Infer audio support from HF tags/pipeline (when config.json is unavailable).
    private static func inferAudioFromTags(_ model: HFModelInfo) -> Bool {
        let audioTags = ["audio", "speech", "speech-recognition"]
        if model.tags.contains(where: { tag in
            audioTags.contains(where: { tag.lowercased().contains($0) })
        }) {
            return true
        }
        if let pipeline = model.pipelineTag?.lowercased() {
            return audioTags.contains(where: { pipeline.contains($0) })
        }
        return false
    }
}
