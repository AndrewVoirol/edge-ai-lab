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

// MARK: - Community Models Browser

/// Browseable grid of HuggingFace community models using `HFModelBrowser` API.
///
/// Shows a loading state while fetching, an error state on failure,
/// or a grid of `HFModelCard` views on success.
///
/// Extracted from `DetailColumnView.swift` for reusability. Used in:
/// - macOS `ModelDetailPanel` empty state (when no model is selected)
/// - Future: macOS sidebar community section
struct CommunityModelsBrowser: View {
    @State private var browser = HFModelBrowser()
    @State private var inlineURL: String = ""
    @State private var searchQuery: String = ""
    @State private var searchResults: [HFModelInfo] = []
    @State private var isSearching: Bool = false
    @State private var selectedBrowserModel: HFModelInfo?
    @State private var browserFormat: HFModelFormat = .unknown
    @State private var browserModelSize: Int64?
    @Environment(ConversationViewModel.self) private var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if selectedBrowserModel != nil {
                browserModelDetail
            } else {
                browserGridContent
            }
        }
        .task {
            if browser.discoveredModels.isEmpty {
                await browser.refreshGemmaModels()
            }
        }
        .accessibilityIdentifier("communityModelsBrowser")
    }

    // MARK: - Browser Grid Content

    @ViewBuilder
    private var browserGridContent: some View {
        // Section header
        HStack {
            Image(systemName: "globe")
                .foregroundStyle(AppColors.accentPrimary)
            Text("Community Models")
                .font(AppTypography.sectionHeader)
                .foregroundStyle(AppColors.textSecondary)
            Spacer()

            if browser.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(AppColors.accentPrimary)
            }

            Button {
                Task { await browser.refreshGemmaModels() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(AppIconSize.xs)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .buttonStyle(.plain)
            .help("Refresh community models")
            .accessibilityIdentifier("button_refreshCommunityModels")
        }

        // Search bar
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColors.textTertiary)
                .font(AppIconSize.xs)
            TextField("Search all HuggingFace models…", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(AppTypography.listSubtitle)
                .foregroundStyle(AppColors.textPrimary)
                .onSubmit {
                    guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    Task { await performSearch() }
                }
                .accessibilityIdentifier("communityModels_searchField")
            if isSearching {
                ProgressView()
                    .controlSize(.mini)
                    .tint(AppColors.accentPrimary)
            }
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppColors.textTertiary)
                        .font(AppIconSize.xs)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("communityModels_clearSearch")
            }
        }
        .padding(AppSpacing.sm)
        .padding(.horizontal, AppSpacing.xs)
        .background(AppColors.backgroundTertiary.opacity(AppOpacity.half))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))

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
            // Getting Started banner for users with no local models
            if viewModel.discoveredModels.isEmpty {
                VStack(spacing: AppSpacing.sm) {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "sparkles")
                            .font(AppIconSize.md)
                            .foregroundStyle(AppColors.accentSecondary)
                        Text("Getting Started")
                            .font(AppTypography.sectionHeader)
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                    }

                    Text("No models downloaded yet. We recommend starting with **Gemma 4 E2B** — it's lightweight, fast, and supports multimodal input (images + audio).")
                        .font(AppTypography.listSubtitle)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(AppSpacing.md)
                .glassCard(cornerRadius: AppRadius.lg)
                .accessibilityIdentifier("browser_gettingStarted")
            }
            // Inline URL import — paste a HuggingFace URL to import any model
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "link.badge.plus")
                    .foregroundStyle(AppColors.accentPrimary)
                TextField("Paste a HuggingFace URL…", text: $inlineURL)
                    .textFieldStyle(.plain)
                    .font(AppTypography.listSubtitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .onSubmit {
                        guard !inlineURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        viewModel.startURLImport(inlineURL)
                        inlineURL = ""
                    }
                    .accessibilityIdentifier("urlPaste_inlineField")
                if !inlineURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        viewModel.startURLImport(inlineURL)
                        inlineURL = ""
                    } label: {
                        Text("Import")
                            .font(AppTypography.badge)
                            .foregroundStyle(AppColors.textPrimary)
                            .padding(.horizontal, AppSpacing.sm)
                            .padding(.vertical, AppSpacing.xs)
                            .background(AppColors.accentPrimary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("urlPaste_importButton")
                }
            }
            .padding(AppSpacing.md)
            .glassCard(cornerRadius: AppRadius.md)
            .accessibilityIdentifier("urlPaste_inlineContainer")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.md) {
                ForEach(displayedModels) { model in
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
                        },
                        onDownloadMLXModel: { mlxModel in
                            Task {
                                do {
                                    let manifest = try await browser.fetchFileManifest(for: mlxModel.id)
                                    let required = HFModelBrowser.filterRequiredMLXFiles(manifest)
                                    let descriptors = HFModelBrowser.downloadDescriptors(
                                        repoId: mlxModel.id,
                                        requiredFiles: required
                                    )
                                    viewModel.downloadManager.downloadMLXModel(
                                        modelId: mlxModel.id,
                                        descriptors: descriptors
                                    )
                                } catch {
                                    viewModel.statusMessage = "Failed to fetch model manifest: \(error.localizedDescription)"
                                }
                            }
                        }
                    )
                    .onTapGesture {
                        selectedBrowserModel = model
                        browserFormat = browser.detectFormat(model)
                        browserModelSize = browser.modelSize(model)
                    }
                }
            }
        }
    }

    // MARK: - Browser Model Detail

    @ViewBuilder
    private var browserModelDetail: some View {
        if let model = selectedBrowserModel {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    // Back button
                    Button {
                        selectedBrowserModel = nil
                    } label: {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "chevron.left")
                            Text("Browse Models")
                                .font(AppTypography.subtitle)
                        }
                        .foregroundStyle(AppColors.accentPrimary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("browserDetail_backButton")

                    // Model name (large title)
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text(model.displayName)
                            .font(AppTypography.pageTitle)
                            .foregroundStyle(AppColors.textPrimary)
                            .accessibilityIdentifier("browserDetail_name")

                        // Organization
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "building.2")
                                .font(AppIconSize.xs)
                                .foregroundStyle(AppColors.textTertiary)
                            Text(model.orgName)
                                .font(AppTypography.subtitle)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .accessibilityIdentifier("browserDetail_org")

                        // Format badge
                        browserFormatBadge
                    }

                    // Stats row
                    HStack(spacing: AppSpacing.lg) {
                        browserStatCell(
                            label: "Downloads",
                            value: formatBrowserCount(model.downloads),
                            icon: "arrow.down.circle",
                            color: AppColors.accentPrimary
                        )
                        browserStatCell(
                            label: "Likes",
                            value: "\(model.likes)",
                            icon: "heart",
                            color: AppColors.destructive
                        )
                        if let size = browserModelSize {
                            browserStatCell(
                                label: "File Size",
                                value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file),
                                icon: "doc.zipper",
                                color: AppColors.accentSecondary
                            )
                        }
                    }
                    .padding(AppSpacing.md)
                    .glassCard(cornerRadius: AppRadius.lg)

                    // Tags section
                    browserTagsSection(model: model)

                    // Quantization info
                    if let quant = model.quantizationInfo {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text("Quantization")
                                .font(AppTypography.sectionHeader)
                                .foregroundStyle(AppColors.textSecondary)

                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: "cpu")
                                    .foregroundStyle(AppColors.accentPrimary)
                                Text(quant.uppercased())
                                    .font(AppTypography.metric)
                                    .foregroundStyle(AppColors.accentPrimary)
                            }
                            .padding(AppSpacing.md)
                            .glassCard(cornerRadius: AppRadius.md)
                        }
                    }

                    // Download / Load actions
                    browserDetailActions(model: model)

                    Spacer(minLength: AppSpacing.xl)
                }
                .padding(AppSpacing.lg)
            }
        }
    }

    // MARK: - Detail Subviews

    /// Format badge for the detail view.
    @ViewBuilder
    private var browserFormatBadge: some View {
        let (text, color): (String, Color) = switch browserFormat {
        case .litertlm: ("LiteRT", AppColors.engineLiteRT)
        case .mlx: ("MLX", AppColors.engineMLX)
        case .gguf: ("GGUF", AppColors.engineGGUF)
        case .unknown: ("Unknown", AppColors.textTertiary)
        }
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "gearshape.2")
                .font(AppIconSize.xs)
            Text(text)
                .font(AppTypography.badge)
        }
        .foregroundStyle(color)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(color.opacity(AppOpacity.rinse))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
        .accessibilityIdentifier("browserDetail_formatBadge")
    }

    /// Stat cell for the detail stats row.
    private func browserStatCell(
        label: String,
        value: String,
        icon: String,
        color: Color
    ) -> some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(AppIconSize.md)
                .foregroundStyle(color)
            Text(value)
                .font(AppTypography.metric)
                .foregroundStyle(AppColors.textPrimary)
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Tags section showing relevant tags from the model.
    @ViewBuilder
    private func browserTagsSection(model: HFModelInfo) -> some View {
        let relevantTags = model.tags.filter { tag in
            let lower = tag.lowercased()
            // Filter out generic/internal tags, keep informative ones
            return !lower.hasPrefix("arxiv:") && !lower.hasPrefix("doi:")
                && lower != "text-generation" && lower != "transformers"
                && !lower.isEmpty
        }

        if !relevantTags.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Tags")
                    .font(AppTypography.sectionHeader)
                    .foregroundStyle(AppColors.textSecondary)

                FlowLayout(spacing: AppSpacing.xs) {
                    ForEach(relevantTags.prefix(12), id: \.self) { tag in
                        Text(tag)
                            .font(AppTypography.badge)
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.horizontal, AppSpacing.sm)
                            .padding(.vertical, AppSpacing.xxs)
                            .background(AppColors.backgroundTertiary.opacity(AppOpacity.prominent))
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                    }
                }
            }
            .padding(AppSpacing.md)
            .glassCard(cornerRadius: AppRadius.lg)
        }
    }

    /// Download and Load action buttons for the detail view.
    @ViewBuilder
    private func browserDetailActions(model: HFModelInfo) -> some View {
        VStack(spacing: AppSpacing.md) {
            if browserFormat == .litertlm {
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
                            .background(AppColors.accentPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("browserDetail_downloadButton")
                    }

                case .downloading(let progress):
                    VStack(spacing: AppSpacing.sm) {
                        ProgressView(value: progress)
                            .tint(AppColors.accentPrimary)
                        Text("Downloading… \(Int(progress * 100))%")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(AppSpacing.md)
                    .glassCard(cornerRadius: AppRadius.md)

                case .downloaded(let url):
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppColors.success)
                        Text("Downloaded")
                            .font(AppTypography.subtitle)
                            .foregroundStyle(AppColors.success)
                    }
                    .padding(AppSpacing.md)
                    .glassCard(cornerRadius: AppRadius.md)

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
                        .background(AppColors.accentPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("browserDetail_loadButton")

                case .failed(let message):
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppColors.destructive)
                        Text(message)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.destructive)
                            .lineLimit(2)
                    }
                    .padding(AppSpacing.md)
                    .glassCard(cornerRadius: AppRadius.md)

                default:
                    EmptyView()
                }

            } else if browserFormat == .mlx {
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
                        .background(AppColors.accentSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("browserDetail_downloadButton")

                case .downloadingDirectory(let progress, let completed, let total):
                    VStack(spacing: AppSpacing.sm) {
                        ProgressView(value: progress)
                            .tint(AppColors.accentSecondary)
                        Text("\(completed)/\(total) files · \(Int(progress * 100))%")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(AppSpacing.md)
                    .glassCard(cornerRadius: AppRadius.md)

                case .downloaded:
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppColors.success)
                        Text("Downloaded")
                            .font(AppTypography.subtitle)
                            .foregroundStyle(AppColors.success)
                    }
                    .padding(AppSpacing.md)
                    .glassCard(cornerRadius: AppRadius.md)

                default:
                    EmptyView()
                }
            }
        }
    }

    // MARK: - Helpers

    /// Models to display — search results when searching, otherwise the default listing.
    private var displayedModels: [HFModelInfo] {
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return browser.discoveredModels
        }
        return searchResults
    }

    /// Execute a HuggingFace search across all models.
    private func performSearch() async {
        isSearching = true
        do {
            searchResults = try await browser.searchModels(query: searchQuery)
        } catch {
            // Silently fall back to default listing on search failure
            searchResults = []
        }
        isSearching = false
    }

    /// Find the .litertlm sibling for a given model.
    private func litertlmSibling(for model: HFModelInfo) -> HFSibling? {
        if let sibling = model.siblings?.first(where: { $0.rfilename.hasSuffix(".litertlm") }) {
            return sibling
        }
        if browserFormat == .litertlm {
            let repoName = model.id.split(separator: "/").last.map(String.init) ?? model.id
            let baseName = repoName
                .replacingOccurrences(of: "-litert-lm", with: "")
                .replacingOccurrences(of: "-litert_lm", with: "")
            return HFSibling(rfilename: "\(baseName).litertlm", size: nil, lfs: nil)
        }
        return nil
    }

    /// Format a large count with K/M suffix.
    private func formatBrowserCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}
