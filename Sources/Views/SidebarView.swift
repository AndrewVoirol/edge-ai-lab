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
import UniformTypeIdentifiers

// MARK: - Sidebar Section

/// Navigation sections available in the sidebar.
///
/// Each case maps to a distinct detail view in the middle column
/// of a `NavigationSplitView`.
enum SidebarSection: String, Hashable, Identifiable {
    case models
    case benchmarks
    case benchmarkComparison
    case evaluations
    case conversations

    var id: String { rawValue }

    /// SF Symbol name for section icons.
    var systemImage: String {
        switch self {
        case .models:              return "cube.box"
        case .benchmarks:          return "chart.line.uptrend.xyaxis"
        case .benchmarkComparison: return "arrow.left.arrow.right"
        case .evaluations:         return "testtube.2"
        case .conversations:       return "bubble.left.and.bubble.right"
        }
    }

    /// Human-readable title.
    var title: String {
        switch self {
        case .models:              return "Models"
        case .benchmarks:          return "Benchmarks"
        case .benchmarkComparison: return "Compare Models"
        case .evaluations:         return "Evaluations"
        case .conversations:       return "Conversations"
        }
    }
}

// MARK: - Sidebar View

/// Vertical sidebar for `NavigationSplitView`, providing model management,
/// benchmark navigation, and conversation controls.
///
/// Layout:
/// - **Active Model** — always-visible status header (not selectable)
/// - **Models** — collapsible section with discovered + downloadable model rows
/// - **Benchmarks** — navigation links to dashboard and comparison
/// - **Conversations** — new-chat button and future history
///
/// Accessibility: Every interactive element has `.accessibilityIdentifier`
/// for agent discoverability and UI testing.
struct SidebarView: View {
    @Environment(ConversationViewModel.self) private var viewModel
    @Binding var selectedSection: SidebarSection?
    @Binding var selectedModelId: String?
    @Binding var showcaseModel: ModelMetadata?
    @Binding var showcaseModelURL: URL?

    /// Model pending delete confirmation.
    @State private var modelToDelete: DiscoveredModel?
    @State private var showDeleteConfirmation = false

    /// Downloadable model pending delete confirmation (sidebar download status).
    @State private var downloadableModelToDelete: ModelMetadata?
    @State private var showDownloadableDeleteConfirmation = false

    var body: some View {
        List(selection: $selectedSection) {
            // MARK: Active Model (non-selectable header)

            Section {
                activeModelRow
            } header: {
                Text("Active Model")
                    .font(AppTypography.sectionHeader)
                    .foregroundStyle(AppColors.textSecondary)
            }

            // MARK: Models (collapsible)

            Section(isExpanded: .constant(true)) {
                // On-disk discovered models
                ForEach(viewModel.discoveredModels) { model in
                    SidebarModelRow(
                        model: model,
                        isActive: viewModel.activeModelURL == model.url,
                        experimentalFlags: viewModel.experimentalFlags,
                        onDelete: model.source != .edgeGallery ? {
                            modelToDelete = model
                            showDeleteConfirmation = true
                        } : nil
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedSection = .models
                        Task {
                            await viewModel.handleModelSelection(model.url)
                        }
                    }
                    .contextMenu {
                        if let metadata = model.metadata {
                            Button {
                                showcaseModelURL = model.url
                                showcaseModel = metadata
                            } label: {
                                Label("Model Info", systemImage: "info.circle")
                            }
                            .accessibilityIdentifier("sidebar_context_info_\(model.filename)")

                            if model.source != .edgeGallery {
                                Button(role: .destructive) {
                                    modelToDelete = model
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete Model", systemImage: "trash")
                                }
                                .accessibilityIdentifier("sidebar_context_delete_\(model.filename)")
                            }
                        }
                    }
                    .accessibilityIdentifier("sidebar_model_\(model.filename)")
                    .accessibilityHint("Double-tap to load this model")
                }

                // Getting Started card — shown when no models are on disk
                if viewModel.discoveredModels.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "sparkles")
                                .font(.title3)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [AppColors.accentGold, AppColors.accentTeal],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            Text("Get Started")
                                .font(AppTypography.sectionHeader)
                                .foregroundStyle(AppColors.textPrimary)
                        }

                        Text("Models run entirely on your device.\nNo cloud. No API keys.")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)

                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text("Recommended first model:")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textTertiary)
                            HStack(spacing: AppSpacing.xs) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundStyle(AppColors.accentCyan)
                                Text("Gemma 4 E2B (~2.6 GB)")
                                    .font(AppTypography.subtitle)
                                    .foregroundStyle(AppColors.accentCyan)
                            }
                        }
                    }
                    .padding(AppSpacing.md)
                    .glassCard(cornerRadius: AppRadius.md)
                    .accessibilityIdentifier("sidebar_gettingStarted")
                }

                // Registry models not yet on disk (downloadable)
                ForEach(downloadableModels) { model in
                    downloadableModelRow(model)
                        .accessibilityIdentifier("sidebar_downloadable_\(model.modelFile)")
                }
            } header: {
                Label("Models", systemImage: SidebarSection.models.systemImage)
                    .font(AppTypography.sectionHeader)
                    .foregroundStyle(AppColors.textSecondary)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedSection = .models
                    }
            }

            // MARK: Benchmarks

            Section {
                NavigationLink(value: SidebarSection.benchmarks) {
                    Label("Dashboard", systemImage: "chart.bar.xaxis")
                }
                .accessibilityIdentifier("sidebar_benchmarks_dashboard")

                NavigationLink(value: SidebarSection.benchmarkComparison) {
                    Label("Compare Models", systemImage: "arrow.left.arrow.right")
                }
                .accessibilityIdentifier("sidebar_benchmarks_compare")
            } header: {
                Label("Benchmarks", systemImage: SidebarSection.benchmarks.systemImage)
                    .font(AppTypography.sectionHeader)
                    .foregroundStyle(AppColors.textSecondary)
            }

            // MARK: Evaluations

            Section {
                NavigationLink(value: SidebarSection.evaluations) {
                    Label("Run Evaluation", systemImage: "play.circle")
                }
                .accessibilityIdentifier("sidebar_evaluations_run")
            } header: {
                Label("Evaluations", systemImage: SidebarSection.evaluations.systemImage)
                    .font(AppTypography.sectionHeader)
                    .foregroundStyle(AppColors.textSecondary)
            }

            // MARK: Conversations

            Section {
                Button {
                    Task { await viewModel.newConversation() }
                } label: {
                    Label("New Chat", systemImage: "plus.bubble")
                }
                .accessibilityIdentifier("sidebar_newChat")

                if viewModel.conversationStore.indexEntries.isEmpty {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundStyle(AppColors.textTertiary.opacity(0.6))
                        Text("Conversations will appear here")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .accessibilityIdentifier("sidebar_conversations_emptyState")
                } else {
                    ForEach(viewModel.conversationStore.indexEntries) { entry in
                        conversationRow(entry)
                            .accessibilityIdentifier("sidebar_conversation_\(entry.id.uuidString.prefix(8))")
                            .accessibilityHint("Double-tap to open conversation")
                    }
                }
            } header: {
                HStack {
                    Label("Conversations", systemImage: SidebarSection.conversations.systemImage)
                        .font(AppTypography.sectionHeader)
                        .foregroundStyle(AppColors.textSecondary)
                    if !viewModel.conversationStore.indexEntries.isEmpty {
                        Spacer()
                        Text("\(viewModel.conversationStore.indexEntries.count)")
                            .font(AppTypography.badge)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
            }
        }
        #if os(macOS)
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(AppColors.backgroundPrimary)
        #endif
        .accessibilityIdentifier("sidebar_list")
        .alert("Delete Model?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                modelToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let model = modelToDelete {
                    if let metadata = model.metadata {
                        viewModel.downloadManager.deleteModel(metadata)
                    } else {
                        viewModel.downloadManager.deleteModel(filename: model.filename)
                    }
                    viewModel.refreshDiscoveredModels()
                    modelToDelete = nil
                }
            }
        } message: {
            if let model = modelToDelete {
                Text("\"\(model.metadata?.name ?? model.filename)\" will be permanently removed from disk. This cannot be undone.")
            }
        }
        .alert("Delete Model?", isPresented: $showDownloadableDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                downloadableModelToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let metadata = downloadableModelToDelete {
                    viewModel.downloadManager.deleteModel(metadata)
                    viewModel.refreshDiscoveredModels()
                    downloadableModelToDelete = nil
                }
            }
        } message: {
            if let metadata = downloadableModelToDelete {
                Text("\"\(metadata.name)\" will be permanently removed from disk. This cannot be undone.")
            }
        }
    }

    // MARK: - Active Model Row

    /// Non-selectable row displaying the currently loaded model's status.
    @ViewBuilder
    private var activeModelRow: some View {
        if viewModel.isLoadingModel {
            // Loading state
            HStack(spacing: AppSpacing.sm) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityIdentifier("sidebar_activeModel_spinner")
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.activeModelMetadata?.name ?? "Loading model…")
                        .font(AppTypography.subtitle)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    Text("Loading…")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.warning)
                }
            }
            .accessibilityIdentifier("sidebar_activeModel_loading")
            .accessibilityLabel("Loading model")
        } else if let metadata = viewModel.activeModelMetadata {
            // Model loaded
            HStack(spacing: AppSpacing.sm) {
                Circle()
                    .fill(AppColors.success)
                    .frame(width: 8, height: 8)
                    .glow(AppColors.success, radius: 6, opacity: 0.5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(metadata.name)
                        .font(AppTypography.subtitle)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    Text("Loaded")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.success)
                }
            }
            .accessibilityIdentifier("sidebar_activeModel_loaded")
            .accessibilityLabel("Active model: \(metadata.name), loaded")
        } else {
            // No model
            HStack(spacing: AppSpacing.sm) {
                Circle()
                    .fill(AppColors.textTertiary.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text("No model loaded")
                    .font(AppTypography.subtitle)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .accessibilityIdentifier("sidebar_activeModel_empty")
            .accessibilityLabel("No model loaded")
        }
    }

    // MARK: - Downloadable Models

    /// Registry models that are not yet discovered on disk.
    private var downloadableModels: [ModelMetadata] {
        let discoveredFilenames = Set(viewModel.discoveredModels.map(\.filename))
        return ModelRegistry.knownModels.filter { !discoveredFilenames.contains($0.modelFile) }
    }

    /// Row for a model that can be downloaded from HuggingFace.
    @ViewBuilder
    private func downloadableModelRow(_ model: ModelMetadata) -> some View {
        let state = viewModel.downloadManager.downloadStates[model.modelFile] ?? .notDownloaded

        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(model.name)
                .font(AppTypography.subtitle)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)

            ModelCapabilityBadges(
                metadata: model,
                experimentalFlags: viewModel.experimentalFlags
            )

            downloadStatusView(for: model, state: state)
        }
        .padding(.vertical, AppSpacing.xs)
    }

    /// Status indicator and action controls for each download state.
    @ViewBuilder
    private func downloadStatusView(
        for model: ModelMetadata,
        state: ModelDownloadManager.DownloadState
    ) -> some View {
        switch state {
        case .notDownloaded:
            Button {
                viewModel.downloadManager.download(model)
            } label: {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "arrow.down.circle")
                    Text(ByteCountFormatter.string(
                        fromByteCount: model.sizeInBytes,
                        countStyle: .file
                    ))
                    .font(AppTypography.caption)
                }
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.accentCyan)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sidebar_download_\(model.modelFile)")

        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 2) {
                ProgressView(value: progress)
                    .tint(AppColors.accentTeal)
                    .accessibilityLabel("Downloading, \(Int(progress * 100)) percent")
                HStack {
                    Text("\(Int(progress * 100))%")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                    Spacer()
                    Button {
                        Task { await viewModel.downloadManager.cancelDownload(model) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sidebar_cancelDownload_\(model.modelFile)")
                }
            }

        case .downloaded:
            HStack(spacing: AppSpacing.xs) {
                Circle()
                    .fill(AppColors.success)
                    .frame(width: 5, height: 5)
                    .accessibilityHidden(true)
                Text("Ready")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                Spacer()
                Button {
                    downloadableModelToDelete = model
                    showDownloadableDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.caption2)
                        .foregroundStyle(AppColors.danger)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar_deleteModel_\(model.modelFile)")
            }

        case .failed(let message):
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppColors.danger)
                    .font(.caption2)
                Text(message)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.danger)
                    .lineLimit(1)
            }

        case .authRequired:
            Button {
                viewModel.downloadManager.showTokenPrompt = true
                viewModel.downloadManager.pendingAuthModel = model
            } label: {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "lock.fill")
                    Text("Auth required")
                }
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.warning)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sidebar_auth_\(model.modelFile)")

        case .queued(let position):
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundStyle(AppColors.textTertiary)
                Text("Queued (#\(position))")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                Spacer()
                Button {
                    Task { await viewModel.downloadManager.cancelDownload(model) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar_cancelQueued_\(model.modelFile)")
            }

        case .paused(_, let progress):
            VStack(alignment: .leading, spacing: 2) {
                ProgressView(value: progress)
                    .tint(AppColors.warning)
                HStack {
                    Text("Paused · \(Int(progress * 100))%")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.warning)
                    Spacer()
                    Button {
                        viewModel.downloadManager.resumeDownload(model)
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(AppColors.accentCyan)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sidebar_resumeDownload_\(model.modelFile)")
                }
            }
        }
    }

    // MARK: - Conversation Row

    /// State for rename alert.
    @State private var renameTarget: ConversationIndexEntry?
    @State private var renameText: String = ""
    @State private var showRenameAlert: Bool = false

    /// Row for a saved conversation in the sidebar.
    @ViewBuilder
    private func conversationRow(_ entry: ConversationIndexEntry) -> some View {
        let isActive = viewModel.activeConversationId == entry.id

        Button {
            viewModel.loadConversation(id: entry.id)
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                // Title line
                HStack(spacing: AppSpacing.xs) {
                    Text(entry.title)
                        .font(isActive ? AppTypography.sectionHeader : AppTypography.subtitle)
                        .foregroundStyle(isActive ? AppColors.accentCyan : AppColors.textPrimary)
                        .lineLimit(2)

                    Spacer()

                    if entry.forkedFrom != nil {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption2)
                            .foregroundStyle(AppColors.accentTeal)
                    }
                }

                // Badges row: model tag + feature badges
                HStack(spacing: AppSpacing.xs) {
                    // Model badge
                    Text(entry.modelShortName)
                        .font(AppTypography.badge)
                        .foregroundStyle(AppColors.accentCyan)
                        .padding(.horizontal, AppSpacing.xs)
                        .padding(.vertical, 1)
                        .background(AppColors.accentCyan.opacity(0.1))
                        .clipShape(Capsule())

                    // Feature badges
                    ForEach(entry.activeFeatureBadges, id: \.self) { badge in
                        Text(badge)
                            .font(AppTypography.badge)
                            .foregroundStyle(AppColors.accentTeal)
                            .padding(.horizontal, AppSpacing.xs)
                            .padding(.vertical, 1)
                            .background(AppColors.accentTeal.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    // Relative timestamp
                    Text(relativeTimestamp(entry.lastModifiedAt))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }

                // Benchmark summary if available
                if let speed = entry.averageDecodeSpeed, speed > 0 {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "speedometer")
                            .font(.caption2)
                            .foregroundStyle(AppColors.textTertiary)
                        Text(String(format: "%.1f tok/s", speed))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)
                        Text("·")
                            .foregroundStyle(AppColors.textTertiary)
                        Text("\(entry.messageCount) msgs")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
            }
            .padding(.vertical, AppSpacing.xs)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.sm)
                .strokeBorder(isActive ? AppColors.accentCyan.opacity(0.4) : .clear, lineWidth: 1)
        )
        .contextMenu {
            Button {
                renameTarget = entry
                renameText = entry.title
                showRenameAlert = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button {
                viewModel.forkConversation(id: entry.id)
            } label: {
                Label("Fork Experiment", systemImage: "arrow.triangle.branch")
            }

            Button {
                exportConversation(entry.id)
            } label: {
                Label("Export JSON", systemImage: "square.and.arrow.up")
            }

            Divider()

            Button(role: .destructive) {
                viewModel.deleteConversation(id: entry.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Rename Conversation", isPresented: $showRenameAlert) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let target = renameTarget {
                    viewModel.renameConversation(id: target.id, newTitle: renameText)
                }
            }
        }
    }

    // MARK: - Conversation Export

    /// Export a conversation as a JSON file via save panel.
    private func exportConversation(_ id: UUID) {
        #if os(macOS)
        do {
            let data = try viewModel.conversationStore.exportJSON(id: id)
            let panel = NSSavePanel()
            panel.title = "Export Conversation"
            panel.nameFieldStringValue = "\(id.uuidString.prefix(8)).json"
            panel.allowedContentTypes = [.json]
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    try? data.write(to: url)
                }
            }
        } catch {
            // Silent failure for export — not critical
        }
        #endif
    }

    // MARK: - Relative Timestamp

    /// Format a date as a relative timestamp for sidebar display.
    private func relativeTimestamp(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        if interval < 172800 { return "Yesterday" }
        if interval < 604800 { return "\(Int(interval / 86400))d ago" }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

// MARK: - Sidebar Model Row

/// Consistent model row for discovered (on-disk) models shown in the sidebar.
///
/// Displays:
/// - Model name (from metadata or raw filename)
/// - Active/available status indicator
/// - Gallery badge for Edge Gallery–sourced models
/// - Capability badges (Vision, Audio, MTP, etc.)
private struct SidebarModelRow: View {
    let model: DiscoveredModel
    let isActive: Bool
    let experimentalFlags: ExperimentalFlagsState
    let onDelete: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            // Name + Gallery badge + trash icon
            HStack(spacing: AppSpacing.xs) {
                Text(model.metadata?.name ?? model.filename)
                    .font(AppTypography.subtitle)
                    .foregroundStyle(isActive ? AppColors.accentCyan : AppColors.textPrimary)
                    .lineLimit(1)

                if model.source == .edgeGallery {
                    Text("Gallery")
                        .font(AppTypography.badge)
                        .foregroundStyle(AppColors.accentCyan)
                        .padding(.horizontal, AppSpacing.xs)
                        .padding(.vertical, 1)
                        .background(AppColors.accentCyan.opacity(0.1))
                        .clipShape(Capsule())
                }

                Spacer()

                // Trash icon — visible on hover, not for Gallery-managed models
                if isHovered && model.source != .edgeGallery && onDelete != nil {
                    Button {
                        onDelete?()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption2)
                            .foregroundStyle(AppColors.danger.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                    .accessibilityIdentifier("sidebar_delete_\(model.filename)")
                }
            }

            // Capability badges
            if let metadata = model.metadata {
                ModelCapabilityBadges(
                    metadata: metadata,
                    experimentalFlags: experimentalFlags
                )
            }

            // Status indicator + size
            HStack(spacing: AppSpacing.xs) {
                Circle()
                    .fill(isActive ? AppColors.accentCyan : AppColors.success)
                    .frame(width: 5, height: 5)
                Text(isActive ? "Loaded" : "Available")
                    .font(AppTypography.caption)
                    .foregroundStyle(isActive ? AppColors.accentCyan : AppColors.textTertiary)
            }
        }
        .padding(.vertical, AppSpacing.xs)
        .onHover { hovering in
            withAnimation(AppAnimation.quick) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Previews

#Preview("Sidebar — No Model") {
    SidebarView(
        selectedSection: .constant(nil),
        selectedModelId: .constant(nil),
        showcaseModel: .constant(nil),
        showcaseModelURL: .constant(nil)
    )
    .preferredColorScheme(.dark)
}

#Preview("Sidebar — Models Section") {
    SidebarView(
        selectedSection: .constant(.models),
        selectedModelId: .constant(nil),
        showcaseModel: .constant(nil),
        showcaseModelURL: .constant(nil)
    )
    .preferredColorScheme(.dark)
}
