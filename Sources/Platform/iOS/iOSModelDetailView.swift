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

// MARK: - iOS Model Detail View

/// iPhone-optimized model detail view, pushed from the Model Hub via `NavigationLink`.
///
/// Architecture (per Apple HIG "Toolbars"):
/// - Inline navigation title (`.navigationBarTitleDisplayMode(.inline)`)
/// - `.prominent` toolbar style for primary action (Load/Download)
/// - Vertical `ScrollView` with sections
/// - Confirmation alert before destructive actions
///
/// Layout:
/// 1. Header: Model name, architecture badge, size
/// 2. Action Bar: Primary action (Download/Load/Running)
/// 3. Capabilities: Horizontal capability chips
/// 4. Platform Support: Backend compatibility for current platform
/// 5. Configuration: Default inference parameters
/// 6. Description: Full model description
/// 7. Danger Zone: Delete button (if downloaded)
///
/// Accessibility: Every interactive element has `.accessibilityIdentifier`.
struct iOSModelDetailView: View {
    @Environment(ConversationViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(iOSNavigationRouter.self) private var router
    let profile: ModelCapabilityProfile

    @State private var showDeleteConfirmation = false
    @State private var showDownloadConfirmation = false
    @State private var storageCheck: ModelDownloadManager.StorageCheck?

    // MARK: - Computed State

    private var downloadState: ModelDownloadManager.DownloadState {
        viewModel.downloadManager.checkState(for: profile)
    }

    private var isActiveModel: Bool {
        viewModel.activeCapabilityProfile?.modelFile == (profile.modelFile ?? profile.id) && viewModel.isEngineReady
    }

    private var isLoading: Bool {
        viewModel.isLoadingModel && viewModel.activeCapabilityProfile?.modelFile == (profile.modelFile ?? profile.id)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                // Header
                headerSection

                // Primary Action
                actionSection

                // Download progress (if downloading)
                if case .downloading(let progress) = downloadState {
                    downloadProgressSection(progress: progress)
                } else if case .downloadingDirectory(let progress, _, _) = downloadState {
                    downloadProgressSection(progress: progress)
                }

                // Queued indicator
                if case .queued(let position) = downloadState {
                    queuedSection(position: position)
                }

                // Paused indicator
                if case .paused(_, let progress) = downloadState {
                    pausedSection(progress: progress)
                } else if case .pausedDirectory(let progress, _, _) = downloadState {
                    pausedSection(progress: progress)
                }

                // Capabilities
                capabilitiesSection

                // Platform Support
                platformSection

                // Default Configuration
                configurationSection

                // Description
                descriptionSection

                // Benchmark (if this is the active model)
                if isActiveModel, let metrics = viewModel.performanceMetrics {
                    BenchmarkSummaryCard(metrics: metrics)
                }

                // One-Tap Benchmark Runner
                if isActiveModel {
                    OneTapBenchmarkSection(viewModel: viewModel)
                }

                // Danger Zone
                if case .downloaded = downloadState {
                    dangerZoneSection
                } else if downloadState.isPausedState {
                    dangerZoneSection
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
        }
        .background(AppColors.backgroundPrimary)
        .navigationTitle(profile.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: isActiveModel)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.showcaseModel = profile
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("Model Info")
                .accessibilityIdentifier("modelDetail_showcaseButton")
            }
        }
        .alert("Delete Model?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteModel()
            }
            .accessibilityIdentifier("modelDetail_deleteConfirmAlert")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("modelDetail_deleteCancelAlert")
        } message: {
            Text("This will remove \"\(profile.displayName)\" (\(formattedSize)) from your device. You can re-download it later.")
        }
        .confirmationDialog(
            "Download \(profile.displayName)?",
            isPresented: $showDownloadConfirmation
        ) {
            if let check = storageCheck, check.hasEnoughSpace {
                Button("Download (\(check.formattedModelSize))") {
                    viewModel.downloadManager.download(profile)
                }
                .accessibilityIdentifier("modelDetail_downloadConfirmDialog")
            } else {
                Button("Not Enough Storage", role: .cancel) {}
                    .accessibilityIdentifier("modelDetail_notEnoughStorage")
            }
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("modelDetail_downloadCancelDialog")
        } message: {
            if let check = storageCheck {
                if check.hasEnoughSpace {
                    Text("This will use \(check.formattedModelSize). You have \(check.formattedAvailableSpace) available.")
                } else {
                    Text("This model requires \(check.formattedModelSize) but you only have \(check.formattedAvailableSpace) available. Free up space and try again.")
                }
            }
        }
        .accessibilityIdentifier("iOSModelDetail_\(profile.modelFile ?? profile.id)")
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: AppSpacing.md) {
            // Large model icon
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .fill(isActiveModel ? AppColors.accentPrimary.opacity(AppOpacity.fill) : AppColors.backgroundTertiary)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.lg)
                            .stroke(isActiveModel ? AppColors.accentPrimaryBorder : AppColors.border, lineWidth: AppLineWidth.hairline)
                    )

                VStack(spacing: AppSpacing.sm) {
                    Image(systemName: (profile.architecture?.architectureClass ?? "").contains("MoE")
                        ? "square.grid.3x3.topleft.filled"
                        : "square.stack.3d.up.fill")
                        .font(AppIconSize.xxl)
                        .foregroundStyle(isActiveModel ? AppColors.accentPrimary : AppColors.textSecondary)

                    if isActiveModel {
                        Text("Running")
                            .font(AppTypography.badge)
                            .foregroundStyle(AppColors.accentPrimary)
                    }
                }
            }
            .frame(width: 80, height: 80)
            .accessibilityIdentifier("modelDetail_icon")

            // Model name and architecture
            VStack(spacing: AppSpacing.xs) {
                Text(profile.displayName)
                    .font(AppTypography.pageTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text(profile.architecture?.architectureClass ?? "Unknown")
                    .font(AppTypography.listSubtitle)
                    .foregroundStyle(AppColors.textSecondary)

                // Confidence badge for dynamically-imported models
                if let dynamicEntry = viewModel.dynamicModelCatalog.allModels().first(where: { ($0.metadata.modelFile ?? $0.metadata.id) == (profile.modelFile ?? profile.id) }),
                   dynamicEntry.source != .knownRegistry {
                    Label(dynamicEntry.confidence.label,
                          systemImage: dynamicEntry.confidence.symbolName)
                        .badge(ConfidenceTier.color(for: dynamicEntry.confidence))
                        .accessibilityIdentifier("modelDetail_confidenceBadge")
                }

                HStack(spacing: AppSpacing.sm) {
                    Label(formattedSize, systemImage: "internaldrive")
                        .font(AppTypography.listSubtitle)
                        .foregroundStyle(AppColors.textSecondary)

                    Text("·")
                        .foregroundStyle(AppColors.textTertiary)

                    Label(formattedContextWindow, systemImage: "text.word.spacing")
                        .font(AppTypography.listSubtitle)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .padding(.top, AppSpacing.md)
        .accessibilityIdentifier("modelDetail_header")
    }

    // MARK: - Action Section

    private var actionSection: some View {
        Group {
            if isActiveModel {
                // Running state — show status + Open Chat action
                VStack(spacing: AppSpacing.sm) {
                    HStack(spacing: AppSpacing.sm) {
                        Circle()
                            .fill(AppColors.success)
                            .frame(width: AppSize.dotXl, height: AppSize.dotXl)
                            .pulsingGlow(AppColors.success)
                        Text("Model is running")
                            .font(AppTypography.subtitle)
                            .foregroundStyle(AppColors.success)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.md)
                    .background(AppColors.success.opacity(AppOpacity.faint))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                    .accessibilityIdentifier("modelDetail_running")

                    Button {
                        router.navigateToChat()
                    } label: {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(AppIconSize.md)
                            Text("Open Chat")
                                .font(AppTypography.subtitle)
                        }
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.md)
                        .background(AppColors.accentPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                    }
                    .sensoryFeedback(.impact(weight: .medium), trigger: router.selectedTab)
                    .accessibilityLabel("Open chat with this model")
                    .accessibilityIdentifier("modelDetail_openChat")

                    Button {
                        Task { await viewModel.shutdown() }
                    } label: {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "eject.fill")
                            Text("Unload Model")
                                .font(AppTypography.subtitle)
                        }
                        .foregroundStyle(AppColors.warning)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.sm)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppColors.warning)
                    .accessibilityIdentifier("modelDetail_unloadButton")
                    .accessibilityLabel("Unload model from memory")
                }

            } else if isLoading {
                // Loading state
                HStack(spacing: AppSpacing.sm) {
                    ProgressView()
                        .tint(AppColors.accentPrimary)
                    Text("Loading…")
                        .font(AppTypography.subtitle)
                        .foregroundStyle(AppColors.accentPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.md)
                .background(AppColors.accentPrimaryFaint)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))

            } else if case .downloaded(let url) = downloadState {
                // Downloaded — Load button
                Button {
                    Task { await viewModel.handleModelSelection(url) }
                } label: {
                    Label("Load Model", systemImage: "bolt.fill")
                        .font(AppTypography.subtitle)
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.md)
                        .background(AppColors.accentPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                }
                .sensoryFeedback(.impact(weight: .medium), trigger: viewModel.isLoadingModel)
                .accessibilityHint("Double-tap to load this model for chat")
                .accessibilityIdentifier("modelDetail_loadButton")

            } else if downloadState.isActivelyDownloading {
                // Downloading — Pause + Cancel buttons
                HStack(spacing: AppSpacing.md) {
                    Button {
                        Task { await viewModel.downloadManager.pauseDownload(profile) }
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                            .font(AppTypography.subtitle)
                            .foregroundStyle(AppColors.warning)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppSpacing.md)
                            .background(AppColors.warning.opacity(AppOpacity.faint))
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                    }
                    .accessibilityIdentifier("modelDetail_pauseButton")

                    Button {
                        Task { await viewModel.downloadManager.cancelDownload(profile) }
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                            .font(AppTypography.subtitle)
                            .foregroundStyle(AppColors.destructive)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppSpacing.md)
                            .background(AppColors.destructive.opacity(AppOpacity.faint))
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                    }
                    .accessibilityIdentifier("modelDetail_cancelButton")
                }

            } else if downloadState.isPausedState {
                // Paused — Resume button
                Button {
                    viewModel.downloadManager.resumeDownload(profile)
                } label: {
                    Label("Resume Download", systemImage: "play.fill")
                        .font(AppTypography.subtitle)
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.md)
                        .background(AppColors.accentPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                }
                .accessibilityIdentifier("modelDetail_resumeButton")

            } else if case .queued(let position) = downloadState {
                // Queued — show position with cancel option
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(AppColors.textSecondary)
                    Text("Queued (#\(position))")
                        .font(AppTypography.subtitle)
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                    Button("Cancel") {
                        Task { await viewModel.downloadManager.cancelDownload(profile) }
                    }
                    .foregroundStyle(AppColors.destructive)
                    .accessibilityIdentifier("modelDetail_cancelQueuedButton")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.md)
                .padding(.horizontal, AppSpacing.md)
                .background(AppColors.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))

            } else {
                // Not downloaded — Download button
                Button {
                    confirmDownload()
                } label: {
                    Label("Download Model", systemImage: "icloud.and.arrow.down")
                        .font(AppTypography.subtitle)
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.md)
                        .background(AppColors.accentPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                }
                .sensoryFeedback(.impact(weight: .medium), trigger: downloadState.isDownloading)
                .accessibilityIdentifier("modelDetail_downloadButton")
            }
        }
    }

    // MARK: - Download Progress

    private func downloadProgressSection(progress: Double) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            ProgressView(value: progress, total: 1.0)
                .tint(AppColors.accentPrimary)

            if let dp = viewModel.downloadManager.downloadProgress[profile.modelFile ?? profile.id] {
                // Rich progress: percentage + speed + ETA
                HStack {
                    Text(String(format: "%.0f%%", progress * 100))
                        .font(AppTypography.listSubtitle)
                        .foregroundStyle(AppColors.textSecondary)

                    Text("·")
                        .foregroundStyle(AppColors.textTertiary)

                    Text(dp.formattedSpeed)
                        .font(AppTypography.listSubtitle)
                        .foregroundStyle(AppColors.textSecondary)

                    Spacer()

                    if let eta = dp.formattedETA {
                        Text("~\(eta) remaining")
                            .font(AppTypography.listSubtitle)
                            .foregroundStyle(AppColors.textTertiary)
                    } else {
                        Text("\(dp.formattedBytesWritten) / \(dp.formattedTotalBytes)")
                            .font(AppTypography.listSubtitle)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
            } else {
                HStack {
                    Text(String(format: "Downloading… %.0f%%", progress * 100))
                        .font(AppTypography.listSubtitle)
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                    Text(formattedSize)
                        .font(AppTypography.listSubtitle)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    }

    // MARK: - Queued Section

    private func queuedSection(position: Int) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "clock.fill")
                .foregroundStyle(AppColors.textSecondary)
            Text("Waiting in download queue (position #\(position))")
                .font(AppTypography.listSubtitle)
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    }

    // MARK: - Paused Section

    private func pausedSection(progress: Double) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            ProgressView(value: progress, total: 1.0)
                .tint(AppColors.warning)

            HStack {
                Image(systemName: "pause.fill")
                    .foregroundStyle(AppColors.warning)
                Text(String(format: "Paused at %.0f%%", progress * 100))
                    .font(AppTypography.listSubtitle)
                    .foregroundStyle(AppColors.warning)
                Spacer()
                Text(formattedSize)
                    .font(AppTypography.listSubtitle)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    }

    // MARK: - Capabilities Section

    private var capabilitiesSection: some View {
        detailCard(title: "Capabilities", icon: "sparkles") {
            FlowLayout(spacing: AppSpacing.sm) {
                capabilityChip("Text Generation", icon: "text.bubble", color: AppColors.textSecondary, enabled: true)
                capabilityChip("Vision", icon: "eye", color: AppColors.capabilityVision, enabled: profile.hasVision)
                capabilityChip("Audio", icon: "waveform", color: AppColors.capabilityAudio, enabled: profile.hasAudio)
                capabilityChip("Speculative Decoding", icon: "bolt.horizontal", color: AppColors.capabilityMTP, enabled: profile.hasMTP)
                capabilityChip("Tool Calling", icon: "wrench.and.screwdriver", color: AppColors.toolAction, enabled: profile.hasToolCalling)
                capabilityChip("Thinking", icon: "brain", color: AppColors.capabilityThinking, enabled: profile.hasThinking)
            }
        }
    }

    // MARK: - Platform Section

    private var platformSection: some View {
        detailCard(title: "Platform Support", icon: "iphone") {
            let capability = (profile.platformSupport ?? PlatformSupport()).currentPlatform
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                platformRow("GPU", supported: capability.supportsGPU)
                platformRow("CPU", supported: capability.supportsCPU)

                if capability == .unknown {
                    Text("Backend compatibility will be determined at load time.")
                        .font(AppTypography.listTertiary)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
    }

    // MARK: - Configuration Section

    private var configurationSection: some View {
        detailCard(title: "Default Configuration", icon: "slider.horizontal.3") {
            VStack(spacing: AppSpacing.sm) {
                configRow("Top-K", value: "\(profile.defaultConfig?.topK ?? 64)")
                configRow("Top-P", value: String(format: "%.2f", profile.defaultConfig?.topP ?? 0.95))
                configRow("Temperature", value: String(format: "%.1f", profile.defaultConfig?.temperature ?? 1.0))
                configRow("Context Window", value: formattedContextWindow)
                configRow("Max Tokens", value: "\(profile.defaultConfig?.maxTokens ?? 4096)")
            }
        }
    }

    // MARK: - Description Section

    private var descriptionSection: some View {
        detailCard(title: "About", icon: "info.circle") {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(profile.modelDescription ?? "")
                    .font(AppTypography.listSubtitle)
                    .foregroundStyle(AppColors.textSecondary)

                Text("Recommended for: \(profile.recommendedFor ?? "")")
                    .font(AppTypography.listTertiary)
                    .foregroundStyle(AppColors.textTertiary)

                if (profile.memoryGB ?? 0) > 0 {
                    Text("Minimum \(profile.memoryGB ?? 8) GB device memory")
                        .font(AppTypography.listTertiary)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
    }


    // MARK: - Danger Zone


    private var dangerZoneSection: some View {
        VStack(spacing: AppSpacing.sm) {
            Divider()
                .overlay(AppColors.border)

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete from Device", systemImage: "trash")
                    .font(AppTypography.subtitle)
                    .foregroundStyle(AppColors.destructive)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.md)
                    .background(AppColors.destructive.opacity(AppOpacity.tint))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
            }
            .accessibilityIdentifier("modelDetail_deleteButton")
        }
        .padding(.top, AppSpacing.md)
    }

    // MARK: - Reusable Components

    private func detailCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Label(title, systemImage: icon)
                .font(AppTypography.sectionHeader)
                .foregroundStyle(AppColors.textSecondary)

            content()
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .stroke(AppColors.border, lineWidth: AppLineWidth.hairline)
        )
    }

    private func capabilityChip(_ label: String, icon: String, color: Color, enabled: Bool) -> some View {
        Label(label, systemImage: icon)
            .font(AppTypography.badge)
            .foregroundStyle(enabled ? color : AppColors.textTertiary)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
            .background(enabled ? color.opacity(AppOpacity.fill) : AppColors.backgroundTertiary)
            .clipShape(Capsule())
            .opacity(enabled ? 1.0 : 0.5)
            .accessibilityLabel("\(label): \(enabled ? "supported" : "not supported")")
    }

    private func platformRow(_ backend: String, supported: Bool) -> some View {
        HStack {
            Image(systemName: supported ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(supported ? AppColors.success : AppColors.textTertiary)
            Text(backend)
                .font(AppTypography.listSubtitle)
                .foregroundStyle(supported ? AppColors.textPrimary : AppColors.textTertiary)
        }
    }

    private func configRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(AppTypography.listSubtitle)
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
            Text(value)
                .font(AppTypography.mono)
                .foregroundStyle(AppColors.textPrimary)
        }
    }

    private func metricDisplay(label: String, value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(label)
                .font(AppTypography.badge)
                .foregroundStyle(AppColors.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xxs) {
                Text(value)
                    .font(AppTypography.metricLarge)
                    .foregroundStyle(color)
                Text(unit)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
    }

    // MARK: - Helpers

    private var formattedSize: String {
        ModelDetailFormatters.formattedSize(profile.fileSizeBytes ?? 0)
    }

    private var formattedContextWindow: String {
        profile.contextWindowSize.map { ModelDetailFormatters.formattedContextWindow($0) } ?? "Unknown"
    }

    /// Confirm download with storage check.
    private func confirmDownload() {
        storageCheck = viewModel.downloadManager.checkStorage(for: profile)
        showDownloadConfirmation = true
    }

    /// Delete using centralized download manager + dismiss back to hub.
    private func deleteModel() {
        viewModel.downloadManager.deleteModel(profile)
        viewModel.refreshDiscoveredModels()
        viewModel.downloadManager.refreshStates()
        dismiss()
    }


}

// MARK: - Download State Helpers

extension ModelDownloadManager.DownloadState {
    /// Whether this state represents any kind of active download (single or multi-file).
    var isDownloading: Bool {
        if case .downloading = self { return true }
        if case .downloadingDirectory = self { return true }
        return false
    }

    /// Alias for `isDownloading` — used in conditional UI rendering.
    var isActivelyDownloading: Bool { isDownloading }

    /// Whether this state represents any kind of paused download.
    var isPausedState: Bool {
        if case .paused = self { return true }
        if case .pausedDirectory = self { return true }
        return false
    }
}
#endif

