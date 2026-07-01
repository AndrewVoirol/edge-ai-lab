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

// MARK: - iOS Model Row

/// A reusable list row for the iOS Model Hub showing model metadata and download state.
///
/// Design (per Apple HIG "Lists and Tables"):
/// - Leading: Architecture icon (SF Symbol)
/// - Title: Model name (`.body`, primary label)
/// - Subtitle: Architecture type + size (`.subheadline`, secondary label)
/// - Capability badges: Inline chips for image, audio, thinking
/// - Trailing: State-appropriate accessory (download, progress, checkmark, error)
///
/// Disclosure indicator (chevron) is provided automatically by the parent `NavigationLink`.
///
/// Accessibility: Every interactive element has `.accessibilityIdentifier`.
struct iOSModelRow: View {
    @Environment(ModelDownloadManager.self) private var downloadManager
    let metadata: ModelMetadata
    let downloadState: ModelDownloadManager.DownloadState
    let isActive: Bool

    /// Callback for download button tap (prevents NavigationLink activation).
    var onDownloadTap: (() -> Void)?
    /// Callback for cancel download tap.
    var onCancelTap: (() -> Void)?
    /// Callback for retry tap.
    var onRetryTap: (() -> Void)?
    /// Callback for pause download.
    var onPauseTap: (() -> Void)?
    /// Callback for resume download.
    var onResumeTap: (() -> Void)?

    init(
        metadata: ModelMetadata,
        downloadState: ModelDownloadManager.DownloadState = .notDownloaded,
        isActive: Bool = false,
        onDownloadTap: (() -> Void)? = nil,
        onCancelTap: (() -> Void)? = nil,
        onRetryTap: (() -> Void)? = nil,
        onPauseTap: (() -> Void)? = nil,
        onResumeTap: (() -> Void)? = nil
    ) {
        self.metadata = metadata
        self.downloadState = downloadState
        self.isActive = isActive
        self.onDownloadTap = onDownloadTap
        self.onCancelTap = onCancelTap
        self.onRetryTap = onRetryTap
        self.onPauseTap = onPauseTap
        self.onResumeTap = onResumeTap
    }

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            // Leading: Model icon
            modelIcon
                .frame(width: 40, height: 40)
                .accessibilityIdentifier("modelRow_icon_\(metadata.modelFile)")

            // Center: Title, subtitle, capabilities
            VStack(alignment: .leading, spacing: 3) {
                // Model name
                Text(metadata.name)
                    .font(AppTypography.listTitle)
                    .foregroundStyle(isActive ? AppColors.accentCyan : AppColors.textPrimary)
                    .lineLimit(1)

                // Architecture + size
                HStack(spacing: AppSpacing.xs) {
                    Text(metadata.architectureType)
                        .font(AppTypography.listSubtitle)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)

                    Text("·")
                        .foregroundStyle(AppColors.textTertiary)

                    Text(formattedSize)
                        .font(AppTypography.listSubtitle)
                        .foregroundStyle(AppColors.textSecondary)
                }

                // Download progress subtitle (replaces capabilities when downloading)
                if case .downloading(let progress) = downloadState {
                    downloadProgressRow(progress: progress)
                } else if case .downloadingDirectory(let progress, _, _) = downloadState {
                    downloadProgressRow(progress: progress)
                } else if case .queued(let position) = downloadState {
                    queuedRow(position: position)
                } else if case .paused(_, let progress) = downloadState {
                    pausedRow(progress: progress)
                } else if case .pausedDirectory(let progress, _, _) = downloadState {
                    pausedRow(progress: progress)
                } else {
                    // Capability badges
                    capabilityBadges
                }
            }

            Spacer()

            // Trailing: State accessory
            stateAccessory
        }
        .padding(.vertical, AppSpacing.listRowVertical)
        .contentShape(Rectangle()) // Ensure full row is tappable
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("modelRow_\(metadata.modelFile)")
    }

    // MARK: - Model Icon

    private var modelIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.sm)
                .fill(isActive ? AppColors.accentCyan.opacity(0.15) : AppColors.backgroundTertiary)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.sm)
                        .stroke(isActive ? AppColors.accentCyan.opacity(0.3) : AppColors.border, lineWidth: 0.5)
                )

            Image(systemName: iconName)
                .font(AppIconSize.lg)
                .foregroundStyle(isActive ? AppColors.accentCyan : AppColors.textSecondary)
        }
    }

    /// SF Symbol for the model architecture type.
    private var iconName: String {
        if metadata.architectureType.contains("MoE") {
            return "square.grid.3x3.topleft.filled" // MoE = mixture
        } else if metadata.architectureType.contains("Dense") {
            return "square.stack.3d.up.fill" // Dense = stacked
        } else {
            return "cpu" // Generic
        }
    }

    // MARK: - Capability Badges

    private var capabilityBadges: some View {
        HStack(spacing: AppSpacing.xs) {
            if metadata.supportsImage {
                Label("Vision", systemImage: "eye")
                    .font(AppTypography.badge)
                    .foregroundStyle(AppColors.badgeVision)
                    .accessibilityIdentifier("modelRow_badge_vision_\(metadata.modelFile)")
            }
            if metadata.supportsAudio {
                Label("Audio", systemImage: "waveform")
                    .font(AppTypography.badge)
                    .foregroundStyle(AppColors.badgeAudio)
                    .accessibilityIdentifier("modelRow_badge_audio_\(metadata.modelFile)")
            }
            if metadata.supportsMTP {
                Label("MTP", systemImage: "bolt.horizontal")
                    .font(AppTypography.badge)
                    .foregroundStyle(AppColors.badgeMTP)
                    .accessibilityIdentifier("modelRow_badge_mtp_\(metadata.modelFile)")
            }
        }
    }

    // MARK: - Download Progress

    private func downloadProgressRow(progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ProgressView(value: progress, total: 1.0)
                .tint(AppColors.accentCyan)
                .accessibilityIdentifier("modelRow_progress_\(metadata.modelFile)")

            // Try to show rich progress (speed + ETA)
            if let dp = downloadManager.downloadProgress[metadata.modelFile] {
                HStack {
                    Text(String(format: "%.0f%%", progress * 100))
                        .font(AppTypography.listTertiary)
                        .foregroundStyle(AppColors.textTertiary)

                    if dp.speedBytesPerSecond > 0 {
                        Text("· \(dp.formattedSpeed)")
                            .font(AppTypography.listTertiary)
                            .foregroundStyle(AppColors.textTertiary)
                    }

                    Spacer()

                    if let eta = dp.formattedETA {
                        Text("~\(eta)")
                            .font(AppTypography.listTertiary)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
            } else {
                HStack {
                    Text(String(format: "%.0f%% of %@", progress * 100, formattedSize))
                        .font(AppTypography.listTertiary)
                        .foregroundStyle(AppColors.textTertiary)
                    Spacer()
                }
            }
        }
    }

    // MARK: - Queued Row

    private func queuedRow(position: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(AppIconSize.xxs)
                .foregroundStyle(AppColors.textTertiary)
            Text("Queued (#\(position))")
                .font(AppTypography.listTertiary)
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    // MARK: - Paused Row

    private func pausedRow(progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ProgressView(value: progress, total: 1.0)
                .tint(AppColors.warning)
            HStack(spacing: 4) {
                Image(systemName: "pause.fill")
                    .font(AppIconSize.xxs)
                    .foregroundStyle(AppColors.warning)
                Text(String(format: "Paused at %.0f%%", progress * 100))
                    .font(AppTypography.listTertiary)
                    .foregroundStyle(AppColors.warning)
                Spacer()
            }
        }
    }

    // MARK: - State Accessory

    @ViewBuilder
    private var stateAccessory: some View {
        switch downloadState {
        case .notDownloaded:
            // icloud.and.arrow.down — per HIG download affordance
            Button {
                onDownloadTap?()
            } label: {
                Image(systemName: metadata.requiresAuth ? "lock.icloud" : "icloud.and.arrow.down")
                    .font(AppIconSize.lg)
                    .foregroundStyle(AppColors.accentCyan)
                    .frame(width: 44, height: 44) // HIG: 44pt minimum tap target
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("modelRow_download_\(metadata.modelFile)")

        case .downloading, .downloadingDirectory:
            // Circular progress with cancel — per HIG progress indicators
            Button {
                onCancelTap?()
            } label: {
                ZStack {
                    Circle()
                        .stroke(AppColors.textTertiary.opacity(0.3), lineWidth: 2)
                    Image(systemName: "stop.fill")
                        .font(AppIconSize.xxs)
                        .foregroundStyle(AppColors.accentCyan)
                }
                .frame(width: 28, height: 28)
                .frame(width: 44, height: 44) // Expanded tap target
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel download")
            .accessibilityIdentifier("modelRow_cancel_\(metadata.modelFile)")

        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .font(AppIconSize.lg)
                .foregroundStyle(AppColors.success)
                .frame(width: 44, height: 44)
                .accessibilityLabel("Downloaded")
                .accessibilityIdentifier("modelRow_downloaded_\(metadata.modelFile)")

        case .failed(let message):
            Button {
                onRetryTap?()
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(AppIconSize.lg)
                        .foregroundStyle(AppColors.danger)
                    Text("Retry")
                        .font(AppTypography.badge)
                        .foregroundStyle(AppColors.danger)
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Download failed: \(message). Tap to retry.")
            .accessibilityIdentifier("modelRow_retry_\(metadata.modelFile)")

        case .authRequired:
            Image(systemName: "lock.circle.fill")
                .font(AppIconSize.lg)
                .foregroundStyle(AppColors.warning)
                .frame(width: 44, height: 44)
                .accessibilityLabel("Authentication required")
                .accessibilityIdentifier("modelRow_auth_\(metadata.modelFile)")

        case .queued:
            // Clock icon for queued state
            Image(systemName: "clock.fill")
                .font(AppIconSize.lg)
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 44, height: 44)
                .accessibilityLabel("Queued for download")
                .accessibilityIdentifier("modelRow_queued_\(metadata.modelFile)")

        case .paused, .pausedDirectory:
            // Resume button for paused state
            Button {
                onResumeTap?()
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(AppIconSize.lg)
                    .foregroundStyle(AppColors.accentCyan)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Resume download")
            .accessibilityIdentifier("modelRow_resume_\(metadata.modelFile)")
        }
    }

    // MARK: - Helpers

    /// Formatted file size string.
    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: metadata.sizeInBytes, countStyle: .file)
    }
}
#endif
