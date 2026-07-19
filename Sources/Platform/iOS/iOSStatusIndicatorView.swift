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

#if os(iOS)
import SwiftUI

// MARK: - iOS Status Indicator View

/// A content-layer status indicator for the iOS Chat tab showing model name,
/// performance metrics, and thermal state.
///
/// Design decisions (per Apple HIG "Materials"):
/// - Lives in the content layer, NOT the functional layer (no Liquid Glass)
/// - Uses `.ultraThinMaterial` with Dark Forest tint for visual consistency
/// - Pinned above the input area in the Chat tab
/// - Tappable to expand/collapse for detailed metrics
///
/// Haptic feedback:
/// - `.selection` on tap to expand/collapse
///
/// Accessibility: Every interactive element has `.accessibilityIdentifier`.
struct iOSStatusIndicatorView: View {
    @Environment(ConversationViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isExpanded = false

    var body: some View {
        if viewModel.isEngineReady || viewModel.isLoadingModel {
            VStack(spacing: 0) { // design-system-exempt: zero spacing for tight packing
                // Divider
                Rectangle()
                    .fill(AppColors.border)
                    .frame(height: 0.5)

                // Status content
                Button {
                    withAnimation(AppAnimation.spring) {
                        isExpanded.toggle()
                    }
                } label: {
                    VStack(spacing: 0) { // design-system-exempt: zero spacing for tight packing
                        // Collapsed: Single row
                        collapsedRow

                        // Expanded: Detail metrics
                        if isExpanded {
                            expandedContent
                                .transition(.slideDown)
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.sm)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: isExpanded)
                .accessibilityLabel("Model status: \(viewModel.activeModelMetadata?.name ?? "Loading"), tap to \(isExpanded ? "collapse" : "expand")")
                .accessibilityIdentifier("statusIndicator")
            }
            .background {
                if reduceTransparency {
                    AppColors.backgroundSecondary.opacity(AppOpacity.glass)
                } else {
                    AppColors.backgroundSecondary.opacity(AppOpacity.strong)
                        .background(.ultraThinMaterial)
                }
            }
        }
    }

    // MARK: - Collapsed Row

    private var collapsedRow: some View {
        HStack(spacing: AppSpacing.sm) {
            // Status dot
            if viewModel.isLoadingModel {
                ProgressView()
                    .controlSize(.mini)
                    .tint(AppColors.accentPrimary)
            } else {
                Circle()
                    .fill(AppColors.success)
                    .frame(width: AppSize.dotMd, height: AppSize.dotMd)
                    .pulsingGlow(AppColors.success)
            }

            // Model name
            if let metadata = viewModel.activeModelMetadata {
                Text(metadata.name)
                    .font(AppTypography.sectionHeader)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            } else if viewModel.isLoadingModel {
                Text("Loading…")
                    .font(AppTypography.sectionHeader)
                    .foregroundStyle(AppColors.textSecondary)
            }

            // Backend badge
            if let result = viewModel.backendResult, viewModel.isEngineReady {
                Text(result.activeBackend == .gpu ? "GPU" : "CPU")
                    .font(AppTypography.badge)
                    .foregroundStyle(result.activeBackend == .gpu ? AppColors.success : AppColors.warning)
                    .padding(.horizontal, AppSpacing.xs)
                    .padding(.vertical, AppSpacing.xxs)
                    .background(
                        (result.activeBackend == .gpu ? AppColors.success : AppColors.warning).opacity(AppOpacity.fill)
                    )
                    .clipShape(Capsule())
            }

            Spacer()

            // Decode speed
            if let metrics = viewModel.performanceMetrics {
                let tier = PerformanceTier(decodeSpeed: metrics.tokensPerSecond)
                Text(String(format: "%.1f tok/s", metrics.tokensPerSecond))
                    .font(AppTypography.metric)
                    .foregroundStyle(tier.color)
            }

            // Thermal indicator
            if let metrics = viewModel.inferenceMetrics,
               metrics.endSnapshot.thermalLevel != .nominal {
                let thermal = metrics.endSnapshot.thermalLevel
                Image(systemName: thermal.symbolName)
                    .font(AppIconSize.xxs)
                    .foregroundStyle(AppColors.thermal(thermal))
                    .accessibilityIdentifier("statusIndicator_thermal")
            }

            // Expand/collapse chevron
            Image(systemName: "chevron.up")
                .font(AppIconSize.xxs)
                .foregroundStyle(AppColors.textTertiary)
                .rotationEffect(.degrees(isExpanded ? 0 : 180))
                .accessibilityHidden(true)
        }
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(spacing: AppSpacing.sm) {
            Divider()
                .overlay(AppColors.border)
                .padding(.vertical, AppSpacing.xs)

            if let metrics = viewModel.performanceMetrics {
                // Metrics grid
                HStack(spacing: AppSpacing.lg) {
                    expandedMetric(label: "Decode", value: String(format: "%.1f", metrics.tokensPerSecond), unit: "tok/s")
                    expandedMetric(label: "Prefill", value: String(format: "%.1f", metrics.promptTokensPerSecond ?? 0), unit: "tok/s")
                    expandedMetric(label: "TTFT", value: String(format: "%.2f", metrics.timeToFirstToken ?? 0), unit: "s")
                    if let initTime = metrics.initTimeSeconds {
                        expandedMetric(label: "Init", value: String(format: "%.2f", initTime), unit: "s")
                    }
                }
            }

            // Device metrics
            if let metrics = viewModel.inferenceMetrics {
                HStack(spacing: AppSpacing.lg) {
                    expandedMetric(
                        label: "Memory",
                        value: DeviceMetrics.formattedAvailableMemory,
                        unit: ""
                    )
                    expandedMetric(
                        label: "Thermal",
                        value: metrics.endSnapshot.thermalLevel.label,
                        unit: ""
                    )
                }
            }

            // Capability badges
            if let metadata = viewModel.activeModelMetadata {
                HStack(spacing: AppSpacing.xs) {
                    if metadata.supportsImage {
                        Text("Vision").badge(AppColors.capabilityVision)
                    }
                    if metadata.supportsAudio {
                        Text("Audio").badge(AppColors.capabilityAudio)
                    }
                    if metadata.supportsMTP {
                        Text("Spec. Dec").badge(AppColors.capabilityMTP)
                    }
                    if metadata.supportsToolCalling {
                        Text("Tools").badge(AppColors.toolAction)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Helpers

    private func expandedMetric(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(label)
                .font(AppTypography.badge)
                .foregroundStyle(AppColors.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xxs) {
                Text(value)
                    .font(AppTypography.metric)
                    .foregroundStyle(AppColors.textPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
    }


}
#endif
