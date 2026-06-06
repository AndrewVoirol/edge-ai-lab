import SwiftUI

// MARK: - Model Strip View

/// The horizontal model card strip showing discovered and downloadable models.
///
/// Accessibility: Every interactive element has `.accessibilityIdentifier`
/// for agent discoverability and UI testing.
struct ModelStripView: View {
    @Bindable private var viewModel = ConversationViewModel.shared
    @Binding var showcaseModel: ModelMetadata?
    @Binding var showcaseModelURL: URL?

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
    }

    /// Registry models that are not yet discovered on disk.
    private var downloadableModels: [ModelMetadata] {
        let discoveredFilenames = Set(viewModel.discoveredModels.map(\.filename))
        return ModelRegistry.knownModels.filter { !discoveredFilenames.contains($0.modelFile) }
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
                    Text(model.metadata?.name ?? model.filename)
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(isActive ? AppColors.accentCyan : AppColors.textPrimary)
                        .lineLimit(1)
                    if model.source == .edgeGallery {
                        Text("Gallery")
                            .font(AppTypography.badge)
                            .foregroundStyle(AppColors.accentCyan)
                            .padding(.horizontal, AppSpacing.xs)
                            .padding(.vertical, 1)
                            .background(AppColors.accentCyan.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                
                if let metadata = model.metadata {
                    ModelCapabilityBadges(metadata: metadata, experimentalFlags: viewModel.experimentalFlags)
                }
                
                HStack(spacing: AppSpacing.xs) {
                    Circle()
                        .fill(isActive ? AppColors.accentCyan : AppColors.success)
                        .frame(width: 5, height: 5)
                    Text(isActive ? "Loaded Engine" : "Click to Load Engine")
                        .font(AppTypography.caption)
                        .foregroundStyle(isActive ? AppColors.accentCyan : AppColors.textTertiary)
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .contentShape(Rectangle())
            .glassCard(cornerRadius: AppRadius.md)
            .interactiveHover()
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .stroke(isActive ? AppColors.accentCyan : Color.clear, lineWidth: 1)
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
                        viewModel.downloadManager.deleteModel(metadata)
                        viewModel.refreshDiscoveredModels()
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
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                
            ModelCapabilityBadges(metadata: model, experimentalFlags: viewModel.experimentalFlags)


            switch state {
            case .notDownloaded:
                Button {
                    viewModel.downloadManager.download(model)
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "arrow.down.circle")
                        Text(ByteCountFormatter.string(fromByteCount: model.sizeInBytes, countStyle: .file))
                            .font(AppTypography.caption)
                    }
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.accentCyan)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("download_\(model.modelFile)")

            case .downloading(let progress):
                VStack(alignment: .leading, spacing: 2) {
                    ProgressView(value: progress)
                        .tint(AppColors.accentTeal)
                        .frame(width: 80)
                    HStack {
                        Text("\(Int(progress * 100))%")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)
                        Spacer()
                        Button {
                            viewModel.downloadManager.cancelDownload(model)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
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
                        viewModel.downloadManager.deleteModel(model)
                        viewModel.refreshDiscoveredModels()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption2)
                            .foregroundStyle(AppColors.danger)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("button_deleteModel_\(model.modelFile)")
                }

            case .failed(let message):
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppColors.danger)
                        .font(.caption2)
                    Text(message)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.danger)
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
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .contentShape(Rectangle())
        .glassCard(cornerRadius: AppRadius.md)
    }
}
