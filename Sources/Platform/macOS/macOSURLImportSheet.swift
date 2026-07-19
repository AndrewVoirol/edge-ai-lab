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

    /// Whether the import state is `.readyToDownload` (the bottom action bar is visible).
    private var isReadyToDownload: Bool {
        guard let manager = coordinator.importManager else { return false }
        if case .readyToDownload = manager.state { return true }
        return false
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) { // design-system-exempt: zero spacing for tight packing
                urlInputBar
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.lg)

                ScrollView {
                    VStack(spacing: AppSpacing.md) {
                        if let manager = coordinator.importManager {
                            stateContent(manager)
                        } else {
                            idleContent
                        }
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.vertical, AppSpacing.lg)
                    .animation(AppAnimation.standard, value: coordinator.importManager?.state.stateKey)
                }

                // ── Persistent bottom action bar ──
                if let manager = coordinator.importManager,
                   case .readyToDownload(let meta, let files) = manager.state,
                   let file = selectedFile(from: files) {
                    VStack(spacing: 0) { // design-system-exempt: zero spacing for tight packing
                        Divider().overlay(AppColors.border)

                        HStack(spacing: AppSpacing.md) {
                            // File size
                            if let size = file.size ?? file.lfs?.size {
                                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(AppColors.textTertiary)
                            }

                            Spacer()

                            // Cancel
                            Button("Cancel") {
                                coordinator.cancelObservation()
                                dismiss()
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("urlImport_cancel_bottom")

                            // Download
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
                                Label("Download \(Self.quantLabel(for: file.rfilename))",
                                      systemImage: "icloud.and.arrow.down")
                                    .font(AppTypography.subtitle)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppColors.accentPrimary)
                            .controlSize(.large)
                            .accessibilityIdentifier("urlImport_downloadButton")
                        }
                        .padding(AppSpacing.lg)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appBackground()
            .navigationTitle("Import from URL")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    // Show "Done" in terminal state, or "Cancel" when bottom bar isn't visible
                    // (bottom bar only appears in .readyToDownload state)
                    if coordinator.isTerminalState {
                        Button("Done") {
                            coordinator.cancelObservation()
                            dismiss()
                        }
                        .accessibilityIdentifier("urlImport_done")
                    } else if !isReadyToDownload {
                        Button("Cancel") {
                            coordinator.cancelObservation()
                            dismiss()
                        }
                        .accessibilityIdentifier("urlImport_cancel")
                    }
                }
            }
        }
        .frame(minWidth: 540, idealHeight: 550, maxHeight: 750)
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
            .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || coordinator.isImporting)
            .glow(AppColors.accentPrimary, radius: 8, opacity: AppOpacity.rinse)
            .accessibilityIdentifier("urlImport_importButton")
        }
    }

    // MARK: - Idle Content

    private var idleContent: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "link.badge.plus")
                .font(AppIconSize.hero)
                .foregroundStyle(AppColors.textTertiary)
            Text("Paste a HuggingFace model URL above to get started.")
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xxl)
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
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.xl)
        .glassCard()
        .transition(.contentReveal)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Ready to Download Card

    @ViewBuilder
    private func readyToDownloadCard(meta: DynamicModelMetadata, files: [HFSibling]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            // ── Model Identity Card ──
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(meta.metadata.name)
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Text(meta.metadata.description)
                    .font(AppTypography.listSubtitle)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(2)

                Label(meta.confidence.label,
                      systemImage: meta.confidence.symbolName)
                    .badge(ConfidenceTier.color(for: meta.confidence))
            }
            .accessibilityIdentifier("urlImport_modelInfo")

            Divider().overlay(AppColors.border)

            // Progressive disclosure — collapsed by default to save space
            DisclosureGroup(isExpanded: $isMetadataExpanded) {
                metadataDetails(meta: meta)
                    .padding(.top, AppSpacing.sm)
            } label: {
                Label("Model Details", systemImage: "info.circle")
                    .font(AppTypography.sectionHeader)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .accessibilityIdentifier("urlImport_detailsDisclosure")
        }
        .padding(AppSpacing.xl)
        .glassCard()
        .transition(.contentReveal)

        // ── File Picker Card (separate from model info) ──
        if files.count > 1 {
            filePicker(files: files)
                .padding(AppSpacing.xl)
                .glassCard()
                .transition(.contentReveal)
        }


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
                .frame(width: 100, alignment: .trailing) // design-system-exempt: structural label column width
            Text(value)
                .font(AppTypography.listSubtitle)
                .foregroundStyle(AppColors.textPrimary)
        }
    }

    // MARK: - File Picker

    private func filePicker(files: [HFSibling]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Select Quantization")
                .font(AppTypography.sectionHeader)
                .foregroundStyle(AppColors.textSecondary)

            Text("\(files.count) variants available")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)

            // Scrollable list for repos with many quantization variants
            ScrollView {
                VStack(spacing: 2) { // design-system-exempt: tight packing for compact list
                    ForEach(Array(files.enumerated()), id: \.offset) { index, file in
                        Button {
                            selectedFileIndex = index
                        } label: {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: selectedFileIndex == index
                                      ? "checkmark.circle.fill"
                                      : "circle")
                                    .foregroundStyle(selectedFileIndex == index
                                                     ? AppColors.accentPrimary
                                                     : AppColors.textTertiary)
                                    .font(AppIconSize.sm)

                                VStack(alignment: .leading, spacing: 2) { // design-system-exempt: tight label packing
                                    Text(Self.quantLabel(for: file.rfilename))
                                        .font(AppTypography.subtitle)
                                        .foregroundStyle(AppColors.textPrimary)
                                    Text(file.rfilename)
                                        .font(AppTypography.mono)
                                        .foregroundStyle(AppColors.textTertiary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                Spacer()

                                if let size = file.size ?? file.lfs?.size {
                                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                        .font(AppTypography.mono)
                                        .foregroundStyle(AppColors.textSecondary)
                                } else {
                                    Text("Size unknown")
                                        .font(AppTypography.caption)
                                        .foregroundStyle(AppColors.textQuaternary)
                                }
                            }
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, AppSpacing.sm)
                            .background(
                                selectedFileIndex == index
                                    ? AppColors.accentPrimary.opacity(AppOpacity.faint)
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                        }
                        .buttonStyle(.plain)
                        .interactiveHover()
                        .accessibilityIdentifier("urlImport_fileOption_\(index)")
                    }
                }
            }
            .frame(maxHeight: 280) // design-system-exempt: limit file list height to prevent sheet overflow
        }
        .accessibilityIdentifier("urlImport_filePicker")
    }

    /// Extract a human-readable quantization label from a GGUF filename.
    ///
    /// Examples:
    /// - `"gemma-4-E2B-it-Q4_K_M.gguf"` → `"Q4_K_M"`
    /// - `"gemma-4-E2B-it-BF16.gguf"` → `"BF16"`
    /// - `"model.safetensors"` → `"model.safetensors"` (no quant pattern found)
    private static func quantLabel(for filename: String) -> String {
        // Known quantization patterns (ordered by specificity)
        let patterns = [
            "UD-IQ2_M", "UD-IQ3_XXS",
            "UD-Q2_K_XL", "UD-Q3_K_XL", "UD-Q4_K_XL", "UD-Q5_K_XL", "UD-Q6_K_XL", "UD-Q8_K_XL",
            "IQ4_NL", "IQ4_XS", "IQ3_XXS", "IQ2_M",
            "Q3_K_S", "Q3_K_M", "Q3_K_L",
            "Q4_K_S", "Q4_K_M", "Q4_K_L",
            "Q5_K_S", "Q5_K_M", "Q5_K_L",
            "Q6_K", "Q8_0", "Q4_0", "Q4_1", "Q5_0", "Q5_1",
            "BF16", "F16", "F32",
        ]
        for pattern in patterns {
            if filename.range(of: pattern, options: .caseInsensitive) != nil {
                return pattern  // Always return canonical uppercase
            }
        }
        // Readable fallback for non-GGUF files
        if filename.hasSuffix(".safetensors") { return "Model Weights" }
        if filename.hasSuffix(".bin") { return "Model Binary" }
        return filename
    }

    // MARK: - Complete Card

    private func completeCard(meta: DynamicModelMetadata) -> some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(AppIconSize.hero)
                .foregroundStyle(AppColors.success)
                .glow(AppColors.success, radius: 10, opacity: AppOpacity.half)

            Text(meta.metadata.name)
                .font(AppTypography.cardTitle)
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
            .glow(AppColors.accentSecondary, radius: 10, opacity: AppOpacity.medium)
            .accessibilityIdentifier("urlImport_loadButton")
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.xl)
        .glassCard()
        .accessibilityIdentifier("urlImport_complete")
        .transition(.contentReveal)
    }

    // MARK: - Failed Card

    private func failedCard(error: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            // Header row
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(AppIconSize.xl)
                    .foregroundStyle(AppColors.warning)

                Text("Import Failed")
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)
            }

            // Error explanation — left-aligned, readable secondary text
            Text(error)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(AppColors.border)

            // Action: clear and re-import
            Button {
                coordinator.importManager?.reset()
                coordinator = URLImportCoordinator()
            } label: {
                Label("Try a Different URL", systemImage: "arrow.counterclockwise")
                    .font(AppTypography.subtitle)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("urlImport_retryButton")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.xl)
        .glassCard()
        .accessibilityIdentifier("urlImport_error")
        .transition(.contentReveal)
    }

    // MARK: - Helpers

    private func selectedFile(from files: [HFSibling]) -> HFSibling? {
        guard !files.isEmpty else { return nil }
        let index = min(selectedFileIndex, files.count - 1)
        return files[index]
    }

}
#endif
