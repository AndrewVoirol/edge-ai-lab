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

// MARK: - EnginePickerView

/// Settings section for selecting the active inference engine.
///
/// Presents a `Picker` bound to the view model's `selectedRuntimeType`,
/// showing only runtimes that are currently supported for inference.
/// Includes a status label when an engine is ready and an auto-detect
/// hint when model metadata is available.
struct EnginePickerView: View {
    @Bindable var viewModel: ConversationViewModel

    var body: some View {
        Section {
            // Engine runtime picker
            Picker(selection: $viewModel.selectedRuntimeType) {
                ForEach(RuntimeType.supportedCases) { runtime in
                    Label(runtime.displayName, systemImage: runtime.iconName)
                        .tag(runtime)
                        .accessibilityIdentifier("engine_option_\(runtime.rawValue)")
                }
            } label: {
                Text("Runtime")
                    .accessibilityIdentifier("engine_picker_label")
            }
            .accessibilityIdentifier("engine_picker")
            .onChange(of: viewModel.selectedRuntimeType) { _, newValue in
                Task {
                    await viewModel.switchEngine(to: newValue)
                }
            }

            // Active engine status
            if viewModel.isEngineReady {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.sprout)
                    Text("\(viewModel.selectedRuntimeType.displayName) engine ready")
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .accessibilityIdentifier("engine_status_ready")
            }

            // GPU/CPU Backend picker
            let capability = viewModel.activeModelMetadata?.platformSupport.currentPlatform ?? .unknown
            let availableBackends = BackendPickerLogic.availableBackends(for: capability)

            if availableBackends.count > 1 {
                Picker(selection: $viewModel.preferredBackend) {
                    ForEach(availableBackends) { backend in
                        Label(backend.displayName, systemImage: backend.iconName)
                            .tag(backend)
                            .accessibilityIdentifier("backend_option_\(backend.rawValue)")
                    }
                } label: {
                    Label("Accelerator", systemImage: "bolt.horizontal")
                        .accessibilityIdentifier("backend_picker_label")
                }
                .accessibilityIdentifier("backend_picker")
            } else if let only = availableBackends.first {
                HStack {
                    Image(systemName: only.iconName)
                        .foregroundStyle(AppColors.textSecondary)
                    Text("\(only.displayName) only")
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
                .accessibilityIdentifier("backend_single_option")
            }

            // Auto-detect hint when model metadata is available
            if let metadata = viewModel.activeModelMetadata {
                let detectedType = metadata.runtimeType
                if detectedType != viewModel.selectedRuntimeType {
                    Label {
                        Text("This model uses \(detectedType.displayName) — switch to match?")
                            .font(.caption)
                    } icon: {
                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(AppColors.moss)
                    }
                    .foregroundStyle(AppColors.caution)
                    .accessibilityIdentifier("engine_autodetect_hint")
                } else {
                    Label {
                        Text("Engine matches model format")
                            .font(.caption)
                    } icon: {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(AppColors.sprout)
                    }
                    .foregroundStyle(AppColors.textTertiary)
                    .accessibilityIdentifier("engine_format_match")
                }
            }
        } header: {
            Label("Engine", systemImage: "engine.combustion")
                .foregroundStyle(AppColors.textSecondary)
                .accessibilityIdentifier("engine_section_header")
        }
    }
}
