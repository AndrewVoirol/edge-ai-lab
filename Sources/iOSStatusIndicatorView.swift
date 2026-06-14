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
import LiteRTLM
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
    @State private var isExpanded = false

    var body: some View {
        if viewModel.isEngineReady || viewModel.isLoadingModel {
            VStack(spacing: 0) {
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
                    VStack(spacing: 0) {
                        // Collapsed: Single row
                        collapsedRow

                        // Expanded: Detail metrics
                        if isExpanded {
                            expandedContent
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.sm)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: isExpanded)
                .accessibilityIdentifier("statusIndicator")
            }
            .background(
                AppColors.backgroundSecondary.opacity(0.7)
                    .background(.ultraThinMaterial)
            )
        }
    }

    // MARK: - Collapsed Row

    private var collapsedRow: some View {
        HStack(spacing: AppSpacing.sm) {
            // Status dot
            if viewModel.isLoadingModel {
                ProgressView()
                    .controlSize(.mini)
                    .tint(AppColors.accentCyan)
            } else {
                Circle()
                    .fill(AppColors.success)
                    .frame(width: 6, height: 6)
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
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        (result.activeBackend == .gpu ? AppColors.success : AppColors.warning).opacity(0.12)
                    )
                    .clipShape(Capsule())
            }

            Spacer()

            // Decode speed
            if let info = viewModel.benchmarkInfo {
                let tier = PerformanceTier(decodeSpeed: info.lastDecodeTokensPerSecond)
                Text(String(format: "%.1f tok/s", info.lastDecodeTokensPerSecond))
                    .font(AppTypography.metric)
                    .foregroundStyle(tier.color)
            }

            // Thermal indicator
            if let metrics = viewModel.inferenceMetrics,
               metrics.endSnapshot.thermalLevel != .nominal {
                let thermal = metrics.endSnapshot.thermalLevel
                Image(systemName: thermal.symbolName)
                    .font(.caption2)
                    .foregroundStyle(thermalColor(for: thermal))
                    .accessibilityIdentifier("statusIndicator_thermal")
            }

            // Expand/collapse chevron
            Image(systemName: "chevron.up")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppColors.textTertiary)
                .rotationEffect(.degrees(isExpanded ? 0 : 180))
        }
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(spacing: AppSpacing.sm) {
            Divider()
                .overlay(AppColors.border)
                .padding(.vertical, AppSpacing.xs)

            if let info = viewModel.benchmarkInfo {
                // Metrics grid
                HStack(spacing: AppSpacing.lg) {
                    expandedMetric(label: "Decode", value: String(format: "%.1f", info.lastDecodeTokensPerSecond), unit: "tok/s")
                    expandedMetric(label: "Prefill", value: String(format: "%.1f", info.lastPrefillTokensPerSecond), unit: "tok/s")
                    expandedMetric(label: "TTFT", value: String(format: "%.2f", info.timeToFirstTokenInSecond), unit: "s")
                    expandedMetric(label: "Init", value: String(format: "%.2f", info.initTimeInSecond), unit: "s")
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
                        Text("Vision").badge(AppColors.badgeVision)
                    }
                    if metadata.supportsAudio {
                        Text("Audio").badge(AppColors.badgeAudio)
                    }
                    if metadata.supportsMTP {
                        Text("MTP").badge(AppColors.badgeMTP)
                    }
                    if metadata.supportsToolCalling {
                        Text("Tools").badge(AppColors.toolCall)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Helpers

    private func expandedMetric(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(AppTypography.badge)
                .foregroundStyle(AppColors.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
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

    private func thermalColor(for state: ThermalLevel) -> Color {
        switch state {
        case .nominal: return AppColors.success
        case .fair: return AppColors.warning
        case .serious: return AppColors.danger
        case .critical: return AppColors.danger
        }
    }
}
#endif
