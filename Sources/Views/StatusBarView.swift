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

// MARK: - Status Bar View (macOS)

/// The macOS-only status bar at the bottom of the window showing model status
/// and capability badges.
///
/// Accessibility: Every interactive element has `.accessibilityIdentifier`
/// for agent discoverability and UI testing.
#if os(macOS)
struct StatusBarView: View {
    @Environment(ConversationViewModel.self) private var viewModel

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            if viewModel.isLoadingModel {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityIdentifier("progress_loading")
                    .accessibilityLabel("Loading model")
                if viewModel.showLoadingCancelButton {
                    Button {
                        viewModel.cancelModelLoad()
                    } label: {
                        Text("Cancel")
                            .font(AppTypography.badge)
                            .foregroundStyle(AppColors.destructive)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("statusBar_cancelModelLoad")
                    .accessibilityLabel("Cancel model loading")
                    .transition(.opacity)
                }
            }
            Text(viewModel.statusMessage)
                .font(AppTypography.sectionHeader)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)

            if let result = viewModel.backendResult, viewModel.isEngineReady {
                HStack(spacing: AppSpacing.xs) {
                    Circle()
                        .fill(result.activeBackend == .gpu ? AppColors.success : AppColors.warning)
                        .frame(width: 6, height: 6)
                        .glow(result.activeBackend == .gpu ? AppColors.success : AppColors.warning,
                              radius: 3, opacity: 0.5)
                    Text(result.activeBackend == .gpu ? "GPU" : "CPU")
                        .font(AppTypography.badge)
                        .foregroundStyle(result.activeBackend == .gpu ? AppColors.success : AppColors.warning)
                }
                .accessibilityIdentifier("statusBar_backend")
                .accessibilityLabel(result.activeBackend == .gpu ? "Backend: loaded on GPU" : "Backend: loaded on CPU")
            }

            if let profile = viewModel.activeCapabilityProfile, viewModel.isEngineReady {
                HStack(spacing: AppSpacing.xs) {
                    if profile.hasMTP { Text("Spec. Dec").badge(AppColors.capabilityMTP) }
                    if profile.hasVision { Text("Vision").badge(AppColors.capabilityVision) }
                    if profile.hasAudio { Text("Audio").badge(AppColors.capabilityAudio) }
                    if profile.hasToolCalling { Text("Tools").badge(AppColors.toolAction) }
                }
            }

            // Thermal state indicator
            if let metrics = viewModel.inferenceMetrics,
               metrics.endSnapshot.thermalLevel != .nominal {
                let thermal = metrics.endSnapshot.thermalLevel
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: thermal.symbolName)
                        .font(AppIconSize.xxs)
                        .foregroundStyle(AppColors.thermal(thermal))
                    Text(thermal.label)
                        .font(AppTypography.badge)
                        .foregroundStyle(AppColors.thermal(thermal))
                }
                .accessibilityIdentifier("statusBar_thermal")
                .accessibilityLabel("Thermal state: \(thermal.label)")
            }

            Spacer()
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.xs)
        .background(AppColors.backgroundTertiary)
        .accessibilityIdentifier("statusBar")
        .accessibilityValue(viewModel.statusMessage)
    }


}
#endif
