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
    let metadata: ModelMetadata

    @State private var showDeleteConfirmation = false
    @State private var showDownloadConfirmation = false
    @State private var storageCheck: ModelDownloadManager.StorageCheck?

    // MARK: - Computed State

    private var downloadState: ModelDownloadManager.DownloadState {
        viewModel.downloadManager.checkState(for: metadata)
    }

    private var isActiveModel: Bool {
        viewModel.activeModelMetadata?.modelFile == metadata.modelFile && viewModel.isEngineReady
    }

    private var isLoading: Bool {
        viewModel.isLoadingModel && viewModel.activeModelMetadata?.modelFile == metadata.modelFile
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
                }

                // Queued indicator
                if case .queued(let position) = downloadState {
                    queuedSection(position: position)
                }

                // Paused indicator
                if case .paused(_, let progress) = downloadState {
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
                if isActiveModel, let info = viewModel.benchmarkInfo {
                    benchmarkSection(info: info)
                }

                // Danger Zone
                if case .downloaded = downloadState {
                    dangerZoneSection
                } else if case .paused = downloadState {
                    dangerZoneSection
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
        }
        .background(AppColors.backgroundPrimary)
        .navigationTitle(metadata.name)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: isActiveModel)
        .alert("Delete Model?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteModel()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove \"\(metadata.name)\" (\(formattedSize)) from your device. You can re-download it later.")
        }
        .confirmationDialog(
            "Download \(metadata.name)?",
            isPresented: $showDownloadConfirmation
        ) {
            if let check = storageCheck, check.hasEnoughSpace {
                Button("Download (\(check.formattedModelSize))") {
                    viewModel.downloadManager.download(metadata)
                }
            } else {
                Button("Not Enough Storage", role: .cancel) {}
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let check = storageCheck {
                if check.hasEnoughSpace {
                    Text("This will use \(check.formattedModelSize). You have \(check.formattedAvailableSpace) available.")
                } else {
                    Text("This model requires \(check.formattedModelSize) but you only have \(check.formattedAvailableSpace) available. Free up space and try again.")
                }
            }
        }
        .accessibilityIdentifier("iOSModelDetail_\(metadata.modelFile)")
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: AppSpacing.md) {
            // Large model icon
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .fill(isActiveModel ? AppColors.accentCyan.opacity(0.12) : AppColors.backgroundTertiary)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.lg)
                            .stroke(isActiveModel ? AppColors.accentCyan.opacity(0.3) : AppColors.border, lineWidth: 0.5)
                    )

                VStack(spacing: AppSpacing.sm) {
                    Image(systemName: metadata.architectureType.contains("MoE")
                        ? "square.grid.3x3.topleft.filled"
                        : "square.stack.3d.up.fill")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(isActiveModel ? AppColors.accentCyan : AppColors.textSecondary)

                    if isActiveModel {
                        Text("Running")
                            .font(AppTypography.badge)
                            .foregroundStyle(AppColors.accentCyan)
                    }
                }
            }
            .frame(width: 80, height: 80)
            .accessibilityIdentifier("modelDetail_icon")

            // Model name and architecture
            VStack(spacing: AppSpacing.xs) {
                Text(metadata.name)
                    .font(.system(.title2, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text(metadata.architectureType)
                    .font(AppTypography.listSubtitle)
                    .foregroundStyle(AppColors.textSecondary)

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
                // Running state — show status
                HStack(spacing: AppSpacing.sm) {
                    Circle()
                        .fill(AppColors.success)
                        .frame(width: 8, height: 8)
                        .pulsingGlow(AppColors.success)
                    Text("Model is running")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(AppColors.success)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.md)
                .background(AppColors.success.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                .accessibilityIdentifier("modelDetail_running")

            } else if isLoading {
                // Loading state
                HStack(spacing: AppSpacing.sm) {
                    ProgressView()
                        .tint(AppColors.accentCyan)
                    Text("Loading…")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(AppColors.accentCyan)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.md)
                .background(AppColors.accentCyan.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))

            } else if case .downloaded(let url) = downloadState {
                // Downloaded — Load button
                Button {
                    Task { await viewModel.handleModelSelection(url) }
                } label: {
                    Label("Load Model", systemImage: "bolt.fill")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.md)
                        .background(AppColors.accentCyan)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                }
                .sensoryFeedback(.impact(weight: .medium), trigger: viewModel.isLoadingModel)
                .accessibilityIdentifier("modelDetail_loadButton")

            } else if case .downloading = downloadState {
                // Downloading — Pause + Cancel buttons
                HStack(spacing: AppSpacing.md) {
                    Button {
                        viewModel.downloadManager.pauseDownload(metadata)
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                            .font(.system(.body, weight: .semibold))
                            .foregroundStyle(AppColors.warning)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppSpacing.md)
                            .background(AppColors.warning.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                    }
                    .accessibilityIdentifier("modelDetail_pauseButton")

                    Button {
                        viewModel.downloadManager.cancelDownload(metadata)
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                            .font(.system(.body, weight: .semibold))
                            .foregroundStyle(AppColors.danger)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppSpacing.md)
                            .background(AppColors.danger.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                    }
                    .accessibilityIdentifier("modelDetail_cancelButton")
                }

            } else if case .paused = downloadState {
                // Paused — Resume button
                Button {
                    viewModel.downloadManager.resumeDownload(metadata)
                } label: {
                    Label("Resume Download", systemImage: "play.fill")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.md)
                        .background(AppColors.accentCyan)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                }
                .accessibilityIdentifier("modelDetail_resumeButton")

            } else if case .queued(let position) = downloadState {
                // Queued — show position with cancel option
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(AppColors.textSecondary)
                    Text("Queued (#\(position))")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                    Button("Cancel") {
                        viewModel.downloadManager.cancelDownload(metadata)
                    }
                    .foregroundStyle(AppColors.danger)
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
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.md)
                        .background(AppColors.accentCyan)
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
                .tint(AppColors.accentCyan)

            if let dp = viewModel.downloadManager.downloadProgress[metadata.modelFile] {
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
                capabilityChip("Vision", icon: "eye", color: AppColors.badgeVision, enabled: metadata.supportsImage)
                capabilityChip("Audio", icon: "waveform", color: AppColors.badgeAudio, enabled: metadata.supportsAudio)
                capabilityChip("MTP / Speculative", icon: "bolt.horizontal", color: AppColors.badgeMTP, enabled: metadata.supportsMTP)
                capabilityChip("Tool Calling", icon: "wrench.and.screwdriver", color: AppColors.toolCall, enabled: metadata.supportsToolCalling)
                capabilityChip("Thinking", icon: "brain", color: AppColors.badgeThinking, enabled: metadata.capabilities.contains("llm_thinking"))
            }
        }
    }

    // MARK: - Platform Section

    private var platformSection: some View {
        detailCard(title: "Platform Support", icon: "iphone") {
            let capability = metadata.platformSupport.currentPlatform
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
                configRow("Top-K", value: "\(metadata.defaultConfig.topK)")
                configRow("Top-P", value: String(format: "%.2f", metadata.defaultConfig.topP))
                configRow("Temperature", value: String(format: "%.1f", metadata.defaultConfig.temperature))
                configRow("Context Window", value: formattedContextWindow)
                configRow("Max Tokens", value: "\(metadata.defaultConfig.maxTokens)")
            }
        }
    }

    // MARK: - Description Section

    private var descriptionSection: some View {
        detailCard(title: "About", icon: "info.circle") {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(metadata.description)
                    .font(AppTypography.listSubtitle)
                    .foregroundStyle(AppColors.textSecondary)

                Text("Recommended for: \(metadata.recommendedFor)")
                    .font(AppTypography.listTertiary)
                    .foregroundStyle(AppColors.textTertiary)

                if metadata.minDeviceMemoryGB > 0 {
                    Text("Minimum \(metadata.minDeviceMemoryGB) GB device memory")
                        .font(AppTypography.listTertiary)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
    }

    // MARK: - Benchmark Section

    private func benchmarkSection(info: BenchmarkInfo) -> some View {
        detailCard(title: "Last Benchmark", icon: "speedometer") {
            VStack(spacing: AppSpacing.sm) {
                HStack {
                    metricDisplay(
                        label: "Decode",
                        value: String(format: "%.1f", info.lastDecodeTokensPerSecond),
                        unit: "tok/s",
                        color: PerformanceTier(decodeSpeed: info.lastDecodeTokensPerSecond).color
                    )
                    Spacer()
                    metricDisplay(
                        label: "Prefill",
                        value: String(format: "%.1f", info.lastPrefillTokensPerSecond),
                        unit: "tok/s",
                        color: AppColors.textSecondary
                    )
                }

                HStack {
                    metricDisplay(
                        label: "TTFT",
                        value: String(format: "%.2f", info.timeToFirstTokenInSecond),
                        unit: "s",
                        color: AppColors.textSecondary
                    )
                    Spacer()
                    metricDisplay(
                        label: "Init",
                        value: String(format: "%.2f", info.initTimeInSecond),
                        unit: "s",
                        color: AppColors.textSecondary
                    )
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
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(AppColors.danger)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.md)
                    .background(AppColors.danger.opacity(0.08))
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
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)

            content()
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg)
                .stroke(AppColors.border, lineWidth: 0.5)
        )
    }

    private func capabilityChip(_ label: String, icon: String, color: Color, enabled: Bool) -> some View {
        Label(label, systemImage: icon)
            .font(AppTypography.badge)
            .foregroundStyle(enabled ? color : AppColors.textTertiary)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, 5)
            .background(enabled ? color.opacity(0.12) : AppColors.backgroundTertiary)
            .clipShape(Capsule())
            .opacity(enabled ? 1.0 : 0.5)
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
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppTypography.badge)
                .foregroundStyle(AppColors.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
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
        ByteCountFormatter.string(fromByteCount: metadata.sizeInBytes, countStyle: .file)
    }

    private var formattedContextWindow: String {
        if metadata.contextWindowSize >= 1_000_000 {
            return "\(metadata.contextWindowSize / 1_000_000)M ctx"
        } else {
            return "\(metadata.contextWindowSize / 1_000)K ctx"
        }
    }

    /// Confirm download with storage check.
    private func confirmDownload() {
        storageCheck = viewModel.downloadManager.checkStorage(for: metadata)
        showDownloadConfirmation = true
    }

    /// Delete using centralized download manager + dismiss back to hub.
    private func deleteModel() {
        viewModel.downloadManager.deleteModel(metadata)
        viewModel.refreshDiscoveredModels()
        viewModel.downloadManager.refreshStates()
        dismiss()
    }
}

// MARK: - Download State Helpers

extension ModelDownloadManager.DownloadState {
    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
}

// MARK: - Flow Layout

/// A simple horizontal flow layout that wraps items to the next line.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layoutResult(for: proposal.width ?? 0, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layoutResult(for: bounds.width, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func layoutResult(for containerWidth: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > containerWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxWidth = max(maxWidth, currentX - spacing)
        }

        return (CGSize(width: maxWidth, height: currentY + lineHeight), positions)
    }
}
#endif
