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

// MARK: - Metadata Source

/// Tracks how a model's metadata was obtained.
///
/// The source determines both the confidence level and how the metadata
/// should be treated during catalog merges (e.g., known registry always wins).
enum MetadataSource: String, Codable, Sendable {
    /// From the built-in `ModelRegistry.knownModels` — hand-verified metadata.
    case knownRegistry
    /// Inferred from HuggingFace API responses and model card parsing.
    case huggingFaceInferred
    /// Imported from the Kaggle Models API.
    case kaggle
    /// Manually entered or corrected by the user.
    case userProvided
}

// MARK: - Metadata Confidence

/// Confidence level for inferred model metadata.
///
/// Higher confidence means more signals were available during inference.
/// The UI uses this to show users how reliable the displayed capabilities are.
enum MetadataConfidence: String, Codable, Sendable, Comparable {
    /// Hand-verified by the developer or confirmed via runtime testing.
    case verified
    /// Multiple strong signals agree (e.g., library_name + file extension + tags).
    case high
    /// Some signals available but gaps exist (e.g., no README, limited tags).
    case medium
    /// Minimal signals — mostly defaults. User should verify before relying on this.
    case low

    // MARK: - Display

    /// Emoji indicator for inline UI display.
    var emoji: String {
        switch self {
        case .verified: return "✅"
        case .high: return "🟢"
        case .medium: return "🟡"
        case .low: return "🔴"
        }
    }

    /// Human-readable label for settings/detail views.
    var label: String {
        switch self {
        case .verified: return "Verified"
        case .high: return "High Confidence"
        case .medium: return "Medium Confidence"
        case .low: return "Low Confidence"
        }
    }

    // MARK: - Comparable

    /// Ordering: verified > high > medium > low.
    private var sortOrder: Int {
        switch self {
        case .verified: return 3
        case .high: return 2
        case .medium: return 1
        case .low: return 0
        }
    }

    static func < (lhs: MetadataConfidence, rhs: MetadataConfidence) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

// MARK: - Dynamic Model Metadata

/// A model catalog entry that wraps `ModelMetadata` with additional provenance
/// and confidence information.
///
/// `DynamicModelMetadata` is the unit of persistence in `DynamicModelCatalog`.
/// It tracks where the metadata came from, how confident we are in the inferred
/// fields, and when the model was imported/verified.
///
/// ## Factory Methods
/// Use `fromKnownModel(_:)` for registry models and
/// `fromHuggingFace(repoId:metadata:confidence:)` for imported models.
struct DynamicModelMetadata: Codable, Sendable, Identifiable {

    /// Unique identifier — HuggingFace repo ID for imported models,
    /// or modelFile for known registry models.
    let id: String

    /// How this metadata was obtained.
    let source: MetadataSource

    /// The core model metadata (capabilities, platform support, config, etc.).
    var metadata: ModelMetadata

    /// Confidence in the inferred metadata fields.
    let confidence: MetadataConfidence

    /// When this model was first imported into the catalog.
    let importedAt: Date

    /// When the metadata was last verified (e.g., re-fetched from HF, runtime probed).
    var lastVerifiedAt: Date?

    /// Optional user-provided notes about this model.
    var userNotes: String?

    // MARK: - Factory Methods

    /// Create a `DynamicModelMetadata` entry from a known registry model.
    ///
    /// Known models have hand-verified metadata, so confidence is always `.verified`
    /// and source is `.knownRegistry`.
    ///
    /// - Parameter model: A `ModelMetadata` from `ModelRegistry.knownModels`.
    /// - Returns: A fully-populated catalog entry.
    static func fromKnownModel(_ model: ModelMetadata) -> DynamicModelMetadata {
        DynamicModelMetadata(
            id: model.modelFile,
            source: .knownRegistry,
            metadata: model,
            confidence: .verified,
            importedAt: Date.distantPast,
            lastVerifiedAt: Date.distantPast,
            userNotes: nil
        )
    }

    /// Create a `DynamicModelMetadata` entry from HuggingFace inference.
    ///
    /// The `ModelCardParser` produces a `ModelMetadata` and confidence level by
    /// analyzing the HF API response and model card content.
    ///
    /// - Parameters:
    ///   - repoId: The HuggingFace repository ID (e.g., "litert-community/gemma-4-E2B-it-litert-lm").
    ///   - metadata: The inferred `ModelMetadata` from `ModelCardParser`.
    ///   - confidence: The confidence level from the parser.
    /// - Returns: A catalog entry ready for persistence.
    static func fromHuggingFace(
        repoId: String,
        metadata: ModelMetadata,
        confidence: MetadataConfidence
    ) -> DynamicModelMetadata {
        DynamicModelMetadata(
            id: repoId,
            source: .huggingFaceInferred,
            metadata: metadata,
            confidence: confidence,
            importedAt: Date(),
            lastVerifiedAt: nil,
            userNotes: nil
        )
    }

    /// Create a `DynamicModelMetadata` entry from a Kaggle model handle.
    ///
    /// Since the Kaggle API provides limited metadata compared to HuggingFace,
    /// this uses conservative defaults for most fields. The model file will be
    /// determined after downloading and extracting the `.tar.gz` archive.
    ///
    /// - Parameters:
    ///   - handle: The parsed `KaggleModelHandle` from the URL.
    ///   - downloadURL: The constructed Kaggle API download URL.
    /// - Returns: A catalog entry ready for persistence.
    static func fromKaggle(
        handle: KaggleModelHandle,
        downloadURL: URL
    ) -> DynamicModelMetadata {
        let displayName = handle.variation ?? handle.modelSlug
        let modelId = "kaggle/\(handle.owner)/\(handle.modelSlug)"
        let modelFile = "\(displayName).litertlm"  // Best guess; updated after extraction

        let metadata = ModelMetadata(
            name: displayName,
            modelId: modelId,
            modelFile: modelFile,
            description: "Model from Kaggle: \(handle.owner)/\(handle.modelSlug)",
            sizeInBytes: 0,              // Unknown until downloaded
            minDeviceMemoryGB: 8,        // Conservative default
            contextWindowSize: 32_000,   // Conservative default
            architectureType: "Unknown",
            recommendedFor: "Imported from Kaggle",
            supportsImage: false,
            supportsAudio: false,
            capabilities: ["llm_thinking"],
            defaultConfig: ModelDefaultConfig(
                topK: 64,
                topP: 0.95,
                temperature: 1.0,
                maxContextLength: 32_000,
                maxTokens: 4_000,
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

        return DynamicModelMetadata(
            id: modelId,
            source: .kaggle,
            metadata: metadata,
            confidence: .low,
            importedAt: Date(),
            lastVerifiedAt: nil,
            userNotes: nil
        )
    }

}

