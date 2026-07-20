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
import os

// MARK: - Model Card Parser

/// Heuristic parser that infers `ModelCapabilityProfile` from HuggingFace API responses.
///
/// `ModelCardParser` examines multiple signals from the HF API — tags, library name,
/// sibling file listings, and README content — to build a best-effort `ModelCapabilityProfile`
/// for models not in the known registry.
///
/// ## Inference Heuristics
///
/// | Signal | Source | Inference |
/// |--------|--------|-----------|
/// | Filename contains `-web` | siblings | GPU-only |
/// | Tags include `vision` / `image-text-to-text` | HF API | supportsImage = true |
/// | Tags include `audio` | HF API | supportsAudio = true |
/// | Name contains `E2B`, `E4B`, `12B`, etc. | model ID | parameter count, memory |
/// | README mentions "MTP" or "speculative" | readme | supportsMTP = true |
/// | LFS file size | siblings | sizeInBytes, minDeviceMemoryGB |
/// | `library_name` = "litert" | HF API | runtimeType = .litertlm |
/// | Author is `google/*` | HF API | requiresAuth = true |
///
/// For anything unknown, safe defaults are used.
enum ModelCardParser {

    private static let logger = Logger(
        subsystem: "com.andrewvoirol.EdgeAILab",
        category: "modelCardParser"
    )

    // MARK: - Public API

    /// Infer `ModelCapabilityProfile` and confidence from a HuggingFace model's API response.
    ///
    /// - Parameters:
    ///   - model: The HuggingFace model info (from list or detail endpoint).
    ///   - siblings: Optional file listing (from detail endpoint). Overrides `model.siblings` if provided.
    ///   - readmeContent: Optional README.md content for deeper analysis.
    /// - Returns: A tuple of inferred `ModelCapabilityProfile` and `MetadataConfidence`.
    static func inferMetadata(
        from model: HFModelInfo,
        siblings: [HFSibling]? = nil,
        readmeContent: String? = nil
    ) -> (ModelCapabilityProfile, MetadataConfidence) {
        let effectiveSiblings = siblings ?? model.siblings
        var signalCount = 0

        // — Runtime type
        let runtimeType = inferRuntimeType(model: model, siblings: effectiveSiblings)
        if runtimeType != .litertlm { signalCount += 1 } // Non-default means we found a signal

        // — Model file
        let modelFile = inferPrimaryModelFile(
            repoId: model.id,
            siblings: effectiveSiblings,
            runtimeType: runtimeType
        )
        signalCount += (modelFile != nil) ? 2 : 0  // File found is a strong signal

        // — File size
        let sizeInBytes = inferFileSize(siblings: effectiveSiblings, filename: modelFile)
        if sizeInBytes > 0 { signalCount += 1 }

        // — Parameter count & memory
        var paramInfo = inferParameterInfo(from: model.id)
        // Override with API-provided parameter count if available
        if let apiParams = model.totalParameters {
            let label = Self.formatParameterLabel(apiParams)
            let memoryGB = Self.estimateMemoryGB(parameterCount: apiParams)
            paramInfo = ParameterInfo(label: label, estimatedParams: label, minMemoryGB: memoryGB)
            signalCount += 2  // Strong API signal
        }
        if paramInfo.label != nil { signalCount += 1 }

        // — Capabilities
        let supportsImage = inferImageSupport(model: model, readmeContent: readmeContent)
        let supportsAudio = inferAudioSupport(model: model, readmeContent: readmeContent)
        let supportsMTP = inferMTPSupport(model: model, readmeContent: readmeContent)
        if supportsImage || supportsAudio || supportsMTP { signalCount += 1 }

        // — Backend support
        let isWebVariant = modelFile?.contains("-web") ?? false
        let platformSupport = inferPlatformSupport(isWebVariant: isWebVariant, runtimeType: runtimeType)

        // — Build capabilities array
        var capabilities: [String] = ["llm_thinking"]
        if supportsMTP { capabilities.append("speculative_decoding") }

        // — Context window
        let contextWindow = inferContextWindow(model: model, readmeContent: readmeContent)
        if model.contextLength != nil { signalCount += 2 }  // Direct API signal is very strong

        // — Architecture description
        let archType: String
        if let apiArch = model.architecture {
            // Use API architecture (e.g., "Gemma4ForConditionalGeneration")
            let cleanArch = apiArch
                .replacingOccurrences(of: "ForConditionalGeneration", with: " (Multimodal)")
                .replacingOccurrences(of: "ForCausalLM", with: " (Text)")
            archType = cleanArch
        } else if let ggufArch = model.ggufArchitecture {
            archType = ggufArch.capitalized
        } else {
            archType = paramInfo.label.map { "\($0)" } ?? "Unknown Architecture"
        }

        // — Accelerators string
        let accelerators = isWebVariant ? "gpu" : "gpu,cpu"

        // — Display name
        let displayName = inferDisplayName(model: model, paramInfo: paramInfo, isWebVariant: isWebVariant)

        // — Capability sources
        // Use .apiMetadata for data derived from HF API (tags, pipeline_tag, etc.)
        // and .heuristic for name-based inference
        let capSource: CapabilitySource = (model.tags.isEmpty && model.pipelineTag == nil) ? .heuristic : .apiMetadata
        // archSource intentionally omitted — architecture info comes directly from model fields

        // — Build profile
        let profile = ModelCapabilityProfile(
            id: modelFile ?? "\(model.displayName).litertlm",
            displayName: displayName,
            repoId: model.id,
            runtimeType: runtimeType,
            supportsVision: SourcedValue(supportsImage, source: capSource),
            supportsAudio: SourcedValue(supportsAudio, source: capSource),
            supportsThinking: SourcedValue(true, source: .heuristic),
            supportsToolCalling: SourcedValue(false, source: .heuristic),
            supportsMTP: SourcedValue(supportsMTP, source: readmeContent != nil ? .readme : .heuristic),
            supportsConstrainedDecoding: SourcedValue(true, source: .heuristic),
            architecture: ArchitectureInfo(
                architectureClass: archType,
                modelType: nil,
                isMoE: archType.contains("MoE") || archType.contains("Edge"),
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
            contextWindow: SourcedValue(contextWindow, source: model.contextLength != nil ? .apiMetadata : .heuristic),
            fileSizeBytes: sizeInBytes,
            estimatedMemoryGB: SourcedValue(paramInfo.minMemoryGB, source: model.totalParameters != nil ? .apiMetadata : .heuristic),
            totalParameters: model.totalParameters,
            parameterLabel: paramInfo.label,
            confidence: scoreConfidence(signalCount: signalCount, hasReadme: readmeContent != nil),
            source: .huggingFaceInferred,
            lastUpdated: Date(),
            repoSha: nil,
            license: nil, licenseLink: nil, baseModelId: nil,
            downloads: model.downloads, likes: model.likes, downloadsAllTime: nil,
            supportedLanguages: [],
            tags: model.tags,
            defaultConfig: ModelDefaultConfig(
                topK: isWebVariant ? 1 : 64,
                topP: isWebVariant ? 1.0 : 0.95,
                temperature: 1.0,
                maxContextLength: min(contextWindow, 32_000),
                maxTokens: 4_000,
                accelerators: accelerators,
                visionAccelerator: supportsImage ? "gpu" : nil
            ),
            platformSupport: platformSupport,
            modelDescription: inferDescription(model: model, paramInfo: paramInfo),
            recommendedFor: inferRecommendation(paramInfo: paramInfo, runtimeType: runtimeType),
            modelFile: modelFile ?? "\(model.displayName).litertlm",
            modelId: model.id
        )

        // — Confidence scoring
        let confidence = scoreConfidence(signalCount: signalCount, hasReadme: readmeContent != nil)

        logger.info(
            """
            📋 Inferred profile for \(model.id, privacy: .public): \
            runtime=\(runtimeType.displayName, privacy: .public), \
            file=\(modelFile ?? "unknown", privacy: .public), \
            size=\(sizeInBytes), \
            confidence=\(confidence.label, privacy: .public) \
            (signals: \(signalCount))
            """
        )

        return (profile, confidence)
    }

    // MARK: - Runtime Type Inference

    /// Determine the runtime type from library name, tags, and file extensions.
    private static func inferRuntimeType(model: HFModelInfo, siblings: [HFSibling]?) -> RuntimeType {
        // Check library_name first (most reliable)
        if let lib = model.libraryName?.lowercased() {
            if lib.contains("litert") { return .litertlm }
            if lib == "mlx" { return .mlx }
            if lib == "gguf" || lib == "llama.cpp" { return .gguf }
        }

        // Check for GGUF metadata presence (strong signal)
        if model.gguf != nil { return .gguf }

        // Check tags
        if model.tags.contains(where: { $0.lowercased().contains("litert") }) { return .litertlm }
        if model.tags.contains(where: { $0.lowercased() == "mlx" }) { return .mlx }
        if model.tags.contains(where: { $0.lowercased() == "gguf" }) { return .gguf }

        // Check file extensions in siblings
        if let siblings {
            let filenames = siblings.map(\.rfilename)
            if filenames.contains(where: { $0.hasSuffix(".litertlm") }) { return .litertlm }
            if filenames.contains(where: { $0.hasSuffix(".gguf") }) { return .gguf }

            // config.json + *.safetensors is necessary but NOT sufficient for MLX.
            // Every raw transformers repo (BF16/FP32 weights) also has this layout.
            // Only classify as MLX if we also have a positive MLX signal:
            //   - author is mlx-community
            //   - tags include "mlx"
            //   - library_name is "mlx"
            //   - repo ID contains "-mlx" or "mlx-"
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
                // No MLX signal → this is a raw transformers repo, not runnable on-device.
                // Fall through to model ID check, then return nil.
            }
        }

        // Check model ID
        if model.id.lowercased().contains("litert") { return .litertlm }
        if model.author.lowercased() == "mlx-community" { return .mlx }
        if model.id.lowercased().contains("gguf") { return .gguf }

        return .litertlm  // Default assumption
    }

    // MARK: - Model File Inference

    /// Find the primary model file from the siblings listing.
    private static func inferPrimaryModelFile(
        repoId: String,
        siblings: [HFSibling]?,
        runtimeType: RuntimeType
    ) -> String? {
        guard let siblings else { return nil }

        let targetExtension = runtimeType.fileExtension

        // For LiteRT-LM: find .litertlm files, prefer non-web variant
        let candidates = siblings.filter { $0.rfilename.hasSuffix(".\(targetExtension)") }

        if candidates.isEmpty { return nil }
        if candidates.count == 1 { return candidates.first?.rfilename }

        // Prefer standard variant over web variant
        if let standard = candidates.first(where: { !$0.rfilename.contains("-web") }) {
            return standard.rfilename
        }

        // Fall back to first candidate
        return candidates.first?.rfilename
    }

    // MARK: - File Size Inference

    /// Extract file size from siblings, preferring LFS sizes.
    private static func inferFileSize(siblings: [HFSibling]?, filename: String?) -> Int64 {
        guard let siblings else { return 0 }

        // If we know the specific file, get its size
        if let filename,
           let sibling = siblings.first(where: { $0.rfilename == filename }) {
            if let lfs = sibling.lfs { return lfs.size }
            if let size = sibling.size { return size }
        }

        // Fall back to largest file (likely the model weights)
        let sizes: [Int64] = siblings.compactMap { sibling in
            if let lfs = sibling.lfs { return lfs.size }
            return sibling.size
        }
        return sizes.max() ?? 0
    }

    // MARK: - Parameter Count Inference

    /// Information about model parameters extracted from the model name.
    struct ParameterInfo {
        let label: String?        // e.g., "Dense 12B", "MoE Edge (2B effective)"
        let estimatedParams: String?  // e.g., "12B", "E2B"
        let minMemoryGB: Int
    }

    /// Parse parameter count from the model ID or name.
    private static func inferParameterInfo(from repoId: String) -> ParameterInfo {
        let lowered = repoId.lowercased()

        // Dense models
        if lowered.contains("12b") || lowered.contains("13b") {
            return ParameterInfo(label: "Dense 12B", estimatedParams: "12B", minMemoryGB: 16)
        }
        if lowered.contains("27b") {
            return ParameterInfo(label: "Dense 27B", estimatedParams: "27B", minMemoryGB: 32)
        }
        if lowered.contains("9b") {
            return ParameterInfo(label: "Dense 9B", estimatedParams: "9B", minMemoryGB: 12)
        }
        if lowered.contains("7b") {
            return ParameterInfo(label: "Dense 7B", estimatedParams: "7B", minMemoryGB: 12)
        }
        if lowered.contains("3b") && !lowered.contains("e3b") {
            return ParameterInfo(label: "Dense 3B", estimatedParams: "3B", minMemoryGB: 8)
        }
        if lowered.contains("2b") && !lowered.contains("e2b") {
            return ParameterInfo(label: "Dense 2B", estimatedParams: "2B", minMemoryGB: 8)
        }
        if lowered.contains("1b") {
            return ParameterInfo(label: "Dense 1B", estimatedParams: "1B", minMemoryGB: 4)
        }

        // MoE Edge models (Gemma 4 style)
        if lowered.contains("e2b") {
            return ParameterInfo(label: "MoE Edge (2B effective)", estimatedParams: "E2B", minMemoryGB: 8)
        }
        if lowered.contains("e4b") {
            return ParameterInfo(label: "MoE Edge (4B effective)", estimatedParams: "E4B", minMemoryGB: 12)
        }

        // If file size is known, estimate from that
        return ParameterInfo(label: nil, estimatedParams: nil, minMemoryGB: 8)
    }

    // MARK: - Capability Inference

    /// Check if the model supports image input.
    private static func inferImageSupport(model: HFModelInfo, readmeContent: String?) -> Bool {
        // Check architecture name for multimodal indicator
        if let arch = model.architecture?.lowercased() {
            if arch.contains("conditionalgeneration") || arch.contains("vision") {
                return true
            }
        }

        // Check tags
        let imageIndicators = ["vision", "image-text-to-text", "visual-question-answering", "multimodal"]
        if model.tags.contains(where: { tag in
            imageIndicators.contains(where: { tag.lowercased().contains($0) })
        }) {
            return true
        }

        // Check pipeline tag
        if let pipeline = model.pipelineTag?.lowercased() {
            if imageIndicators.contains(where: { pipeline.contains($0) }) {
                return true
            }
        }

        // Check README
        if let readme = readmeContent?.lowercased() {
            if readme.contains("image input") || readme.contains("vision") || readme.contains("multimodal") {
                return true
            }
        }

        return false
    }

    /// Check if the model supports audio input.
    private static func inferAudioSupport(model: HFModelInfo, readmeContent: String?) -> Bool {
        // Check architecture name for audio indicator
        if let arch = model.architecture?.lowercased() {
            if arch.contains("audio") || arch.contains("speech") {
                return true
            }
        }

        if model.tags.contains(where: { $0.lowercased().contains("audio") }) {
            return true
        }

        if let pipeline = model.pipelineTag?.lowercased(),
           pipeline.contains("audio") {
            return true
        }

        if let readme = readmeContent?.lowercased(),
           readme.contains("audio input") || readme.contains("speech") {
            return true
        }

        return false
    }

    /// Check if Multi-Token Prediction (speculative decoding) is supported.
    private static func inferMTPSupport(model: HFModelInfo, readmeContent: String?) -> Bool {
        if model.tags.contains(where: {
            $0.lowercased().contains("mtp") || $0.lowercased().contains("speculative")
        }) {
            return true
        }

        if let readme = readmeContent?.lowercased() {
            if readme.contains("mtp") || readme.contains("speculative decoding")
                || readme.contains("multi-token prediction") {
                return true
            }
        }

        return false
    }

    // MARK: - Platform Support Inference

    /// Infer platform support from model characteristics.
    private static func inferPlatformSupport(isWebVariant: Bool, runtimeType: RuntimeType) -> PlatformSupport {
        switch runtimeType {
        case .litertlm:
            if isWebVariant {
                // Web variants are GPU-only
                return PlatformSupport(
                    macOS: .gpuOnly,
                    iOSDevice: .gpuOnly,
                    iOSSimulator: .gpuOnly
                )
            } else {
                // Standard LiteRT-LM models support both GPU and CPU
                return PlatformSupport(
                    macOS: .gpuAndCpu,
                    iOSDevice: .gpuAndCpu,
                    iOSSimulator: .cpuOnly
                )
            }

        case .mlx:
            // MLX runs on macOS with Metal, limited iOS support
            return PlatformSupport(
                macOS: .gpuOnly,
                iOSDevice: .unknown,
                iOSSimulator: .unknown
            )

        case .gguf:
            // GGUF typically supports CPU inference
            return PlatformSupport(
                macOS: .gpuAndCpu,
                iOSDevice: .cpuOnly,
                iOSSimulator: .cpuOnly
            )
        }
    }

    // MARK: - Context Window Inference

    /// Infer context window size from model metadata.
    private static func inferContextWindow(model: HFModelInfo, readmeContent: String?) -> Int {
        // Prefer API-provided context length (from gguf.context_length)
        if let ctx = model.contextLength {
            return ctx
        }

        // Check README for explicit context length
        if let readme = readmeContent?.lowercased() {
            if readme.contains("256k") || readme.contains("256,000") || readme.contains("256000") {
                return 256_000
            }
            if readme.contains("128k") || readme.contains("128,000") || readme.contains("128000") {
                return 128_000
            }
            if readme.contains("32k") || readme.contains("32,000") || readme.contains("32000") {
                return 32_000
            }
            if readme.contains("8k") || readme.contains("8,000") || readme.contains("8192") {
                return 8_192
            }
        }

        // Default to 128K for Gemma models, 32K for others
        if model.id.lowercased().contains("gemma") {
            return 128_000
        }

        return 32_000
    }

    // MARK: - Display Helpers

    /// Generate a human-readable display name.
    private static func inferDisplayName(
        model: HFModelInfo,
        paramInfo: ParameterInfo,
        isWebVariant: Bool
    ) -> String {
        let baseName = model.displayName
            .replacingOccurrences(of: "-litert-lm", with: "")
            .replacingOccurrences(of: "-litert", with: "")

        if let params = paramInfo.estimatedParams {
            let variant = isWebVariant ? " · Mobile GPU" : " · Standard"
            return "\(baseName) \(params)\(variant)"
        }

        return baseName
    }

    /// Generate a description.
    private static func inferDescription(model: HFModelInfo, paramInfo: ParameterInfo) -> String {
        var parts: [String] = []

        if let params = paramInfo.estimatedParams {
            parts.append("\(params) parameter model")
        } else {
            parts.append("Model")
        }

        parts.append("from \(model.author)")

        if let pipeline = model.pipelineTag {
            parts.append("for \(pipeline)")
        }

        return parts.joined(separator: " ") + "."
    }

    /// Generate a recommendation string.
    private static func inferRecommendation(paramInfo: ParameterInfo, runtimeType: RuntimeType) -> String {
        guard runtimeType.isSupported else {
            return "Not yet runnable (\(runtimeType.displayName))"
        }

        switch paramInfo.minMemoryGB {
        case ...4:
            return "Lightweight mobile inference"
        case 5...8:
            return "Mobile and tablet use"
        case 9...12:
            return "Balanced quality and speed"
        case 13...16:
            return "Desktop power users"
        default:
            return "High-memory workstations"
        }
    }

    // MARK: - Confidence Scoring

    /// Score confidence based on how many inference signals were available.
    private static func scoreConfidence(signalCount: Int, hasReadme: Bool) -> MetadataConfidence {
        var score = signalCount
        if hasReadme { score += 1 }

        switch score {
        case 5...:
            return .high
        case 3...4:
            return .medium
        default:
            return .low
        }
    }

    // MARK: - API Data Helpers

    /// Format a raw parameter count into a human-readable label.
    private static func formatParameterLabel(_ count: Int64) -> String {
        if count >= 1_000_000_000 {
            let billions = Double(count) / 1_000_000_000
            if billions >= 10 {
                return "\(Int(billions))B"
            }
            return String(format: "%.1fB", billions)
        }
        if count >= 1_000_000 {
            return "\(count / 1_000_000)M"
        }
        return "\(count)"
    }

    /// Estimate minimum memory requirement from parameter count.
    private static func estimateMemoryGB(parameterCount: Int64) -> Int {
        // Rough estimate: 1B params ≈ 2 GB at 16-bit, ≈ 1 GB at 8-bit, ≈ 0.5 GB at 4-bit
        // Use 2 bytes/param as conservative estimate (FP16/BF16)
        let estimatedGB = Double(parameterCount) * 2.0 / 1_073_741_824.0
        return max(4, Int(ceil(estimatedGB)))
    }
}
