import Foundation

// MARK: - Known Model Catalog

/// Catalog of known models with pre-built `ModelCapabilityProfile` entries.
///
/// This replaces `ModelRegistry` — instead of looking up `ModelMetadata` objects
/// and converting them, each model entry is a `ModelCapabilityProfile` directly
/// usable by the capability system without conversion.
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
    // Each profile is built from the corresponding ModelRegistry entry via
    // ModelCapabilityProfileBuilder.fromModelMetadata() to ensure property mapping
    // is consistent and complete.

    /// Standard build with both CPU (XNNPACK) and desktop GPU (Metal) subgraphs.
    @available(*, deprecated, message: "ModelRegistry still needed — profiles built from ModelRegistry entries")
    private static let _buildMarker: Void = ()

    // swiftlint:disable identifier_name

    /// Gemma 4 E2B Standard (Desktop GPU+CPU) — default test model
    static let gemma4E2BStandard = ModelCapabilityProfileBuilder.fromModelMetadata(
        ModelRegistry.gemma4E2BStandard, source: .knownRegistry, confidence: .verified
    )

    /// Gemma 4 E2B Web (Mobile GPU) — fastest mobile decode
    static let gemma4E2BWeb = ModelCapabilityProfileBuilder.fromModelMetadata(
        ModelRegistry.gemma4E2BWeb, source: .knownRegistry, confidence: .verified
    )

    /// Gemma 4 E4B Standard (Desktop GPU+CPU)
    static let gemma4E4BStandard = ModelCapabilityProfileBuilder.fromModelMetadata(
        ModelRegistry.gemma4E4BStandard, source: .knownRegistry, confidence: .verified
    )

    /// Gemma 4 E4B Web (Mobile GPU)
    static let gemma4E4BWeb = ModelCapabilityProfileBuilder.fromModelMetadata(
        ModelRegistry.gemma4E4BWeb, source: .knownRegistry, confidence: .verified
    )

    /// Gemma 4 12B Dense Multimodal — flagship
    static let gemma4_12B = ModelCapabilityProfileBuilder.fromModelMetadata(
        ModelRegistry.gemma4_12B, source: .knownRegistry, confidence: .verified
    )

    /// Gemma 4 E2B MLX 4-bit
    static let gemma4E2B_MLX = ModelCapabilityProfileBuilder.fromModelMetadata(
        ModelRegistry.gemma4E2B_MLX, source: .knownRegistry, confidence: .verified
    )

    /// Gemma 4 E4B MLX 4-bit
    static let gemma4E4B_MLX = ModelCapabilityProfileBuilder.fromModelMetadata(
        ModelRegistry.gemma4E4B_MLX, source: .knownRegistry, confidence: .verified
    )

    /// Gemma 3n E2B Standard INT4 (gated)
    static let gemma3nE2BStandard = ModelCapabilityProfileBuilder.fromModelMetadata(
        ModelRegistry.gemma3nE2BStandard, source: .knownRegistry, confidence: .verified
    )

    /// Gemma 3n E2B HW-Optimized (gated)
    static let gemma3nE2BHW = ModelCapabilityProfileBuilder.fromModelMetadata(
        ModelRegistry.gemma3nE2BHW, source: .knownRegistry, confidence: .verified
    )

    // swiftlint:enable identifier_name
}
