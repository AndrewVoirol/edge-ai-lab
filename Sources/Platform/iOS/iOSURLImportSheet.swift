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
import os
import SwiftUI

// MARK: - iOS URL Import Sheet

/// HuggingFace URL import sheet for iOS — allows pasting a HF model URL
/// to import and download a community model.
///
/// Workflow:
/// 1. User pastes a HuggingFace URL
/// 2. URLImportManager parses → fetches → analyzes → readyToDownload
/// 3. User confirms download
/// 4. Model is added to DynamicModelCatalog and download begins
///
/// Presented as a `.sheet` from `iOSModelHubView`.
///
/// Accessibility: Every interactive element has `.accessibilityIdentifier`.
struct iOSURLImportSheet: View {
    private static let logger = Logger(
        subsystem: "com.andrewvoirol.EdgeAILab",
        category: "iOSURLImportSheet"
    )

    @Environment(ConversationViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var coordinator = URLImportCoordinator()
    @State private var selectedFileIndex = 0

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                // MARK: URL Input
                Section {
                    TextField("https://huggingface.co/org/model", text: $urlText)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("urlImport_urlField")
                } header: {
                    Text("HuggingFace Model URL")
                } footer: {
                    Text("Paste a HuggingFace model URL to import and download.")
                }

                // MARK: Import Button
                Section {
                    Button {
                        coordinator.startImport(urlText: urlText, catalog: viewModel.dynamicModelCatalog)
                        selectedFileIndex = 0
                    } label: {
                        Label("Import Model", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                            .font(AppTypography.subtitle)
                    }
                    .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("urlImport_importButton")
                }

                // MARK: Status
                if let manager = coordinator.importManager {
                    statusSection(manager)
                }
            }
            .navigationTitle("Import from URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if coordinator.isTerminalState {
                        Button("Done") {
                            coordinator.cancelObservation()
                            dismiss()
                        }
                        .accessibilityIdentifier("urlImport_done")
                    } else {
                        Button("Cancel") {
                            coordinator.cancelObservation()
                            dismiss()
                        }
                        .accessibilityIdentifier("urlImport_cancel")
                    }
                }
            }
        }
        .accessibilityIdentifier("urlImport_root")
    }

    // MARK: - Status Section

    @ViewBuilder
    private func statusSection(_ manager: URLImportManager) -> some View {
        switch manager.state {
        case .idle:
            EmptyView()

        case .parsing:
            Section("Status") {
                HStack(spacing: AppSpacing.sm) {
                    ProgressView()
                    Text("Parsing URL…")
                        .font(AppTypography.listSubtitle)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .accessibilityIdentifier("urlImport_parsing")
            }

        case .fetching(let repoId):
            Section("Status") {
                HStack(spacing: AppSpacing.sm) {
                    ProgressView()
                    Text("Fetching \(repoId)…")
                        .font(AppTypography.listSubtitle)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .accessibilityIdentifier("urlImport_fetching")
            }

        case .analyzing:
            Section("Status") {
                HStack(spacing: AppSpacing.sm) {
                    ProgressView()
                    Text("Analyzing model…")
                        .font(AppTypography.listSubtitle)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .accessibilityIdentifier("urlImport_analyzing")
            }

        case .readyToDownload(let meta, let files):
            Section("Model Found") {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text(meta.metadata.name)
                        .font(AppTypography.listTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(meta.metadata.description)
                        .font(AppTypography.listSubtitle)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(3)
                    Label(meta.confidence.label,
                          systemImage: meta.confidence.symbolName)
                        .badge(ConfidenceTier.color(for: meta.confidence))
                }
                .accessibilityIdentifier("urlImport_modelInfo")

                // File picker for multi-file repos
                if files.count > 1 {
                    Picker("Quantization", selection: $selectedFileIndex) {
                        ForEach(Array(files.enumerated()), id: \.offset) { index, file in
                            HStack {
                                Text(Self.quantLabel(for: file.rfilename))
                                Spacer()
                                if let size = file.size ?? file.lfs?.size {
                                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                        .font(AppTypography.caption)
                                        .foregroundStyle(AppColors.textTertiary)
                                }
                            }
                            .tag(index)
                        }
                    }
                    .pickerStyle(.inline)
                    .accessibilityIdentifier("urlImport_filePicker")
                }

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
                            onComplete: { dismiss() },
                            onFail: nil
                        )
                    } label: {
                        Label("Download \(Self.quantLabel(for: file.rfilename))", systemImage: "icloud.and.arrow.down")
                            .frame(maxWidth: .infinity)
                            .font(AppTypography.subtitle)
                    }
                    .accessibilityIdentifier("urlImport_downloadButton")
                }
            }

        case .downloading(let filename):
            Section("Status") {
                HStack(spacing: AppSpacing.sm) {
                    ProgressView()
                    Text("Downloading \(filename)…")
                        .font(AppTypography.listSubtitle)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .accessibilityIdentifier("urlImport_downloading")
            }

        case .complete(let meta):
            Section("Complete") {
                Label(meta.metadata.name, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.success)
                    .accessibilityIdentifier("urlImport_complete")
            }

        case .failed(let error):
            Section("Error") {
                Text(error)
                    .foregroundStyle(AppColors.destructive)
                    .font(AppTypography.listSubtitle)
                    .accessibilityIdentifier("urlImport_error")
            }
        }
    }

    // MARK: - Helpers

    private func selectedFile(from files: [HFSibling]) -> HFSibling? {
        guard !files.isEmpty else { return nil }
        let index = min(selectedFileIndex, files.count - 1)
        return files[index]
    }

    /// Extract a human-readable quantization label from a GGUF filename.
    private static func quantLabel(for filename: String) -> String {
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
            if filename.contains(pattern) {
                return pattern
            }
        }
        return filename
    }
}
#endif
