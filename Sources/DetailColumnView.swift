import SwiftUI
import LiteRTLM

// MARK: - Detail Column View

/// Middle column of the three-column `NavigationSplitView`.
///
/// Switches content based on the selected sidebar section:
/// - **Models** (or nil) → `ModelDetailPanel` showing the selected model's info or an empty state.
/// - **Benchmarks** → The existing `PerformanceDashboardView` embedded directly.
/// - **Conversations** → A placeholder prompting the user to start a conversation.
///
/// Accessibility: Every interactive element has `.accessibilityIdentifier`
/// for agent discoverability and UI testing.
struct DetailColumnView: View {
    @Bindable private var viewModel = ConversationViewModel.shared
    @Binding var selectedSection: SidebarSection?
    @Binding var selectedModelId: String?

    var body: some View {
        Group {
            switch selectedSection {
            case nil, .models:
                ModelDetailPanel(
                    viewModel: viewModel,
                    selectedModelId: $selectedModelId
                )
            case .benchmarks:
                PerformanceDashboardView()
            case .conversations:
                ConversationDetailPlaceholder()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.backgroundPrimary)
        .accessibilityIdentifier("detailColumn_root")
    }
}

// MARK: - Model Detail Panel

/// Shows detailed model information when a model is selected from the sidebar,
/// or an empty state when no model is selected.
///
/// Layout:
/// - Model name (large, cream text)
/// - Capability badges (Vision, Audio, MTP, etc.)
/// - Stats grid: file size, min RAM, context window
/// - Backend info (GPU/CPU)
/// - "Loaded" status with green indicator
/// - Benchmark summary card (last inference metrics)
private struct ModelDetailPanel: View {
    @Bindable var viewModel: ConversationViewModel
    @Binding var selectedModelId: String?

    /// Resolved metadata for the selected model ID from the known registry.
    private var selectedMetadata: ModelMetadata? {
        guard let modelId = selectedModelId else { return nil }
        return ModelRegistry.lookup(filename: modelId)
    }

    /// Whether the currently active model matches the selected model.
    private var isActiveModel: Bool {
        guard let selected = selectedMetadata,
              let active = viewModel.activeModelMetadata else {
            return false
        }
        return selected.modelFile == active.modelFile
    }

    var body: some View {
        Group {
            if let metadata = selectedMetadata {
                modelDetailContent(metadata)
            } else {
                emptyState
            }
        }
        .accessibilityIdentifier("modelDetailPanel_root")
    }

    // MARK: - Model Detail Content

    @ViewBuilder
    private func modelDetailContent(_ metadata: ModelMetadata) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                // MARK: Header — Name + Status
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text(metadata.name)
                        .font(.system(.title2, design: .default, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                        .accessibilityIdentifier("modelDetail_name")

                    Text(metadata.description)
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("modelDetail_description")

                    // Status indicator
                    if isActiveModel {
                        HStack(spacing: AppSpacing.xs) {
                            Circle()
                                .fill(AppColors.success)
                                .frame(width: 8, height: 8)
                                .glow(AppColors.success, radius: 6, opacity: 0.5)
                            Text("Loaded")
                                .font(AppTypography.badge)
                                .foregroundStyle(AppColors.success)
                        }
                        .accessibilityIdentifier("modelDetail_status_loaded")
                    } else {
                        HStack(spacing: AppSpacing.xs) {
                            Circle()
                                .fill(AppColors.textTertiary.opacity(0.4))
                                .frame(width: 8, height: 8)
                            Text("Not Loaded")
                                .font(AppTypography.badge)
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        .accessibilityIdentifier("modelDetail_status_notLoaded")
                    }
                }

                // MARK: Capability Badges
                ModelCapabilityBadges(
                    metadata: metadata,
                    experimentalFlags: viewModel.experimentalFlags
                )
                .accessibilityIdentifier("modelDetail_badges")

                // MARK: Stats Grid
                statsGrid(for: metadata)

                // MARK: Backend Info
                backendInfoCard(for: metadata)

                // MARK: Benchmark Summary
                if isActiveModel, let benchmarkInfo = viewModel.benchmarkInfo {
                    BenchmarkSummaryCard(benchmarkInfo: benchmarkInfo)
                }

                Spacer(minLength: AppSpacing.xl)
            }
            .padding(AppSpacing.lg)
        }
    }

    // MARK: - Stats Grid

    private func statsGrid(for metadata: ModelMetadata) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Specifications")
                .font(AppTypography.sectionHeader)
                .foregroundStyle(AppColors.textSecondary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: AppSpacing.md) {
                // File Size
                statCell(
                    label: "File Size",
                    value: ByteCountFormatter.string(
                        fromByteCount: metadata.sizeInBytes,
                        countStyle: .file
                    ),
                    icon: "doc.zipper",
                    color: AppColors.accentGold
                )

                // Min RAM
                statCell(
                    label: "Min RAM",
                    value: "\(metadata.minDeviceMemoryGB) GB",
                    icon: "memorychip",
                    color: AppColors.accentTeal
                )

                // Context Window
                statCell(
                    label: "Context",
                    value: formatTokenCount(metadata.contextWindowSize),
                    icon: "text.alignleft",
                    color: AppColors.accentCyan
                )
            }
        }
    }

    /// Compact stat cell for the specs grid.
    private func statCell(
        label: String,
        value: String,
        icon: String,
        color: Color
    ) -> some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(AppTypography.metric)
                .foregroundStyle(AppColors.textPrimary)

            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.md)
        .glassCard(cornerRadius: AppRadius.md)
        .accessibilityIdentifier("modelDetail_stat_\(label)")
    }

    // MARK: - Backend Info Card

    private func backendInfoCard(for metadata: ModelMetadata) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Backend")
                .font(AppTypography.sectionHeader)
                .foregroundStyle(AppColors.textSecondary)

            HStack(spacing: AppSpacing.lg) {
                // Architecture
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Architecture")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                    Text(metadata.architectureType)
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                }

                Spacer()

                // Platform capability
                VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                    Text("Current Platform")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)

                    HStack(spacing: AppSpacing.xs) {
                        let capability = metadata.platformSupport.currentPlatform
                        if capability.supportsGPU {
                            Text("GPU")
                                .badge(AppColors.accentCyan)
                        }
                        if capability.supportsCPU {
                            Text("CPU")
                                .badge(AppColors.accentTeal)
                        }
                    }
                }

                // Recommended for
                VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                    Text("Recommended For")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                    Text(metadata.recommendedFor)
                        .font(.system(.caption, weight: .medium))
                        .foregroundStyle(AppColors.accentGold)
                }
            }
            .padding(AppSpacing.md)
            .glassCard(cornerRadius: AppRadius.md)
        }
        .accessibilityIdentifier("modelDetail_backendInfo")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "tree")
                .font(.system(size: 56))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.accentTeal, AppColors.accentCyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .accessibilityIdentifier("modelDetail_emptyIcon")

            Text("Select a model from the sidebar")
                .font(.system(.title3, design: .default, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)

            Text("View model specifications, capabilities, and benchmark results")
                .font(.subheadline)
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("modelDetail_emptyState")
    }

    // MARK: - Helpers

    /// Formats large token counts for display (e.g., 128000 → "128K").
    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.0fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.0fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

// MARK: - Benchmark Summary Card

/// Compact benchmark metrics card showing the last inference run's performance.
///
/// Displays:
/// - Decode speed (large metric font) with `PerformanceTier` coloring
/// - Time to first token (TTFT)
/// - Total decode tokens generated
private struct BenchmarkSummaryCard: View {
    let benchmarkInfo: BenchmarkInfo

    private var decodeTier: PerformanceTier {
        PerformanceTier(decodeSpeed: benchmarkInfo.lastDecodeTokensPerSecond)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Section header
            HStack {
                Text("Last Inference")
                    .font(AppTypography.sectionHeader)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Text(decodeTier.label)
                    .badge(decodeTier.color)
            }

            // Metrics grid
            HStack(spacing: AppSpacing.md) {
                // Decode Speed — hero metric
                VStack(spacing: AppSpacing.xs) {
                    Text(String(format: "%.1f", benchmarkInfo.lastDecodeTokensPerSecond))
                        .font(AppTypography.metricLarge)
                        .foregroundStyle(decodeTier.color)
                        .contentTransition(.numericText())
                    Text("tok/s")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
                .frame(maxWidth: .infinity)

                // Divider
                Rectangle()
                    .fill(AppColors.border)
                    .frame(width: 0.5, height: 40)

                // TTFT
                VStack(spacing: AppSpacing.xs) {
                    Text(String(format: "%.3f", benchmarkInfo.timeToFirstTokenInSecond))
                        .font(AppTypography.metric)
                        .foregroundStyle(AppColors.accentTeal)
                    Text("TTFT (s)")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
                .frame(maxWidth: .infinity)

                // Divider
                Rectangle()
                    .fill(AppColors.border)
                    .frame(width: 0.5, height: 40)

                // Tokens generated
                VStack(spacing: AppSpacing.xs) {
                    Text("\(benchmarkInfo.lastDecodeTokenCount)")
                        .font(AppTypography.metric)
                        .foregroundStyle(AppColors.accentGold)
                    Text("Tokens")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(AppSpacing.md)
            .glassCard(cornerRadius: AppRadius.md)
        }
        .accessibilityIdentifier("benchmarkSummary_card")
    }
}

// MARK: - Conversation Detail Placeholder

/// Placeholder view shown when the Conversations section is selected in the sidebar.
/// Prompts the user to start or select a conversation.
private struct ConversationDetailPlaceholder: View {
    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.accentGold, AppColors.accentGold.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .accessibilityIdentifier("conversationPlaceholder_icon")

            Text("Select a conversation")
                .font(.system(.title3, design: .default, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)

            Text("Start a new chat or pick one from the sidebar")
                .font(.subheadline)
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("conversationPlaceholder_root")
    }
}

// MARK: - Previews

#Preview("Detail — No Selection") {
    DetailColumnView(
        selectedSection: .constant(nil),
        selectedModelId: .constant(nil)
    )
    .preferredColorScheme(.dark)
}

#Preview("Detail — Models Section") {
    DetailColumnView(
        selectedSection: .constant(.models),
        selectedModelId: .constant("gemma-4-E2B-it.litertlm")
    )
    .preferredColorScheme(.dark)
}

#Preview("Detail — Benchmarks") {
    DetailColumnView(
        selectedSection: .constant(.benchmarks),
        selectedModelId: .constant(nil)
    )
    .preferredColorScheme(.dark)
}

#Preview("Detail — Conversations") {
    DetailColumnView(
        selectedSection: .constant(.conversations),
        selectedModelId: .constant(nil)
    )
    .preferredColorScheme(.dark)
}
