import Foundation

// MARK: - Known Model Catalog

/// Catalog of known models with pre-built `ModelCapabilityProfile` entries.
///
/// This is the single source of truth for known model metadata. Each profile
/// is defined directly with hand-verified data — no intermediate `ModelMetadata`
/// or `ModelRegistry` types involved.
///
/// Models are sourced from:
/// - HuggingFace litert-community models (LiteRT-LM)
/// - mlx-community models (MLX)
/// - google/ namespace (gated models)
///
/// For dynamically discovered or user-imported models, use
/// `ModelCapabilityProfileBuilder.synthesized()` instead.
enum KnownModelCatalog {

    // MARK: - Catalog Array

    /// All known models in the catalog.
    /// Ordered by recommendation: 12B first (flagship), then E4B, then E2B, then 3n.
    static let allModels: [ModelCapabilityProfile] = [
        gemma4_12B,
        gemma4E4BStandard,
        gemma4E4BWeb,
        gemma4E2BStandard,
        gemma4E2BWeb,
        // MLX Models
        gemma4E2B_MLX,
        gemma4E4B_MLX,
    ]

    // MARK: - Lookup

    /// Look up a known model by filename.
    /// - Parameter filename: The model filename (e.g., "gemma-4-E2B-it-web.litertlm")
    /// - Returns: The matching profile, or nil if unknown.
    static func lookup(filename: String) -> ModelCapabilityProfile? {
        allModels.first { $0.modelFile == filename }
    }

    /// Look up a known model by file path.
    /// - Parameter path: Full path to the model file.
    /// - Returns: The matching profile, or nil if unknown.
    static func lookup(path: String) -> ModelCapabilityProfile? {
        let filename = (path as NSString).lastPathComponent
        return lookup(filename: filename)
    }

    /// Look up a known model by HuggingFace repo ID.
    /// - Parameter repoId: The HuggingFace repo ID (e.g., "litert-community/gemma-4-E2B-it-litert-lm")
    /// - Returns: The matching profile, or nil if unknown.
    static func lookup(repoId: String) -> ModelCapabilityProfile? {
        allModels.first { $0.repoId == repoId || $0.modelId == repoId }
    }

    // MARK: - Pre-built Profiles

    // swiftlint:disable identifier_name function_body_length

    // MARK: Gemma 4 E2B (Standard)

    /// Standard build with both CPU (XNNPACK) and desktop GPU (Metal) subgraphs.
    /// Desktop Metal shaders also work on A-series iOS GPUs (verified on iPhone 16 Pro Max).
    ///
    /// Gallery iOS benchmark reference (v1.0.6, iPhone 16 Pro Max, Gemma-4-E2B-it, GPU):
    ///   Prefill: 305.45 tok/s | Decode: 39.23 tok/s
    ///   TTFT: 0.87s | Init: 1006.00ms
    ///
    /// Our benchmark (Session 5, iPhone 16 Pro Max, GPU, greedy):
    ///   Decode: 43.09 tok/s (✅ +3.5% vs Gallery)
    ///   Init: 3236ms
    static let gemma4E2BStandard = ModelCapabilityProfile(
        id: "gemma-4-E2B-it.litertlm",
        displayName: "Gemma 4 E2B · Desktop GPU+CPU",
        repoId: "litert-community/gemma-4-E2B-it-litert-lm",
        runtimeType: .litertlm,
        supportsVision: SourcedValue(true, source: .catalog),
        supportsAudio: SourcedValue(true, source: .catalog),
        supportsThinking: SourcedValue(true, source: .catalog),
        supportsToolCalling: SourcedValue(true, source: .heuristic),
        supportsMTP: SourcedValue(true, source: .catalog),
        supportsConstrainedDecoding: SourcedValue(true, source: .catalog),
        architecture: ArchitectureInfo(
            architectureClass: nil, modelType: nil, isMoE: true,
            hiddenSize: nil, numLayers: nil, numAttentionHeads: nil,
            numKeyValueHeads: nil, vocabSize: nil, headDim: nil,
            maxImageResolution: nil, dtype: nil,
            quantizationBits: nil, quantizationMethod: nil
        ),
        contextWindow: SourcedValue(128_000, source: .catalog),
        fileSizeBytes: 2_588_147_712,
        estimatedMemoryGB: SourcedValue(8, source: .catalog),
        totalParameters: nil,
        parameterLabel: nil,
        confidence: .verified,
        source: .knownRegistry,
        lastUpdated: Date(),
        repoSha: nil,
        license: nil, licenseLink: nil, baseModelId: nil,
        downloads: nil, likes: nil, downloadsAllTime: nil,
        supportedLanguages: [],
        tags: [],
        defaultConfig: ModelDefaultConfig(
            topK: 64, topP: 0.95, temperature: 1.0,
            maxContextLength: 32_000, maxTokens: 4_000,
            accelerators: "gpu,cpu", visionAccelerator: "gpu"
        ),
        platformSupport: PlatformSupport(
            macOS: .gpuAndCpu, iOSDevice: .gpuAndCpu, iOSSimulator: .cpuOnly
        ),
        modelDescription: "Standard Gemma 4 E2B model with CPU (XNNPACK) and desktop GPU (Metal) support. Desktop Metal shaders also work on A-series iOS GPUs (verified on iPhone 16 Pro Max).",
        recommendedFor: "Mobile chat, quick responses",
        modelFile: "gemma-4-E2B-it.litertlm",
        modelId: "litert-community/gemma-4-E2B-it-litert-lm"
    )

    // MARK: Gemma 4 E2B (Web / Mobile GPU)

    /// Web variant with mobile GPU artisan shaders for A-series chips. No CPU subgraph.
    static let gemma4E2BWeb = ModelCapabilityProfile(
        id: "gemma-4-E2B-it-web.litertlm",
        displayName: "Gemma 4 E2B · Mobile GPU",
        repoId: "litert-community/gemma-4-E2B-it-litert-lm",
        runtimeType: .litertlm,
        supportsVision: SourcedValue(false, source: .catalog),
        supportsAudio: SourcedValue(false, source: .catalog),
        supportsThinking: SourcedValue(true, source: .catalog),
        supportsToolCalling: SourcedValue(true, source: .heuristic),
        supportsMTP: SourcedValue(true, source: .catalog),
        supportsConstrainedDecoding: SourcedValue(true, source: .catalog),
        architecture: ArchitectureInfo(
            architectureClass: nil, modelType: nil, isMoE: true,
            hiddenSize: nil, numLayers: nil, numAttentionHeads: nil,
            numKeyValueHeads: nil, vocabSize: nil, headDim: nil,
            maxImageResolution: nil, dtype: nil,
            quantizationBits: nil, quantizationMethod: nil
        ),
        contextWindow: SourcedValue(128_000, source: .catalog),
        fileSizeBytes: 2_008_432_640,
        estimatedMemoryGB: SourcedValue(8, source: .catalog),
        totalParameters: nil,
        parameterLabel: nil,
        confidence: .verified,
        source: .knownRegistry,
        lastUpdated: Date(),
        repoSha: nil,
        license: nil, licenseLink: nil, baseModelId: nil,
        downloads: nil, likes: nil, downloadsAllTime: nil,
        supportedLanguages: [],
        tags: [],
        defaultConfig: ModelDefaultConfig(
            topK: 1, topP: 1.0, temperature: 1.0,
            maxContextLength: 32_000, maxTokens: 4_000,
            accelerators: "gpu", visionAccelerator: nil
        ),
        platformSupport: PlatformSupport(
            macOS: .gpuOnly, iOSDevice: .gpuOnly, iOSSimulator: .gpuOnly
        ),
        modelDescription: "Mobile-optimized Gemma 4 E2B with GPU artisan shaders for A-series and M-series chips. GPU-only — no CPU subgraph. Fastest decode on iOS device (39.9 tok/s).",
        recommendedFor: "Fastest mobile inference",
        modelFile: "gemma-4-E2B-it-web.litertlm",
        modelId: "litert-community/gemma-4-E2B-it-litert-lm"
    )

    // MARK: Gemma 4 E4B (Standard)

    /// Gemma 4 E4B standard build — larger 4B-effective model with CPU + GPU subgraphs.
    static let gemma4E4BStandard = ModelCapabilityProfile(
        id: "gemma-4-E4B-it.litertlm",
        displayName: "Gemma 4 E4B · Desktop GPU+CPU",
        repoId: "litert-community/gemma-4-E4B-it-litert-lm",
        runtimeType: .litertlm,
        supportsVision: SourcedValue(true, source: .catalog),
        supportsAudio: SourcedValue(true, source: .catalog),
        supportsThinking: SourcedValue(true, source: .catalog),
        supportsToolCalling: SourcedValue(true, source: .heuristic),
        supportsMTP: SourcedValue(true, source: .catalog),
        supportsConstrainedDecoding: SourcedValue(true, source: .catalog),
        architecture: ArchitectureInfo(
            architectureClass: nil, modelType: nil, isMoE: true,
            hiddenSize: nil, numLayers: nil, numAttentionHeads: nil,
            numKeyValueHeads: nil, vocabSize: nil, headDim: nil,
            maxImageResolution: nil, dtype: nil,
            quantizationBits: nil, quantizationMethod: nil
        ),
        contextWindow: SourcedValue(128_000, source: .catalog),
        fileSizeBytes: 3_660_000_000,
        estimatedMemoryGB: SourcedValue(12, source: .catalog),
        totalParameters: nil,
        parameterLabel: nil,
        confidence: .verified,
        source: .knownRegistry,
        lastUpdated: Date(),
        repoSha: nil,
        license: nil, licenseLink: nil, baseModelId: nil,
        downloads: nil, likes: nil, downloadsAllTime: nil,
        supportedLanguages: [],
        tags: [],
        defaultConfig: ModelDefaultConfig(
            topK: 64, topP: 0.95, temperature: 1.0,
            maxContextLength: 32_000, maxTokens: 4_000,
            accelerators: "gpu,cpu", visionAccelerator: "gpu"
        ),
        platformSupport: PlatformSupport(
            macOS: .gpuAndCpu, iOSDevice: .gpuAndCpu, iOSSimulator: .cpuOnly
        ),
        modelDescription: "Gemma 4 E4B standard model (4B effective params). CPU (XNNPACK) + desktop GPU (Metal). Higher quality than E2B but requires more memory.",
        recommendedFor: "Balanced quality and speed",
        modelFile: "gemma-4-E4B-it.litertlm",
        modelId: "litert-community/gemma-4-E4B-it-litert-lm"
    )

    // MARK: Gemma 4 E4B (Web / Mobile GPU)

    /// Gemma 4 E4B web/mobile variant — GPU-only for A-series chips.
    static let gemma4E4BWeb = ModelCapabilityProfile(
        id: "gemma-4-E4B-it-web.litertlm",
        displayName: "Gemma 4 E4B · Mobile GPU",
        repoId: "litert-community/gemma-4-E4B-it-litert-lm",
        runtimeType: .litertlm,
        supportsVision: SourcedValue(false, source: .catalog),
        supportsAudio: SourcedValue(false, source: .catalog),
        supportsThinking: SourcedValue(true, source: .catalog),
        supportsToolCalling: SourcedValue(true, source: .heuristic),
        supportsMTP: SourcedValue(true, source: .catalog),
        supportsConstrainedDecoding: SourcedValue(true, source: .catalog),
        architecture: ArchitectureInfo(
            architectureClass: nil, modelType: nil, isMoE: true,
            hiddenSize: nil, numLayers: nil, numAttentionHeads: nil,
            numKeyValueHeads: nil, vocabSize: nil, headDim: nil,
            maxImageResolution: nil, dtype: nil,
            quantizationBits: nil, quantizationMethod: nil
        ),
        contextWindow: SourcedValue(128_000, source: .catalog),
        fileSizeBytes: 2_970_000_000,
        estimatedMemoryGB: SourcedValue(12, source: .catalog),
        totalParameters: nil,
        parameterLabel: nil,
        confidence: .verified,
        source: .knownRegistry,
        lastUpdated: Date(),
        repoSha: nil,
        license: nil, licenseLink: nil, baseModelId: nil,
        downloads: nil, likes: nil, downloadsAllTime: nil,
        supportedLanguages: [],
        tags: [],
        defaultConfig: ModelDefaultConfig(
            topK: 1, topP: 1.0, temperature: 1.0,
            maxContextLength: 32_000, maxTokens: 4_000,
            accelerators: "gpu", visionAccelerator: nil
        ),
        platformSupport: PlatformSupport(
            macOS: .gpuOnly, iOSDevice: .gpuOnly, iOSSimulator: .gpuOnly
        ),
        modelDescription: "Mobile-optimized Gemma 4 E4B with GPU artisan shaders for A-series chips. GPU-only — no CPU subgraph.",
        recommendedFor: "Mobile text workflows",
        modelFile: "gemma-4-E4B-it-web.litertlm",
        modelId: "litert-community/gemma-4-E4B-it-litert-lm"
    )

    // MARK: Gemma 4 12B (Dense Multimodal)

    /// Gemma 4 12B — Dense encoder-free multimodal model (text + image + audio).
    /// Released June 3, 2026. 256K context window. Requires 16GB+ unified memory.
    /// Outperforms Gemma 3 27B on multiple benchmarks. Apache 2.0 license.
    static let gemma4_12B = ModelCapabilityProfile(
        id: "gemma-4-12B-it.litertlm",
        displayName: "Gemma 4 12B · Dense Multimodal",
        repoId: "litert-community/gemma-4-12B-it-litert-lm",
        runtimeType: .litertlm,
        supportsVision: SourcedValue(true, source: .catalog),
        supportsAudio: SourcedValue(true, source: .catalog),
        supportsThinking: SourcedValue(true, source: .catalog),
        supportsToolCalling: SourcedValue(true, source: .heuristic),
        supportsMTP: SourcedValue(true, source: .catalog),
        supportsConstrainedDecoding: SourcedValue(true, source: .catalog),
        architecture: ArchitectureInfo(
            architectureClass: nil, modelType: nil, isMoE: false,
            hiddenSize: nil, numLayers: nil, numAttentionHeads: nil,
            numKeyValueHeads: nil, vocabSize: nil, headDim: nil,
            maxImageResolution: nil, dtype: nil,
            quantizationBits: nil, quantizationMethod: nil
        ),
        contextWindow: SourcedValue(256_000, source: .catalog),
        fileSizeBytes: 6_547_589_312,
        estimatedMemoryGB: SourcedValue(16, source: .catalog),
        totalParameters: nil,
        parameterLabel: nil,
        confidence: .verified,
        source: .knownRegistry,
        lastUpdated: Date(),
        repoSha: nil,
        license: nil, licenseLink: nil, baseModelId: nil,
        downloads: nil, likes: nil, downloadsAllTime: nil,
        supportedLanguages: [],
        tags: [],
        defaultConfig: ModelDefaultConfig(
            topK: 64, topP: 0.95, temperature: 1.0,
            maxContextLength: 256_000, maxTokens: 8_000,
            accelerators: "gpu,cpu", visionAccelerator: "gpu"
        ),
        platformSupport: PlatformSupport(
            macOS: .gpuAndCpu, iOSDevice: .gpuAndCpu, iOSSimulator: .cpuOnly
        ),
        modelDescription: "Dense 12B model with native text, image, and audio. 256K context. Requires 16GB+ unified memory. Best quality on-device.",
        recommendedFor: "Desktop power users, coding, deep analysis",
        modelFile: "gemma-4-12B-it.litertlm",
        modelId: "litert-community/gemma-4-12B-it-litert-lm"
    )

    // MARK: Gemma 4 E2B (MLX 4-bit)

    /// MLX 4-bit quantized Gemma 4 E2B for Apple Silicon.
    /// Runs on Metal GPU via mlx-swift. Multi-file directory model.
    static let gemma4E2B_MLX = ModelCapabilityProfile(
        id: "mlx-community--gemma-4-E2B-it-4bit",
        displayName: "Gemma 4 E2B · MLX 4-bit",
        repoId: "mlx-community/gemma-4-E2B-it-4bit",
        runtimeType: .mlx,
        supportsVision: SourcedValue(true, source: .catalog),
        supportsAudio: SourcedValue(true, source: .catalog),
        supportsThinking: SourcedValue(true, source: .catalog),
        supportsToolCalling: SourcedValue(true, source: .heuristic),
        supportsMTP: SourcedValue(false, source: .catalog),
        supportsConstrainedDecoding: SourcedValue(false, source: .catalog),
        architecture: ArchitectureInfo(
            architectureClass: nil, modelType: nil, isMoE: true,
            hiddenSize: nil, numLayers: nil, numAttentionHeads: nil,
            numKeyValueHeads: nil, vocabSize: nil, headDim: nil,
            maxImageResolution: nil, dtype: nil,
            quantizationBits: 4, quantizationMethod: "mlx"
        ),
        contextWindow: SourcedValue(128_000, source: .catalog),
        fileSizeBytes: 2_200_000_000,
        estimatedMemoryGB: SourcedValue(8, source: .catalog),
        totalParameters: nil,
        parameterLabel: nil,
        confidence: .verified,
        source: .knownRegistry,
        lastUpdated: Date(),
        repoSha: nil,
        license: nil, licenseLink: nil, baseModelId: nil,
        downloads: nil, likes: nil, downloadsAllTime: nil,
        supportedLanguages: [],
        tags: [],
        defaultConfig: ModelDefaultConfig(
            topK: 40, topP: 0.9, temperature: 0.6,
            maxContextLength: 32_000, maxTokens: 4_000,
            accelerators: "gpu", visionAccelerator: "gpu"
        ),
        platformSupport: PlatformSupport(
            macOS: .gpuOnly, iOSDevice: .gpuOnly, iOSSimulator: .unknown
        ),
        modelDescription: "MLX 4-bit quantized Gemma 4 E2B for Apple Silicon. Runs on Metal GPU via mlx-swift. Multi-file directory model.",
        recommendedFor: "Apple Silicon chat, fast Metal GPU inference",
        modelFile: "mlx-community--gemma-4-E2B-it-4bit",
        modelId: "mlx-community/gemma-4-E2B-it-4bit"
    )

    // MARK: Gemma 4 E4B (MLX 4-bit)

    /// MLX 4-bit quantized Gemma 4 E4B for Apple Silicon.
    /// Higher quality than E2B. Multi-file directory model.
    static let gemma4E4B_MLX = ModelCapabilityProfile(
        id: "mlx-community--gemma-4-E4B-it-4bit",
        displayName: "Gemma 4 E4B · MLX 4-bit",
        repoId: "mlx-community/gemma-4-E4B-it-4bit",
        runtimeType: .mlx,
        supportsVision: SourcedValue(true, source: .catalog),
        supportsAudio: SourcedValue(true, source: .catalog),
        supportsThinking: SourcedValue(true, source: .catalog),
        supportsToolCalling: SourcedValue(true, source: .heuristic),
        supportsMTP: SourcedValue(false, source: .catalog),
        supportsConstrainedDecoding: SourcedValue(false, source: .catalog),
        architecture: ArchitectureInfo(
            architectureClass: nil, modelType: nil, isMoE: true,
            hiddenSize: nil, numLayers: nil, numAttentionHeads: nil,
            numKeyValueHeads: nil, vocabSize: nil, headDim: nil,
            maxImageResolution: nil, dtype: nil,
            quantizationBits: 4, quantizationMethod: "mlx"
        ),
        contextWindow: SourcedValue(128_000, source: .catalog),
        fileSizeBytes: 3_400_000_000,
        estimatedMemoryGB: SourcedValue(12, source: .catalog),
        totalParameters: nil,
        parameterLabel: nil,
        confidence: .verified,
        source: .knownRegistry,
        lastUpdated: Date(),
        repoSha: nil,
        license: nil, licenseLink: nil, baseModelId: nil,
        downloads: nil, likes: nil, downloadsAllTime: nil,
        supportedLanguages: [],
        tags: [],
        defaultConfig: ModelDefaultConfig(
            topK: 40, topP: 0.9, temperature: 0.6,
            maxContextLength: 32_000, maxTokens: 4_000,
            accelerators: "gpu", visionAccelerator: "gpu"
        ),
        platformSupport: PlatformSupport(
            macOS: .gpuOnly, iOSDevice: .gpuOnly, iOSSimulator: .unknown
        ),
        modelDescription: "MLX 4-bit quantized Gemma 4 E4B for Apple Silicon. Higher quality than E2B. Multi-file directory model.",
        recommendedFor: "Apple Silicon balanced quality",
        modelFile: "mlx-community--gemma-4-E4B-it-4bit",
        modelId: "mlx-community/gemma-4-E4B-it-4bit"
    )

    // MARK: Gemma 3n E2B (Standard INT4 — Gated)

    /// Gemma 3n E2B standard INT4 quantized model.
    /// This is the model used by the official AI Edge Gallery iOS app.
    /// **Gated model**: Requires HuggingFace authentication.
    static let gemma3nE2BStandard = ModelCapabilityProfile(
        id: "gemma-3n-E2B-it-int4.litertlm",
        displayName: "Gemma 3n E2B · INT4",
        repoId: "google/gemma-3n-E2B-it-litert-lm",
        runtimeType: .litertlm,
        supportsVision: SourcedValue(false, source: .catalog),
        supportsAudio: SourcedValue(false, source: .catalog),
        supportsThinking: SourcedValue(true, source: .catalog),
        supportsToolCalling: SourcedValue(true, source: .heuristic),
        supportsMTP: SourcedValue(false, source: .catalog),
        supportsConstrainedDecoding: SourcedValue(true, source: .catalog),
        architecture: ArchitectureInfo(
            architectureClass: nil, modelType: nil, isMoE: true,
            hiddenSize: nil, numLayers: nil, numAttentionHeads: nil,
            numKeyValueHeads: nil, vocabSize: nil, headDim: nil,
            maxImageResolution: nil, dtype: nil,
            quantizationBits: nil, quantizationMethod: nil
        ),
        contextWindow: SourcedValue(128_000, source: .catalog),
        fileSizeBytes: 3_390_000_000,
        estimatedMemoryGB: SourcedValue(8, source: .catalog),
        totalParameters: nil,
        parameterLabel: nil,
        confidence: .verified,
        source: .knownRegistry,
        lastUpdated: Date(),
        repoSha: nil,
        license: nil, licenseLink: nil, baseModelId: nil,
        downloads: nil, likes: nil, downloadsAllTime: nil,
        supportedLanguages: [],
        tags: [],
        defaultConfig: ModelDefaultConfig(
            topK: 64, topP: 0.95, temperature: 1.0,
            maxContextLength: 32_000, maxTokens: 4_000,
            accelerators: "gpu", visionAccelerator: nil
        ),
        platformSupport: PlatformSupport(
            macOS: .gpuOnly, iOSDevice: .gpuOnly, iOSSimulator: .gpuOnly
        ),
        modelDescription: "Gemma 3n E2B with INT4 quantization. GPU-only (mobile Metal shaders). Same model as the AI Edge Gallery app. Requires HuggingFace auth.",
        recommendedFor: "Gallery-compatible mobile chat",
        modelFile: "gemma-3n-E2B-it-int4.litertlm",
        modelId: "google/gemma-3n-E2B-it-litert-lm"
    )

    // MARK: Gemma 3n E2B (HW-Optimized — Gated)

    /// Gemma 3n E2B hardware-optimized variant for A-series chips.
    /// Highest hardware-level GPU shader optimization. GPU-only, no CPU fallback.
    /// **Gated model**: Requires HuggingFace authentication.
    static let gemma3nE2BHW = ModelCapabilityProfile(
        id: "gemma-3n-E2B-HW.litertlm",
        displayName: "Gemma 3n E2B · HW-Optimized",
        repoId: "google/gemma-3n-E2B-it-litert-lm",
        runtimeType: .litertlm,
        supportsVision: SourcedValue(false, source: .catalog),
        supportsAudio: SourcedValue(false, source: .catalog),
        supportsThinking: SourcedValue(true, source: .catalog),
        supportsToolCalling: SourcedValue(true, source: .heuristic),
        supportsMTP: SourcedValue(false, source: .catalog),
        supportsConstrainedDecoding: SourcedValue(true, source: .catalog),
        architecture: ArchitectureInfo(
            architectureClass: nil, modelType: nil, isMoE: true,
            hiddenSize: nil, numLayers: nil, numAttentionHeads: nil,
            numKeyValueHeads: nil, vocabSize: nil, headDim: nil,
            maxImageResolution: nil, dtype: nil,
            quantizationBits: nil, quantizationMethod: nil
        ),
        contextWindow: SourcedValue(128_000, source: .catalog),
        fileSizeBytes: 2_830_000_000,
        estimatedMemoryGB: SourcedValue(8, source: .catalog),
        totalParameters: nil,
        parameterLabel: nil,
        confidence: .verified,
        source: .knownRegistry,
        lastUpdated: Date(),
        repoSha: nil,
        license: nil, licenseLink: nil, baseModelId: nil,
        downloads: nil, likes: nil, downloadsAllTime: nil,
        supportedLanguages: [],
        tags: [],
        defaultConfig: ModelDefaultConfig(
            topK: 64, topP: 0.95, temperature: 1.0,
            maxContextLength: 32_000, maxTokens: 4_000,
            accelerators: "gpu", visionAccelerator: nil
        ),
        platformSupport: PlatformSupport(
            macOS: .gpuOnly, iOSDevice: .gpuOnly, iOSSimulator: .gpuOnly
        ),
        modelDescription: "Hardware-optimized Gemma 3n E2B with A-series-specific Metal GPU shaders. Best mobile GPU performance. Requires HuggingFace auth.",
        recommendedFor: "Maximum mobile GPU throughput",
        modelFile: "gemma-3n-E2B-HW.litertlm",
        modelId: "google/gemma-3n-E2B-it-litert-lm"
    )

    // swiftlint:enable identifier_name function_body_length
}
