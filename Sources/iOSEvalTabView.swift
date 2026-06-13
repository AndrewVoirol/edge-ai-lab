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

// MARK: - iOS Eval Tab View

/// iOS-optimized evaluation tab view — the root view for the Evaluations tab.
///
/// Architecture (per Apple HIG "Lists and Tables"):
/// - `List` with `.insetGrouped` style
/// - Sections:
///   1. "Evaluation Suite" — inline Picker for suite selection
///   2. "Models to Evaluate" — multi-select from discoveredModels
///   3. Run button — disabled when no suite/model selected or already running
///   4. "Progress" — shown when evalRunner is active
///   5. "Past Runs" — EvalRunIndexEntry list from evalStore
///
/// Accessibility: Every interactive element has `.accessibilityIdentifier`.
struct iOSEvalTabView: View {
    @Environment(ConversationViewModel.self) private var viewModel

    @State private var evalStore = EvalStore()
    @State private var selectedSuiteId: UUID?
    @State private var selectedModelFiles: Set<String> = []
    @State private var isRunning = false
    @State private var runProgress: Double = 0
    @State private var runStatusText = ""
    @State private var evalRunner: EvalRunner?
    @State private var showComparisonForRun: EvalRun?
    @State private var customSuites: [EvalSuite] = []
    @State private var exportShareItem: ExportShareItem?
    @State private var showSuiteEditor = false
    @State private var editingSuite: EvalSuite?

    // MARK: - Computed Properties

    private var allSuites: [EvalSuite] { BuiltInEvalSuites.allBuiltIn + customSuites }

    private var selectedSuite: EvalSuite? {
        guard let id = selectedSuiteId else { return nil }
        return allSuites.first(where: { $0.id == id })
    }

    private var canRun: Bool {
        selectedSuiteId != nil && !selectedModelFiles.isEmpty && !isRunning
    }

    // MARK: - Body

    var body: some View {
        List {
            // MARK: Suite Picker
            Section("Evaluation Suite") {
                Picker("Suite", selection: $selectedSuiteId) {
                    Text("Select a suite").tag(UUID?.none)
                    ForEach(allSuites) { suite in
                        Text(suite.name).tag(UUID?.some(suite.id))
                    }
                }
                .accessibilityIdentifier("evalTab_suitePicker")

                if let suite = selectedSuite {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: suite.category.symbolName)
                            .foregroundStyle(AppColors.accentCyan)
                        Text(suite.displaySummary)
                            .font(AppTypography.listSubtitle)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .accessibilityIdentifier("evalTab_suiteDetail")
                }
            }

            // MARK: Custom Suites
            Section {
                ForEach(customSuites) { cs in
                    HStack {
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text(cs.name)
                                .font(AppTypography.listTitle)
                                .foregroundStyle(AppColors.textPrimary)
                            Text(cs.displaySummary)
                                .font(AppTypography.listSubtitle)
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingSuite = cs
                        showSuiteEditor = true
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            evalStore.deleteCustomSuite(id: cs.id)
                            customSuites = evalStore.loadCustomSuites()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .accessibilityIdentifier("evalTab_customSuite_\(cs.id.uuidString.prefix(8))")
                }

                Button {
                    editingSuite = nil
                    showSuiteEditor = true
                } label: {
                    Label("New Custom Suite", systemImage: "plus.circle")
                        .foregroundStyle(AppColors.accentCyan)
                }
                .accessibilityIdentifier("evalTab_newSuiteButton")
            } header: {
                Text("Custom Suites")
            }

            // MARK: Model Selection
            Section("Models to Evaluate") {
                ForEach(viewModel.discoveredModels, id: \.url) { discovered in
                    if let metadata = discovered.metadata {
                        HStack {
                            Text(metadata.name)
                                .font(AppTypography.listTitle)
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            if selectedModelFiles.contains(discovered.filename) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppColors.accentCyan)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(AppColors.textTertiary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedModelFiles.contains(discovered.filename) {
                                selectedModelFiles.remove(discovered.filename)
                            } else {
                                selectedModelFiles.insert(discovered.filename)
                            }
                        }
                        .accessibilityIdentifier("evalTab_model_\(discovered.filename)")
                    }
                }
                if viewModel.discoveredModels.isEmpty {
                    Text("No models on device")
                        .foregroundStyle(AppColors.textTertiary)
                        .font(AppTypography.listSubtitle)
                        .accessibilityIdentifier("evalTab_noModels")
                }
            }

            // MARK: Run Button
            Section {
                Button {
                    Task { await startEvaluation() }
                } label: {
                    Label("Run Evaluation", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .font(.system(.body, weight: .semibold))
                }
                .disabled(!canRun)
                .listRowBackground(canRun ? AppColors.accentCyan : AppColors.backgroundTertiary)
                .accessibilityIdentifier("evalTab_runButton")
            }

            // MARK: Progress
            if isRunning {
                Section("Progress") {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        ProgressView(value: runProgress)
                            .tint(AppColors.accentCyan)
                            .accessibilityIdentifier("evalTab_progressBar")
                        Text(runStatusText)
                            .font(AppTypography.listSubtitle)
                            .foregroundStyle(AppColors.textSecondary)
                            .accessibilityIdentifier("evalTab_progressLabel")
                    }

                    Button {
                        evalRunner?.cancel()
                        isRunning = false
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                            .foregroundStyle(AppColors.danger)
                    }
                    .accessibilityIdentifier("evalTab_cancelButton")
                }
            }

            // MARK: Past Runs
            if !evalStore.indexEntries.isEmpty {
                Section("Past Runs") {
                    ForEach(evalStore.indexEntries) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                Text(entry.suiteName)
                                    .font(AppTypography.listTitle)
                                    .foregroundStyle(AppColors.textPrimary)
                                Text(formatDate(entry.startedAt))
                                    .font(AppTypography.listSubtitle)
                                    .foregroundStyle(AppColors.textTertiary)
                            }
                            Spacer()
                            Text("\(Int(entry.overallPassRate * 100))%")
                                .font(AppTypography.mono)
                                .foregroundStyle(
                                    entry.overallPassRate > 0.8
                                        ? AppColors.success
                                        : entry.overallPassRate > 0.5
                                            ? AppColors.warning
                                            : AppColors.danger
                                )
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let run = try? evalStore.load(id: entry.id) {
                                showComparisonForRun = run
                            }
                        }
                        .accessibilityIdentifier("evalTab_run_\(entry.id.uuidString.prefix(8))")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        exportAndShare(format: .json)
                    } label: {
                        Label("Export JSON", systemImage: "doc.text")
                    }
                    .accessibilityIdentifier("evalTab_exportJSON")

                    Button {
                        exportAndShare(format: .csv)
                    } label: {
                        Label("Export CSV", systemImage: "tablecells")
                    }
                    .accessibilityIdentifier("evalTab_exportCSV")
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(AppColors.accentTeal)
                        .font(AppTypography.body)
                }
                .disabled(evalStore.indexEntries.isEmpty)
                .accessibilityIdentifier("evalTab_exportMenu")
            }
        }
        .sheet(isPresented: $showSuiteEditor) {
            iOSSuiteEditorSheet(
                suite: editingSuite,
                onSave: { suite in
                    evalStore.saveCustomSuite(suite)
                    customSuites = evalStore.loadCustomSuites()
                    showSuiteEditor = false
                },
                onCancel: {
                    showSuiteEditor = false
                }
            )
        }
        .sheet(item: $showComparisonForRun) { run in
            EvalComparisonView(evalRun: run, evalStore: evalStore)
        }
        .sheet(item: $exportShareItem) { item in
            ActivityViewController(activityItems: [item.fileURL])
                .presentationDetents([.medium])
        }
        .onAppear {
            customSuites = evalStore.loadCustomSuites()
        }
        .accessibilityIdentifier("evalTab_root")
    }

    // MARK: - Eval Execution

    private func startEvaluation() async {
        guard let suite = selectedSuite else { return }

        // Build model entries from selected filenames
        let modelEntries: [EvalModelEntry] = viewModel.discoveredModels
            .filter { selectedModelFiles.contains($0.filename) }
            .compactMap { discovered in
                guard let metadata = discovered.metadata else { return nil }
                return EvalModelEntry(
                    metadata: metadata,
                    modelPath: discovered.url.path
                )
            }

        guard !modelEntries.isEmpty else { return }

        // Create the runner
        let runner = EvalRunner(engine: viewModel.engine, store: evalStore)
        evalRunner = runner
        isRunning = true
        runProgress = 0
        runStatusText = "Preparing…"

        do {
            let cacheDir = FileManager.default.urls(
                for: .cachesDirectory, in: .userDomainMask
            ).first?.path ?? NSTemporaryDirectory()

            // Start a task to track progress updates
            let progressTask = Task { @MainActor in
                while isRunning {
                    runProgress = runner.overallProgress
                    runStatusText = runner.progressDescription
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }

            _ = try await runner.run(
                suite: suite,
                models: modelEntries,
                flags: viewModel.experimentalFlags,
                cacheDir: cacheDir
            )

            progressTask.cancel()
        } catch {
            // Runner handles its own error state
        }

        isRunning = false
        runProgress = 0
        runStatusText = ""
        evalStore.refresh()
    }

    // MARK: - Export

    /// Supported export formats for eval runs.
    private enum ExportFormat {
        case json
        case csv

        var fileExtension: String {
            switch self {
            case .json: return "json"
            case .csv: return "csv"
            }
        }
    }

    /// Exports the most recent eval run in the specified format and presents
    /// a share sheet.
    private func exportAndShare(format: ExportFormat) {
        // Get the most recent eval run from the store
        guard let mostRecentEntry = evalStore.indexEntries.first else { return }

        do {
            let data: Data
            switch format {
            case .json:
                data = try evalStore.exportJSON(id: mostRecentEntry.id)
            case .csv:
                data = try evalStore.exportCSV(id: mostRecentEntry.id)
            }

            // Write to a temp file for sharing
            let filename = "\(mostRecentEntry.suiteName)-\(mostRecentEntry.id.uuidString.prefix(8)).\(format.fileExtension)"
            let sanitizedFilename = filename.replacingOccurrences(of: " ", with: "_")
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(sanitizedFilename)
            try data.write(to: tempURL, options: .atomic)

            exportShareItem = ExportShareItem(fileURL: tempURL)
        } catch {
            // Silently fail — the export menu is disabled when no runs exist
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Export Share Item

/// Identifiable wrapper for a file URL to use with `.sheet(item:)`.
private struct ExportShareItem: Identifiable {
    let id = UUID()
    let fileURL: URL
}

// MARK: - Activity View Controller

/// UIKit `UIActivityViewController` wrapper for SwiftUI share sheets.
private struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
