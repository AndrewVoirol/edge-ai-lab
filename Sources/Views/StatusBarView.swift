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
            }
            Text(viewModel.statusMessage)
                .font(AppTypography.sectionHeader)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)

            if let result = viewModel.backendResult, viewModel.isEngineReady {
                HStack(spacing: AppSpacing.xs) {
                    Circle()
                        .fill(result.activeBackend == .gpu ? AppColors.sprout : AppColors.caution)
                        .frame(width: 6, height: 6)
                        .glow(result.activeBackend == .gpu ? AppColors.sprout : AppColors.caution,
                              radius: 3, opacity: 0.5)
                    Text(result.activeBackend == .gpu ? "GPU" : "CPU")
                        .font(AppTypography.badge)
                        .foregroundStyle(result.activeBackend == .gpu ? AppColors.sprout : AppColors.caution)
                }
                .accessibilityIdentifier("statusBar_backend")
                .accessibilityLabel(result.activeBackend == .gpu ? "Backend: loaded on GPU" : "Backend: loaded on CPU")
            }

            if let metadata = viewModel.activeModelMetadata, viewModel.isEngineReady {
                HStack(spacing: AppSpacing.xs) {
                    if metadata.supportsMTP { Text("MTP").badge(AppColors.badgeMTP) }
                    if metadata.supportsImage { Text("Vision").badge(AppColors.badgeVision) }
                    if metadata.supportsAudio { Text("Audio").badge(AppColors.badgeAudio) }
                    if metadata.supportsToolCalling { Text("Tools").badge(AppColors.action) }
                }
            }

            // Thermal state indicator
            if let metrics = viewModel.inferenceMetrics,
               metrics.endSnapshot.thermalLevel != .nominal {
                let thermal = metrics.endSnapshot.thermalLevel
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: thermal.symbolName)
                        .font(.caption2)
                        .foregroundStyle(thermalColor(for: thermal))
                    Text(thermal.label)
                        .font(AppTypography.badge)
                        .foregroundStyle(thermalColor(for: thermal))
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

    private func thermalColor(for state: ThermalLevel) -> Color {
        switch state {
        case .nominal: return AppColors.sprout
        case .fair: return AppColors.caution
        case .serious: return AppColors.ember
        case .critical: return AppColors.ember
        }
    }
}
#endif
