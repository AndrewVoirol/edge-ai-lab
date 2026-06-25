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

// MARK: - Experiment Configuration Snapshot

/// A frozen snapshot of the active inference configuration at the time a conversation was created.
///
/// Captures everything needed to reproduce an experiment:
/// - **Model identity**: name, file, HF repo, variant info (IT, web, HW, etc.)
/// - **Backend**: GPU/CPU, fallback status
/// - **Sampler**: temperature, topK, topP, seed
/// - **Flags**: thinking, tool calling, MTP, agent skills, benchmarking
/// - **System message**: custom persona/instructions
///
/// This struct is `Codable` for JSON persistence and provides computed properties
/// for generating light sidebar summaries without loading the full conversation.
struct ExperimentConfig: Codable, Sendable, Equatable {

    // MARK: - Model Identity

    /// Human-readable model name (e.g., "Gemma 4 E2B · Desktop GPU+CPU").
    let modelName: String

    /// Expected filename on disk (e.g., "gemma-4-E2B-it.litertlm").
    let modelFile: String

    /// HuggingFace model identifier (e.g., "litert-community/gemma-4-E2B-it-litert-lm").
    let modelId: String?

    /// Architecture type (e.g., "MoE Edge (2B effective)", "Dense Multimodal").
    let architectureType: String?

    /// Model variant descriptor parsed from the filename/model name.
    /// Examples: "IT" (instruction-tuned), "web" (mobile GPU), "HW" (hardware-optimized),
    ///           "int4" (quantization), "12B" (size).
    let modelVariant: String?

    // MARK: - Backend

    /// Active backend string: "GPU" or "CPU".
    let backend: String

    /// Whether the engine fell back from GPU to CPU during initialization.
    let didFallback: Bool

    // MARK: - Sampler Configuration

    /// Temperature for sampling (higher = more random).
    let temperature: Float

    /// Top-K sampling parameter.
    let topK: Int

    /// Top-P (nucleus) sampling parameter.
    let topP: Float

    /// Seed for reproducible generation (0 = non-deterministic).
    let seed: Int

    // MARK: - Experimental Flags

    /// Whether thinking mode is enabled (model reasoning is surfaced).
    let thinkingEnabled: Bool

    /// Whether tool calling is enabled.
    let toolCallingEnabled: Bool

    /// Whether agent skills (Wikipedia, Maps) are enabled.
    let agentSkillsEnabled: Bool

    /// Whether speculative decoding (MTP) is enabled.
    let mtpEnabled: Bool

    /// Whether benchmarking is enabled.
    let benchmarkEnabled: Bool

    // MARK: - System Message

    /// Optional system message that was active during this experiment.
    let systemMessage: String?

    // MARK: - Timestamp

    /// When this configuration was captured.
    let createdAt: Date

    // MARK: - Computed Properties

    /// Short model name for sidebar display (e.g., "E2B", "12B", "E4B").
    var modelShortName: String {
        // Extract the size/variant from the model name
        if modelName.contains("12B") { return "12B" }
        if modelName.contains("E4B") { return "E4B" }
        if modelName.contains("E2B") { return "E2B" }
        if modelName.contains("3n") { return "3n" }
        // Fallback: use first word of name
        return String(modelName.split(separator: " ").first ?? "Model")
    }

    /// Light summary string for sidebar display.
    /// Format: "E2B · GPU · Thinking · Tools"
    var lightSummary: String {
        var parts = [modelShortName, backend]
        if didFallback { parts.append("⚠️ Fallback") }
        if thinkingEnabled { parts.append("Thinking") }
        if toolCallingEnabled { parts.append("Tools") }
        if mtpEnabled { parts.append("MTP") }
        if agentSkillsEnabled { parts.append("Skills") }
        return parts.joined(separator: " · ")
    }

    /// Active features as an array of badge-friendly strings.
    var activeFeatureBadges: [String] {
        var badges: [String] = []
        if thinkingEnabled { badges.append("Thinking") }
        if toolCallingEnabled { badges.append("Tools") }
        if mtpEnabled { badges.append("MTP") }
        if agentSkillsEnabled { badges.append("Skills") }
        return badges
    }

    /// Create an `ExperimentConfig` from individual state values.
    ///
    /// This factory method accepts discrete parameters instead of a ViewModel reference,
    /// keeping `ExperimentConfig` decoupled from the view layer. Any caller that has
    /// access to model metadata, sampler config, and flags can construct a snapshot.
    @MainActor
    static func capture(
        modelMetadata: ModelMetadata?,
        modelURL: URL?,
        backendResult: BackendResult?,
        topK: Int,
        topP: Float,
        temperature: Float,
        seed: Int,
        systemMessage: String,
        flags: ExperimentalFlagsState
    ) -> ExperimentConfig {
        let backendLabel: String
        let didFallback: Bool
        if let result = backendResult {
            backendLabel = result.activeBackend == .gpu ? "GPU" : "CPU"
            didFallback = result.didFallback
        } else {
            backendLabel = "Unknown"
            didFallback = false
        }

        // Parse model variant from filename
        let variant = Self.parseVariant(from: modelURL?.lastPathComponent ?? "")

        return ExperimentConfig(
            modelName: modelMetadata?.name ?? modelURL?.lastPathComponent ?? "Unknown Model",
            modelFile: modelURL?.lastPathComponent ?? "unknown",
            modelId: modelMetadata?.modelId,
            architectureType: modelMetadata?.architectureType,
            modelVariant: variant,
            backend: backendLabel,
            didFallback: didFallback,
            temperature: temperature,
            topK: topK,
            topP: topP,
            seed: seed,
            thinkingEnabled: flags.enableThinking,
            toolCallingEnabled: flags.enableToolCalling,
            agentSkillsEnabled: flags.enableAgentSkills,
            mtpEnabled: flags.enableSpeculativeDecoding ?? false,
            benchmarkEnabled: flags.enableBenchmark,
            systemMessage: systemMessage.isEmpty ? nil : systemMessage,
            createdAt: Date()
        )
    }

    // MARK: - Variant Parsing

    /// Parse the model variant from a filename.
    ///
    /// Recognizes common patterns:
    /// - `-it` → "IT" (instruction-tuned)
    /// - `-web` → "Web" (mobile GPU)
    /// - `-HW` → "HW" (hardware-optimized)
    /// - `-int4` → "INT4" (quantization)
    /// - `-int8` → "INT8"
    ///
    /// - Parameter filename: The model filename (e.g., "gemma-4-E2B-it-web.litertlm").
    /// - Returns: A human-readable variant string, or nil if no variant detected.
    static func parseVariant(from filename: String) -> String? {
        let lower = filename.lowercased()
        var parts: [String] = []

        if lower.contains("-it") { parts.append("IT") }
        if lower.contains("-web") { parts.append("Web") }
        if lower.contains("-hw") { parts.append("HW") }
        if lower.contains("-int4") || lower.contains("int4") { parts.append("INT4") }
        if lower.contains("-int8") || lower.contains("int8") { parts.append("INT8") }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
