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

// MARK: - Model Strip View

/// The horizontal model card strip showing discovered and downloadable models.
///
/// Accessibility: Every interactive element has `.accessibilityIdentifier`
/// for agent discoverability and UI testing.
struct ModelStripView: View {
    @Environment(ConversationViewModel.self) private var viewModel
    @Binding var showcaseModel: ModelMetadata?
    @Binding var showcaseModelURL: URL?

    /// Model pending delete confirmation.
    @State private var metadataToDelete: ModelMetadata?
    @State private var showDeleteConfirmation = false

    var body: some View {
        modelManagementSection
    }

    // MARK: - Model Management Section

    private var modelManagementSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text("Models")
                    .font(AppTypography.sectionHeader)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Text(viewModel.downloadManager.documentsDirectory.path)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.sm)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.md) {
                    // On-disk discovered models
                    ForEach(viewModel.discoveredModels) { model in
                        discoveredModelCard(model)
                    }

                    // Registry models not yet on disk (downloadable)
                    ForEach(downloadableModels) { model in
                        downloadableModelCard(model)
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.sm)
            }
        }
        .accessibilityIdentifier("section_models")
        .alert("Delete Model?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                metadataToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let metadata = metadataToDelete {
                    viewModel.downloadManager.deleteModel(metadata)
                    viewModel.refreshDiscoveredModels()
                    metadataToDelete = nil
                }
            }
        } message: {
            if let metadata = metadataToDelete {
                Text("\"\(metadata.name)\" will be permanently removed from disk. This cannot be undone.")
            }
        }
    }

    /// Registry models that are not yet discovered on disk.
    private var downloadableModels: [ModelMetadata] {
        let discoveredFilenames = Set(viewModel.discoveredModels.map(\.filename))
        return ModelRegistry.knownModels.filter { model in
            if model.isMLXDirectoryModel {
                // MLX models: check both discovered filenames and download state
                let dirName = model.modelFile
                if discoveredFilenames.contains(dirName) { return false }
                if case .downloaded = viewModel.downloadManager.checkMLXModelState(modelId: model.modelId) {
                    return false
                }
                return true
            } else {
                return !discoveredFilenames.contains(model.modelFile)
            }
        }
    }

    // MARK: - Model Cards

    private func discoveredModelCard(_ model: DiscoveredModel) -> some View {
        let isActive = viewModel.activeModelURL == model.url
        return Button {
            Task {
                await viewModel.handleModelSelection(model.url)
            }
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.xs) {
                    Text(model.resolvedMetadata.name)
                        .font(AppTypography.sectionHeader)
                        .foregroundStyle(isActive ? AppColors.accentPrimary : AppColors.textPrimary)
                        .lineLimit(1)
                    if model.source == .edgeGallery {
                        Text("Gallery")
                            .font(AppTypography.badge)
                            .foregroundStyle(AppColors.accentPrimary)
                            .padding(.horizontal, AppSpacing.xs)
                            .padding(.vertical, AppSpacing.xxs)
                            .background(AppColors.accentPrimary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                
                if let metadata = model.metadata {
                    ModelCapabilityBadges(metadata: metadata, runtimeFlags: viewModel.runtimeFlags)
                }
                
                HStack(spacing: AppSpacing.xs) {
                    Circle()
                        .fill(isActive ? AppColors.accentPrimary : AppColors.success)
                        .frame(width: 5, height: 5)
                    Text(isActive ? "Loaded Engine" : "Click to Load Engine")
                        .font(AppTypography.caption)
                        .foregroundStyle(isActive ? AppColors.accentPrimary : AppColors.textTertiary)
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .contentShape(Rectangle())
            .glassCard(cornerRadius: AppRadius.md)
            .interactiveHover()
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .stroke(isActive ? AppColors.accentPrimary : Color.clear, lineWidth: AppLineWidth.regular)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let metadata = model.metadata {
                Button {
                    showcaseModelURL = model.url
                    showcaseModel = metadata
                } label: {
                    Label("Model Info", systemImage: "info.circle")
                }
                
                if model.source != .edgeGallery {
                    Button(role: .destructive) {
                        metadataToDelete = metadata
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Model", systemImage: "trash")
                    }
                    .accessibilityIdentifier("context_deleteModel_\(model.filename)")
                }
            }
        }
        .accessibilityIdentifier("modelCard_\(model.filename)")
    }

    private func downloadableModelCard(_ model: ModelMetadata) -> some View {
        let state = viewModel.downloadManager.downloadStates[model.modelFile] ?? .notDownloaded

        return VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(model.name)
                .font(AppTypography.sectionHeader)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                
            ModelCapabilityBadges(metadata: model, runtimeFlags: viewModel.runtimeFlags)


            switch state {
            case .notDownloaded:
                Button {
                    if model.isMLXDirectoryModel {
                        Task {
                            await viewModel.downloadMLXRegistryModel(model)
                        }
                    } else {
                        viewModel.downloadManager.download(model)
                    }
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "arrow.down.circle")
                        Text(ByteCountFormatter.string(fromByteCount: model.sizeInBytes, countStyle: .file))
                            .font(AppTypography.caption)
                    }
                    .font(AppTypography.caption)
                    .foregroundStyle(model.isMLXDirectoryModel ? AppColors.accentSecondary : AppColors.accentPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("download_\(model.modelFile)")

            case .downloading(let progress):
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    ProgressView(value: progress)
                        .tint(AppColors.accentPrimary)
                        .frame(width: 80)
                    HStack {
                        Text("\(Int(progress * 100))%")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)
                        Spacer()
                        Button {
                            Task { await viewModel.downloadManager.cancelDownload(model) }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("cancelDownload_\(model.modelFile)")
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
                        metadataToDelete = model
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.destructive)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("button_deleteModel_\(model.modelFile)")
                }

            case .failed(let message):
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppColors.destructive)
                        .font(AppTypography.caption)
                    Text(message)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.destructive)
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
                .accessibilityIdentifier("auth_\(model.modelFile)")

            case .queued(let position):
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "clock")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                    Text("Queued (#\(position))")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }

            case .paused(_, let progress):
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "pause.fill")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.warning)
                    Text("Paused · \(Int(progress * 100))%")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.warning)
                }

            case .downloadingDirectory(let progress, let completed, let total):
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    ProgressView(value: progress)
                        .tint(AppColors.accentSecondary)
                        .frame(width: 80)
                    Text("\(completed)/\(total) files · \(Int(progress * 100))%")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }

            case .pausedDirectory(let progress, let completed, let total):
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "pause.fill")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.warning)
                    Text("Paused · \(completed)/\(total) · \(Int(progress * 100))%")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.warning)
                }
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .contentShape(Rectangle())
        .glassCard(cornerRadius: AppRadius.md)
        .interactiveHover()
    }
}
