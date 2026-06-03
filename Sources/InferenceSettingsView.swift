import SwiftUI
import LiteRTLM

/// Settings view for configuring ExperimentalFlags, inference parameters,
/// and HuggingFace token management.
/// Flags are user-toggleable with benchmarking defaulting to ON.
struct InferenceSettingsView: View {
    @Bindable var viewModel: ConversationViewModel
    @State private var hfTokenInput = ""
    @State private var hfTokenSaved = HFTokenStorage.hasToken
    @State private var hfTokenMessage = ""

    /// Helper for displaying tool information in a ForEach.
    /// Tool protocol has static properties, so we need to extract them at build time.
    private struct ToolDisplayItem {
        let name: String
        let desc: String
    }

    private var toolDisplayItems: [ToolDisplayItem] {
        [
            ToolDisplayItem(name: CalculatorTool.name, desc: CalculatorTool.description),
            ToolDisplayItem(name: DateTimeTool.name, desc: DateTimeTool.description),
            ToolDisplayItem(name: DeviceInfoTool.name, desc: DeviceInfoTool.description),
            ToolDisplayItem(name: UnitConverterTool.name, desc: UnitConverterTool.description),
            ToolDisplayItem(name: TextAnalyzerTool.name, desc: TextAnalyzerTool.description),
            ToolDisplayItem(name: SystemHealthTool.name, desc: SystemHealthTool.description),
        ]
    }


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

            Section("Thinking Mode") {
                Toggle("Enable Thinking", isOn: Binding(
                    get: { viewModel.experimentalFlags.enableThinking },
                    set: { newValue in
                        viewModel.experimentalFlags.enableThinking = newValue
                    }
                ))
                .help("When enabled, the model's reasoning is displayed in a collapsible 'Thinking' section before the response.")

                Label(
                    "The model may output reasoning in <think> blocks. When enabled, these are parsed and shown separately from the response.",
                    systemImage: "brain.head.profile"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Tool Calling") {
                Toggle("Enable Tool Calling", isOn: Binding(
                    get: { viewModel.experimentalFlags.enableToolCalling },
                    set: { newValue in
                        viewModel.experimentalFlags.enableToolCalling = newValue
                    }
                ))
                .help("Allow the model to invoke built-in tools during inference.")

                if viewModel.experimentalFlags.enableToolCalling {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Available Tools (\(ToolRegistry.defaultTools.count))")
                            .font(.caption)
                            .fontWeight(.semibold)

                        ForEach(toolDisplayItems, id: \.name) { item in
                            HStack(spacing: 6) {
                                Image(systemName: "wrench.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                Text(item.name)
                                    .font(.caption)
                                    .fontDesign(.monospaced)
                                Text("— \(item.desc)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    Label(
                        "Tools are side-effect-free and work fully offline. The model can invoke tools to calculate, check time, analyze text, convert units, and introspect device health.",
                        systemImage: "checkmark.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Sampler Configuration") {
                Stepper("Top-K: \(viewModel.topK)", value: $viewModel.topK, in: 1...128)
                    .help("Number of most likely tokens to consider. Set to 1 for greedy (deterministic) decoding.")

                HStack {
                    Text("Top-P: \(viewModel.topP, specifier: "%.2f")")
                    Slider(value: $viewModel.topP, in: 0.0...1.0, step: 0.05)
                }
                .help("Cumulative probability threshold for nucleus sampling.")

                HStack {
                    Text("Temperature: \(viewModel.temperature, specifier: "%.2f")")
                    Slider(value: $viewModel.temperature, in: 0.0...2.0, step: 0.1)
                }
                .help("Controls randomness. 0 = deterministic, higher = more creative.")

                Stepper("Seed: \(viewModel.seed)", value: $viewModel.seed, in: 0...Int.max)
                    .help("Seed for reproducible generation. 0 = non-deterministic (random). Same seed + same prompt = same output.")

                Button {
                    viewModel.topK = 1
                    viewModel.topP = 1.0
                    viewModel.temperature = 1.0
                } label: {
                    Label("Greedy (Gallery Match)", systemImage: "target")
                }
                .help("Set topK=1, topP=1.0 to match AI Edge Gallery's benchmark settings for apples-to-apples comparison.")

                Button {
                    viewModel.topK = 64
                    viewModel.topP = 0.95
                    viewModel.temperature = 1.0
                } label: {
                    Label("Default Sampling", systemImage: "dice")
                }
                .help("Reset to SDK defaults: topK=64, topP=0.95, temperature=1.0.")

                Text("⚠️ Sampler changes take effect on next model load.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("System Message") {
                TextEditor(text: $viewModel.systemMessage)
                    .frame(minHeight: 60, maxHeight: 120)
                    .font(.body)
                    .help("Set the model's persona or instructions. Applied on next model load.")

                if !viewModel.systemMessage.isEmpty {
                    Button(role: .destructive) {
                        viewModel.systemMessage = ""
                    } label: {
                        Label("Clear System Message", systemImage: "trash")
                    }
                }

                Text("Examples: \"You are a helpful coding assistant.\", \"Respond only in JSON format.\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("⚠️ System message takes effect on next model load.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            Section("HuggingFace Token") {
                if hfTokenSaved {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
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
                } else {
                    Text("Required for downloading gated models from HuggingFace (e.g., google/* repos). Public models (litert-community/*) don't need a token.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    SecureField("hf_...", text: $hfTokenInput)
                        .textFieldStyle(.roundedBorder)

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
                }

                if !hfTokenMessage.isEmpty {
                    Text(hfTokenMessage)
                        .font(.caption)
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
