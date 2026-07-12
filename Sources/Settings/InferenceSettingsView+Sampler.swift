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

extension InferenceSettingsView {

    @ViewBuilder
    var samplerSection: some View {
        Section {
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

            Text("Lower = more focused and deterministic · Higher = more creative and varied")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)

            SettingsImpactLabel(
                descriptor: FlagRegistry.temperature,
                currentRuntime: viewModel.selectedRuntimeType
            )

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
        } header: {
            Label("Sampler Configuration", systemImage: "slider.horizontal.3")
                .foregroundStyle(AppColors.accentSecondary)
        }
    }

    @ViewBuilder
    var systemMessageSection: some View {
        Section {
            TextEditor(text: $viewModel.systemMessage)
                .frame(minHeight: 60, maxHeight: 120)
                .font(.body)
                .help("Set the model's persona or instructions. Changes auto-apply by reloading the engine.")
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
                .foregroundStyle(AppColors.textSecondary)
        } header: {
            Label("System Message", systemImage: "text.bubble")
                .foregroundStyle(AppColors.textSecondary)
        }
    }
}
