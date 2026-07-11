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

// MARK: - iOS HuggingFace Model Detail View

/// iPhone-optimized detail view for a community HuggingFace model.
///
/// Pushed via `NavigationLink` from `iOSModelHubView` when the user taps a
/// community model row. Displays model metadata, download controls, and
/// load-into-engine actions for both LiteRT-LM and MLX format models.
///
/// Layout:
/// 1. Header: Display name, organization, format badge
/// 2. Stats Row: Downloads, Likes, File Size (glass card)
/// 3. Tags: Filtered relevant tags in a `FlowLayout`
/// 4. Quantization: CPU badge (if available)
/// 5. Actions: Full download/load state machine (LiteRT & MLX)
/// 6. HuggingFace Link: External link to the model page
struct iOSHFModelDetailView: View {
    let model: HFModelInfo
    let format: HFModelFormat
    let modelSize: Int64?

    @Environment(ConversationViewModel.self) private var viewModel
    @State private var browser = HFModelBrowser()

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                // 1. Header
                headerSection

                // 2. Stats Row
                statsRow

                // 3. Tags
                tagsSection

                // 4. Quantization Info
                quantizationSection

                // 5. Download / Load Actions
                actionsSection

                // 6. HuggingFace Link
                huggingFaceLink

                Spacer(minLength: AppSpacing.xl)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
        }
        .background(AppColors.backgroundPrimary)
        .navigationTitle(model.displayName)
        .navigationBarTitleDisplayMode(.large)
        .accessibilityIdentifier("hfDetail_root")
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(model.displayName)
                .font(AppTypography.pageTitle)
                .foregroundStyle(AppColors.textPrimary)
                .accessibilityIdentifier("hfDetail_name")

            // Organization
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "building.2")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
                Text(model.orgName)
                    .font(AppTypography.subtitle)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .accessibilityIdentifier("hfDetail_org")

            // Format badge
            formatBadge
        }
        .accessibilityIdentifier("hfDetail_header")
    }

    @ViewBuilder
    private var formatBadge: some View {
        let (text, color): (String, Color) = switch format {
        case .litertlm: ("LiteRT", AppColors.sprout)
        case .mlx: ("MLX", AppColors.amber)
        case .gguf: ("GGUF", AppColors.moss)
        case .unknown: ("Unknown", AppColors.textTertiary)
        }
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "gearshape.2")
                .font(.caption)
            Text(text)
                .font(AppTypography.badge)
        }
        .foregroundStyle(color)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(color.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
        .accessibilityIdentifier("hfDetail_formatBadge")
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: AppSpacing.lg) {
            statCell(
                label: "Downloads",
                value: formatCount(model.downloads),
                icon: "arrow.down.circle",
                color: AppColors.moss
            )
            statCell(
                label: "Likes",
                value: "\(model.likes)",
                icon: "heart",
                color: AppColors.ember
            )
            if let size = modelSize {
                statCell(
                    label: "File Size",
                    value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file),
                    icon: "doc.zipper",
                    color: AppColors.amber
                )
            }
        }
        .padding(AppSpacing.md)
        .glassCard(cornerRadius: AppRadius.lg)
        .accessibilityIdentifier("hfDetail_statsRow")
    }

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
        .accessibilityIdentifier("hfDetail_stat_\(label)")
    }

    // MARK: - Tags Section

    @ViewBuilder
    private var tagsSection: some View {
        let relevantTags = model.tags.filter { tag in
            let lower = tag.lowercased()
            return !lower.hasPrefix("arxiv:") && !lower.hasPrefix("doi:")
                && lower != "text-generation" && lower != "transformers"
                && !lower.isEmpty
        }

        if !relevantTags.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Tags")
                    .font(AppTypography.sectionHeader)
                    .foregroundStyle(AppColors.textSecondary)
                    .accessibilityIdentifier("hfDetail_tagsHeader")

                FlowLayout(spacing: AppSpacing.xs) {
                    ForEach(relevantTags.prefix(12), id: \.self) { tag in
                        Text(tag)
                            .font(AppTypography.badge)
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.horizontal, AppSpacing.sm)
                            .padding(.vertical, 3)
                            .background(AppColors.backgroundTertiary.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                            .accessibilityIdentifier("hfDetail_tag_\(tag)")
                    }
                }
            }
            .padding(AppSpacing.md)
            .glassCard(cornerRadius: AppRadius.lg)
            .accessibilityIdentifier("hfDetail_tagsSection")
        }
    }

    // MARK: - Quantization Info

    @ViewBuilder
    private var quantizationSection: some View {
        if let quant = model.quantizationInfo {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Quantization")
                    .font(AppTypography.sectionHeader)
                    .foregroundStyle(AppColors.textSecondary)
                    .accessibilityIdentifier("hfDetail_quantHeader")

                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "cpu")
                        .foregroundStyle(AppColors.moss)
                    Text(quant.uppercased())
                        .font(AppTypography.metric)
                        .foregroundStyle(AppColors.moss)
                }
                .padding(AppSpacing.md)
                .glassCard(cornerRadius: AppRadius.md)
            }
            .accessibilityIdentifier("hfDetail_quantSection")
        }
    }

    // MARK: - Actions Section

    @ViewBuilder
    private var actionsSection: some View {
        VStack(spacing: AppSpacing.md) {
            if format == .litertlm {
                litertlmActions
            } else if format == .mlx {
                mlxActions
            }
        }
        .accessibilityIdentifier("hfDetail_actionsSection")
    }

    // MARK: LiteRT-LM Actions

    @ViewBuilder
    private var litertlmActions: some View {
        let sibling = litertlmSibling(for: model)
        let state = sibling.map { viewModel.downloadManager.downloadStates[$0.rfilename] ?? .notDownloaded }
            ?? .notDownloaded

        switch state {
        case .notDownloaded:
            if let sibling {
                Button {
                    viewModel.downloadManager.downloadCommunityModel(model: model, sibling: sibling)
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Download Model")
                            .font(AppTypography.subtitle)
                    }
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(AppSpacing.md)
                    .background(AppColors.moss)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("hfDetail_downloadButton")
            }

        case .downloading(let progress):
            VStack(spacing: AppSpacing.sm) {
                ProgressView(value: progress)
                    .tint(AppColors.moss)
                Text("Downloading… \(Int(progress * 100))%")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(AppSpacing.md)
            .glassCard(cornerRadius: AppRadius.md)
            .accessibilityIdentifier("hfDetail_downloadProgress")

        case .downloaded(let url):
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.sprout)
                Text("Downloaded")
                    .font(AppTypography.subtitle)
                    .foregroundStyle(AppColors.sprout)
            }
            .padding(AppSpacing.md)
            .glassCard(cornerRadius: AppRadius.md)
            .accessibilityIdentifier("hfDetail_downloadedBadge")

            Button {
                Task {
                    await viewModel.handleModelSelection(url)
                    viewModel.refreshDiscoveredModels()
                }
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "bolt.fill")
                    Text("Load Model")
                        .font(AppTypography.subtitle)
                }
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(AppSpacing.md)
                .background(AppColors.moss)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("hfDetail_loadButton")

        case .failed(let message):
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppColors.ember)
                Text(message)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.ember)
                    .lineLimit(3)
            }
            .padding(AppSpacing.md)
            .glassCard(cornerRadius: AppRadius.md)
            .accessibilityIdentifier("hfDetail_errorBadge")

        default:
            EmptyView()
        }
    }

    // MARK: MLX Actions

    @ViewBuilder
    private var mlxActions: some View {
        let dirName = model.id.replacingOccurrences(of: "/", with: "--")
        let state = viewModel.downloadManager.downloadStates[dirName] ?? .notDownloaded

        switch state {
        case .notDownloaded:
            Button {
                Task {
                    do {
                        let manifest = try await browser.fetchFileManifest(for: model.id)
                        let required = HFModelBrowser.filterRequiredMLXFiles(manifest)
                        let descriptors = HFModelBrowser.downloadDescriptors(
                            repoId: model.id,
                            requiredFiles: required
                        )
                        viewModel.downloadManager.downloadMLXModel(
                            modelId: model.id,
                            descriptors: descriptors
                        )
                    } catch {
                        viewModel.statusMessage = "Failed to fetch model manifest: \(error.localizedDescription)"
                    }
                }
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Download Model")
                        .font(AppTypography.subtitle)
                }
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(AppSpacing.md)
                .background(AppColors.amber)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("hfDetail_downloadButton")

        case .downloadingDirectory(let progress, let completed, let total):
            VStack(spacing: AppSpacing.sm) {
                ProgressView(value: progress)
                    .tint(AppColors.amber)
                Text("\(completed)/\(total) files · \(Int(progress * 100))%")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(AppSpacing.md)
            .glassCard(cornerRadius: AppRadius.md)
            .accessibilityIdentifier("hfDetail_mlxDownloadProgress")

        case .downloaded:
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.sprout)
                Text("Downloaded")
                    .font(AppTypography.subtitle)
                    .foregroundStyle(AppColors.sprout)
            }
            .padding(AppSpacing.md)
            .glassCard(cornerRadius: AppRadius.md)
            .accessibilityIdentifier("hfDetail_mlxDownloadedBadge")

        default:
            EmptyView()
        }
    }

    // MARK: - HuggingFace Link

    private var huggingFaceLink: some View {
        Link(destination: URL(string: "https://huggingface.co/\(model.id)")!) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "link")
                    .foregroundStyle(AppColors.moss)
                Text("View on HuggingFace")
                    .font(AppTypography.subtitle)
                    .foregroundStyle(AppColors.moss)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(AppSpacing.md)
            .glassCard(cornerRadius: AppRadius.md)
        }
        .accessibilityIdentifier("hfDetail_huggingFaceLink")
    }

    // MARK: - Helpers

    /// Find the `.litertlm` sibling for a given model, or synthesize one
    /// from the repo name if the sibling list doesn't include it.
    private func litertlmSibling(for model: HFModelInfo) -> HFSibling? {
        if let sibling = model.siblings?.first(where: { $0.rfilename.hasSuffix(".litertlm") }) {
            return sibling
        }
        if format == .litertlm {
            let repoName = model.id.split(separator: "/").last.map(String.init) ?? model.id
            let baseName = repoName
                .replacingOccurrences(of: "-litert-lm", with: "")
                .replacingOccurrences(of: "-litert_lm", with: "")
            return HFSibling(rfilename: "\(baseName).litertlm", size: nil, lfs: nil)
        }
        return nil
    }

    /// Format a large count with K/M suffix.
    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}
#endif
