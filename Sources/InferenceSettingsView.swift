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

                Toggle("Speculative Decoding", isOn: Binding(
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
                .help("Enable speculative decoding for potentially faster token generation.")

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
