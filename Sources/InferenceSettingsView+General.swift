import SwiftUI
import LiteRTLM

extension InferenceSettingsView {

    @ViewBuilder
    var backendSection: some View {
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
    }

    @ViewBuilder
    var experimentalFlagsSection: some View {
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
    }
}
