import SwiftUI

/// Settings view for configuring ExperimentalFlags and inference parameters.
/// Flags are user-toggleable with benchmarking defaulting to ON.
struct InferenceSettingsView: View {
    @Bindable var viewModel: ConversationViewModel

    var body: some View {
        Form {
            Section("Backend") {
                Toggle("Use GPU", isOn: $viewModel.useGPU)
                    .help("Use GPU acceleration for inference. Disable to fall back to CPU.")

                // Show platform compatibility context
                if let result = viewModel.backendResult {
                    HStack {
                        Image(systemName: result.activeBackend == .gpu ? "bolt.fill" : "cpu")
                            .foregroundStyle(result.activeBackend == .gpu ? .green : .orange)
                        Text("Active: \(result.activeBackend == .gpu ? "GPU (Metal)" : "CPU (XNNPACK)")")
                            .font(.caption)
                    }

                    if result.didFallback, let reason = result.fallbackReason {
                        Label(reason, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }

                // Model compatibility hint from metadata
                if let metadata = viewModel.activeModelMetadata {
                    let capability = metadata.platformSupport.currentPlatform
                    switch capability {
                    case .gpuOnly:
                        Label("This model only supports GPU on this platform.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    case .cpuOnly:
                        Label("GPU is not available for this model on this platform.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    case .gpuAndCpu:
                        Label("Both GPU and CPU are available.", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.green)
                    case .unknown:
                        Label("Backend compatibility unknown — will probe at runtime.", systemImage: "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Experimental Flags") {
                Toggle("Enable Benchmarking", isOn: Binding(
                    get: { viewModel.experimentalFlags.enableBenchmark },
                    set: { newValue in
                        viewModel.experimentalFlags = ExperimentalFlagsState(
                            enableBenchmark: newValue,
                            enableSpeculativeDecoding: viewModel.experimentalFlags.enableSpeculativeDecoding,
                            enableConversationConstrainedDecoding: viewModel.experimentalFlags.enableConversationConstrainedDecoding,
                            visualTokenBudget: viewModel.experimentalFlags.visualTokenBudget
                        )
                    }
                ))
                .help("Collect TTFT, decode speed, and prefill speed after each inference.")

                Toggle("Multi-Token Prediction (MTP)", isOn: Binding(
                    get: { viewModel.experimentalFlags.enableSpeculativeDecoding ?? false },
                    set: { newValue in
                        viewModel.experimentalFlags = ExperimentalFlagsState(
                            enableBenchmark: viewModel.experimentalFlags.enableBenchmark,
                            enableSpeculativeDecoding: newValue,
                            enableConversationConstrainedDecoding: viewModel.experimentalFlags.enableConversationConstrainedDecoding,
                            visualTokenBudget: viewModel.experimentalFlags.visualTokenBudget
                        )
                    }
                ))
                .help("Enable speculative decoding (Multi-Token Prediction) for faster decode speeds on GPU backends. Recommended for GPU/Metal.")

                if let metadata = viewModel.activeModelMetadata, metadata.supportsMTP {
                    Label("This model supports MTP for accelerated decoding.", systemImage: "hare")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Toggle("Constrained Decoding", isOn: Binding(
                    get: { viewModel.experimentalFlags.enableConversationConstrainedDecoding },
                    set: { newValue in
                        viewModel.experimentalFlags = ExperimentalFlagsState(
                            enableBenchmark: viewModel.experimentalFlags.enableBenchmark,
                            enableSpeculativeDecoding: viewModel.experimentalFlags.enableSpeculativeDecoding,
                            enableConversationConstrainedDecoding: newValue,
                            visualTokenBudget: viewModel.experimentalFlags.visualTokenBudget
                        )
                    }
                ))
                .help("Enable constrained decoding for structured outputs.")
            }

            // Model info section (shown when metadata is available)
            if let metadata = viewModel.activeModelMetadata {
                Section("Model Info") {
                    LabeledContent("Name") { Text(metadata.name) }
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
                }
            }

            Section("Performance") {
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
                } else {
                    Text("No benchmark data yet. Run an inference with benchmarking enabled.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
        .frame(minWidth: 350)
        #endif
    }
}

