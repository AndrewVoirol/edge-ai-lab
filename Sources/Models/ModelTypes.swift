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

// MARK: - Backend Capability

/// Describes what backends a loaded model supports on the current platform.
/// Determined either from the known-model catalog or via runtime probing.
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

// MARK: - Runtime Type

/// Identifies the runtime engine required to execute a model.
///
/// Edge AI Lab supports LiteRT-LM, MLX, and GGUF runtimes.
enum RuntimeType: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Google LiteRT-LM format — the primary runtime for this app.
    case litertlm = "LiteRT-LM"
    /// Apple MLX format (safetensors weights + config.json).
    case mlx = "MLX"
    /// GGUF quantized format (llama.cpp compatible).
    case gguf = "GGUF"

    /// Identifiable conformance — uses the raw value as a stable ID.
    var id: String { rawValue }

    /// Human-readable name for display in the UI.
    var displayName: String { rawValue }

    /// SF Symbol name representing this engine type.
    var iconName: String {
        switch self {
        case .litertlm: return "cpu"
        case .mlx: return "apple.logo"
        case .gguf: return "memorychip"
        }
    }

    /// Expected file extension for models of this runtime type.
    var fileExtension: String {
        switch self {
        case .litertlm: return "litertlm"
        case .mlx: return "safetensors"
        case .gguf: return "gguf"
        }
    }

    /// Whether this runtime is currently supported for inference.
    var isSupported: Bool {
        self == .litertlm || self == .mlx || self == .gguf
    }

    /// All runtime types that are currently supported for inference.
    static var supportedCases: [RuntimeType] {
        allCases.filter(\.isSupported)
    }
}

// MARK: - Model Default Configuration

/// Default generation configuration for a model (sampling parameters and accelerator hints).
struct ModelDefaultConfig: Codable, Sendable, Hashable {
    let topK: Int
    let topP: Double
    let temperature: Double
    let maxContextLength: Int
    let maxTokens: Int
    let accelerators: String       // e.g., "gpu,cpu" or "gpu"
    let visionAccelerator: String? // e.g., "gpu"
}

// MARK: - Platform Support

/// Platform-specific backend support matrix.
/// Encodes which backends work on which platforms for a given model.
struct PlatformSupport: Codable, Sendable, Hashable {
    let macOS: BackendCapability
    let iOSDevice: BackendCapability
    let iOSSimulator: BackendCapability

    init(
        macOS: BackendCapability = .unknown,
        iOSDevice: BackendCapability = .unknown,
        iOSSimulator: BackendCapability = .unknown
    ) {
        self.macOS = macOS
        self.iOSDevice = iOSDevice
        self.iOSSimulator = iOSSimulator
    }

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
