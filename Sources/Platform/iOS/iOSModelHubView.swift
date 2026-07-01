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
///   3. "Get More Models" — registry models not yet downloaded
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
    @State private var modelToDownload: ModelMetadata?
    @State private var showDownloadConfirmation = false
    @State private var storageCheck: ModelDownloadManager.StorageCheck?
    @State private var showURLImport = false

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

    /// Registry models that are NOT downloaded and NOT downloading.
    private var availableModels: [ModelMetadata] {
        ModelRegistry.knownModels.filter { model in
            let state = viewModel.downloadManager.checkState(for: model)
            switch state {
            case .notDownloaded, .failed, .authRequired:
                return matchesSearch(model)
            case .queued, .paused, .pausedDirectory:
                return false // Show in "On This Device" section
            default:
                return false
            }
        }
    }

    // MARK: - Body

    var body: some View {
        modelList
            .listStyle(.insetGrouped)
            // FB14832017: .searchable text clipping in Liquid Glass (iOS 26 beta).
            // Search bar text truncates when the bar collapses into the navigation
            // title area. No API workaround exists; filed as Apple Feedback.
            .searchable(text: $searchText, prompt: "Search models…")
            .refreshable {
                viewModel.refreshDiscoveredModels()
                viewModel.downloadManager.refreshStates()
            }
            .navigationDestination(for: ModelMetadata.self) { metadata in
                iOSModelDetailView(metadata: metadata)
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
                Button("Cancel", role: .cancel) {}
            } message: { model in
                Text("This will remove \"\(model.name)\" from your device. You can re-download it later.")
            }
            .confirmationDialog(
                "Download \(modelToDownload?.name ?? "")?",
                isPresented: $showDownloadConfirmation,
                presenting: modelToDownload
            ) { model in
                if let check = storageCheck, check.hasEnoughSpace {
                    Button("Download (\(check.formattedModelSize))") {
                        viewModel.downloadManager.download(model)
                    }
                } else {
                    Button("Not Enough Storage", role: .cancel) {}
                }
                Button("Cancel", role: .cancel) {}
            } message: { model in
                if let check = storageCheck {
                    if check.hasEnoughSpace {
                        Text("This will use \(check.formattedModelSize). You have \(check.formattedAvailableSpace) available.")
                    } else {
                        Text("This model requires \(check.formattedModelSize) but you only have \(check.formattedAvailableSpace) available. Free up space and try again.")
                    }
                }
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
                activeModelRow(active)
            } header: {
                Label("Now Running", systemImage: "bolt.fill")
                    .foregroundStyle(AppColors.accentCyan)
            }
        }
    }

    // MARK: - On This Device Section

    @ViewBuilder
    private var onThisDeviceSection: some View {
        if !onDeviceModels.isEmpty {
            Section("On This Device") {
                ForEach(onDeviceModels, id: \.metadata.modelFile) { item in
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
                onCancelTap: {
                    Task { await viewModel.downloadManager.cancelDownload(item.metadata) }
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
            .tint(AppColors.accentCyan)
        }
    }

    // MARK: - Get More Models Section

    @ViewBuilder
    private var getMoreModelsSection: some View {
        if !availableModels.isEmpty {
            Section {
                ForEach(availableModels) { metadata in
                    availableModelRow(metadata: metadata)
                }
            } header: {
                Text("Get More Models")
            } footer: {
                Text("Models are downloaded to your device for private, offline inference.")
                    .font(AppTypography.listTertiary)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
    }

    private func availableModelRow(metadata: ModelMetadata) -> some View {
        NavigationLink(value: metadata) {
            iOSModelRow(
                metadata: metadata,
                downloadState: viewModel.downloadManager.checkState(for: metadata),
                onDownloadTap: {
                    confirmDownload(metadata)
                },
                onRetryTap: {
                    confirmDownload(metadata)
                },
                onPauseTap: {
                    Task { await viewModel.downloadManager.pauseDownload(metadata) }
                },
                onResumeTap: {
                    viewModel.downloadManager.resumeDownload(metadata)
                }
            )
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
                    .fill(AppColors.accentCyan.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.sm)
                            .stroke(AppColors.accentCyan.opacity(0.3), lineWidth: 0.5)
                    )
                Image(systemName: "bolt.fill")
                    .font(AppIconSize.lg)
                    .foregroundStyle(AppColors.accentCyan)
            }
            .frame(width: 40, height: 40)
            .pulsingGlow(AppColors.accentCyan)

            VStack(alignment: .leading, spacing: 3) {
                Text(metadata.name)
                    .font(AppTypography.listTitle)
                    .foregroundStyle(AppColors.accentCyan)
                    .lineLimit(1)

                HStack(spacing: AppSpacing.xs) {
                    if let result = viewModel.backendResult {
                        Text(result.activeBackend == .gpu ? "GPU" : "CPU")
                            .font(AppTypography.badge)
                            .foregroundStyle(result.activeBackend == .gpu ? AppColors.success : AppColors.warning)
                    }

                    if let info = viewModel.benchmarkInfo {
                        Text(String(format: "%.1f tok/s", info.lastDecodeTokensPerSecond))
                            .font(AppTypography.badge)
                            .foregroundStyle(PerformanceTier(decodeSpeed: info.lastDecodeTokensPerSecond).color)
                    }
                }

                // Capability badges
                HStack(spacing: AppSpacing.xs) {
                    if metadata.supportsImage {
                        Label("Vision", systemImage: "eye")
                            .font(AppTypography.badge)
                            .foregroundStyle(AppColors.badgeVision)
                    }
                    if metadata.supportsAudio {
                        Label("Audio", systemImage: "waveform")
                            .font(AppTypography.badge)
                            .foregroundStyle(AppColors.badgeAudio)
                    }
                }
            }

            Spacer()

            // Ready indicator
            Circle()
                .fill(AppColors.success)
                .frame(width: 8, height: 8)
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

    /// Confirm download with storage check dialog.
    private func confirmDownload(_ metadata: ModelMetadata) {
        storageCheck = viewModel.downloadManager.checkStorage(for: metadata)
        modelToDownload = metadata
        showDownloadConfirmation = true
    }

    /// Delete a model using the centralized download manager.
    private func deleteModel(_ metadata: ModelMetadata) {
        viewModel.downloadManager.deleteModel(metadata)

        // Refresh the model list
        viewModel.refreshDiscoveredModels()
        viewModel.downloadManager.refreshStates()
    }
}

// MARK: - Sort Order

enum ModelSortOrder: String, CaseIterable {
    case recommended
    case name
    case size
}
#endif
