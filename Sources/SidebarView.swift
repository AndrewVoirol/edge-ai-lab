import SwiftUI

// MARK: - Sidebar Section

/// Navigation sections available in the sidebar.
///
/// Each case maps to a distinct detail view in the middle column
/// of a `NavigationSplitView`.
enum SidebarSection: String, Hashable, Identifiable {
    case models
    case benchmarks
    case conversations

    var id: String { rawValue }

    /// SF Symbol name for section icons.
    var systemImage: String {
        switch self {
        case .models:        return "cube.box"
        case .benchmarks:    return "chart.line.uptrend.xyaxis"
        case .conversations: return "bubble.left.and.bubble.right"
        }
    }

    /// Human-readable title.
    var title: String {
        switch self {
        case .models:        return "Models"
        case .benchmarks:    return "Benchmarks"
        case .conversations: return "Conversations"
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
    @Bindable private var viewModel = ConversationViewModel.shared
    @Binding var selectedSection: SidebarSection?
    @Binding var selectedModelId: String?
    @Binding var showcaseModel: ModelMetadata?
    @Binding var showcaseModelURL: URL?

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
                        experimentalFlags: viewModel.experimentalFlags
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
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
                                    viewModel.downloadManager.deleteModel(metadata)
                                    viewModel.refreshDiscoveredModels()
                                } label: {
                                    Label("Delete Model", systemImage: "trash")
                                }
                                .accessibilityIdentifier("sidebar_context_delete_\(model.filename)")
                            }
                        }
                    }
                    .accessibilityIdentifier("sidebar_model_\(model.filename)")
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
            }

            // MARK: Benchmarks

            Section {
                NavigationLink(value: SidebarSection.benchmarks) {
                    Label("Dashboard", systemImage: "chart.bar.xaxis")
                }
                .accessibilityIdentifier("sidebar_benchmarks_dashboard")

                NavigationLink(value: SidebarSection.benchmarks) {
                    Label("Compare Models", systemImage: "arrow.left.arrow.right")
                }
                .accessibilityIdentifier("sidebar_benchmarks_compare")
            } header: {
                Label("Benchmarks", systemImage: SidebarSection.benchmarks.systemImage)
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

                Text("Chat history coming soon")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
            } header: {
                Label("Conversations", systemImage: SidebarSection.conversations.systemImage)
                    .font(AppTypography.sectionHeader)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        #if os(macOS)
        .listStyle(.sidebar)
        #endif
        .accessibilityIdentifier("sidebar_list")
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
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    Text("Loading…")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.warning)
                }
            }
            .accessibilityIdentifier("sidebar_activeModel_loading")
        } else if let metadata = viewModel.activeModelMetadata {
            // Model loaded
            HStack(spacing: AppSpacing.sm) {
                Circle()
                    .fill(AppColors.success)
                    .frame(width: 8, height: 8)
                    .glow(AppColors.success, radius: 6, opacity: 0.5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(metadata.name)
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    Text("Loaded")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.success)
                }
            }
            .accessibilityIdentifier("sidebar_activeModel_loaded")
        } else {
            // No model
            HStack(spacing: AppSpacing.sm) {
                Circle()
                    .fill(AppColors.textTertiary.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text("No model loaded")
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(AppColors.textTertiary)
            }
            .accessibilityIdentifier("sidebar_activeModel_empty")
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
                .font(.system(.subheadline, weight: .medium))
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
                HStack {
                    Text("\(Int(progress * 100))%")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                    Spacer()
                    Button {
                        viewModel.downloadManager.cancelDownload(model)
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
                Text("Ready")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                Spacer()
                Button {
                    viewModel.downloadManager.deleteModel(model)
                    viewModel.refreshDiscoveredModels()
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
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            // Name + Gallery badge
            HStack(spacing: AppSpacing.xs) {
                Text(model.metadata?.name ?? model.filename)
                    .font(.system(.subheadline, weight: .medium))
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
            }

            // Capability badges
            if let metadata = model.metadata {
                ModelCapabilityBadges(
                    metadata: metadata,
                    experimentalFlags: experimentalFlags
                )
            }

            // Status indicator
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
