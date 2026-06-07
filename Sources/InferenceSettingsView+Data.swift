import SwiftUI
import LiteRTLM

extension InferenceSettingsView {

    @ViewBuilder
    var modelInfoSection: some View {
        // Model info section (shown when metadata is available)
        if let metadata = viewModel.activeModelMetadata {
            Section {
                LabeledContent("Name") { Text(metadata.name) }
                if let path = viewModel.activeModelURL?.path {
                    LabeledContent("Path") {
                        Text(path)
                            .font(.caption)
                            .textSelection(.enabled)
                            .lineLimit(3)
                    }
                }
                LabeledContent("Size") {
                    Text(ByteCountFormatter.string(fromByteCount: metadata.sizeInBytes, countStyle: .file))
                }
                LabeledContent("Min Memory") { Text("\(metadata.minDeviceMemoryGB) GB") }
                if metadata.supportsImage {
                    Label("Image input supported", systemImage: "photo")
                        .font(.caption)
                }
                if metadata.supportsAudio {
                    Label("Audio input supported", systemImage: "waveform")
                        .font(.caption)
                }
            } header: {
                Label("Model Info", systemImage: "info.circle")
                    .foregroundStyle(AppColors.accentTeal)
            }
        }
    }

    @ViewBuilder
    var performanceSection: some View {
        Section(header: Label("Performance", systemImage: "chart.bar")
            .foregroundStyle(AppColors.accentGold)) {
            if let info = viewModel.benchmarkInfo {
                LabeledContent("Init Time") {
                    Text(String(format: "%.3f s", info.initTimeInSecond))
                        .monospacedDigit()
                }
                LabeledContent("Time to First Token") {
                    Text(String(format: "%.3f s", info.timeToFirstTokenInSecond))
                        .monospacedDigit()
                }
                LabeledContent("Decode Speed") {
                    Text(String(format: "%.1f tok/s", info.lastDecodeTokensPerSecond))
                        .monospacedDigit()
                }
                LabeledContent("Prefill Speed") {
                    Text(String(format: "%.1f tok/s", info.lastPrefillTokensPerSecond))
                        .monospacedDigit()
                }
                LabeledContent("Prefill Tokens") {
                    Text("\(info.lastPrefillTokenCount)")
                        .monospacedDigit()
                }
                LabeledContent("Decode Tokens") {
                    Text("\(info.lastDecodeTokenCount)")
                        .monospacedDigit()
                }

                // Device-level instrumentation (from Work Stream 3)
                if let metrics = viewModel.inferenceMetrics {
                    LabeledContent("Thermal (Start)") {
                        HStack(spacing: 4) {
                            Image(systemName: metrics.startSnapshot.thermalLevel.symbolName)
                            Text(metrics.startSnapshot.thermalLevel.label)
                        }
                    }
                    if metrics.thermalStateChanged {
                        LabeledContent("Thermal (End)") {
                            HStack(spacing: 4) {
                                Image(systemName: metrics.endSnapshot.thermalLevel.symbolName)
                                Text(metrics.endSnapshot.thermalLevel.label)
                            }
                        }
                    }
                    LabeledContent("Memory Available") {
                        Text(String(format: "%.0f MB", metrics.endSnapshot.availableMemoryMB))
                            .monospacedDigit()
                    }
                    if !metrics.tokenLatenciesMs.isEmpty {
                        LabeledContent("Median Latency") {
                            Text(String(format: "%.1f ms", metrics.medianTokenLatencyMs))
                                .monospacedDigit()
                        }
                        LabeledContent("P95 Latency") {
                            Text(String(format: "%.1f ms", metrics.p95TokenLatencyMs))
                                .monospacedDigit()
                        }
                    }
                }
            } else {
                Text("No benchmark data yet. Run an inference with benchmarking enabled.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    var hfTokenSection: some View {
        Section(header: Label("HuggingFace Token", systemImage: "key.fill")
            .foregroundStyle(AppColors.textSecondary)) {
            if hfTokenSaved {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.success)
                    Text("Token saved in Keychain")
                        .font(.caption)
                }

                Button(role: .destructive) {
                    HFTokenStorage.delete()
                    hfTokenSaved = false
                    hfTokenMessage = "Token cleared."
                } label: {
                    Label("Clear Token", systemImage: "trash")
                }
                .accessibilityIdentifier("button_clearToken")
            } else {
                Text("Required for downloading gated models from HuggingFace (e.g., google/* repos). Public models (litert-community/*) don't need a token.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SecureField("hf_...", text: $hfTokenInput)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("secureField_hfToken")

                Button {
                    guard !hfTokenInput.isEmpty else { return }
                    do {
                        try HFTokenStorage.save(token: hfTokenInput)
                        hfTokenSaved = true
                        hfTokenInput = ""
                        hfTokenMessage = "Token saved."

                        // Retry pending download if there is one
                        if let model = viewModel.downloadManager.pendingAuthModel {
                            viewModel.downloadManager.retryWithToken(model)
                        }
                    } catch {
                        hfTokenMessage = "Save failed: \(error.localizedDescription)"
                    }
                } label: {
                    Label("Save Token", systemImage: "key.fill")
                }
                .disabled(hfTokenInput.isEmpty)
                .accessibilityIdentifier("button_saveToken")
            }

            if !hfTokenMessage.isEmpty {
                Text(hfTokenMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
