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

// MARK: - iOS Model Hub View

/// The primary model management experience on iPhone.
///
/// Architecture (per Apple HIG "Lists and Tables" + "Toolbars"):
/// - `List` with `.insetGrouped` style — HIG: "Prefer displaying text in a list"
/// - Three user-facing sections:
///   1. "Now Running" — the currently loaded model (0-1 items)
///   2. "On This Device" — downloaded + actively downloading models
///   3. "Get More Models" — HuggingFace community browser with live search
/// - `.searchable` integration — bottom-aligned on iPhone in iOS 26+
/// - Swipe actions — trailing delete, leading load (HIG-confirmed API)
/// - Pull-to-refresh — HIG: "A refresh control lets people immediately reload content"
/// - Large title — HIG: "Use a large title to help people stay oriented"
///
/// Haptic feedback:
/// - `.sensoryFeedback(.success)` on model load completion
///
/// Accessibility: Every interactive element has `.accessibilityIdentifier`.
struct iOSModelHubView: View {
    @Environment(ConversationViewModel.self) private var viewModel
    @State private var searchText = ""
    @State private var modelToDelete: ModelMetadata?
    @State private var showDeleteConfirmation = false
    @State private var sortOrder: ModelSortOrder = .recommended

    @State private var showURLImport = false
    @State private var browser = HFModelBrowser()
    @State private var communitySearchQuery = ""
    @State private var communitySearchResults: [HFModelInfo] = []
    @State private var isCommunitySearching = false

    // MARK: - Computed Collections

    /// The currently loaded model's metadata, if any.
    private var activeModel: ModelMetadata? {
        viewModel.activeModelMetadata
    }

    /// Models that exist on disk (downloaded or discovered), excluding the active model.
    private var onDeviceModels: [(metadata: ModelMetadata, url: URL, state: ModelDownloadManager.DownloadState)] {
        var results: [(ModelMetadata, URL, ModelDownloadManager.DownloadState)] = []

        // Include discovered models (on-disk .litertlm files)
        for discovered in viewModel.discoveredModels {
            guard let metadata = discovered.metadata else { continue }
            // Skip the active model — it's in "Now Running"
            if metadata.modelFile == activeModel?.modelFile { continue }
            // Apply search filter
            if !matchesSearch(metadata) { continue }
            results.append((metadata, discovered.url, .downloaded(discovered.url)))
        }

        // Include models that are actively downloading, queued, or paused
        for model in ModelRegistry.knownModels {
            let state = viewModel.downloadManager.checkState(for: model)
            switch state {
            case .downloading(let progress):
                if !matchesSearch(model) { continue }
                if results.contains(where: { $0.0.modelFile == model.modelFile }) { continue }
                results.append((model, URL(fileURLWithPath: ""), .downloading(progress: progress)))
            case .downloadingDirectory(let progress, let completed, let total):
                if !matchesSearch(model) { continue }
                if results.contains(where: { $0.0.modelFile == model.modelFile }) { continue }
                results.append((model, URL(fileURLWithPath: ""), .downloadingDirectory(progress: progress, completedFiles: completed, totalFiles: total)))
            case .queued(let position):
                if !matchesSearch(model) { continue }
                if results.contains(where: { $0.0.modelFile == model.modelFile }) { continue }
                results.append((model, URL(fileURLWithPath: ""), .queued(position: position)))
            case .paused(let data, let progress):
                if !matchesSearch(model) { continue }
                if results.contains(where: { $0.0.modelFile == model.modelFile }) { continue }
                results.append((model, URL(fileURLWithPath: ""), .paused(resumeData: data, progress: progress)))
            case .pausedDirectory(let progress, let completed, let total):
                if !matchesSearch(model) { continue }
                if results.contains(where: { $0.0.modelFile == model.modelFile }) { continue }
                results.append((model, URL(fileURLWithPath: ""), .pausedDirectory(progress: progress, completedFiles: completed, totalFiles: total)))
            default:
                break
            }
        }

        return sortModels(results)
    }

    /// Community models to display — search results when searching, otherwise the default listing.
    private var displayedCommunityModels: [HFModelInfo] {
        if communitySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return browser.discoveredModels
        }
        return communitySearchResults
    }

    // MARK: - Body

    var body: some View {
        modelList
            .listStyle(.insetGrouped)
            // FB14832017: .searchable text clipping in Liquid Glass (iOS 26 beta).
            // Search bar text truncates when the bar collapses into the navigation
            // title area. No API workaround exists; filed as Apple Feedback.
            .searchable(text: $searchText, prompt: "Search models…")
            .searchToolbarBehavior(.minimize)
            .refreshable {
                viewModel.refreshDiscoveredModels()
                viewModel.downloadManager.refreshStates()
                await browser.refreshGemmaModels()
            }
            .navigationDestination(for: ModelMetadata.self) { metadata in
                iOSModelDetailView(metadata: metadata)
            }
            .navigationDestination(for: ModelSource.self) { source in
                switch source {
                case .onDevice(let metadata):
                    iOSModelDetailView(metadata: metadata)
                case .huggingFace(let hfModel):
                    iOSHFModelDetailView(
                        model: hfModel,
                        format: browser.detectFormat(hfModel),
                        modelSize: browser.modelSize(hfModel)
                    )
                }
            }
            .sensoryFeedback(.success, trigger: viewModel.isEngineReady)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    sortMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showURLImport = true
                    } label: {
                        Image(systemName: "link.badge.plus")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .accessibilityLabel("Import model from URL")
                    .accessibilityIdentifier("modelHub_urlImport")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    addModelButton
                }
            }
            .alert("Delete Model?", isPresented: $showDeleteConfirmation, presenting: modelToDelete) { model in
                Button("Delete", role: .destructive) {
                    deleteModel(model)
                }
                .accessibilityIdentifier("button_deleteConfirmAlert")
                Button("Cancel", role: .cancel) {}
                    .accessibilityIdentifier("button_deleteCancelAlert")
            } message: { model in
                Text("This will remove \"\(model.name)\" from your device. You can re-download it later.")
            }

            .sheet(isPresented: $showURLImport) {
                iOSURLImportSheet()
            }
            .accessibilityIdentifier("iOSModelHub")
            .onAppear {
                // Refresh model state on every tab visit — not just pull-to-refresh —
                // so the Models tab always shows current filesystem and engine state.
                viewModel.refreshDiscoveredModels()
                viewModel.downloadManager.refreshStates()
            }
            .task {
                if browser.discoveredModels.isEmpty {
                    await browser.refreshGemmaModels()
                }
            }
    }

    // MARK: - List

    private var modelList: some View {
        List {
            nowRunningSection
            onThisDeviceSection
            getMoreModelsSection
            storageFooter
        }
    }

    // MARK: - Now Running Section

    @ViewBuilder
    private var nowRunningSection: some View {
        if let active = activeModel, viewModel.isEngineReady {
            Section {
                NavigationLink(value: active) {
                    activeModelRow(active)
                }
                .glassEffect(in: .rect(cornerRadius: AppRadius.md))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button {
                        Task { await viewModel.shutdown() }
                    } label: {
                        Label("Unload", systemImage: "eject")
                    }
                    .tint(AppColors.warning)
                }
            } header: {
                Label("Now Running", systemImage: "bolt.fill")
                    .foregroundStyle(AppColors.accentPrimary)
            }
        }
    }

    // MARK: - On This Device Section

    @ViewBuilder
    private var onThisDeviceSection: some View {
        let models = onDeviceModels
        if !models.isEmpty {
            Section("On This Device") {
                ForEach(models, id: \.metadata.modelFile) { item in
                    onDeviceModelRow(item: item)
                }
            }
        }
    }

    private func onDeviceModelRow(item: (metadata: ModelMetadata, url: URL, state: ModelDownloadManager.DownloadState)) -> some View {
        NavigationLink(value: item.metadata) {
            iOSModelRow(
                metadata: item.metadata,
                downloadState: item.state,
                onDownloadTap: {
                    viewModel.downloadManager.download(item.metadata)
                },
                onCancelTap: {
                    Task { await viewModel.downloadManager.cancelDownload(item.metadata) }
                },
                onRetryTap: {
                    viewModel.downloadManager.download(item.metadata)
                },
                onPauseTap: {
                    Task { await viewModel.downloadManager.pauseDownload(item.metadata) }
                },
                onResumeTap: {
                    viewModel.downloadManager.resumeDownload(item.metadata)
                }
            )
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                modelToDelete = item.metadata
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            loadSwipeButton(for: item.state)
        }
    }

    @ViewBuilder
    private func loadSwipeButton(for state: ModelDownloadManager.DownloadState) -> some View {
        if case .downloaded(let url) = state {
            Button {
                Task { await viewModel.handleModelSelection(url) }
            } label: {
                Label("Load", systemImage: "bolt")
            }
            .tint(AppColors.accentPrimary)
        }
    }

    // MARK: - Get More Models Section (Community Browser)

    @ViewBuilder
    private var getMoreModelsSection: some View {
        Section {
            // Community search bar
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppColors.textTertiary)
                    .font(AppIconSize.xs)
                TextField("Search HuggingFace models…", text: $communitySearchQuery)
                    .textFieldStyle(.plain)
                    .font(AppTypography.listSubtitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .onSubmit {
                        guard !communitySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        Task { await performCommunitySearch() }
                    }
                    .accessibilityIdentifier("communityModels_iOS_searchField")
                if isCommunitySearching {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(AppColors.accentPrimary)
                }
                if !communitySearchQuery.isEmpty {
                    Button {
                        communitySearchQuery = ""
                        communitySearchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppColors.textTertiary)
                            .font(AppIconSize.xs)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("communityModels_iOS_clearSearch")
                }
            }

            // Community model rows
            if let error = browser.lastError {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(AppColors.warning)
                    Text(error)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(2)
                }
                .accessibilityIdentifier("communityModels_iOS_error")
            } else if browser.discoveredModels.isEmpty && !browser.isLoading {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppColors.textTertiary)
                    Text("No models found. Pull to refresh.")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
            } else {
                ForEach(displayedCommunityModels) { model in
                    NavigationLink(value: ModelSource.huggingFace(model)) {
                        communityModelRow(model: model)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            HStack {
                Text("Get More Models")
                Spacer()
                if browser.isLoading {
                    ProgressView()
                        .controlSize(.mini)
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
                .accessibilityIdentifier("communityModels_iOS_refresh")
            }
        } footer: {
            Text("Browse and download models from HuggingFace for private, offline inference.")
                .font(AppTypography.listTertiary)
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    /// A single community model row for the iOS list.
    private func communityModelRow(model: HFModelInfo) -> some View {
        let format = browser.detectFormat(model)
        let modelSize = browser.modelSize(model)

        return HStack(spacing: AppSpacing.md) {
            // Format icon
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.sm)
                    .fill(formatColor(format).opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.sm)
                            .stroke(formatColor(format).opacity(0.3), lineWidth: AppLineWidth.hairline)
                    )
                Image(systemName: format == .mlx ? "cpu" : "shippingbox")
                    .font(AppIconSize.md)
                    .foregroundStyle(formatColor(format))
            }
            .frame(width: 36, height: 36)

            // Model info
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(model.displayName)
                    .font(AppTypography.listTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                HStack(spacing: AppSpacing.sm) {
                    // Format badge
                    Text(formatLabel(format))
                        .font(AppTypography.badge)
                        .foregroundStyle(formatColor(format))

                    // Organization
                    Text(model.orgName)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                }

                HStack(spacing: AppSpacing.sm) {
                    // Downloads
                    Label(formatCount(model.downloads), systemImage: "arrow.down.circle")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)

                    // Size
                    if let size = modelSize {
                        Label(ByteCountFormatter.string(fromByteCount: size, countStyle: .file), systemImage: "doc")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }

            Spacer()

            // Download action
            communityDownloadButton(model: model, format: format)
        }
        .padding(.vertical, AppSpacing.listRowVertical)
        .accessibilityIdentifier("communityModel_iOS_\(model.id.replacingOccurrences(of: "/", with: "_"))")
    }

    /// Download button for a community model row, state-aware.
    @ViewBuilder
    private func communityDownloadButton(model: HFModelInfo, format: HFModelFormat) -> some View {
        let state = communityDownloadState(model: model, format: format)

        switch state {
        case .notDownloaded:
            Button {
                triggerCommunityDownload(model: model, format: format)
            } label: {
                Image(systemName: "arrow.down.circle.fill")
                    .font(AppIconSize.lg)
                    .foregroundStyle(formatColor(format))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("communityDownload_iOS_\(model.id.replacingOccurrences(of: "/", with: "_"))")

        case .downloading(let progress):
            ProgressView(value: progress)
                .tint(AppColors.accentPrimary)
                .frame(width: 36)

        case .downloadingDirectory(let progress, _, _):
            ProgressView(value: progress)
                .tint(AppColors.accentSecondary)
                .frame(width: 36)

        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .font(AppIconSize.lg)
                .foregroundStyle(AppColors.success)

        case .failed:
            Button {
                triggerCommunityDownload(model: model, format: format)
            } label: {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(AppIconSize.lg)
                    .foregroundStyle(AppColors.destructive)
            }
            .buttonStyle(.plain)

        default:
            EmptyView()
        }
    }

    // MARK: - Toolbar

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $sortOrder) {
                Label("Recommended", systemImage: "star").tag(ModelSortOrder.recommended)
                Label("Name", systemImage: "textformat").tag(ModelSortOrder.name)
                Label("Size", systemImage: "arrow.up.arrow.down").tag(ModelSortOrder.size)
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .foregroundStyle(AppColors.textSecondary)
        }
        .accessibilityLabel("Sort models")
        .accessibilityIdentifier("modelHub_sort")
    }

    private var addModelButton: some View {
        Button {
            viewModel.isFilePickerPresented = true
        } label: {
            Image(systemName: "plus")
                .foregroundStyle(AppColors.textSecondary)
        }
        .accessibilityLabel("Add model from file")
        .accessibilityIdentifier("modelHub_addModel")
    }

    // MARK: - Active Model Row

    private func activeModelRow(_ metadata: ModelMetadata) -> some View {
        HStack(spacing: AppSpacing.md) {
            // Leading: Pulsing indicator
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.sm)
                    .fill(AppColors.accentPrimaryTint)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.sm)
                            .stroke(AppColors.accentPrimaryBorder, lineWidth: AppLineWidth.hairline)
                    )
                Image(systemName: "bolt.fill")
                    .font(AppIconSize.lg)
                    .foregroundStyle(AppColors.accentPrimary)
            }
            .frame(width: 40, height: 40)
            .pulsingGlow(AppColors.accentPrimary)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(metadata.name)
                    .font(AppTypography.listTitle)
                    .foregroundStyle(AppColors.accentPrimary)
                    .lineLimit(1)

                HStack(spacing: AppSpacing.xs) {
                    if let result = viewModel.backendResult {
                        Text(result.activeBackend == .gpu ? "GPU" : "CPU")
                            .font(AppTypography.badge)
                            .foregroundStyle(result.activeBackend == .gpu ? AppColors.success : AppColors.warning)
                    }

                    if let metrics = viewModel.performanceMetrics {
                        Text(String(format: "%.1f tok/s", metrics.tokensPerSecond))
                            .font(AppTypography.badge)
                            .foregroundStyle(PerformanceTier(decodeSpeed: metrics.tokensPerSecond).color)
                    }
                }

                // Capability badges
                HStack(spacing: AppSpacing.xs) {
                    if metadata.supportsImage {
                        Label("Vision", systemImage: "eye")
                            .font(AppTypography.badge)
                            .foregroundStyle(AppColors.capabilityVision)
                            .accessibilityIdentifier("activeModel_badge_vision")
                    }
                    if metadata.supportsAudio {
                        Label("Audio", systemImage: "waveform")
                            .font(AppTypography.badge)
                            .foregroundStyle(AppColors.capabilityAudio)
                            .accessibilityIdentifier("activeModel_badge_audio")
                    }
                }
            }

            Spacer()

            // Ready indicator
            Circle()
                .fill(AppColors.success)
                .frame(width: AppSize.dotXl, height: AppSize.dotXl)
                .pulsingGlow(AppColors.success)
        }
        .padding(.vertical, AppSpacing.listRowVertical)
        .accessibilityIdentifier("modelHub_activeModel")
    }

    // MARK: - Storage Footer

    @ViewBuilder
    private var storageFooter: some View {
        let totalSize = viewModel.discoveredModels.reduce(Int64(0)) { $0 + $1.sizeInBytes }
        if totalSize > 0 {
            Section {
                HStack {
                    Image(systemName: "internaldrive")
                        .foregroundStyle(AppColors.textTertiary)
                    Text("Models on device: \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))")
                        .font(AppTypography.listTertiary)
                        .foregroundStyle(AppColors.textTertiary)
                }
                .accessibilityIdentifier("modelHub_storageFooter")
                .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: - Helpers

    private func matchesSearch(_ metadata: ModelMetadata) -> Bool {
        guard !searchText.isEmpty else { return true }
        let query = searchText.lowercased()
        return metadata.name.lowercased().contains(query)
            || metadata.architectureType.lowercased().contains(query)
            || metadata.description.lowercased().contains(query)
    }

    private func sortModels(_ models: [(ModelMetadata, URL, ModelDownloadManager.DownloadState)]) -> [(metadata: ModelMetadata, url: URL, state: ModelDownloadManager.DownloadState)] {
        switch sortOrder {
        case .recommended:
            return models // Keep registry order (flagship first)
        case .name:
            return models.sorted { $0.0.name < $1.0.name }
        case .size:
            return models.sorted { $0.0.sizeInBytes < $1.0.sizeInBytes }
        }
    }



    /// Delete a model using the centralized download manager.
    private func deleteModel(_ metadata: ModelMetadata) {
        viewModel.downloadManager.deleteModel(metadata)

        // Refresh the model list
        viewModel.refreshDiscoveredModels()
        viewModel.downloadManager.refreshStates()
    }

    /// Execute a HuggingFace community search.
    private func performCommunitySearch() async {
        isCommunitySearching = true
        do {
            communitySearchResults = try await browser.searchModels(query: communitySearchQuery)
        } catch {
            communitySearchResults = []
        }
        isCommunitySearching = false
    }

    /// Get the download state for a community model.
    private func communityDownloadState(model: HFModelInfo, format: HFModelFormat) -> ModelDownloadManager.DownloadState {
        if format == .mlx {
            let dirName = model.id.replacingOccurrences(of: "/", with: "--")
            return viewModel.downloadManager.downloadStates[dirName] ?? .notDownloaded
        }
        if let sibling = communityLitertlmSibling(for: model, format: format) {
            return viewModel.downloadManager.downloadStates[sibling.rfilename] ?? .notDownloaded
        }
        return .notDownloaded
    }

    /// Find the .litertlm sibling for a community model.
    private func communityLitertlmSibling(for model: HFModelInfo, format: HFModelFormat) -> HFSibling? {
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

    /// Trigger a download for a community model.
    private func triggerCommunityDownload(model: HFModelInfo, format: HFModelFormat) {
        if format == .litertlm {
            if let sibling = communityLitertlmSibling(for: model, format: format) {
                viewModel.downloadManager.downloadCommunityModel(model: model, sibling: sibling)
            }
        } else if format == .mlx {
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
        }
    }

    /// Format color for a model format.
    private func formatColor(_ format: HFModelFormat) -> Color {
        switch format {
        case .litertlm: AppColors.success
        case .mlx: AppColors.accentSecondary
        case .gguf: AppColors.accentPrimary
        case .unknown: AppColors.textTertiary
        }
    }

    /// Format label for a model format.
    private func formatLabel(_ format: HFModelFormat) -> String {
        switch format {
        case .litertlm: "LiteRT"
        case .mlx: "MLX"
        case .gguf: "GGUF"
        case .unknown: "Unknown"
        }
    }

    /// Format large counts with K/M suffix.
    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

// MARK: - Sort Order

enum ModelSortOrder: String, CaseIterable {
    case recommended
    case name
    case size
}
#endif
