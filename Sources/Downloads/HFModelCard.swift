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

/// Card view for displaying a HuggingFace model in the browser.
///
/// Shows the model's display name, organization, download/like stats,
/// quantization badge, format badge, and a download action button.
/// Uses the Dark Forest design system tokens throughout.
struct HFModelCard: View {
    let model: HFModelInfo
    let format: HFModelFormat
    let modelSize: Int64?
    let downloadManager: ModelDownloadManager
    let onLoadModel: ((String, URL) -> Void)?

    /// Callback to initiate an MLX multi-file download.
    /// Parameter is the HFModelInfo to download.
    let onDownloadMLXModel: ((HFModelInfo) -> Void)?

    /// The `.litertlm` sibling file for download targeting.
    ///
    /// Priority:
    /// 1. Use actual sibling from the API response if available
    /// 2. Otherwise, infer the filename from the model ID naming convention
    ///    (e.g., "litert-community/gemma-4-E2B-it-litert-lm" → "gemma-4-E2B-it.litertlm")
    private var litertlmSibling: HFSibling? {
        // Check actual siblings first (available from detail endpoint)
        if let sibling = model.siblings?.first(where: { $0.rfilename.hasSuffix(".litertlm") }) {
            return sibling
        }

        // Infer from model ID when siblings aren't populated (list endpoint)
        if format == .litertlm {
            let repoName = model.id.split(separator: "/").last.map(String.init) ?? model.id
            // Strip "-litert-lm" suffix to get base model name, then add .litertlm extension
            let baseName = repoName
                .replacingOccurrences(of: "-litert-lm", with: "")
                .replacingOccurrences(of: "-litert_lm", with: "")
            return HFSibling(rfilename: "\(baseName).litertlm", size: nil, lfs: nil)
        }

        return nil
    }

    /// The first `.gguf` sibling file for download targeting.
    ///
    /// Excludes companion files (mmproj, MTP) — only standalone model files.
    private var ggufSibling: HFSibling? {
        model.siblings?.first(where: {
            let name = $0.rfilename.lowercased()
            return name.hasSuffix(".gguf")
                && !name.contains("mmproj")
                && !name.hasPrefix("mtp")
                && !name.contains("imatrix")
        })
    }

    /// The primary download target for this model's format.
    private var primarySibling: HFSibling? {
        switch format {
        case .litertlm: return litertlmSibling
        case .gguf: return ggufSibling
        default: return nil
        }
    }

    /// Download state for this model's file or directory.
    private var downloadState: ModelDownloadManager.DownloadState {
        if format == .mlx {
            let dirName = model.id.replacingOccurrences(of: "/", with: "--")
            return downloadManager.downloadStates[dirName] ?? .notDownloaded
        }
        guard let sibling = primarySibling else { return .notDownloaded }
        return downloadManager.downloadStates[sibling.rfilename] ?? .notDownloaded
    }

    @State private var showLoadPrompt = false
    @State private var downloadedURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Header row: display name + format badge
            HStack {
                Text(model.displayName)
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                if let params = model.parameterCountLabel {
                    Text(params)
                        .badge(AppColors.accentSecondary)
                        .accessibilityIdentifier("hf_card_params_\(model.id.replacingOccurrences(of: "/", with: "_"))")
                }

                Spacer()

                formatBadge
            }

            // Organization with avatar
            HStack(spacing: AppSpacing.xs) {
                if let encoded = model.orgName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                   let avatarURL = URL(string: "https://huggingface.co/api/organizations/\(encoded)/avatar") {
                    AsyncImage(
                        url: avatarURL
                    ) { image in
                        image.resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image(systemName: "building.2")
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .frame(width: 20, height: 20)
                    .clipShape(Circle())
                    .accessibilityHidden(true)
                } else {
                    Image(systemName: "building.2")
                        .foregroundStyle(AppColors.textTertiary)
                        .frame(width: 20, height: 20)
                }

                Text(model.orgName)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }

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

                // Size — prefer API-provided estimate, fall back to sibling-level size
                if let size = model.estimatedDownloadSize ?? modelSize {
                    Label(formatBytes(size), systemImage: "doc")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()
            }

            // Quantization info if available
            if let quant = model.quantizationInfo {
                Text(quant.uppercased())
                    .font(AppTypography.badge)
                    .foregroundStyle(AppColors.accentPrimary)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xxs)
                    .background(AppColors.accentPrimaryTint)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
            }

            // Capability badges — uses enriched metadata from Wave 1
            HStack(spacing: AppSpacing.xs) {
                if model.hasVisionSupport {
                    Label("Vision", systemImage: "eye.fill")
                        .badge(AppColors.capabilityVision)
                        .accessibilityIdentifier("hf_card_vision_\(model.id.replacingOccurrences(of: "/", with: "_"))")
                }
                if model.hasAudioSupport {
                    Label("Audio", systemImage: "waveform")
                        .badge(AppColors.capabilityAudio)
                        .accessibilityIdentifier("hf_card_audio_\(model.id.replacingOccurrences(of: "/", with: "_"))")
                }
                if model.isGated {
                    Label("Gated", systemImage: "lock.fill")
                        .badge(AppColors.warning)
                        .accessibilityIdentifier("hf_card_gated_\(model.id.replacingOccurrences(of: "/", with: "_"))")
                }
            }

            // Context window + architecture info
            if let ctxLen = model.maxContextLength, ctxLen > 0 {
                HStack(spacing: AppSpacing.sm) {
                    Label(formatContextWindow(ctxLen), systemImage: "text.word.spacing")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .accessibilityIdentifier("hf_card_context_\(model.id.replacingOccurrences(of: "/", with: "_"))")
                    if model.isMoE {
                        Label("MoE", systemImage: "point.3.filled.connected.trianglepath.dotted")
                            .badge(AppColors.accentSecondary)
                            .accessibilityIdentifier("hf_card_moe_\(model.id.replacingOccurrences(of: "/", with: "_"))")
                    }
                }
            } else if model.isMoE {
                Label("MoE", systemImage: "point.3.filled.connected.trianglepath.dotted")
                    .badge(AppColors.accentSecondary)
                    .accessibilityIdentifier("hf_card_moe_\(model.id.replacingOccurrences(of: "/", with: "_"))")
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
        .alert("Model Ready!", isPresented: $showLoadPrompt) {
            Button("Load Now") {
                if let url = downloadedURL, let sibling = litertlmSibling {
                    onLoadModel?(sibling.rfilename, url)
                }
            }
            .accessibilityIdentifier("button_loadNowAlert")
            Button("Later", role: .cancel) {}
                .accessibilityIdentifier("button_loadLaterAlert")
        } message: {
            Text("The model has been downloaded and is ready to use.")
        }
    }

    // MARK: - Format Badge

    /// Format badge colored by runtime identity (NOT status — engine colors are intentionally outside green family).
    @ViewBuilder
    private var formatBadge: some View {
        let (text, color): (String, Color) = switch format {
        case .litertlm: ("LiteRT", AppColors.engineLiteRT)
        case .mlx: ("MLX", AppColors.engineMLX)
        case .gguf: ("GGUF", AppColors.engineGGUF)
        case .unknown: ("Unknown", AppColors.textTertiary)

        }
        Text(text)
            .font(AppTypography.badge)
            .foregroundStyle(color)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xxs)
            .background(color.opacity(AppOpacity.rinse))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
    }

    // MARK: - Action Button

    /// Download button with state-aware rendering.
    @ViewBuilder
    private var actionButton: some View {
        switch downloadState {
        case .notDownloaded:
            if format == .litertlm, let sibling = litertlmSibling {
                Button {
                    downloadManager.downloadCommunityModel(model: model, sibling: sibling)
                    // Register post-download callback keyed by filename
                    downloadManager.postDownloadCallbacks[sibling.rfilename] = { filename, url in
                        downloadedURL = url
                        showLoadPrompt = true
                    }
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Download")
                            .font(AppTypography.caption)
                    }
                    .foregroundStyle(AppColors.accentPrimary)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.xs)
                    .background(AppColors.accentPrimaryFaint)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("hf_download_\(model.id.replacingOccurrences(of: "/", with: "_"))")
            } else if format == .mlx {
                // MLX multi-file download — label shows file info when available
                let sizeLabel = modelSize.map { formatBytes($0) } ?? "MLX"
                Button {
                    onDownloadMLXModel?(model)
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Download (\(sizeLabel))")
                            .font(AppTypography.caption)
                    }
                    .foregroundStyle(AppColors.accentSecondary)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.xs)
                    .background(AppColors.accentSecondary.opacity(AppOpacity.faint))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("hf_download_mlx_\(model.id.replacingOccurrences(of: "/", with: "_"))")
            } else if format == .gguf, let ggufFile = ggufSibling {
                // GGUF single-file download
                let sizeLabel = modelSize.map { formatBytes($0) } ?? "GGUF"
                Button {
                    downloadManager.downloadCommunityModel(model: model, sibling: ggufFile)
                    downloadManager.postDownloadCallbacks[ggufFile.rfilename] = { filename, url in
                        downloadedURL = url
                        showLoadPrompt = true
                    }
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Download (\(sizeLabel))")
                            .font(AppTypography.caption)
                    }
                    .foregroundStyle(AppColors.accentPrimary)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.xs)
                    .background(AppColors.accentPrimaryFaint)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("hf_download_gguf_\(model.id.replacingOccurrences(of: "/", with: "_"))")
            } else {
                Text("Unsupported Format")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.xs)
                    .background(AppColors.accentPrimaryFaint)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
            }

        case .downloading(let progress):
            VStack(spacing: AppSpacing.xxs) {
                ProgressView(value: progress)
                    .tint(AppColors.accentPrimary)
                HStack {
                    Text("\(Int(progress * 100))%")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                    Spacer()
                    Button {
                        if let sibling = primarySibling {
                            Task { await downloadManager.cancelDownload(filename: sibling.rfilename) }
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(AppIconSize.xxs)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("hf_cancelDownload_\(model.id.replacingOccurrences(of: "/", with: "_"))")
                }
            }

        case .downloaded:
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.success)
                Text("Downloaded")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.success)
            }

        case .failed(let message):
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppColors.destructive)
                    .font(AppIconSize.xxs)
                Text(message)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.destructive)
                    .lineLimit(1)
            }

        case .authRequired:
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "lock.fill")
                Text("Auth required")
            }
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.warning)

        case .queued(let position):
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "clock")
                    .foregroundStyle(AppColors.textTertiary)
                Text("Queued (#\(position))")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }

        case .paused(_, let progress):
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "pause.fill")
                    .foregroundStyle(AppColors.warning)
                Text("Paused · \(Int(progress * 100))%")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.warning)
            }

        case .downloadingDirectory(let progress, let completed, let total):
            VStack(spacing: AppSpacing.xxs) {
                ProgressView(value: progress)
                    .tint(AppColors.accentSecondary)
                HStack {
                    Text("\(completed)/\(total) files · \(Int(progress * 100))%")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                    Spacer()
                    Button {
                        downloadManager.cancelDirectoryDownload(modelId: model.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(AppIconSize.xxs)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("hf_cancelDirDownload_\(model.id.replacingOccurrences(of: "/", with: "_"))")
                }
            }

        case .pausedDirectory(let progress, let completed, let total):
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "pause.fill")
                    .foregroundStyle(AppColors.warning)
                Text("Paused · \(completed)/\(total) files · \(Int(progress * 100))%")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.warning)
            }
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

    /// Format context window size (e.g., 8192 → "8K ctx", 131072 → "128K ctx").
    private func formatContextWindow(_ tokens: Int) -> String {
        if tokens >= 1_000 {
            let k = Double(tokens) / 1_000
            if k == Double(Int(k)) {
                return "\(Int(k))K ctx"
            }
            return String(format: "%.1fK ctx", k)
        }
        return "\(tokens) ctx"
    }
}
