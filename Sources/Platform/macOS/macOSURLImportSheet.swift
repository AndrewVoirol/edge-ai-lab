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

#if os(macOS)
import os
import SwiftUI

// MARK: - macOS URL Import Sheet

/// HuggingFace URL import sheet for macOS — allows pasting a HF model URL
/// to import and download a community model.
///
/// Workflow:
/// 1. User pastes a HuggingFace URL
/// 2. URLImportManager parses → fetches → analyzes → readyToDownload
/// 3. User reviews metadata (with progressive disclosure for full details)
/// 4. User selects a file (if multiple) and confirms download
/// 5. Model is added to DynamicModelCatalog and download begins
///
/// Presented as a `.sheet` from `ContentView`.
///
/// Design: Dark Forest / Moss palette with glass cards, glow effects,
/// and a macOS-native layout (not an iOS Form port).
struct macOSURLImportSheet: View {
    private static let logger = Logger(
        subsystem: "com.andrewvoirol.EdgeAILab",
        category: "macOSURLImportSheet"
    )

    @Environment(ConversationViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var coordinator = URLImportCoordinator()
    @State private var selectedFileIndex = 0
    @State private var isMetadataExpanded = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) { // design-system-exempt: zero spacing for tight packing
                urlInputBar
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.lg)

                if let manager = coordinator.importManager {
                    stateContent(manager)
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.top, AppSpacing.lg)
                } else {
                    idleContent
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appBackground()
            .navigationTitle("Import from URL")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(coordinator.isTerminalState ? "Done" : "Cancel") {
                        coordinator.cancelObservation()
                        dismiss()
                    }
                    .accessibilityIdentifier("urlImport_done")
                }
            }
        }
        .frame(minWidth: 500, minHeight: 450)
        .onAppear {
            // Pick up pending URL from inline quick-paste
            if let pending = viewModel.pendingImportURL {
                urlText = pending
                viewModel.pendingImportURL = nil
                coordinator.startImport(urlText: urlText, catalog: viewModel.dynamicModelCatalog)
            }
        }
    }

    // MARK: - URL Input Bar

    private var urlInputBar: some View {
        HStack(spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "doc.on.clipboard")
                    .foregroundStyle(AppColors.textTertiary)
                    .font(AppIconSize.sm)

                TextField("https://huggingface.co/org/model", text: $urlText)
                    .textFieldStyle(.plain)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                    .accessibilityIdentifier("urlImport_urlField")
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .forestGlass(cornerRadius: AppRadius.md)

            Button {
                coordinator.startImport(urlText: urlText, catalog: viewModel.dynamicModelCatalog)
                selectedFileIndex = 0
                isMetadataExpanded = false
            } label: {
                Label("Import", systemImage: "arrow.down.circle.fill")
                    .font(AppTypography.subtitle)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.accentPrimary)
            .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .glow(AppColors.accentPrimary, radius: 8, opacity: 0.25)
            .accessibilityIdentifier("urlImport_importButton")
        }
    }

    // MARK: - Idle Content

    private var idleContent: some View {
        VStack(spacing: AppSpacing.md) {
            Spacer()
            Image(systemName: "link.badge.plus")
                .font(AppIconSize.xxl)
                .foregroundStyle(AppColors.textTertiary)
            Text("Paste a HuggingFace model URL above to get started.")
                .font(AppTypography.listSubtitle)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(AppSpacing.xl)
        .accessibilityIdentifier("urlImport_idle")
    }

    // MARK: - State Content

    @ViewBuilder
    private func stateContent(_ manager: URLImportManager) -> some View {
        switch manager.state {
        case .idle:
            EmptyView()

        case .parsing:
            statusCard(icon: nil, text: "Parsing URL…", identifier: "urlImport_parsing")

        case .fetching(let repoId):
            statusCard(icon: nil, text: "Fetching \(repoId)…", identifier: "urlImport_fetching")

        case .analyzing:
            statusCard(icon: nil, text: "Analyzing model…", identifier: "urlImport_analyzing")

        case .readyToDownload(let meta, let files):
            readyToDownloadCard(meta: meta, files: files)

        case .downloading(let filename):
            statusCard(icon: nil, text: "Downloading \(filename)…", identifier: "urlImport_downloading")

        case .complete(let meta):
            completeCard(meta: meta)

        case .failed(let error):
            failedCard(error: error)
        }
    }

    // MARK: - Status Card (Loading States)

    private func statusCard(icon: String?, text: String, identifier: String) -> some View {
        HStack(spacing: AppSpacing.md) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(AppTypography.listSubtitle)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.xl)
        .glassCard()
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Ready to Download Card

    private func readyToDownloadCard(meta: DynamicModelMetadata, files: [HFSibling]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            // Model summary
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(meta.metadata.name)
                    .font(AppTypography.listTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Text(meta.metadata.description)
                    .font(AppTypography.listSubtitle)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(3)

                // Confidence badge
                HStack(spacing: AppSpacing.xs) {
                    Text(meta.confidence.emoji)
                    Text(meta.confidence.label)
                        .badge(ConfidenceTier.color(for: meta.confidence))
                }
            }
            .accessibilityIdentifier("urlImport_modelInfo")

            Divider().overlay(AppColors.border)

            // Progressive disclosure — full metadata
            DisclosureGroup(isExpanded: $isMetadataExpanded) {
                metadataDetails(meta: meta)
                    .padding(.top, AppSpacing.sm)
            } label: {
                Label("Model Details", systemImage: "info.circle")
                    .font(AppTypography.sectionHeader)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .accessibilityIdentifier("urlImport_detailsDisclosure")

            // File picker (multi-file repos)
            if files.count > 1 {
                Divider().overlay(AppColors.border)
                filePicker(files: files)
            }

            Divider().overlay(AppColors.border)

            // Download action
            if let file = selectedFile(from: files) {
                Button {
                    coordinator.importManager?.confirmDownload(
                        metadata: meta,
                        file: file,
                        downloadManager: viewModel.downloadManager
                    )
                    coordinator.observeDownloadCompletion(
                        filename: file.rfilename,
                        metadata: meta,
                        downloadManager: viewModel.downloadManager,
                        onComplete: nil,
                        onFail: nil
                    )
                } label: {
                    Label("Download \(file.rfilename)", systemImage: "icloud.and.arrow.down")
                        .frame(maxWidth: .infinity)
                        .font(AppTypography.subtitle)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.accentPrimary)
                .controlSize(.large)
                .glow(AppColors.accentPrimary, radius: 10, opacity: 0.3)
                .accessibilityIdentifier("urlImport_downloadButton")
            }
        }
        .padding(AppSpacing.xl)
        .glassCard()
    }

    // MARK: - Metadata Details (Progressive Disclosure)

    private func metadataDetails(meta: DynamicModelMetadata) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            detailRow(label: "Runtime", value: meta.metadata.runtimeType.displayName)
            detailRow(label: "Architecture", value: meta.metadata.architectureType)
            detailRow(label: "Context Window", value: "\(meta.metadata.contextWindowSize.formatted()) tokens")

            if !meta.metadata.capabilities.isEmpty {
                detailRow(label: "Capabilities", value: meta.metadata.capabilities.joined(separator: ", "))
            }

            HStack(spacing: AppSpacing.md) {
                if meta.metadata.supportsImage {
                    Label("Vision", systemImage: "eye")
                        .badge(AppColors.capabilityVision)
                }
                if meta.metadata.supportsAudio {
                    Label("Audio", systemImage: "waveform")
                        .badge(AppColors.capabilityAudio)
                }
            }
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
                .frame(width: 100, alignment: .trailing)
            Text(value)
                .font(AppTypography.listSubtitle)
                .foregroundStyle(AppColors.textPrimary)
        }
    }

    // MARK: - File Picker

    private func filePicker(files: [HFSibling]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Select File")
                .font(AppTypography.sectionHeader)
                .foregroundStyle(AppColors.textSecondary)

            Picker("Model file", selection: $selectedFileIndex) {
                ForEach(Array(files.enumerated()), id: \.offset) { index, file in
                    HStack {
                        Text(file.rfilename)
                            .font(AppTypography.mono)
                        if let size = file.size ?? file.lfs?.size {
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                    .tag(index)
                }
            }
            .pickerStyle(.radioGroup)
            .accessibilityIdentifier("urlImport_filePicker")
        }
    }

    // MARK: - Complete Card

    private func completeCard(meta: DynamicModelMetadata) -> some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(AppIconSize.hero)
                .foregroundStyle(AppColors.success)
                .glow(AppColors.success, radius: 14, opacity: 0.5)

            Text(meta.metadata.name)
                .font(AppTypography.listTitle)
                .foregroundStyle(AppColors.textPrimary)

            Text("Model imported successfully.")
                .font(AppTypography.listSubtitle)
                .foregroundStyle(AppColors.textSecondary)

            Button {
                viewModel.loadImportedModel(meta)
                dismiss()
            } label: {
                Label("Load Model", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .font(AppTypography.subtitle)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.accentSecondary)
            .controlSize(.large)
            .glow(AppColors.accentSecondary, radius: 10, opacity: 0.3)
            .accessibilityIdentifier("urlImport_loadButton")
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.xl)
        .glassCard()
        .accessibilityIdentifier("urlImport_complete")
    }

    // MARK: - Failed Card

    private func failedCard(error: String) -> some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(AppIconSize.xxl)
                .foregroundStyle(AppColors.destructive)

            Text(error)
                .font(AppTypography.listSubtitle)
                .foregroundStyle(AppColors.destructive)
                .multilineTextAlignment(.center)

            Button {
                coordinator.importManager?.reset()
                coordinator = URLImportCoordinator()
            } label: {
                Label("Try Again", systemImage: "arrow.counterclockwise")
                    .font(AppTypography.subtitle)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("urlImport_retryButton")
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.xl)
        .glassCard()
        .accessibilityIdentifier("urlImport_error")
    }

    // MARK: - Helpers

    private func selectedFile(from files: [HFSibling]) -> HFSibling? {
        guard !files.isEmpty else { return nil }
        let index = min(selectedFileIndex, files.count - 1)
        return files[index]
    }

}
#endif
