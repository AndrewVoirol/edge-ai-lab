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

// MARK: - Detail Column View

/// Middle column of the three-column `NavigationSplitView`.
///
/// Switches content based on the selected sidebar section:
/// - **Models** (or nil) → `ModelDetailPanel` showing the selected model's info or an empty state.
/// - **Benchmarks** → The existing `PerformanceDashboardView` embedded directly.
/// - **Experiments** → A placeholder prompting the user to start an experiment.
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
            case .evaluations:
                EvalRunnerView()
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

    /// Resolved metadata for the selected model ID — checks the registry first,
    /// then falls back to discovered models (which synthesize metadata from
    /// filename heuristics for user-imported GGUF/community models).
    private var selectedMetadata: ModelMetadata? {
        guard let modelId = selectedModelId else { return nil }
        if let registryMatch = ModelRegistry.lookup(filename: modelId) {
            return registryMatch
        }
        // Use resolvedMetadata which always returns non-nil (synthesizes if needed)
        return viewModel.discoveredModels
            .first { $0.filename == modelId }?
            .resolvedMetadata
    }

    /// Whether the currently active model matches the selected model.
    /// Checks metadata identity first, then falls back to URL comparison
    /// for community models where metadata instances may differ.
    private var isActiveModel: Bool {
        guard let selected = selectedMetadata else { return false }
        // Primary check: metadata-based identity
        if let active = viewModel.activeModelMetadata,
           selected.modelFile == active.modelFile {
            return true
        }
        // Fallback: URL-based identity for community/imported models
        if let modelId = selectedModelId,
           let discoveredURL = viewModel.discoveredModels.first(where: { $0.filename == modelId })?.url,
           discoveredURL == viewModel.activeModelURL {
            return true
        }
        return false
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
                    // Back to model list
                    Button {
                        selectedModelId = nil
                    } label: {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "chevron.left")
                            Text("Models")
                        }
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.accentPrimary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("modelDetail_backButton")

                    Text(metadata.name)
                        .font(AppTypography.pageTitle)
                        .foregroundStyle(AppColors.textPrimary)
                        .accessibilityIdentifier("modelDetail_name")

                    Text(metadata.description)
                        .font(AppTypography.listSubtitle)
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

                    // Load / Unload button
                    if isActiveModel {
                        Button {
                            Task { await viewModel.shutdown() }
                        } label: {
                            HStack(spacing: AppSpacing.xs) {
                                Image(systemName: "eject.fill")
                                Text("Unload Model")
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(AppColors.warning)
                        .accessibilityIdentifier("modelDetail_unloadButton")
                    } else if let modelId = selectedModelId,
                              let discovered = viewModel.discoveredModels.first(where: { $0.filename == modelId }) {
                        Button {
                            Task {
                                await viewModel.handleModelSelection(discovered.url)
                            }
                        } label: {
                            HStack(spacing: AppSpacing.xs) {
                                Image(systemName: "arrow.up.circle.fill")
                                Text("Load Model")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppColors.accentPrimary)
                        .accessibilityIdentifier("modelDetail_loadButton")
                    }
                }

                // MARK: Capability Badges
                ModelCapabilityBadges(
                    metadata: metadata,
                    runtimeFlags: viewModel.runtimeFlags
                )
                .accessibilityIdentifier("modelDetail_badges")

                // MARK: Stats Grid
                statsGrid(for: metadata)

                // MARK: Backend Info
                backendInfoCard(for: metadata)

                // MARK: Benchmark Summary
                if isActiveModel, let metrics = viewModel.performanceMetrics {
                    BenchmarkSummaryCard(metrics: metrics)
                }

                // MARK: One-Tap Benchmark
                if isActiveModel {
                    OneTapBenchmarkSection(viewModel: viewModel)
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
                    color: AppColors.accentSecondary
                )

                // Min RAM
                statCell(
                    label: "Min RAM",
                    value: "\(metadata.minDeviceMemoryGB) GB",
                    icon: "memorychip",
                    color: AppColors.accentPrimary
                )

                // Context Window
                statCell(
                    label: "Context",
                    value: formatTokenCount(metadata.contextWindowSize),
                    icon: "text.alignleft",
                    color: AppColors.accentPrimary
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
                .font(AppIconSize.lg)
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
        .glassEffect(in: .rect(cornerRadius: AppRadius.md))
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
                        .font(AppTypography.subtitle)
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
                                .badge(AppColors.accentPrimary)
                        }
                        if capability.supportsCPU {
                            Text("CPU")
                                .badge(AppColors.accentPrimary)
                        }
                    }
                }

                // Recommended for
                VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                    Text("Recommended For")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                    Text(metadata.recommendedFor)
                        .font(AppTypography.badge)
                        .foregroundStyle(AppColors.accentSecondary)
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
                        .font(AppIconSize.hero)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppColors.accentPrimary, AppColors.accentPrimary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .accessibilityIdentifier("modelDetail_emptyIcon")

                    Text("Welcome to Edge AI Lab")
                        .font(AppTypography.pageTitle)
                        .foregroundStyle(AppColors.textPrimary)

                    Text("A research instrument for running Gemma models entirely on-device.\nNo cloud. No API keys. Full control.")
                        .font(AppTypography.listSubtitle)
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
                            iconColor: AppColors.accentPrimary,
                            title: "Browse Models",
                            subtitle: "Download Gemma models from HuggingFace below"
                        )

                        // Card 2: Load from disk
                        gettingStartedCard(
                            icon: "folder",
                            iconColor: AppColors.accentSecondary,
                            title: "Load from Disk",
                            subtitle: "Open a .litertlm file (⌘O)"
                        )

                        // Card 3: Drag & Drop
                        gettingStartedCard(
                            icon: "arrow.down.doc",
                            iconColor: AppColors.accentPrimary,
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
                        featureHighlight(icon: "gauge.open.with.lines.needle.67percent.and.arrowtriangle", title: "Benchmark", subtitle: "Real-time tok/s, TTFT, memory", iconColor: AppColors.accentSecondary)
                        featureHighlight(icon: "brain.head.profile", title: "Thinking Mode", subtitle: "See the model reason step-by-step", iconColor: AppColors.capabilityThinking)
                        featureHighlight(icon: "wrench.and.screwdriver", title: "Tool Calling", subtitle: "Calculator, device info, and more", iconColor: AppColors.toolAction)
                        featureHighlight(icon: "photo.on.rectangle", title: "Multimodal", subtitle: "Images and audio with vision models", iconColor: AppColors.capabilityVision)
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
                .font(AppIconSize.xl)
                .foregroundStyle(iconColor)

            Text(title)
                .font(AppTypography.cardTitle)
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
        iconColor: Color = AppColors.accentPrimary
    ) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(AppIconSize.md)
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(title)
                    .font(AppTypography.sectionHeader)
                    .foregroundStyle(AppColors.textPrimary)
                Text(subtitle)
                    .font(AppTypography.caption)
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
        ModelDetailFormatters.formatTokenCount(count)
    }
}

// BenchmarkSummaryCard has been extracted to Sources/Benchmarking/BenchmarkSummaryCard.swift
// with full EnginePerformanceMetrics + InferenceMetrics support.


// MARK: - Experiment Detail Placeholder

/// Placeholder view shown when the Experiments section is selected in the sidebar.
/// Prompts the user to start or select an experiment.
private struct ConversationDetailPlaceholder: View {
    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(AppIconSize.hero)
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.accentSecondary, AppColors.accentSecondary.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .accessibilityIdentifier("conversationPlaceholder_icon")

            Text("Select an experiment")
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.textSecondary)

            Text("Start a new experiment or pick one from the sidebar")
                .font(AppTypography.subtitle)
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
                        .font(AppIconSize.lg)
                        .foregroundStyle(AppColors.accentSecondary)
                    VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                        Text(activeEntry?.title ?? "Archived Experiment")
                            .font(AppTypography.sectionTitle)
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
                            .font(AppTypography.subtitle)
                    }
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(AppSpacing.md)
                    .background(AppColors.accentPrimary.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md)
                            .stroke(AppColors.accentPrimary.opacity(0.4), lineWidth: AppLineWidth.regular)
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
                .font(AppTypography.metric)
                .foregroundStyle(AppColors.accentPrimary)
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

// CommunityModelsBrowser has been extracted to Sources/Views/CommunityModelsBrowser.swift
// for reusability across macOS detail column and future iOS community browser.




// MARK: - Previews

#Preview("Detail — No Selection") {
    DetailColumnView(
        selectedSection: .constant(nil),
        selectedModelId: .constant(nil)
    )
}

#Preview("Detail — Models Section") {
    DetailColumnView(
        selectedSection: .constant(.models),
        selectedModelId: .constant("gemma-4-E2B-it.litertlm")
    )
}

#Preview("Detail — Benchmarks") {
    DetailColumnView(
        selectedSection: .constant(.benchmarks),
        selectedModelId: .constant(nil)
    )
}

#Preview("Detail — Conversations") {
    DetailColumnView(
        selectedSection: .constant(.conversations),
        selectedModelId: .constant(nil)
    )
}

