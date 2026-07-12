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
import Foundation

// MARK: - Eval Runner View

/// Main evaluation runner UI, displayed in the DetailColumnView when the
/// 'Evaluations' section is selected from the sidebar.
///
/// Layout:
/// 1. Suite Picker — horizontally scrollable cards for available suites
/// 2. Model Picker — checkboxes for on-disk models to evaluate
/// 3. Run Button — gradient CTA with ⌘E shortcut
/// 4. Progress View — live progress during eval execution
/// 5. Results List — past eval runs from EvalStore
struct EvalRunnerView: View {
    @Environment(ConversationViewModel.self) private var viewModel

    // MARK: - State

    @State private var evalRunner: EvalRunner?
    @State private var evalStore = EvalStore()
    @State private var selectedSuiteId: UUID?
    @State private var selectedModelFiles: Set<String> = []
    @State private var isRunning = false
    @State private var showComparisonForRun: EvalRun?
    @State private var customSuites: [EvalSuite] = []
    @State private var showSuiteEditor = false
    @State private var editingSuite: EvalSuite?
    @State private var liveResults: [PromptEvalResult] = []
    @State private var batchOrchestrator: BatchEvalOrchestrator?
    @State private var showBatchConfirm = false
    @State private var isBatchRunning = false

    // MARK: - Computed Properties

    /// All available suites (built-in + custom).
    private var allSuites: [EvalSuite] {
        EvalRunnerLogic.allSuites(builtIn: BuiltInEvalSuites.allBuiltIn, custom: customSuites)
    }

    /// The currently selected suite, if any.
    private var selectedSuite: EvalSuite? {
        guard let id = selectedSuiteId else { return nil }
        return allSuites.first(where: { $0.id == id })
    }

    /// Whether the Run button should be enabled.
    private var canRun: Bool {
        EvalRunnerLogic.canRun(selectedSuiteId: selectedSuiteId, selectedModelFiles: selectedModelFiles, isRunning: isRunning)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                // MARK: Header
                header

                // MARK: Suite Picker
                suitePicker

                // MARK: Model Picker
                modelPicker

                // MARK: Run Button
                HStack(spacing: AppSpacing.md) {
                    runButton
                    runAllButton
                }

                // MARK: Progress (during eval)
                if isRunning, let runner = evalRunner {
                    progressView(runner: runner)
                }

                // MARK: Results List
                resultsList
            }
            .padding(AppSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.backgroundPrimary)
        .sheet(item: $showComparisonForRun) { run in
            EvalComparisonView(evalRun: run, evalStore: evalStore)
        }
        .sheet(isPresented: $showSuiteEditor) {
            EvalSuiteEditorView(
                suite: editingSuite,
                onSave: { suite in
                    if let idx = customSuites.firstIndex(where: { $0.id == suite.id }) {
                        customSuites[idx] = suite
                    } else {
                        customSuites.append(suite)
                    }
                    evalStore.saveCustomSuite(suite)
                    showSuiteEditor = false
                },
                onCancel: {
                    showSuiteEditor = false
                }
            )
        }
        .onAppear {
            customSuites = evalStore.loadCustomSuites()
        }
        .accessibilityIdentifier("evalRunnerView_root")
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Evaluation Runner")
                    .font(AppTypography.pageTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .accessibilityIdentifier("evalRunner_title")

                Text("Run structured eval suites against on-device models and compare results.")
                    .font(AppTypography.listSubtitle)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            Button {
                editingSuite = nil
                showSuiteEditor = true
            } label: {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "plus.circle.fill")
                    Text("New Suite")
                        .font(AppTypography.sectionHeader)
                }
                .foregroundStyle(AppColors.accentPrimary)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .background(AppColors.accentPrimary.opacity(0.1))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("evalRunner_newSuiteButton")
        }
    }

    // MARK: - Suite Picker

    private var suitePicker: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Select Suite")
                .font(AppTypography.sectionHeader)
                .foregroundStyle(AppColors.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.md) {
                    ForEach(allSuites) { suite in
                        suiteCard(suite)
                    }
                }
                .padding(.vertical, AppSpacing.xs)
                .padding(.horizontal, AppSpacing.xxs)
            }
        }
        .accessibilityIdentifier("evalRunner_suitePicker")
    }

    private func suiteCard(_ suite: EvalSuite) -> some View {
        let isSelected = selectedSuiteId == suite.id

        return Button {
            withAnimation(AppAnimation.standard) {
                selectedSuiteId = suite.id
            }
        } label: {
            VStack(spacing: AppSpacing.sm) {
                // Icon
                Image(systemName: suite.category.symbolName)
                    .font(AppIconSize.xl)
                    .foregroundStyle(
                        isSelected
                            ? AppColors.accentPrimary
                            : AppColors.textSecondary
                    )
                    .frame(width: 40, height: 40)
                    .background(
                        (isSelected ? AppColors.accentPrimary : AppColors.textTertiary)
                            .opacity(0.1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))

                // Name
                Text(suite.name)
                    .font(AppTypography.sectionHeader)
                    .foregroundStyle(
                        isSelected ? AppColors.textPrimary : AppColors.textSecondary
                    )
                    .lineLimit(1)

                // Prompt count badge
                Text("\(suite.promptCount) prompts")
                    .badge(isSelected ? AppColors.accentPrimary : AppColors.textTertiary)
            }
            .frame(width: 120)
            .padding(AppSpacing.md)
            .glassCard(cornerRadius: AppRadius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .stroke(
                        isSelected ? AppColors.accentPrimary.opacity(0.6) : Color.clear,
                        lineWidth: AppLineWidth.medium
                    )
            )
            .glow(
                isSelected ? AppColors.accentPrimary : .clear,
                radius: isSelected ? 8 : 0,
                opacity: isSelected ? 0.3 : 0
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(AppAnimation.quick, value: isSelected)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !suite.isBuiltIn {
                Button {
                    editingSuite = suite
                    showSuiteEditor = true
                } label: {
                    Label("Edit Suite", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    customSuites.removeAll { $0.id == suite.id }
                    evalStore.deleteCustomSuite(id: suite.id)
                    if selectedSuiteId == suite.id {
                        selectedSuiteId = nil
                    }
                } label: {
                    Label("Delete Suite", systemImage: "trash")
                }
            }
        }
        .accessibilityIdentifier("evalRunner_suiteCard_\(suite.name)")
    }

    // MARK: - Model Picker

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text("Select Models")
                    .font(AppTypography.sectionHeader)
                    .foregroundStyle(AppColors.textSecondary)

                Spacer()

                if !viewModel.discoveredModels.isEmpty {
                    Button {
                        withAnimation(AppAnimation.standard) {
                            if selectedModelFiles.count == viewModel.discoveredModels.count {
                                selectedModelFiles.removeAll()
                            } else {
                                selectedModelFiles = Set(
                                    viewModel.discoveredModels.map(\.filename)
                                )
                            }
                        }
                    } label: {
                        Text(
                            EvalRunnerLogic.selectAllToggleLabel(
                                selectedCount: selectedModelFiles.count,
                                totalCount: viewModel.discoveredModels.count
                            )
                        )
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.accentPrimary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("evalRunner_selectAllModels")
                }
            }

            if viewModel.discoveredModels.isEmpty {
                // Empty state
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(AppColors.warning)
                    Text("No models on disk. Download a model first to run evaluations.")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(AppSpacing.md)
                .glassCard(cornerRadius: AppRadius.md)
                .accessibilityIdentifier("evalRunner_noModelsWarning")
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: AppSpacing.sm
                ) {
                    ForEach(viewModel.discoveredModels) { model in
                        modelRow(model)
                    }
                }
            }
        }
        .accessibilityIdentifier("evalRunner_modelPicker")
    }

    private func modelRow(_ model: DiscoveredModel) -> some View {
        let isSelected = selectedModelFiles.contains(model.filename)

        return Button {
            withAnimation(AppAnimation.quick) {
                if isSelected {
                    selectedModelFiles.remove(model.filename)
                } else {
                    selectedModelFiles.insert(model.filename)
                }
            }
        } label: {
            HStack(spacing: AppSpacing.sm) {
                // Checkbox
                Image(
                    systemName: isSelected
                        ? "checkmark.square.fill" : "square"
                )
                .font(AppIconSize.lg)
                .foregroundStyle(
                    isSelected ? AppColors.accentPrimary : AppColors.textTertiary
                )

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(model.resolvedMetadata.name)
                        .font(AppTypography.sectionHeader)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: AppSpacing.xs) {
                        Text(model.formattedSize)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)

                        if let metadata = model.metadata {
                            if metadata.supportsImage {
                                Text("Vision")
                                    .badge(AppColors.capabilityVision)
                            }
                            if metadata.supportsAudio {
                                Text("Audio")
                                    .badge(AppColors.capabilityAudio)
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(AppSpacing.sm)
            .glassCard(cornerRadius: AppRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .stroke(
                        isSelected ? AppColors.accentPrimary.opacity(0.4) : Color.clear,
                        lineWidth: AppLineWidth.regular
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("evalRunner_modelRow_\(model.filename)")
    }

    // MARK: - Run Button

    private var runButton: some View {
        Button {
            Task { await startEvaluation() }
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: isRunning ? "stop.fill" : "play.fill")
                    .font(AppIconSize.sm)
                Text(isRunning ? "Running…" : "Run Evaluation")
                    .font(AppTypography.subtitle)
            }
            .foregroundStyle(AppColors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.md)
            .background(
                LinearGradient(
                    colors: canRun
                        ? [AppColors.accentPrimary, AppColors.accentPrimary]
                        : [AppColors.textTertiary.opacity(0.3), AppColors.textTertiary.opacity(0.2)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
            .glow(
                canRun ? AppColors.accentPrimary : .clear,
                radius: canRun ? 8 : 0,
                opacity: canRun ? 0.3 : 0
            )
        }
        .buttonStyle(.plain)
        .disabled(!canRun)
        .keyboardShortcut("e", modifiers: .command)
        .accessibilityIdentifier("evalRunner_runButton")
    }

    // MARK: - Run All Button

    private var runAllButton: some View {
        Button {
            showBatchConfirm = true
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: isBatchRunning ? "stop.fill" : "forward.fill")
                    .font(AppIconSize.sm)
                Text(isBatchRunning ? "Batch Running…" : "Run All")
                    .font(AppTypography.subtitle)
            }
            .foregroundStyle(AppColors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.md)
            .background(
                LinearGradient(
                    colors: (!isRunning && !isBatchRunning && !viewModel.discoveredModels.isEmpty)
                        ? [AppColors.accentSecondary, AppColors.accentPrimary]
                        : [AppColors.textTertiary.opacity(0.3), AppColors.textTertiary.opacity(0.2)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
        }
        .buttonStyle(.plain)
        .disabled(!EvalRunnerLogic.batchCanRun(
            isRunning: isRunning,
            isBatchRunning: isBatchRunning,
            modelCount: viewModel.discoveredModels.count
        ))
        .accessibilityIdentifier("evalRunner_runAllButton")
        .alert("Run All Evaluations?", isPresented: $showBatchConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Run All") {
                Task { await startBatchEvaluation() }
            }
        } message: {
            let plan = buildBatchPlan()
            Text(plan.description)
        }
    }

    // MARK: - Progress View

    private func progressView(runner: EvalRunner) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Section header
            HStack {
                Text("Running Evaluation")
                    .font(AppTypography.sectionHeader)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Button {
                    runner.cancel()
                    isRunning = false
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "xmark.circle.fill")
                        Text("Cancel")
                            .font(AppTypography.caption)
                    }
                    .foregroundStyle(AppColors.destructive)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("evalRunner_cancelButton")
            }

            // Overall progress bar
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                ProgressView(value: runner.overallProgress)
                    .tint(AppColors.accentPrimary)
                    .accessibilityIdentifier("evalRunner_progressBar")

                HStack {
                    // Current status
                    Text(runner.progressDescription)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)

                    Spacer()

                    // Estimated time remaining
                    if runner.estimatedTimeRemaining > 0 {
                        Text(formatTimeRemaining(runner.estimatedTimeRemaining))
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
            }
            .padding(AppSpacing.md)
            .glassCard(cornerRadius: AppRadius.md)

            // Live result feed
            if !liveResults.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Live Results")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)

                    ForEach(liveResults.suffix(6)) { result in
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: result.score.symbolName)
                                .font(AppIconSize.xs)
                                .foregroundStyle(
                                    result.passed ? AppColors.success : AppColors.destructive
                                )

                            Text(result.promptText)
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(1)

                            Spacer()

                            if let speed = result.decodeSpeed {
                                Text(String(format: "%.1f tok/s", speed))
                                    .font(AppTypography.mono)
                                    .foregroundStyle(AppColors.textTertiary)
                            }
                        }
                        .padding(.vertical, AppSpacing.xxs)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(AppSpacing.md)
                .glassCard(cornerRadius: AppRadius.md)
                .accessibilityIdentifier("evalRunner_liveResults")
            }
        }
        .accessibilityIdentifier("evalRunner_progressSection")
    }

    // MARK: - Results List

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text("Past Runs")
                    .font(AppTypography.sectionHeader)
                    .foregroundStyle(AppColors.textSecondary)

                Spacer()

                if !evalStore.indexEntries.isEmpty {
                    Text("\(evalStore.indexEntries.count)")
                        .font(AppTypography.badge)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }

            if evalStore.indexEntries.isEmpty {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "clock")
                        .foregroundStyle(AppColors.textTertiary)
                    Text("Completed evaluations will appear here.")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
                .padding(AppSpacing.md)
                .accessibilityIdentifier("evalRunner_emptyResults")
            } else {
                ForEach(evalStore.indexEntries) { entry in
                    evalRunRow(entry)
                }
            }
        }
        .accessibilityIdentifier("evalRunner_resultsList")
    }

    private func evalRunRow(_ entry: EvalRunIndexEntry) -> some View {
        Button {
            if let run = try? evalStore.load(id: entry.id) {
                showComparisonForRun = run
            }
        } label: {
            HStack(spacing: AppSpacing.md) {
                // Pass rate indicator
                passRateIndicator(entry.overallPassRate)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    // Suite name + model count
                    HStack(spacing: AppSpacing.sm) {
                        Text(entry.suiteName)
                            .font(AppTypography.cardTitle)
                            .foregroundStyle(AppColors.textPrimary)

                        Text("\(entry.modelCount) model\(entry.modelCount == 1 ? "" : "s")")
                            .badge(AppColors.accentPrimary)
                    }

                    // Date + platform
                    HStack(spacing: AppSpacing.sm) {
                        Text(
                            entry.startedAt,
                            format: .dateTime.month(.abbreviated).day().hour().minute()
                        )
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)

                        Text("·")
                            .foregroundStyle(AppColors.textTertiary)

                        Text(entry.platform)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(AppIconSize.xs)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(AppSpacing.md)
            .glassCard(cornerRadius: AppRadius.md)
        }
        .buttonStyle(.plain)
        .interactiveHover()
        .accessibilityIdentifier("evalRunner_runRow_\(entry.id.uuidString.prefix(8))")
    }

    // MARK: - Pass Rate Indicator

    private func passRateIndicator(_ rate: Double) -> some View {
        let percent = EvalRunnerLogic.passRatePercent(rate)
        let color = PassRateTier.color(for: rate)

        return ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: AppLineWidth.heavy)
                .frame(width: AppSize.tapTarget, height: AppSize.tapTarget)

            Circle()
                .trim(from: 0, to: rate)
                .stroke(color, style: StrokeStyle(lineWidth: AppLineWidth.heavy, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: AppSize.tapTarget, height: AppSize.tapTarget)

            Text("\(percent)%")
                .font(AppTypography.metric)
                .foregroundStyle(color)
        }
        .accessibilityLabel("Pass rate: \(percent) percent")
    }

    // MARK: - Helpers



    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        EvalRunnerLogic.formatTimeRemaining(seconds)
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

        // Create the runner — uses InferenceEngine directly
        let runner = EvalRunner(
            engine: viewModel.engine,
            store: evalStore,
            exportPersistence: EvalResultPersistence()
        )
        evalRunner = runner
        isRunning = true
        liveResults = []

        runner.onPromptComplete = { result in
            liveResults.append(result)
        }

        do {
            let cacheDir = FileManager.default.urls(
                for: .cachesDirectory, in: .userDomainMask
            ).first?.path ?? NSTemporaryDirectory()

            _ = try await runner.run(
                suite: suite,
                models: modelEntries,
                flags: viewModel.runtimeFlags,
                cacheDir: cacheDir
            )
        } catch {
            // Runner handles its own error state
        }

        isRunning = false
        evalStore.refresh()
    }

    // MARK: - Batch Eval Execution

    /// Build a plan using all available suites and all discovered models.
    private func buildBatchPlan() -> BatchEvalPlan {
        let modelEntries: [EvalModelEntry] = viewModel.discoveredModels
            .compactMap { discovered in
                guard let metadata = discovered.metadata else { return nil }
                return EvalModelEntry(
                    metadata: metadata,
                    modelPath: discovered.url.path
                )
            }

        return BatchEvalPlan(
            suites: allSuites,
            models: modelEntries
        )
    }

    /// Run all suites against all models sequentially.
    private func startBatchEvaluation() async {
        let plan = buildBatchPlan()
        guard plan.totalRuns > 0 else { return }

        isBatchRunning = true

        let orchestrator = BatchEvalOrchestrator(
            engine: viewModel.engine,
            store: evalStore
        )
        batchOrchestrator = orchestrator

        _ = await orchestrator.runAll(
            plan: plan,
            flags: viewModel.runtimeFlags,
            cacheDir: FileManager.default.urls(
                for: .cachesDirectory, in: .userDomainMask
            ).first?.path ?? NSTemporaryDirectory()
        )

        batchOrchestrator = nil
        isBatchRunning = false
        evalStore.refresh()
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Eval Runner") {
    // Preview placeholder — ConversationViewModel requires a real InstrumentedEngine.
    Text("Preview requires ConversationViewModel")
}
#endif
