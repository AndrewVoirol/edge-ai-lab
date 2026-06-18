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

import SwiftUI
import LiteRTLM

extension InferenceSettingsView {

    @ViewBuilder
    var backendSection: some View {
        Section {
            Toggle("Use GPU", isOn: $viewModel.useGPU)
                .help("Use GPU acceleration for inference. Disable to fall back to CPU.")
                .accessibilityIdentifier("toggle_useGPU")

            // Show platform compatibility context
            if let result = viewModel.backendResult {
                HStack {
                    Image(systemName: result.activeBackend == .gpu ? "bolt.fill" : "cpu")
                        .foregroundStyle(result.activeBackend == .gpu ? AppColors.success : AppColors.warning)
                    Text("Active: \(result.activeBackend == .gpu ? "GPU (Metal)" : "CPU (XNNPACK)")")
                        .font(.caption)
                }

                if result.didFallback, let reason = result.fallbackReason {
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(AppColors.warning)
                }
            }

            // Model compatibility hint from metadata
            if let metadata = viewModel.activeModelMetadata {
                let capability = metadata.platformSupport.currentPlatform
                switch capability {
                case .gpuOnly:
                    Label("This model only supports GPU on this platform.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(AppColors.accentTeal)
                case .cpuOnly:
                    Label("GPU is not available for this model on this platform.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(AppColors.warning)
                case .gpuAndCpu:
                    Label("Both GPU and CPU are available.", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(AppColors.success)
                case .unknown:
                    Label("Backend compatibility unknown — will probe at runtime.", systemImage: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        } header: {
            Label("Backend", systemImage: "cpu")
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    @ViewBuilder
    var experimentalFlagsSection: some View {
        Section {
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
                    .foregroundStyle(AppColors.success)
            }

            Toggle("Constrained Decoding", isOn: $viewModel.experimentalFlags.enableConversationConstrainedDecoding)
            .help("Enable constrained decoding for structured outputs.")
            .accessibilityIdentifier("toggle_constrainedDecoding")
        } header: {
            Label("Experimental Flags", systemImage: "flask")
                .foregroundStyle(AppColors.textSecondary)
        }
    }
}
