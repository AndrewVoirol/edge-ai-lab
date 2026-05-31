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
struct ModelMetadata: Codable, Sendable, Identifiable {
    var id: String { modelId }

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

    /// Whether speculative decoding (MTP) is available for this model.
    var supportsMTP: Bool {
        capabilities.contains("speculative_decoding")
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
    static let knownModels: [ModelMetadata] = [
        gemma3nE2B,
        gemma3nE2BHW,
        gemma4E2BStandard,
        gemma4E2BWeb,
        gemma4E4BStandard,
        gemma4E4BWeb,
    ]

    // MARK: - Gemma 3n E2B (iOS Gallery Model)

    /// The model used by the official Google AI Edge Gallery iOS app (ios_1_0_0.json).
    /// Gemma 3n uses MatFormer + PLE caching for efficient on-device inference.
    /// This is a GPU-only model with mobile-native Metal shaders for A-series chips.
    /// Commit hash pinned by Gallery: 73b019b63436d346f68dd9c1dbfd117eb264d888
    ///
    /// Gallery iOS benchmark (v1.0.6, iPhone 16 Pro Max):
    ///   Prefill: 402.93 tok/s | Decode: 25.47 tok/s
    ///   TTFT: 0.68s | Init: 6499.08ms
    ///   (256 prefill/decode tokens, 3 runs, GPU accelerator)
    static let gemma3nE2B = ModelMetadata(
        name: "Gemma 3n E2B · Mobile GPU",
        modelId: "google/gemma-3n-E2B-it-litert-lm",
        modelFile: "gemma-3n-E2B-it-int4.litertlm",
        description: "Gemma 3n E2B — the model used by the official AI Edge Gallery iOS app. INT4 quantized with mobile-native GPU shaders. Supports text, vision, and audio input.",
        sizeInBytes: 3_388_604_416,  // ~3.39 GB
        minDeviceMemoryGB: 6,
        supportsImage: true,
        supportsAudio: true,
        capabilities: ["speculative_decoding"],
        defaultConfig: ModelDefaultConfig(
            topK: 64,
            topP: 0.95,
            temperature: 1.0,
            maxContextLength: 4_096,
            maxTokens: 4_096,
            accelerators: "gpu",
            visionAccelerator: nil
        ),
        platformSupport: PlatformSupport(
            macOS: .gpuOnly,          // Same arch as HW variant (78.6 tok/s on macOS)
            iOSDevice: .gpuOnly,      // Mobile-native Metal shaders — Gallery verified (402.93 tok/s prefill)
            iOSSimulator: .gpuOnly    // GPU-only model, sim GPU unreliable
        )
    )

    /// Hardware-optimized Gemma 3n E2B variant — downloaded by Gallery iOS app.
    /// Filename `gemma-3n-E2B-HW.litertlm` suggests a hardware-specific (HW) build
    /// for Apple Silicon / A-series chips. Smaller than the INT4 variant (2.83 GB vs 3.39 GB).
    static let gemma3nE2BHW = ModelMetadata(
        name: "Gemma 3n E2B · Mobile GPU (HW)",
        modelId: "google/gemma-3n-E2B-it-litert-lm",
        modelFile: "gemma-3n-E2B-HW.litertlm",
        description: "Hardware-optimized Gemma 3n E2B with mobile-native GPU shaders for A-series chips. Downloaded by Gallery iOS app.",
        sizeInBytes: 3_037_282_304,  // ~2.83 GB (actual on-disk size)
        minDeviceMemoryGB: 6,
        supportsImage: true,
        supportsAudio: true,
        capabilities: ["speculative_decoding"],
        defaultConfig: ModelDefaultConfig(
            topK: 64,
            topP: 0.95,
            temperature: 1.0,
            maxContextLength: 4_096,
            maxTokens: 4_096,
            accelerators: "gpu",
            visionAccelerator: nil
        ),
        platformSupport: PlatformSupport(
            macOS: .gpuOnly,          // Session 2 verified: 78.6 tok/s decode
            iOSDevice: .gpuOnly,      // Mobile-native Metal shaders — same as INT4 variant
            iOSSimulator: .gpuOnly    // Loads, inference runs (degenerate on sim)
        )
    )

    // MARK: - Gemma 4 E2B (Standard)

    /// Standard build with both CPU (XNNPACK) and desktop GPU (Metal) subgraphs.
    /// Desktop Metal shaders also work on A-series iOS GPUs (verified on iPhone 16 Pro Max).
    ///
    /// Gallery iOS benchmark reference (v1.0.6, iPhone 16 Pro Max, Gemma-4-E2B-it, GPU):
    ///   Prefill: 305.45 tok/s | Decode: 39.23 tok/s
    ///   TTFT: 0.87s | Init: 1006.00ms
    static let gemma4E2BStandard = ModelMetadata(
        name: "Gemma 4 E2B · Desktop GPU+CPU",
        modelId: "litert-community/gemma-4-E2B-it-litert-lm",
        modelFile: "gemma-4-E2B-it.litertlm",
        description: "Standard Gemma 4 E2B model with CPU (XNNPACK) and desktop GPU (Metal) support. Desktop Metal shaders also work on A-series iOS GPUs (verified on iPhone 16 Pro Max).",
        sizeInBytes: 2_588_147_712,
        minDeviceMemoryGB: 8,
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
        supportsImage: true,
        supportsAudio: true,
        capabilities: ["llm_thinking", "speculative_decoding"],
        defaultConfig: ModelDefaultConfig(
            topK: 64,
            topP: 0.95,
            temperature: 1.0,
            maxContextLength: 32_000,
            maxTokens: 4_000,
            accelerators: "gpu",
            visionAccelerator: "gpu"
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
            iOSDevice: .cpuOnly,      // Assumed same pattern as E2B standard
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
        supportsImage: true,
        supportsAudio: true,
        capabilities: ["llm_thinking", "speculative_decoding"],
        defaultConfig: ModelDefaultConfig(
            topK: 64,
            topP: 0.95,
            temperature: 1.0,
            maxContextLength: 32_000,
            maxTokens: 4_000,
            accelerators: "gpu",
            visionAccelerator: "gpu"
        ),
        platformSupport: PlatformSupport(
            macOS: .gpuOnly,          // Same architecture as E2B web
            iOSDevice: .gpuOnly,
            iOSSimulator: .gpuOnly    // Same architecture as E2B web
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
