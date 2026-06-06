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

    @State private var expandedServerID: UUID? = nil

    /// Helper for displaying tool information in a ForEach.
    /// Tool protocol has static properties, so we need to extract them at build time.
    private struct ToolDisplayItem {
        let name: String
        let desc: String
    }

    private var toolDisplayItems: [ToolDisplayItem] {
        var items = [
            ToolDisplayItem(name: CalculatorTool.name, desc: CalculatorTool.description),
            ToolDisplayItem(name: DateTimeTool.name, desc: DateTimeTool.description),
            ToolDisplayItem(name: DeviceInfoTool.name, desc: DeviceInfoTool.description),
            ToolDisplayItem(name: UnitConverterTool.name, desc: UnitConverterTool.description),
            ToolDisplayItem(name: TextAnalyzerTool.name, desc: TextAnalyzerTool.description),
            ToolDisplayItem(name: SystemHealthTool.name, desc: SystemHealthTool.description),
        ]
        if viewModel.experimentalFlags.enableAgentSkills {
            items.append(ToolDisplayItem(name: WikipediaSkillTool.name, desc: WikipediaSkillTool.description))
            items.append(ToolDisplayItem(name: MapSkillTool.name, desc: MapSkillTool.description))
        }
        return items
    }


    var body: some View {
        Form {
            Section("Backend") {
                Toggle("Use GPU", isOn: $viewModel.useGPU)
                    .help("Use GPU acceleration for inference. Disable to fall back to CPU.")
                    .accessibilityIdentifier("toggle_useGPU")

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
                Toggle("Enable Benchmarking", isOn: $viewModel.experimentalFlags.enableBenchmark)
                .help("Collect TTFT, decode speed, and prefill speed after each inference.")
                .accessibilityIdentifier("toggle_enableBenchmark")

                Toggle("Multi-Token Prediction (MTP)", isOn: Binding(
                    get: { viewModel.experimentalFlags.enableSpeculativeDecoding ?? false },
                    set: { viewModel.experimentalFlags.enableSpeculativeDecoding = $0 }
                ))
                .help("Enable speculative decoding (Multi-Token Prediction) for faster decode speeds on GPU backends. Recommended for GPU/Metal.")
                .accessibilityIdentifier("toggle_enableMTP")

                if let metadata = viewModel.activeModelMetadata, metadata.supportsMTP {
                    Label("This model supports MTP for accelerated decoding.", systemImage: "hare")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Toggle("Constrained Decoding", isOn: $viewModel.experimentalFlags.enableConversationConstrainedDecoding)
                .help("Enable constrained decoding for structured outputs.")
                .accessibilityIdentifier("toggle_constrainedDecoding")
            }

            Section("Thinking Mode") {
                Toggle("Enable Thinking", isOn: $viewModel.experimentalFlags.enableThinking)
                .help("When enabled, the model's reasoning is displayed in a collapsible 'Thinking' section before the response.")
                .accessibilityIdentifier("toggle_enableThinking")

                Label(
                    "The model may output reasoning in <think> blocks. When enabled, these are parsed and shown separately from the response.",
                    systemImage: "brain.head.profile"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Tool Calling") {
                Toggle("Enable Tool Calling", isOn: $viewModel.experimentalFlags.enableToolCalling)
                .help("Allow the model to invoke built-in tools during inference.")
                .accessibilityIdentifier("toggle_enableToolCalling")

                if viewModel.experimentalFlags.enableToolCalling {
                    Toggle("Enable Agent Skills", isOn: $viewModel.experimentalFlags.enableAgentSkills)
                    .help("Enable built-in agent skills: Wikipedia search and Apple Maps rendering.")
                    .accessibilityIdentifier("toggle_enableAgentSkills")

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Available Tools (\(toolDisplayItems.count))")
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
                    
                    Text("⚠️ Tool Calling changes take effect on next model load.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            #if os(macOS)
            if viewModel.experimentalFlags.enableToolCalling {
                Section("MCP Servers (macOS Only)") {
                    ForEach(viewModel.mcpServers) { config in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(config.name)
                                        .fontWeight(.medium)
                                    if expandedServerID != config.id {
                                        Text("\(config.command) \(config.args.joined(separator: " "))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                // State Indicator
                                let state = viewModel.getMCPClientState(for: config.id)
                                HStack(spacing: 4) {
                                    Circle()
                                        .frame(width: 8, height: 8)
                                        .foregroundStyle(statusColor(for: state))
                                    Text(statusText(for: state))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Toggle("", isOn: Binding(
                                    get: { config.enabled },
                                    set: { newValue in
                                        var updated = config
                                        updated.enabled = newValue
                                        viewModel.updateMCPServerConfig(updated)
                                    }
                                ))
                                .labelsHidden()
                                .accessibilityIdentifier("toggle_mcp_\(config.name)")
                            }

                            if expandedServerID == config.id {
                                // Inline Editor
                                VStack(alignment: .leading, spacing: 8) {
                                    TextField("Name", text: Binding(
                                        get: { config.name },
                                        set: { var new = config; new.name = $0; viewModel.updateMCPServerConfig(new) }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityIdentifier("textField_mcp_name_\(config.id)")

                                    TextField("Executable/Interpreter (e.g. /usr/local/bin/node)", text: Binding(
                                        get: { config.command },
                                        set: { var new = config; new.command = $0; viewModel.updateMCPServerConfig(new) }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityIdentifier("textField_mcp_command_\(config.id)")

                                    TextField("Arguments (space-separated)", text: Binding(
                                        get: { config.args.joined(separator: " ") },
                                        set: { var new = config; new.args = $0.split(separator: " ").map(String.init); viewModel.updateMCPServerConfig(new) }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityIdentifier("textField_mcp_args_\(config.id)")

                                    VStack(alignment: .leading) {
                                        Text("Environment Variables (One per line: KEY=VALUE)")
                                            .font(.caption)
                                        TextEditor(text: Binding(
                                            get: { config.env.map { "\($0.key)=\($0.value)" }.joined(separator: "\n") },
                                            set: { newEnv in
                                                var new = config
                                                var envDict: [String: String] = [:]
                                                for line in newEnv.split(separator: "\n") {
                                                    let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                                                    if parts.count == 2 { envDict[parts[0]] = parts[1] }
                                                }
                                                new.env = envDict
                                                viewModel.updateMCPServerConfig(new)
                                            }
                                        ))
                                        .frame(minHeight: 60)
                                        .font(.system(.body, design: .monospaced))
                                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.5), lineWidth: 0.5))
                                    }

                                    HStack {
                                        Spacer()
                                        Button("Close") {
                                            expandedServerID = nil
                                        }
                                        .controlSize(.small)
                                        .accessibilityIdentifier("button_close_mcp_\(config.name)")
                                    }
                                }
                                .padding()
                                .background(Color.secondary.opacity(0.05))
                                .cornerRadius(8)
                            } else {
                                // Tools list if connected
                                let tools = viewModel.getMCPTools(for: config.id)
                                if !tools.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Registered Tools:")
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.secondary)
                                        ForEach(tools, id: \.name) { tool in
                                            HStack(spacing: 4) {
                                                Image(systemName: "circle.grid.cross.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(.blue)
                                                Text(tool.name)
                                                    .font(.caption2)
                                                    .monospaced()
                                                Text("— \(tool.description)")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                    .padding(.leading, 8)
                                }

                                // Edit & Delete button
                                HStack {
                                    Button("Edit") {
                                        expandedServerID = config.id
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.caption2)
                                    .accessibilityIdentifier("button_edit_mcp_\(config.name)")

                                    Spacer()

                                    Button("Delete", role: .destructive) {
                                        viewModel.deleteMCPServerConfig(id: config.id)
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                    .accessibilityIdentifier("button_delete_mcp_\(config.name)")
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Button(action: {
                        let newConfig = MCPServerConfig(
                            name: "New Server",
                            enabled: false,
                            command: "",
                            args: [],
                            env: [:]
                        )
                        viewModel.addMCPServerConfig(newConfig)
                        expandedServerID = newConfig.id
                    }) {
                        Label("Add MCP Server", systemImage: "plus")
                    }
                    .accessibilityIdentifier("button_addMCP")
                }
            }
            #endif

            Section("Sampler Configuration") {
                Stepper("Top-K: \(viewModel.topK)", value: $viewModel.topK, in: 1...128)
                    .help("Number of most likely tokens to consider. Set to 1 for greedy (deterministic) decoding.")
                    .accessibilityIdentifier("stepper_topK")

                HStack {
                    Text("Top-P: \(viewModel.topP, specifier: "%.2f")")
                    Slider(value: $viewModel.topP, in: 0.0...1.0, step: 0.05)
                        .accessibilityIdentifier("slider_topP")
                }
                .help("Cumulative probability threshold for nucleus sampling.")

                HStack {
                    Text("Temperature: \(viewModel.temperature, specifier: "%.2f")")
                    Slider(value: $viewModel.temperature, in: 0.0...2.0, step: 0.1)
                        .accessibilityIdentifier("slider_temperature")
                }
                .help("Controls randomness. 0 = deterministic, higher = more creative.")

                Stepper("Seed: \(viewModel.seed)", value: $viewModel.seed, in: 0...Int.max)
                    .help("Seed for reproducible generation. 0 = non-deterministic (SDK default). Same seed + same prompt = same output.")
                    .accessibilityIdentifier("stepper_seed")

                Button {
                    viewModel.topK = 1
                    viewModel.topP = 1.0
                    viewModel.temperature = 1.0
                } label: {
                    Label("Greedy (Gallery Match)", systemImage: "target")
                }
                .help("Set topK=1, topP=1.0 to match AI Edge Gallery's benchmark settings for apples-to-apples comparison.")
                .accessibilityIdentifier("button_greedyMatch")

                Button {
                    viewModel.topK = 64
                    viewModel.topP = 0.95
                    viewModel.temperature = 1.0
                } label: {
                    Label("Default Sampling", systemImage: "dice")
                }
                .help("Reset to SDK defaults: topK=64, topP=0.95, temperature=1.0.")
                .accessibilityIdentifier("button_defaultSampling")

                Text("⚠️ Sampler changes take effect on next model load.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("System Message") {
                TextEditor(text: $viewModel.systemMessage)
                    .frame(minHeight: 60, maxHeight: 120)
                    .font(.body)
                    .help("Set the model's persona or instructions. Applied on next model load.")
                    .accessibilityIdentifier("textEditor_systemMessage")

                if !viewModel.systemMessage.isEmpty {
                    Button(role: .destructive) {
                        viewModel.systemMessage = ""
                    } label: {
                        Label("Clear System Message", systemImage: "trash")
                    }
                    .accessibilityIdentifier("button_clearSystemMessage")
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
        .formStyle(.grouped)
        #if os(macOS)
        .frame(minWidth: 350)
        #endif
    }

    private func statusColor(for state: MCPClientState) -> Color {
        switch state {
        case .stopped: return .gray
        case .starting: return .yellow
        case .connected: return .green
        case .failed: return .red
        }
    }

    private func statusText(for state: MCPClientState) -> String {
        switch state {
        case .stopped: return "Stopped"
        case .starting: return "Connecting"
        case .connected: return "Connected"
        case .failed(let err): return "Error: \(err.prefix(30))..."
        }
    }
}
