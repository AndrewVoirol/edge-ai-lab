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

// MARK: - Backend Capability

/// Describes what backends a loaded model supports on the current platform.
/// Determined either from the known-model registry or via runtime probing.
enum BackendCapability: String, Codable, Sendable {
    /// Model supports GPU only (e.g., web variant — no CPU subgraph)
    case gpuOnly
    /// Model supports CPU only on this platform (e.g., standard model on iOS device — GPU shaders incompatible)
    case cpuOnly
    /// Model supports both GPU and CPU on this platform
    case gpuAndCpu
    /// Not yet determined — needs runtime probing
    case unknown

    /// Whether GPU is a viable backend.
    var supportsGPU: Bool {
        self == .gpuOnly || self == .gpuAndCpu
    }

    /// Whether CPU is a viable backend.
    var supportsCPU: Bool {
        self == .cpuOnly || self == .gpuAndCpu
    }

    /// Recommended backend for this capability on the current platform.
    var recommendedBackend: BackendRecommendation {
        switch self {
        case .gpuOnly:
            return .gpu
        case .cpuOnly:
            return .cpu
        case .gpuAndCpu:
            return .gpu  // Prefer GPU when both available
        case .unknown:
            return .probeRequired
        }
    }
}

/// Backend recommendation result.
enum BackendRecommendation: String, Sendable {
    case gpu
    case cpu
    case probeRequired
}

// MARK: - Model Metadata

/// Metadata about a known LiteRT-LM model, inspired by the Google AI Edge Gallery allowlist.
/// Used to pre-populate UI with capabilities before loading, and to guide backend selection.
struct ModelMetadata: Codable, Sendable, Identifiable, Hashable {
    var id: String { modelFile }

    // MARK: - Hashable (based on unique modelFile)
    static func == (lhs: ModelMetadata, rhs: ModelMetadata) -> Bool {
        lhs.modelFile == rhs.modelFile
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(modelFile)
    }

    /// Human-readable model name (e.g., "Gemma-4-E2B-it")
    let name: String

    /// HuggingFace model identifier (e.g., "litert-community/gemma-4-E2B-it-litert-lm")
    let modelId: String

    /// Expected filename on disk (e.g., "gemma-4-E2B-it.litertlm")
    let modelFile: String

    /// Short description of the model
    let description: String

    /// Expected file size in bytes
    let sizeInBytes: Int64

    /// Minimum device memory required in GB
    let minDeviceMemoryGB: Int

    /// Context window size in tokens (e.g., 128_000 or 256_000).
    let contextWindowSize: Int

    /// Architecture type for display (e.g., "MoE Edge", "Dense Multimodal").
    let architectureType: String

    /// Human-readable recommendation (e.g., "Mobile chat", "Desktop coding").
    let recommendedFor: String

    /// Whether the model supports image input
    let supportsImage: Bool

    /// Whether the model supports audio input
    let supportsAudio: Bool

    /// Supported capabilities (e.g., "speculative_decoding", "llm_thinking")
    let capabilities: [String]

    /// Default inference configuration
    let defaultConfig: ModelDefaultConfig

    /// Platform-specific backend support
    let platformSupport: PlatformSupport

    /// HuggingFace download URL for fetching this model.
    /// Constructed from the modelId and modelFile.
    var downloadURL: URL? {
        URL(string: "https://huggingface.co/\(modelId)/resolve/main/\(modelFile)")
    }

    /// Whether this model requires HuggingFace authentication (gated model).
    /// Models under `google/*` repos are typically gated; `litert-community/*` are public.
    var requiresAuth: Bool {
        modelId.hasPrefix("google/")
    }

    /// Whether speculative decoding (MTP) is available for this model.
    var supportsMTP: Bool {
        capabilities.contains("speculative_decoding")
    }

    /// Whether tool calling is supported (assumed true for -it instruction tuned models).
    var supportsToolCalling: Bool {
        modelId.contains("-it")
    }
}

/// Default inference configuration for a model, mirroring the Gallery allowlist schema.
struct ModelDefaultConfig: Codable, Sendable {
    let topK: Int
    let topP: Double
    let temperature: Double
    let maxContextLength: Int
    let maxTokens: Int
    let accelerators: String       // e.g., "gpu,cpu" or "gpu"
    let visionAccelerator: String? // e.g., "gpu"
}

/// Platform-specific backend support matrix.
/// Encodes which backends work on which platforms for a given model.
struct PlatformSupport: Codable, Sendable {
    let macOS: BackendCapability
    let iOSDevice: BackendCapability
    let iOSSimulator: BackendCapability

    /// Returns the capability for the current runtime platform.
    var currentPlatform: BackendCapability {
        #if targetEnvironment(simulator)
        return iOSSimulator
        #elseif os(iOS)
        return iOSDevice
        #elseif os(macOS)
        return macOS
        #else
        return .unknown
        #endif
    }
}

// MARK: - Known Model Registry

/// Registry of known Gemma 4 models with pre-verified platform compatibility.
/// Populated from HuggingFace litert-community models and Gallery allowlist data.
enum ModelRegistry {

    /// All known models in the registry.
    /// Ordered by recommendation: 12B first (flagship), then E4B, then E2B, then 3n.
    static let knownModels: [ModelMetadata] = [
        gemma4_12B,           // Flagship dense multimodal
        gemma4E4BStandard,
        gemma4E4BWeb,
        gemma4E2BStandard,
        gemma4E2BWeb,
    ]

    // MARK: - Gemma 4 E2B (Standard)

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
    static let gemma4E2BStandard = ModelMetadata(
        name: "Gemma 4 E2B · Desktop GPU+CPU",
        modelId: "litert-community/gemma-4-E2B-it-litert-lm",
        modelFile: "gemma-4-E2B-it.litertlm",
        description: "Standard Gemma 4 E2B model with CPU (XNNPACK) and desktop GPU (Metal) support. Desktop Metal shaders also work on A-series iOS GPUs (verified on iPhone 16 Pro Max).",
        sizeInBytes: 2_588_147_712,
        minDeviceMemoryGB: 8,
        contextWindowSize: 128_000,
        architectureType: "MoE Edge (2B effective)",
        recommendedFor: "Mobile chat, quick responses",
        supportsImage: true,
        supportsAudio: true,
        capabilities: ["llm_thinking", "speculative_decoding"],
        defaultConfig: ModelDefaultConfig(
            topK: 64,
            topP: 0.95,
            temperature: 1.0,
            maxContextLength: 32_000,
            maxTokens: 4_000,
            accelerators: "gpu,cpu",
            visionAccelerator: "gpu"
        ),
        platformSupport: PlatformSupport(
            macOS: .gpuAndCpu,        // Desktop Metal + XNNPACK both work
            iOSDevice: .gpuAndCpu,    // Desktop Metal shaders work on A-series GPU (verified: 16.8 tok/s decode, iPhone 16 Pro Max)
            iOSSimulator: .cpuOnly    // Simulator Metal is unreliable, CPU works
        )
    )

    // MARK: - Gemma 4 E2B (Web / Mobile GPU)

    /// Web variant with mobile GPU artisan shaders for A-series chips. No CPU subgraph.
    static let gemma4E2BWeb = ModelMetadata(
        name: "Gemma 4 E2B · Mobile GPU",
        modelId: "litert-community/gemma-4-E2B-it-litert-lm",
        modelFile: "gemma-4-E2B-it-web.litertlm",
        description: "Mobile-optimized Gemma 4 E2B with GPU artisan shaders for A-series and M-series chips. GPU-only — no CPU subgraph. Fastest decode on iOS device (39.9 tok/s).",
        sizeInBytes: 2_008_432_640,
        minDeviceMemoryGB: 8,
        contextWindowSize: 128_000,
        architectureType: "MoE Edge (2B effective)",
        recommendedFor: "Fastest mobile inference",
        supportsImage: false,
        supportsAudio: false,
        capabilities: ["llm_thinking", "speculative_decoding"],
        defaultConfig: ModelDefaultConfig(
            topK: 1,
            topP: 1.0,
            temperature: 1.0,
            maxContextLength: 32_000,
            maxTokens: 4_000,
            accelerators: "gpu",
            visionAccelerator: nil
        ),
        platformSupport: PlatformSupport(
            macOS: .gpuOnly,          // Session 2 verified: 113.1 tok/s on macOS Metal
            iOSDevice: .gpuOnly,      // A-series Metal GPU — fastest path (42.9 tok/s)
            iOSSimulator: .gpuOnly    // Loads on GPU, degenerate output on sim
        )
    )

    // MARK: - Gemma 4 E4B (Standard)

    /// Gemma 4 E4B standard build — larger 4B-effective model with CPU + GPU subgraphs.
    static let gemma4E4BStandard = ModelMetadata(
        name: "Gemma 4 E4B · Desktop GPU+CPU",
        modelId: "litert-community/gemma-4-E4B-it-litert-lm",
        modelFile: "gemma-4-E4B-it.litertlm",
        description: "Gemma 4 E4B standard model (4B effective params). CPU (XNNPACK) + desktop GPU (Metal). Higher quality than E2B but requires more memory.",
        sizeInBytes: 3_660_000_000,  // ~3.66 GB
        minDeviceMemoryGB: 12,
        contextWindowSize: 128_000,
        architectureType: "MoE Edge (4B effective)",
        recommendedFor: "Balanced quality and speed",
        supportsImage: true,
        supportsAudio: true,
        capabilities: ["llm_thinking", "speculative_decoding"],
        defaultConfig: ModelDefaultConfig(
            topK: 64,
            topP: 0.95,
            temperature: 1.0,
            maxContextLength: 32_000,
            maxTokens: 4_000,
            accelerators: "gpu,cpu",
            visionAccelerator: "gpu"
        ),
        platformSupport: PlatformSupport(
            macOS: .gpuAndCpu,
            iOSDevice: .gpuAndCpu,      // Standard models support Metal GPUs on iOS
            iOSSimulator: .cpuOnly
        )
    )

    // MARK: - Gemma 4 E4B (Web / Mobile GPU)

    /// Gemma 4 E4B web/mobile variant — GPU-only for A-series chips.
    static let gemma4E4BWeb = ModelMetadata(
        name: "Gemma 4 E4B · Mobile GPU",
        modelId: "litert-community/gemma-4-E4B-it-litert-lm",
        modelFile: "gemma-4-E4B-it-web.litertlm",
        description: "Mobile-optimized Gemma 4 E4B with GPU artisan shaders for A-series chips. GPU-only — no CPU subgraph.",
        sizeInBytes: 2_970_000_000,  // ~2.97 GB
        minDeviceMemoryGB: 12,
        contextWindowSize: 128_000,
        architectureType: "MoE Edge (4B effective)",
        recommendedFor: "Mobile text workflows",
        supportsImage: false,
        supportsAudio: false,
        capabilities: ["llm_thinking", "speculative_decoding"],
        defaultConfig: ModelDefaultConfig(
            topK: 1,
            topP: 1.0,
            temperature: 1.0,
            maxContextLength: 32_000,
            maxTokens: 4_000,
            accelerators: "gpu",
            visionAccelerator: nil
        ),
        platformSupport: PlatformSupport(
            macOS: .gpuOnly,          // Same architecture as E2B web
            iOSDevice: .gpuOnly,
            iOSSimulator: .gpuOnly    // Same architecture as E2B web
        )
    )

    // MARK: - Gemma 4 12B (Dense Multimodal)

    /// Gemma 4 12B — Dense encoder-free multimodal model (text + image + audio).
    /// Released June 3, 2026. 256K context window. Requires 16GB+ unified memory.
    /// Outperforms Gemma 3 27B on multiple benchmarks. Apache 2.0 license.
    ///
    /// This model is primarily intended for macOS (M-series with 16GB+) and
    /// iPad Pro, but iOS device loading is not blocked — the increased-memory-limit
    /// entitlement may allow it on high-RAM iPhones. Let the engine try and report.
    static let gemma4_12B = ModelMetadata(
        name: "Gemma 4 12B · Dense Multimodal",
        modelId: "litert-community/gemma-4-12B-it-litert-lm",
        modelFile: "gemma-4-12B-it.litertlm",
        description: "Dense 12B model with native text, image, and audio. 256K context. Requires 16GB+ unified memory. Best quality on-device.",
        sizeInBytes: 6_547_589_312,
        minDeviceMemoryGB: 16,
        contextWindowSize: 256_000,
        architectureType: "Dense Multimodal",
        recommendedFor: "Desktop power users, coding, deep analysis",
        supportsImage: true,
        supportsAudio: true,
        capabilities: ["llm_thinking", "speculative_decoding"],
        defaultConfig: ModelDefaultConfig(
            topK: 64,
            topP: 0.95,
            temperature: 1.0,
            maxContextLength: 256_000,
            maxTokens: 8_000,
            accelerators: "gpu,cpu",
            visionAccelerator: "gpu"
        ),
        platformSupport: PlatformSupport(
            macOS: .gpuAndCpu,        // M-series with 16GB+ — primary target
            iOSDevice: .gpuAndCpu,    // Allow attempt — increased-memory-limit entitlement may help
            iOSSimulator: .cpuOnly    // Simulator Metal unreliable
        )
    )


    // MARK: - Gemma 3n E2B (Standard INT4 — Gated)

    /// Gemma 3n E2B standard INT4 quantized model.
    /// This is the model used by the official AI Edge Gallery iOS app.
    /// **Gated model**: Requires HuggingFace authentication.
    ///
    /// Gallery iOS benchmark reference (v1.0.6, iPhone 16 Pro Max, GPU):
    ///   Prefill: 392.86 tok/s | Decode: 25.57 tok/s
    ///   TTFT: 0.70s | Init: 8194ms
    static let gemma3nE2BStandard = ModelMetadata(
        name: "Gemma 3n E2B · INT4",
        modelId: "google/gemma-3n-E2B-it-litert-lm",
        modelFile: "gemma-3n-E2B-it-int4.litertlm",
        description: "Gemma 3n E2B with INT4 quantization. GPU-only (mobile Metal shaders). Same model as the AI Edge Gallery app. Requires HuggingFace auth.",
        sizeInBytes: 3_390_000_000,  // ~3.39 GB
        minDeviceMemoryGB: 8,
        contextWindowSize: 128_000,
        architectureType: "MoE Edge (2B effective)",
        recommendedFor: "Gallery-compatible mobile chat",
        supportsImage: false,
        supportsAudio: false,
        capabilities: ["llm_thinking"],
        defaultConfig: ModelDefaultConfig(
            topK: 64,
            topP: 0.95,
            temperature: 1.0,
            maxContextLength: 32_000,
            maxTokens: 4_000,
            accelerators: "gpu",
            visionAccelerator: nil
        ),
        platformSupport: PlatformSupport(
            macOS: .gpuOnly,
            iOSDevice: .gpuOnly,      // GPU-only, verified: 25.57 tok/s decode
            iOSSimulator: .gpuOnly    // Loads on GPU, degenerate output on sim
        )
    )

    // MARK: - Gemma 3n E2B (HW-Optimized — Gated)

    /// Gemma 3n E2B hardware-optimized variant for A-series chips.
    /// Highest hardware-level GPU shader optimization. GPU-only, no CPU fallback.
    /// **Gated model**: Requires HuggingFace authentication.
    ///
    /// Verified benchmark (iPhone 16 Pro Max, GPU):
    ///   Decode: 24.0 tok/s | Prefill: 7.8 tok/s
    ///   TTFT: 2.09s | Init: 4.34s
    static let gemma3nE2BHW = ModelMetadata(
        name: "Gemma 3n E2B · HW-Optimized",
        modelId: "google/gemma-3n-E2B-it-litert-lm",
        modelFile: "gemma-3n-E2B-HW.litertlm",
        description: "Hardware-optimized Gemma 3n E2B with A-series-specific Metal GPU shaders. Best mobile GPU performance. Requires HuggingFace auth.",
        sizeInBytes: 2_830_000_000,  // ~2.83 GB
        minDeviceMemoryGB: 8,
        contextWindowSize: 128_000,
        architectureType: "MoE Edge (2B effective, HW-optimized)",
        recommendedFor: "Maximum mobile GPU throughput",
        supportsImage: false,
        supportsAudio: false,
        capabilities: ["llm_thinking"],
        defaultConfig: ModelDefaultConfig(
            topK: 64,
            topP: 0.95,
            temperature: 1.0,
            maxContextLength: 32_000,
            maxTokens: 4_000,
            accelerators: "gpu",
            visionAccelerator: nil
        ),
        platformSupport: PlatformSupport(
            macOS: .gpuOnly,          // macOS verified: 78.6 tok/s
            iOSDevice: .gpuOnly,      // iPhone 16 Pro Max: 24.0 tok/s decode
            iOSSimulator: .gpuOnly    // Loads on GPU, degenerate output on sim
        )
    )

    // MARK: - Lookup

    /// Attempt to match a model file to a known model by filename.
    /// - Parameter filename: The model filename (e.g., "gemma-4-E2B-it-web.litertlm")
    /// - Returns: The matching ModelMetadata, or nil if unknown.
    static func lookup(filename: String) -> ModelMetadata? {
        knownModels.first { $0.modelFile == filename }
    }

    /// Attempt to match a model file to a known model by file path.
    /// - Parameter path: Full path to the model file.
    /// - Returns: The matching ModelMetadata, or nil if unknown.
    static func lookup(path: String) -> ModelMetadata? {
        let filename = (path as NSString).lastPathComponent
        return lookup(filename: filename)
    }

    /// Get the recommended backend for a model file on the current platform.
    /// Falls back to .probeRequired for unknown models.
    static func recommendedBackend(for path: String) -> BackendRecommendation {
        guard let metadata = lookup(path: path) else {
            return .probeRequired
        }
        return metadata.platformSupport.currentPlatform.recommendedBackend
    }
}
