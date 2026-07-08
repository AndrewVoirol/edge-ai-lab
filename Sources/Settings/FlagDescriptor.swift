// Copyright 2026 Andrew Voirol. Apache-2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0

import Foundation

// MARK: - Impact Area

/// Categories of engine behavior that a flag affects.
/// Used in settings UI to show color-coded impact pills.
enum ImpactArea: String, Sendable, CaseIterable {
    case speed = "Speed"
    case quality = "Quality"
    case memory = "Memory"
    case compatibility = "Compatibility"

    /// SF Symbol name for the impact area.
    var symbolName: String {
        switch self {
        case .speed: return "bolt.fill"
        case .quality: return "sparkles"
        case .memory: return "memorychip"
        case .compatibility: return "exclamationmark.triangle"
        }
    }
}

// MARK: - Reload Requirement

/// Whether changing a flag requires reloading the engine session.
///
/// Based on empirically verified behavior:
/// - LiteRT: sampler values can be hot-patched via `applySamplerSettingsInPlace()`
/// - MLX: `GenerateParameters` are rebuilt per-generation, but session isn't reloaded
enum ReloadRequirement: Sendable, Equatable {
    /// Always requires engine reload on both backends.
    case always
    /// Never requires reload — applied in-flight.
    case never
    /// Depends on which engine is active.
    /// `litertReloads`: whether LiteRT needs a reload.
    /// `mlxReloads`: whether MLX needs a reload.
    case engineDependent(litertReloads: Bool, mlxReloads: Bool)

    /// Check whether this flag requires reload for the given runtime.
    func requiresReload(for runtime: RuntimeType) -> Bool {
        switch self {
        case .always: return true
        case .never: return false
        case .engineDependent(let litert, let mlx):
            switch runtime {
            case .litertlm: return litert
            case .mlx: return mlx
            case .gguf: return true  // Conservative default
            }
        }
    }
}

// MARK: - Flag Descriptor

/// Metadata about a feature flag: what it does, what it affects, and what it requires.
///
/// Sources for each field:
/// - `impactAreas`: Determined from Phase 1 + 1.5 invariant testing
/// - `reloadRequirement`: Verified via engine adapter code paths
/// - `engineSupport`: Verified via `MLXFeatureVerificationTests` (8/8 pass)
struct FlagDescriptor: Sendable, Identifiable {
    let id: String
    let displayName: String
    let symbol: String
    let description: String
    let impactAreas: [ImpactArea]
    let reloadRequirement: ReloadRequirement
    /// Which engines support this flag. Empty means all.
    let supportedEngines: Set<RuntimeType>

    /// Whether this flag is supported on the given runtime.
    func isSupported(on runtime: RuntimeType) -> Bool {
        supportedEngines.isEmpty || supportedEngines.contains(runtime)
    }
}

// MARK: - Registry

/// Static registry of all feature flags with their descriptors.
///
/// Each entry is sourced from Phase 1 + 1.5 empirical testing:
/// - CD absence in MLX: `testMLX_ConstrainedDecoding_SDKSupport` — zero SDK hits
/// - Speculative decoding: `testMLX_SpeculativeDecoding_SDKSupport` — SDK has it, adapter doesn't
/// - Sampler reload: LiteRT `applySamplerSettingsInPlace()` vs MLX per-generation rebuild
enum FlagRegistry {
    static let thinking = FlagDescriptor(
        id: "thinking",
        displayName: "Thinking",
        symbol: "brain.head.profile",
        description: "Shows the model's reasoning process before answering. Uses <think> tags (LiteRT) or <|channel>thought (MLX).",
        impactAreas: [.quality],
        reloadRequirement: .always,
        supportedEngines: [.litertlm, .mlx]
    )

    static let speculative = FlagDescriptor(
        id: "mtp",
        displayName: "MTP",
        symbol: "bolt.fill",
        description: "Multi-Token Prediction: predicts multiple tokens at once for faster generation. LiteRT only — MLX SDK has speculative decoding but requires a separate draft model.",
        impactAreas: [.speed],
        reloadRequirement: .always,
        supportedEngines: [.litertlm]
    )

    static let constrainedDecoding = FlagDescriptor(
        id: "cd",
        displayName: "CD",
        symbol: "doc.text.magnifyingglass",
        description: "Constrained Decoding: guides output to follow structured formats. LiteRT only — no grammar/FST decoder in mlx-swift-lm SDK.",
        impactAreas: [.compatibility, .quality],
        reloadRequirement: .always,
        supportedEngines: [.litertlm]
    )

    static let toolCalling = FlagDescriptor(
        id: "tools",
        displayName: "Tools",
        symbol: "wrench.fill",
        description: "Enables the model to call registered tools (calculator, code runner, etc.) during generation.",
        impactAreas: [.quality],
        reloadRequirement: .always,
        supportedEngines: [.litertlm, .mlx]
    )

    static let temperature = FlagDescriptor(
        id: "temperature",
        displayName: "Temperature",
        symbol: "thermometer.medium",
        description: "Controls randomness. Lower = more deterministic, higher = more creative. 0.0 = greedy decoding.",
        impactAreas: [.quality],
        reloadRequirement: .engineDependent(litertReloads: false, mlxReloads: false),
        supportedEngines: []  // All engines
    )

    static let topK = FlagDescriptor(
        id: "topK",
        displayName: "Top-K",
        symbol: "chart.bar.fill",
        description: "Limits sampling to the K most likely next tokens. Lower = more focused, higher = more diverse. 1 = greedy.",
        impactAreas: [.quality],
        reloadRequirement: .engineDependent(litertReloads: false, mlxReloads: false),
        supportedEngines: []
    )

    static let topP = FlagDescriptor(
        id: "topP",
        displayName: "Top-P",
        symbol: "chart.pie.fill",
        description: "Nucleus sampling: keeps the smallest set of tokens whose cumulative probability exceeds P. 1.0 = disabled.",
        impactAreas: [.quality],
        reloadRequirement: .engineDependent(litertReloads: false, mlxReloads: false),
        supportedEngines: []
    )

    static let seed = FlagDescriptor(
        id: "seed",
        displayName: "Seed",
        symbol: "dice",
        description: "Fixed random seed for reproducible output. Set to 0 for random seed each generation.",
        impactAreas: [.quality],
        reloadRequirement: .always,
        supportedEngines: []
    )

    /// All feature flags (non-sampler) in display order.
    static let featureFlags: [FlagDescriptor] = [
        thinking, speculative, constrainedDecoding, toolCalling,
    ]

    /// All sampler flags in display order.
    static let samplerFlags: [FlagDescriptor] = [
        temperature, topK, topP, seed,
    ]

    /// All flags.
    static let all: [FlagDescriptor] = featureFlags + samplerFlags

    /// Look up a descriptor by ID.
    static func descriptor(for id: String) -> FlagDescriptor? {
        all.first { $0.id == id }
    }
}
