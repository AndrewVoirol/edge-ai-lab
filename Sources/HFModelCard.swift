import SwiftUI

/// Card view for displaying a HuggingFace model in the browser.
///
/// Shows the model's display name, organization, download/like stats,
/// quantization badge, format badge, and a download action button.
/// Uses the Dark Forest design system tokens throughout.
///
/// - Note: The download button action is a no-op stub — it will be
///   wired to `ModelDownloadManager` in a future integration pass.
struct HFModelCard: View {
    let model: HFModelInfo
    let format: HFModelFormat
    let modelSize: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Header row: display name + format badge
            HStack {
                Text(model.displayName)
                    .font(.system(.headline, design: .default, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                Spacer()

                formatBadge
            }

            // Organization
            Text(model.orgName)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)

            // Stats row: downloads + likes + size
            HStack(spacing: AppSpacing.lg) {
                // Downloads
                Label(formatDownloads(model.downloads), systemImage: "arrow.down.circle")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)

                // Likes
                Label("\(model.likes)", systemImage: "heart")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)

                // Size
                if let size = modelSize {
                    Label(formatBytes(size), systemImage: "doc")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()
            }

            // Quantization info if available
            if let quant = model.quantizationInfo {
                Text(quant.uppercased())
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(AppColors.accentTeal)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, 2)
                    .background(AppColors.accentTeal.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
            }

            // Action button
            HStack {
                Spacer()
                actionButton
            }
        }
        .padding(AppSpacing.md)
        .glassCard(cornerRadius: AppRadius.lg)
        .interactiveHover()
        .accessibilityIdentifier("hf_model_card_\(model.id.replacingOccurrences(of: "/", with: "_"))")
    }

    // MARK: - Format Badge

    /// Format badge colored by runtime: LiteRT = green, MLX = amber, Unknown = gray.
    @ViewBuilder
    private var formatBadge: some View {
        let (text, color): (String, Color) = switch format {
        case .litertlm: ("LiteRT", AppColors.success)
        case .mlx: ("MLX", AppColors.accentGold)
        case .unknown: ("Unknown", AppColors.textTertiary)
        }
        Text(text)
            .font(.system(.caption2, design: .monospaced, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
    }

    // MARK: - Action Button

    /// Download button for LiteRT models, or "Coming Soon" label for other formats.
    @ViewBuilder
    private var actionButton: some View {
        if format == .litertlm {
            Button {
                // Download action will be wired up later
            } label: {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Download")
                        .font(AppTypography.caption)
                }
                .foregroundStyle(AppColors.accentTeal)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xs)
                .background(AppColors.accentTeal.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("hf_download_\(model.id.replacingOccurrences(of: "/", with: "_"))")
        } else {
            Text("Coming Soon")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xs)
                .background(AppColors.textTertiary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
        }
    }

    // MARK: - Formatting Helpers

    /// Format bytes to human-readable string (e.g., "1.2 GB").
    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Format download count with K/M suffixes (e.g., 12345 → "12.3K").
    private func formatDownloads(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}
