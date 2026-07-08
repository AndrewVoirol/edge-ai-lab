// Copyright 2026 Andrew Voirol. Apache-2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0

import Foundation

// MARK: - Inference Config Snapshot

/// Point-in-time capture of the engine configuration when an inference was produced.
///
/// Attached to each assistant `ChatMessage` so the user can see exactly
/// what config produced each response. This is the "proof" layer — not what
/// was *requested*, but what was *actually applied*.
///
/// All properties are optional per AGENTS.md Codable rules: external data
/// shapes may vary, and older conversations won't have this field.
struct InferenceConfigSnapshot: Sendable, Codable, Equatable {

    // MARK: Model Identity

    /// Display name of the model (e.g., "Gemma 4 E2B Standard").
    let modelName: String?
    /// Runtime backend (e.g., "LiteRT-LM" or "MLX").
    let runtimeType: String?
    /// Compute backend (e.g., "GPU (Metal)" or "CPU (XNNPACK)").
    let computeBackend: String?

    // MARK: Feature Flags

    /// Whether thinking mode was active for this inference.
    let thinkingEnabled: Bool?
    /// Whether MTP/speculative decoding was active.
    let mtpEnabled: Bool?
    /// Whether constrained decoding was active.
    let constrainedDecodingEnabled: Bool?
    /// Whether tool calling was active.
    let toolCallingEnabled: Bool?

    // MARK: Sampler Settings

    let temperature: Float?
    let topK: Int?
    let topP: Float?
    let seed: Int?

    // MARK: Summary

    /// One-line human-readable summary.
    /// e.g., "Gemma 4 E2B · GPU · Think ✓ · MTP ✓ · Tools ✓"
    var summary: String {
        var parts: [String] = []

        if let name = modelName {
            parts.append(name)
        }

        if let backend = computeBackend {
            parts.append(backend)
        }

        var flags: [String] = []
        if thinkingEnabled == true { flags.append("Think ✓") }
        if mtpEnabled == true { flags.append("MTP ✓") }
        if constrainedDecodingEnabled == true { flags.append("CD ✓") }
        if toolCallingEnabled == true { flags.append("Tools ✓") }

        if !flags.isEmpty {
            parts.append(flags.joined(separator: " · "))
        }

        return parts.joined(separator: " · ")
    }

    /// Detailed multi-line description for expanded config view.
    var detailedLines: [(label: String, value: String)] {
        var lines: [(String, String)] = []

        if let name = modelName { lines.append(("Model", name)) }
        if let rt = runtimeType { lines.append(("Engine", rt)) }
        if let cb = computeBackend { lines.append(("Compute", cb)) }

        lines.append(("Thinking", thinkingEnabled == true ? "On" : "Off"))
        lines.append(("MTP", mtpEnabled == true ? "On" : "Off"))
        lines.append(("CD", constrainedDecodingEnabled == true ? "On" : "Off"))
        lines.append(("Tools", toolCallingEnabled == true ? "On" : "Off"))

        if let t = temperature { lines.append(("Temperature", String(format: "%.2f", t))) }
        if let k = topK { lines.append(("Top-K", "\(k)")) }
        if let p = topP { lines.append(("Top-P", String(format: "%.2f", p))) }
        if let s = seed { lines.append(("Seed", s == 0 ? "Random" : "\(s)")) }

        return lines
    }
}

// MARK: - Factory

extension InferenceConfigSnapshot {
    /// Capture current config from ViewModel state.
    ///
    /// Called at inference start — captures what's actually applied,
    /// not what the UI shows.
    static func capture(
        modelName: String?,
        runtimeType: RuntimeType,
        computeBackend: String?,
        flags: RuntimeFlags,
        temperature: Float,
        topK: Int,
        topP: Float,
        seed: Int
    ) -> InferenceConfigSnapshot {
        InferenceConfigSnapshot(
            modelName: modelName,
            runtimeType: runtimeType.rawValue,
            computeBackend: computeBackend,
            thinkingEnabled: flags.enableThinking,
            mtpEnabled: flags.enableSpeculativeDecoding ?? false,
            constrainedDecodingEnabled: flags.enableConversationConstrainedDecoding,
            toolCallingEnabled: flags.enableToolCalling,
            temperature: temperature,
            topK: topK,
            topP: topP,
            seed: seed
        )
    }
}
