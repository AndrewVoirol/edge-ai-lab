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
    @Environment(ConversationViewModel.self) private var viewModel
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
            case .benchmarkComparison:
                BenchmarkComparisonView()
            case .conversations:
                if viewModel.isViewingArchivedConversation {
                    ExperimentDetailView()
                } else {
                    ConversationDetailPlaceholder()
                }
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
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                // Welcome header
                VStack(spacing: AppSpacing.md) {
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

                    Text("Welcome to Edge AI Lab")
                        .font(.system(.title2, design: .default, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)

                    Text("A research instrument for running Gemma models entirely on-device.\nNo cloud. No API keys. Full control.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.xxl)
                }
                .padding(.top, AppSpacing.xl)

                // Getting Started cards
                VStack(spacing: AppSpacing.md) {
                    Text("Get Started")
                        .font(AppTypography.sectionHeader)
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: AppSpacing.md) {
                        // Card 1: Browse community models
                        gettingStartedCard(
                            icon: "arrow.down.circle",
                            iconColor: AppColors.accentCyan,
                            title: "Browse Models",
                            subtitle: "Download Gemma models from HuggingFace below"
                        )

                        // Card 2: Load from disk
                        gettingStartedCard(
                            icon: "folder",
                            iconColor: AppColors.accentGold,
                            title: "Load from Disk",
                            subtitle: "Open a .litertlm file (⌘O)"
                        )

                        // Card 3: Drag & Drop
                        gettingStartedCard(
                            icon: "arrow.down.doc",
                            iconColor: AppColors.accentTeal,
                            title: "Drag & Drop",
                            subtitle: "Drop a .litertlm file onto the window"
                        )
                    }
                }
                .padding(.horizontal, AppSpacing.lg)

                // Feature highlights
                VStack(spacing: AppSpacing.md) {
                    Text("What You Can Do")
                        .font(AppTypography.sectionHeader)
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.sm) {
                        featureHighlight(icon: "gauge.open.with.lines.needle.67percent.and.arrowtriangle", title: "Benchmark", subtitle: "Real-time tok/s, TTFT, memory", iconColor: AppColors.accentGold)
                        featureHighlight(icon: "brain.head.profile", title: "Thinking Mode", subtitle: "See the model reason step-by-step", iconColor: AppColors.badgeThinking)
                        featureHighlight(icon: "wrench.and.screwdriver", title: "Tool Calling", subtitle: "Calculator, device info, and more", iconColor: AppColors.toolCall)
                        featureHighlight(icon: "photo.on.rectangle", title: "Multimodal", subtitle: "Images and audio with vision models", iconColor: AppColors.badgeVision)
                    }
                }
                .padding(.horizontal, AppSpacing.lg)

                // Community Models Browser
                CommunityModelsBrowser()
                    .padding(.horizontal, AppSpacing.lg)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("modelDetail_emptyState")
    }

    /// A card for the Getting Started section.
    private func gettingStartedCard(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String
    ) -> some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(iconColor)

            Text(title)
                .font(.system(.callout, design: .default, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            Text(subtitle)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.md)
        .glassCard(cornerRadius: AppRadius.lg)
    }

    /// A compact feature highlight chip.
    private func featureHighlight(
        icon: String,
        title: String,
        subtitle: String,
        iconColor: Color = AppColors.accentCyan
    ) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text(subtitle)
                    .font(.system(.caption2))
                    .foregroundStyle(AppColors.textTertiary)
            }
            Spacer()
        }
        .padding(AppSpacing.sm)
        .glassCard(cornerRadius: AppRadius.md)
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

// MARK: - Experiment Detail View

/// Shows the frozen experiment configuration and summary when viewing an archived conversation.
///
/// Displays:
/// - Experiment config card (model, backend, sampler, flags)
/// - Benchmark summary (avg speed, total tokens, message count)
/// - Fork Experiment button
private struct ExperimentDetailView: View {
    @Environment(ConversationViewModel.self) private var viewModel

    /// The active conversation's index entry for display metadata.
    private var activeEntry: ConversationIndexEntry? {
        guard let id = viewModel.activeConversationId else { return nil }
        return viewModel.conversationStore.indexEntries.first(where: { $0.id == id })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                // Header
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "archivebox.fill")
                        .font(.title2)
                        .foregroundStyle(AppColors.accentGold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activeEntry?.title ?? "Archived Experiment")
                            .font(.system(.title3, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        if let entry = activeEntry {
                            Text("Created \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                    Spacer()
                }

                // Config card
                configCard

                // Benchmark summary
                if let entry = activeEntry {
                    benchmarkCard(entry)
                }

                // Fork button
                Button {
                    if let id = viewModel.activeConversationId {
                        viewModel.forkConversation(id: id)
                    }
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "arrow.triangle.branch")
                        Text("Fork Experiment")
                            .font(.system(.body, weight: .semibold))
                    }
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(AppSpacing.md)
                    .background(AppColors.accentTeal.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md)
                            .stroke(AppColors.accentTeal.opacity(0.4), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("button_forkExperiment")
            }
            .padding(AppSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("experimentDetailView")
    }

    // MARK: - Config Card

    @ViewBuilder
    private var configCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Experiment Configuration")
                .font(AppTypography.sectionHeader)
                .foregroundStyle(AppColors.textSecondary)

            if let entry = activeEntry {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.sm) {
                    configRow("Model", entry.modelShortName)
                    configRow("Messages", "\(entry.messageCount)")

                    // Feature flags
                    ForEach(entry.activeFeatureBadges, id: \.self) { badge in
                        configRow("Feature", badge)
                    }
                }
            }
        }
        .padding(AppSpacing.md)
        .glassCard(cornerRadius: AppRadius.lg)
    }

    @ViewBuilder
    private func configRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced, weight: .medium))
                .foregroundStyle(AppColors.accentCyan)
        }
        .padding(.vertical, AppSpacing.xs)
    }

    // MARK: - Benchmark Card

    @ViewBuilder
    private func benchmarkCard(_ entry: ConversationIndexEntry) -> some View {
        if let speed = entry.averageDecodeSpeed, speed > 0 {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("Performance Summary")
                    .font(AppTypography.sectionHeader)
                    .foregroundStyle(AppColors.textSecondary)

                HStack(spacing: AppSpacing.xl) {
                    VStack(spacing: AppSpacing.xs) {
                        Text(String(format: "%.1f", speed))
                            .font(AppTypography.metricLarge)
                            .foregroundStyle(PerformanceTier(decodeSpeed: speed).color)
                        Text("tok/s avg")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)
                    }

                    if entry.totalTokens > 0 {
                        VStack(spacing: AppSpacing.xs) {
                            Text("\(entry.totalTokens)")
                                .font(AppTypography.metricLarge)
                                .foregroundStyle(AppColors.textPrimary)
                            Text("tokens")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }

                    VStack(spacing: AppSpacing.xs) {
                        Text("\(entry.messageCount)")
                            .font(AppTypography.metricLarge)
                            .foregroundStyle(AppColors.textPrimary)
                        Text("messages")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
            }
            .padding(AppSpacing.md)
            .glassCard(cornerRadius: AppRadius.lg)
        }
    }
}

// MARK: - Community Models Browser


/// Browseable grid of HuggingFace community models using `HFModelBrowser` API.
///
/// Shows a loading state while fetching, an error state on failure,
/// or a grid of `HFModelCard` views on success.
private struct CommunityModelsBrowser: View {
    @State private var browser = HFModelBrowser()
    @Environment(ConversationViewModel.self) private var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Section header
            HStack {
                Image(systemName: "globe")
                    .foregroundStyle(AppColors.accentTeal)
                Text("Community Models")
                    .font(AppTypography.sectionHeader)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()

                if browser.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AppColors.accentTeal)
                }

                Button {
                    Task { await browser.refreshGemmaModels() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Refresh community models")
                .accessibilityIdentifier("button_refreshCommunityModels")
            }

            // Content
            if let error = browser.lastError {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(AppColors.warning)
                    Text(error)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(2)
                }
                .padding(AppSpacing.md)
                .glassCard(cornerRadius: AppRadius.md)
            } else if browser.discoveredModels.isEmpty && !browser.isLoading {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppColors.textTertiary)
                    Text("No models found. Tap refresh to search HuggingFace.")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
                .padding(AppSpacing.md)
            } else {
                // URL paste placeholder (Coming Soon)
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "link.badge.plus")
                        .foregroundStyle(AppColors.textTertiary)
                    Text("Paste a HuggingFace URL to import any model")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                    Spacer()
                    Text("Coming Soon")
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(AppColors.accentGold)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, 2)
                        .background(AppColors.accentGold.opacity(0.12))
                        .clipShape(Capsule())
                }
                .padding(AppSpacing.md)
                .glassCard(cornerRadius: AppRadius.md)
                .opacity(0.6)
                .accessibilityIdentifier("urlPaste_comingSoon")

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.md) {
                    ForEach(browser.discoveredModels) { model in
                        let format = browser.detectFormat(model)
                        let modelSize = browser.modelSize(model)
                        HFModelCard(
                            model: model,
                            format: format,
                            modelSize: modelSize,
                            downloadManager: viewModel.downloadManager,
                            onLoadModel: { filename, url in
                                Task {
                                    await viewModel.handleModelSelection(url)
                                    viewModel.refreshDiscoveredModels()
                                }
                            }
                        )
                    }
                }
            }
        }
        .task {
            if browser.discoveredModels.isEmpty && !browser.isLoading {
                await browser.refreshGemmaModels()
            }
        }
        .accessibilityIdentifier("communityModelsBrowser")
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

