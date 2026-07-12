// Copyright 2026 Andrew Voirol. Apache-2.0
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

import SwiftUI

// MARK: - DiagnosticsView

/// In-app diagnostics view showing live engine configuration snapshot,
/// model capabilities, and a "Run Diagnostic" test inference.
///
/// Accessible from Settings. Shows the ground truth of what the engine
/// is actually configured with — not what the UI says, but what the
/// engine received. This is the trust verification layer.
struct DiagnosticsView: View {
    @Environment(ConversationViewModel.self) private var viewModel

    @State private var diagnosticResult: DiagnosticResult?
    @State private var isRunningDiagnostic = false
    @State private var diagnosticPrompt = "What is 2 + 2?"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerSection
                engineStateSection
                runtimeFlagsSection
                samplerSection
                modelCapabilitiesSection
                compatibilitySection
                diagnosticTestSection

                if let result = diagnosticResult {
                    diagnosticResultSection(result)
                }

                exportSection
            }
            .padding()
        }
        .accessibilityIdentifier("diagnosticsView")
        #if os(macOS)
        .frame(minWidth: 400, idealWidth: 500, maxWidth: 600)
        #endif
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Engine Diagnostics")
                .font(AppTypography.sectionTitle)
                .accessibilityIdentifier("diagnosticsTitle")
            Text("Live snapshot of the engine's actual configuration. This shows what the engine received, not what the UI displays.")
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Engine State

    private var engineStateSection: some View {
        GroupBox("Engine State") {
            VStack(alignment: .leading, spacing: 8) {
                diagnosticRow("Status", value: viewModel.isGenerating ? "Generating…" : (viewModel.isLoadingModel ? "Loading Model…" : (viewModel.isEngineReady ? "Ready" : "Not Loaded")),
                              status: viewModel.isEngineReady ? .ok : .warning)

                if let metadata = viewModel.activeModelMetadata {
                    diagnosticRow("Model", value: metadata.name)
                    diagnosticRow("Model File", value: metadata.modelFile)
                    diagnosticRow("Runtime", value: metadata.runtimeType.rawValue)
                } else {
                    diagnosticRow("Model", value: "None loaded", status: .warning)
                }

                if let backend = viewModel.backendResult {
                    diagnosticRow("Backend", value: backend.activeBackend == .gpu ? "GPU (Metal)" : "CPU (XNNPACK)")
                    if backend.didFallback, let reason = backend.fallbackReason {
                        diagnosticRow("Fallback", value: reason, status: .info)
                    }
                }
            }
        }
        .accessibilityIdentifier("engineStateSection")
    }

    // MARK: - Runtime Flags

    private var runtimeFlagsSection: some View {
        GroupBox("Runtime Flags (as sent to engine)") {
            let flags = viewModel.runtimeFlags
            VStack(alignment: .leading, spacing: 6) {
                flagRow("Thinking Mode", enabled: flags.enableThinking, key: "enableThinking")
                flagRow("Speculative Decoding (MTP)", enabled: flags.enableSpeculativeDecoding == true, key: "enableSpeculativeDecoding",
                        detail: flags.enableSpeculativeDecoding == nil ? "(nil → engine default)" : nil)
                flagRow("Constrained Decoding", enabled: flags.enableConversationConstrainedDecoding, key: "enableConversationConstrainedDecoding")
                flagRow("Tool Calling", enabled: flags.enableToolCalling, key: "enableToolCalling")
                flagRow("Agent Skills", enabled: flags.enableAgentSkills, key: "enableAgentSkills")
                flagRow("Benchmark", enabled: flags.enableBenchmark, key: "enableBenchmark")

                if let budget = flags.visualTokenBudget {
                    diagnosticRow("Visual Token Budget", value: "\(budget)")
                }
            }
        }
        .accessibilityIdentifier("runtimeFlagsSection")
    }

    // MARK: - Sampler

    private var samplerSection: some View {
        GroupBox("Sampler Configuration") {
            VStack(alignment: .leading, spacing: 6) {
                diagnosticRow("Temperature", value: String(format: "%.2f", viewModel.temperature))
                diagnosticRow("Top-K", value: "\(viewModel.topK)")
                diagnosticRow("Top-P", value: String(format: "%.2f", viewModel.topP))
                diagnosticRow("Seed", value: viewModel.seed == 0 ? "0 (non-deterministic)" : "\(viewModel.seed)")
                if let maxTokens = viewModel.maxNumTokens {
                    diagnosticRow("Max Tokens", value: "\(maxTokens)")
                }
            }
        }
        .accessibilityIdentifier("samplerSection")
    }

    // MARK: - Model Capabilities

    private var modelCapabilitiesSection: some View {
        GroupBox("Model Capabilities (from metadata)") {
            if let metadata = viewModel.activeModelMetadata {
                VStack(alignment: .leading, spacing: 6) {
                    capabilityRow("Vision", supported: metadata.supportsImage)
                    capabilityRow("Audio", supported: metadata.supportsAudio)
                    capabilityRow("Thinking", supported: metadata.capabilities.contains("llm_thinking"))
                    capabilityRow("Tool Calling", supported: metadata.supportsToolCalling)
                    capabilityRow("MTP", supported: metadata.supportsMTP)

                    diagnosticRow("Context Window", value: "\(metadata.contextWindowSize) tokens")
                    diagnosticRow("Architecture", value: metadata.architectureType)
                    diagnosticRow("Capabilities", value: metadata.capabilities.joined(separator: ", "))
                }
            } else {
                Text("No model loaded — capabilities unknown")
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("modelCapabilitiesSection")
    }

    // MARK: - Compatibility Check

    private var compatibilitySection: some View {
        GroupBox("Configuration Compatibility") {
            VStack(alignment: .leading, spacing: 6) {
                let flags = viewModel.runtimeFlags
                let metadata = viewModel.activeModelMetadata

                // Check known conflicts from Phase 1 verification
                if flags.enableThinking && flags.enableConversationConstrainedDecoding && !flags.enableToolCalling {
                    conflictRow("⚠️ Think + CD without tools",
                                detail: "Constrained Decoding's FST grammar rejects thinking tokens when no tool schemas are registered. Output will be zero-length. Enable tool calling or disable CD.")
                }

                if flags.enableConversationConstrainedDecoding && flags.enableSpeculativeDecoding == true {
                    conflictRow("ℹ️ CD + MTP",
                                detail: "MTP bypasses the constraint decoder after the first token. CD has no effect when MTP is active.")
                }

                if let metadata = metadata {
                    if flags.enableThinking && !metadata.capabilities.contains("llm_thinking") {
                        conflictRow("⚠️ Thinking enabled but model doesn't support it",
                                    detail: "Model '\(metadata.name)' does not advertise thinking support.")
                    }
                    if flags.enableToolCalling && !metadata.supportsToolCalling {
                        conflictRow("⚠️ Tool Calling enabled but model doesn't support it",
                                    detail: "Model '\(metadata.name)' does not advertise tool calling support.")
                    }
                }

                if metadata == nil {
                    Text("Load a model to check compatibility")
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                } else if !hasConflicts(flags: flags, metadata: metadata) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("No known conflicts detected")
                            .font(AppTypography.listSubtitle)
                    }
                }
            }
        }
        .accessibilityIdentifier("compatibilitySection")
    }

    // MARK: - Diagnostic Test

    private var diagnosticTestSection: some View {
        GroupBox("Run Diagnostic") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Send a test prompt and observe engine behavior. Results show what actually happened during inference.")
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)

                TextField("Test prompt", text: $diagnosticPrompt)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("diagnosticPromptField")

                Button(action: runDiagnostic) {
                    HStack {
                        if isRunningDiagnostic {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isRunningDiagnostic ? "Running…" : "Run Diagnostic")
                    }
                }
                .disabled(isRunningDiagnostic || !viewModel.isEngineReady)
                .accessibilityIdentifier("runDiagnosticButton")
            }
        }
        .accessibilityIdentifier("diagnosticTestSection")
    }

    private func diagnosticResultSection(_ result: DiagnosticResult) -> some View {
        GroupBox("Diagnostic Result") {
            VStack(alignment: .leading, spacing: 6) {
                diagnosticRow("Prompt", value: result.prompt)
                diagnosticRow("Response Length", value: "\(result.responseLength) chars")
                diagnosticRow("Think Tags Present", value: result.hasThinkTags ? "Yes" : "No",
                              status: viewModel.runtimeFlags.enableThinking == result.hasThinkTags ? .ok : .error)
                diagnosticRow("Wall Clock", value: String(format: "%.2fs", result.wallClockSeconds))

                if let metrics = result.performanceMetrics {
                    diagnosticRow("Decode tok/s", value: String(format: "%.1f", metrics.tokensPerSecond))
                    if let tokenCount = metrics.tokenCount {
                        diagnosticRow("Token Count", value: "\(tokenCount)")
                    }
                }

                if let error = result.error {
                    diagnosticRow("Error", value: error, status: .error)
                }

                if result.responseLength == 0 && result.error == nil {
                    conflictRow("🚨 Zero-length output with no error",
                                detail: "This is a known symptom of the think+CD conflict. Check Runtime Flags and Compatibility sections.")
                }
            }
        }
        .accessibilityIdentifier("diagnosticResultSection")
    }

    // MARK: - Export

    private var exportSection: some View {
        GroupBox("Export") {
            Button("Copy Diagnostic JSON to Clipboard") {
                let json = buildDiagnosticJSON()
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(json, forType: .string)
                #elseif os(iOS)
                UIPasteboard.general.string = json
                #endif
            }
            .accessibilityIdentifier("exportDiagnosticButton")
        }
    }

    // MARK: - Helper Views

    private func diagnosticRow(_ label: String, value: String, status: DiagnosticStatus = .neutral) -> some View {
        HStack {
            Text(label)
                .font(AppTypography.listSubtitle)
                .foregroundStyle(.secondary)
                .frame(width: 160, alignment: .leading)
            Text(value)
                .font(AppTypography.mono)
                .foregroundStyle(status.color)
            Spacer()
        }
    }

    private func flagRow(_ label: String, enabled: Bool, key: String, detail: String? = nil) -> some View {
        HStack {
            Image(systemName: enabled ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(enabled ? .green : .secondary)
            Text(label)
                .font(AppTypography.listSubtitle)
            Spacer()
            Text(key)
                .font(AppTypography.mono)
                .foregroundStyle(.tertiary)
            if let detail = detail {
                Text(detail)
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("flag_\(key)")
    }

    private func capabilityRow(_ label: String, supported: Bool) -> some View {
        HStack {
            Image(systemName: supported ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(supported ? .green : .secondary)
            Text(label)
                .font(AppTypography.listSubtitle)
            Spacer()
            Text(supported ? "Supported" : "Not supported")
                .font(AppTypography.caption)
                .foregroundStyle(supported ? .primary : .secondary)
        }
    }

    private func conflictRow(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(AppTypography.cardTitle)
                .foregroundStyle(.orange)
            Text(detail)
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Logic

    private func hasConflicts(flags: RuntimeFlags, metadata: ModelMetadata?) -> Bool {
        if flags.enableThinking && flags.enableConversationConstrainedDecoding && !flags.enableToolCalling {
            return true
        }
        if flags.enableConversationConstrainedDecoding && flags.enableSpeculativeDecoding == true {
            return true  // Not a hard conflict but a silenced feature — flag it
        }
        if let metadata = metadata {
            if flags.enableThinking && !metadata.capabilities.contains("llm_thinking") { return true }
            if flags.enableToolCalling && !metadata.supportsToolCalling { return true }
        }
        return false
    }

    @MainActor
    private func runDiagnostic() {
        guard !isRunningDiagnostic, viewModel.isEngineReady else { return }
        isRunningDiagnostic = true
        diagnosticResult = nil

        Task {
            let startTime = CFAbsoluteTimeGetCurrent()
            var response = ""
            var inferenceError: String?

            do {
                let engine = viewModel.sessionController.engine
                let config = GenerationConfig(
                    maxTokens: 256,
                    temperature: Double(viewModel.temperature),
                    topP: Double(viewModel.topP),
                    topK: viewModel.topK,
                    seed: viewModel.seed > 0 ? UInt64(viewModel.seed) : nil
                )
                let stream = engine.generateStream(
                    prompt: diagnosticPrompt,
                    config: config
                )
                for try await event in stream {
                    switch event {
                    case .text(let text):
                        response += text
                    case .metrics:
                        break
                    case .done:
                        break
                    case .toolCall:
                        break
                    }
                }
            } catch {
                inferenceError = error.localizedDescription
            }

            let wallClock = CFAbsoluteTimeGetCurrent() - startTime
            diagnosticResult = DiagnosticResult(
                prompt: diagnosticPrompt,
                responseLength: response.count,
                hasThinkTags: response.contains("<think>"),
                wallClockSeconds: wallClock,
                performanceMetrics: viewModel.performanceMetrics,
                error: inferenceError
            )
            isRunningDiagnostic = false
        }
    }

    private func buildDiagnosticJSON() -> String {
        let flags = viewModel.runtimeFlags
        let metadata = viewModel.activeModelMetadata

        var dict: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "engineReady": viewModel.isEngineReady,
            "runtimeFlags": [
                "enableThinking": flags.enableThinking,
                "enableSpeculativeDecoding": flags.enableSpeculativeDecoding as Any,
                "enableConversationConstrainedDecoding": flags.enableConversationConstrainedDecoding,
                "enableToolCalling": flags.enableToolCalling,
                "enableAgentSkills": flags.enableAgentSkills,
                "enableBenchmark": flags.enableBenchmark,
            ],
            "sampler": [
                "temperature": viewModel.temperature,
                "topK": viewModel.topK,
                "topP": viewModel.topP,
                "seed": viewModel.seed,
            ]
        ]

        if let metadata = metadata {
            dict["model"] = [
                "name": metadata.name,
                "file": metadata.modelFile,
                "runtime": metadata.runtimeType.rawValue,
                "supportsImage": metadata.supportsImage,
                "supportsAudio": metadata.supportsAudio,
                "supportsThinking": metadata.capabilities.contains("llm_thinking"),
                "supportsToolCalling": metadata.supportsToolCalling,
                "supportsMTP": metadata.supportsMTP,
                "contextWindowSize": metadata.contextWindowSize,
                "capabilities": metadata.capabilities,
            ]
        }

        if let result = diagnosticResult {
            dict["lastDiagnostic"] = [
                "prompt": result.prompt,
                "responseLength": result.responseLength,
                "hasThinkTags": result.hasThinkTags,
                "wallClockSeconds": result.wallClockSeconds,
                "error": result.error as Any,
            ]
        }

        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{\"error\": \"Failed to serialize diagnostic JSON\"}"
    }
}

// MARK: - Supporting Types

private struct DiagnosticResult {
    let prompt: String
    let responseLength: Int
    let hasThinkTags: Bool
    let wallClockSeconds: Double
    let performanceMetrics: EnginePerformanceMetrics?
    let error: String?
}

private enum DiagnosticStatus {
    case ok, warning, error, info, neutral

    var color: Color {
        switch self {
        case .ok: return .primary
        case .warning: return .orange
        case .error: return .red
        case .info: return .blue
        case .neutral: return .primary
        }
    }
}
