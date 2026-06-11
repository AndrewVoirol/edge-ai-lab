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
    @Environment(ConversationViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var importManager: URLImportManager?

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
                        startImport()
                    } label: {
                        Label("Import Model", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                            .font(.system(.body, weight: .semibold))
                    }
                    .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("urlImport_importButton")
                }

                // MARK: Status
                if let manager = importManager {
                    statusSection(manager)
                }
            }
            .navigationTitle("Import from URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("urlImport_cancel")
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
                    HStack(spacing: AppSpacing.xs) {
                        Text(meta.confidence.emoji)
                        Text(meta.confidence.label)
                            .font(AppTypography.badge)
                            .foregroundStyle(confidenceColor(meta.confidence))
                    }
                }
                .accessibilityIdentifier("urlImport_modelInfo")

                if let file = files.first {
                    Button {
                        importManager?.confirmDownload(
                            metadata: meta,
                            file: file,
                            downloadManager: viewModel.downloadManager
                        )
                        dismiss()
                    } label: {
                        Label("Download \(file.rfilename)", systemImage: "icloud.and.arrow.down")
                            .frame(maxWidth: .infinity)
                            .font(.system(.body, weight: .semibold))
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
                    .foregroundStyle(AppColors.danger)
                    .font(AppTypography.listSubtitle)
                    .accessibilityIdentifier("urlImport_error")
            }
        }
    }

    // MARK: - Actions

    private func startImport() {
        let browser = HFModelBrowser()
        let catalog = viewModel.dynamicModelCatalog
        let manager = URLImportManager(browser: browser, catalog: catalog)
        self.importManager = manager
        Task {
            await manager.importFromURL(urlText)
        }
    }

    // MARK: - Helpers

    private func confidenceColor(_ confidence: MetadataConfidence) -> Color {
        switch confidence {
        case .verified: return AppColors.success
        case .high: return AppColors.success
        case .medium: return AppColors.warning
        case .low: return AppColors.danger
        }
    }
}
#endif
