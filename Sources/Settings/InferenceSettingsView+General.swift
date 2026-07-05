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

import SwiftUI
import LiteRTLM

extension InferenceSettingsView {

    @ViewBuilder
    var backendSection: some View {
        Section {
            // KV-Cache (maxNumTokens) stepper
            let modelContextLength = viewModel.activeModelMetadata?.contextWindowSize
            let presets = KVCacheConfigLogic.presetSteps(modelContextLength: modelContextLength)

            Picker(selection: Binding(
                get: {
                    // Map nil (auto) to 0 for the picker, actual values to themselves
                    viewModel.maxNumTokens ?? 0
                },
                set: { newValue in
                    viewModel.maxNumTokens = newValue == 0 ? nil : newValue
                }
            )) {
                Text("Auto").tag(0)
                    .accessibilityIdentifier("kvcache_option_auto")
                ForEach(presets, id: \.self) { preset in
                    Text("\(preset) tokens").tag(preset)
                        .accessibilityIdentifier("kvcache_option_\(preset)")
                }
            } label: {
                Label("KV-Cache Size", systemImage: "memorychip")
                    .accessibilityIdentifier("kvcache_picker_label")
            }
            .accessibilityIdentifier("kvcache_picker")

            // Display label showing current config
            Text(KVCacheConfigLogic.formatDisplayLabel(
                tokenCount: viewModel.maxNumTokens,
                modelDefault: modelContextLength
            ))
            .font(.caption)
            .foregroundStyle(AppColors.textTertiary)
            .accessibilityIdentifier("kvcache_display_label")

            // Show platform compatibility context for active backend
            if let result = viewModel.backendResult {
                HStack {
                    Image(systemName: result.activeBackend == .gpu ? "bolt.fill" : "cpu")
                        .foregroundStyle(result.activeBackend == .gpu ? AppColors.success : AppColors.warning)
                    Text("Active: \(result.activeBackend == .gpu ? "GPU (Metal)" : "CPU (XNNPACK)")")
                        .font(.caption)
                }
                .accessibilityIdentifier("backend_active_status")

                if result.didFallback, let reason = result.fallbackReason {
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(AppColors.warning)
                        .accessibilityIdentifier("backend_fallback_reason")
                }
            }

            // Restart-required warning
            if viewModel.engineConfigChanged {
                Label(
                    "Settings changed — restart engine to apply",
                    systemImage: "arrow.clockwise.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(AppColors.warning)
                .accessibilityIdentifier("engine_restart_warning")

                Button {
                    Task {
                        await viewModel.restartEngine()
                    }
                } label: {
                    Label("Restart Engine", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("engine_restart_button")
            }
        } header: {
            Label("Backend & Memory", systemImage: "cpu")
                .foregroundStyle(AppColors.textSecondary)
                .accessibilityIdentifier("backend_section_header")
        }
    }

    @ViewBuilder
    var runtimeFlagsSection: some View {
        Section {
            Toggle("Enable Benchmarking", isOn: $viewModel.runtimeFlags.enableBenchmark)
            .help("Collect TTFT, decode speed, and prefill speed after each inference.")
            .accessibilityIdentifier("toggle_enableBenchmark")

            Toggle("Multi-Token Prediction (MTP)", isOn: Binding(
                get: { viewModel.runtimeFlags.enableSpeculativeDecoding ?? false },
                set: { viewModel.runtimeFlags.enableSpeculativeDecoding = $0 }
            ))
            .help("Enable speculative decoding (Multi-Token Prediction) for faster decode speeds on GPU backends. Recommended for GPU/Metal.")
            .accessibilityIdentifier("toggle_enableMTP")

            if let metadata = viewModel.activeModelMetadata, metadata.supportsMTP {
                Label("This model supports MTP for accelerated decoding.", systemImage: "hare")
                    .font(.caption)
                    .foregroundStyle(AppColors.success)
            }

            Toggle("Constrained Decoding", isOn: $viewModel.runtimeFlags.enableConversationConstrainedDecoding)
            .help("Enable constrained decoding for structured outputs.")
            .accessibilityIdentifier("toggle_constrainedDecoding")
        } header: {
            Label("Experimental Flags", systemImage: "flask")
                .foregroundStyle(AppColors.textSecondary)
        }
    }
}
