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
import os

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
    private static let logger = Logger(subsystem: "com.andrewvoirol.EdgeAILab", category: "evalRunnerView")

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
    @State private var evalErrorMessage: String?
    @State private var runsPerPrompt: Int = 1

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

                // MARK: Eval Settings
                evalSettings

                // MARK: Run Button
                VStack(spacing: AppSpacing.sm) {
                    runButton
                    runAllButton
                }

                // MARK: Progress (during eval)
                if isRunning, let runner = evalRunner {
                    progressView(runner: runner)
                }

                // MARK: Batch Progress
                if isBatchRunning, let orchestrator = batchOrchestrator {
                    batchProgressView(orchestrator: orchestrator)
                }

                // MARK: Error Banner
                if let errorMsg = evalErrorMessage {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppColors.destructive)
                        Text(errorMsg)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(3)
                        Spacer()
                        Button {
                            evalErrorMessage = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(AppSpacing.md)
                    .background(AppColors.destructive.opacity(0.15)) // design-system-exempt: error banner background needs partial opacity
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                    .accessibilityIdentifier("evalRunner_errorBanner")
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
                .background(AppColors.accentPrimaryFaint)
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
                            .opacity(AppOpacity.faint)
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

                // Compatibility badge
                compatibilityBadge(for: suite)
            }
            .frame(width: 120)
            .padding(AppSpacing.md)
            .glassCard(cornerRadius: AppRadius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg)
                    .stroke(
                        isSelected ? AppColors.accentPrimary.opacity(AppOpacity.prominent) : Color.clear,
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

    /// Shows compatibility status badge for a suite based on the active model.
    @ViewBuilder
    private func compatibilityBadge(for suite: EvalSuite) -> some View {
        let status = EvalSuiteCompatibility.check(
            suite: suite,
            profile: viewModel.activeCapabilityProfile
        )
        switch status {
        case .compatible:
            Label("Compatible", systemImage: "checkmark.seal.fill")
                .font(AppTypography.badge)
                .foregroundStyle(AppColors.success)
                .accessibilityIdentifier("evalRunner_compat_ok_\(suite.name)")
        case .partiallyCompatible(let reasons):
            Label(reasons.first ?? "Partial", systemImage: "exclamationmark.triangle.fill")
                .font(AppTypography.badge)
                .foregroundStyle(AppColors.warning)
                .lineLimit(1)
                .accessibilityIdentifier("evalRunner_compat_partial_\(suite.name)")
        case .incompatible(let reasons):
            Label(reasons.first ?? "Incompatible", systemImage: "xmark.seal.fill")
                .font(AppTypography.badge)
                .foregroundStyle(AppColors.destructive)
                .lineLimit(1)
                .accessibilityIdentifier("evalRunner_compat_no_\(suite.name)")
        case .unknown:
            EmptyView()
        }
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
        let metadata = model.resolvedMetadata
        let normalized = ModelDetailFormatters.normalizeDisplayName(metadata.name)
        let split = ModelDetailFormatters.splitModelName(normalized)

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
                    // Primary name + quantization suffix
                    HStack(spacing: AppSpacing.xs) {
                        Text(split.primary)
                            .font(AppTypography.sectionHeader)
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)

                        if let quant = split.quantization {
                            Text(quant)
                                .badge(AppColors.textTertiary)
                        }
                    }

                    HStack(spacing: AppSpacing.xs) {
                        // Runtime type badge
                        Text(metadata.runtimeType.rawValue)
                            .badge(AppColors.accentSecondary)

                        Text(model.formattedSize)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)

                        // Capability badges
                        if metadata.supportsImage {
                            Text("Vision")
                                .badge(AppColors.capabilityVision)
                        }
                        if metadata.supportsAudio {
                            Text("Audio")
                                .badge(AppColors.capabilityAudio)
                        }
                        if metadata.supportsMTP {
                            Text("Spec. Dec")
                                .badge(AppColors.capabilityMTP)
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
                        isSelected ? AppColors.accentPrimary.opacity(AppOpacity.dim) : Color.clear,
                        lineWidth: AppLineWidth.regular
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("evalRunner_modelRow_\(model.filename)")
    }

    // MARK: - Eval Settings

    private var evalSettings: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Settings")
                .font(AppTypography.subtitle)
                .foregroundStyle(AppColors.textPrimary)

            HStack {
                Label("Runs per prompt", systemImage: "repeat")
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)

                Spacer()

                Stepper(
                    "\(runsPerPrompt)×",
                    value: $runsPerPrompt,
                    in: 1...5
                )
                .font(AppTypography.body)
                .accessibilityIdentifier("evalRunner_runsPerPromptStepper")
            }

            if runsPerPrompt > 1 {
                Text("Each prompt runs \(runsPerPrompt)× with majority-vote scoring. Estimated time increases proportionally.")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .padding(AppSpacing.md)
        .glassCard(cornerRadius: AppRadius.md)
    }

    // MARK: - Run Button

    private var runButton: some View {
        Button {
            Task { await startEvaluation() }
        } label: {
            VStack(spacing: AppSpacing.xxs) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: isRunning ? "stop.fill" : "play.fill")
                        .font(AppIconSize.sm)
                    Text(isRunning ? "Running…" : "Run Evaluation")
                        .font(AppTypography.subtitle)
                }
                .foregroundStyle(AppColors.textPrimary)

                if !isRunning {
                    Text("Selected suite · selected models")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textPrimary.opacity(AppOpacity.dim))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.md)
            .background(
                LinearGradient(
                    colors: canRun
                        ? [AppColors.accentPrimary, AppColors.accentPrimary] // design-system-exempt: gradient structure needed for ternary branch parity
                        : [AppColors.textTertiary.opacity(0.3), AppColors.textTertiary.opacity(0.2)], // design-system-exempt: gradient stops for disabled button
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
        let batchEnabled = EvalRunnerLogic.batchCanRun(
            isRunning: isRunning,
            isBatchRunning: isBatchRunning,
            modelCount: viewModel.discoveredModels.count
        )

        return Button {
            showBatchConfirm = true
        } label: {
            VStack(spacing: AppSpacing.xxs) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: isBatchRunning ? "stop.fill" : "forward.fill")
                        .font(AppIconSize.xs)
                    Text(isBatchRunning ? "Batch Running…" : "Run All Suites")
                        .font(AppTypography.sectionHeader)
                }
                .foregroundStyle(batchEnabled ? AppColors.accentPrimary : AppColors.textTertiary)

                if !isBatchRunning {
                    Text("All suites · all models")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .stroke(
                        batchEnabled ? AppColors.accentPrimary.opacity(AppOpacity.dim) : AppColors.textTertiary.opacity(0.2), // design-system-exempt: outline button border opacity
                        lineWidth: AppLineWidth.regular
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!batchEnabled)
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
                        .transition(.slideUp)
                    }
                }
                .padding(AppSpacing.md)
                .glassCard(cornerRadius: AppRadius.md)
                .accessibilityIdentifier("evalRunner_liveResults")
            }
        }
        .accessibilityIdentifier("evalRunner_progressSection")
    }

    // MARK: - Batch Progress View

    private func batchProgressView(orchestrator: BatchEvalOrchestrator) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Section header
            HStack {
                Text("Running All Suites")
                    .font(AppTypography.sectionHeader)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Button {
                    orchestrator.cancel()
                    isBatchRunning = false
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "xmark.circle.fill")
                        Text("Cancel Batch")
                            .font(AppTypography.caption)
                    }
                    .foregroundStyle(AppColors.destructive)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("evalRunner_batchCancelButton")
            }

            // Overall progress bar
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                ProgressView(value: orchestrator.overallProgress)
                    .tint(AppColors.accentSecondary)
                    .accessibilityIdentifier("evalRunner_batchProgressBar")

                HStack {
                    // Current status
                    Text(orchestrator.state.displayLabel)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)

                    Spacer()

                    // Runs completed count
                    Text("\(orchestrator.completedRuns)/\(orchestrator.totalRuns) runs")
                        .font(AppTypography.mono)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .padding(AppSpacing.md)
            .glassCard(cornerRadius: AppRadius.md)

            // Current runner progress (nested)
            if let currentRunner = orchestrator.currentRunner {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Current Suite Progress")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)

                    ProgressView(value: currentRunner.overallProgress)
                        .tint(AppColors.accentPrimary)

                    Text(currentRunner.progressDescription)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }
                .padding(AppSpacing.md)
                .glassCard(cornerRadius: AppRadius.md)
            }
        }
        .accessibilityIdentifier("evalRunner_batchProgressSection")
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
        guard let suite = selectedSuite else {
            Self.logger.warning("startEvaluation() — no suite selected, returning early")
            return
        }

        // Clear any previous error
        evalErrorMessage = nil

        // Build model entries from selected filenames.
        // Use resolvedMetadata (never nil) instead of metadata (nil for imported models)
        // to ensure all discovered models can participate in evaluation.
        let modelEntries: [EvalModelEntry] = viewModel.discoveredModels
            .filter { selectedModelFiles.contains($0.filename) }
            .map { discovered in
                EvalModelEntry(
                    metadata: discovered.resolvedMetadata,
                    modelPath: discovered.url.path,
                    mmProjPath: discovered.mmProjPath
                )
            }

        guard !modelEntries.isEmpty else {
            Self.logger.warning("startEvaluation() — no models selected (selectedModelFiles: \(selectedModelFiles.description, privacy: .public), discoveredModels: \(viewModel.discoveredModels.map { $0.filename }.description, privacy: .public))")
            return
        }

        Self.logger.info("▶️ Starting eval: suite='\(suite.name, privacy: .public)' (\(suite.promptCount, privacy: .public) prompts), models=\(modelEntries.map { $0.metadata.name }.description, privacy: .public)")
        Self.logger.debug("📂 Model paths: \(modelEntries.map { $0.modelPath }.description, privacy: .public)")

        // Create the runner — creates its own engine per model based on runtimeType
        let runner = EvalRunner(
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

            Self.logger.info("🚀 Calling runner.run() with cacheDir='\(cacheDir, privacy: .public)'")

            _ = try await runner.run(
                suite: suite,
                models: modelEntries,
                flags: viewModel.runtimeFlags,
                cacheDir: cacheDir,
                runsPerPrompt: runsPerPrompt
            )

            Self.logger.info("✅ runner.run() completed successfully")
        } catch {
            Self.logger.error("❌ runner.run() threw: \(error.localizedDescription, privacy: .public)")
            evalErrorMessage = "Evaluation failed: \(error.localizedDescription)"
        }

        isRunning = false
        evalStore.refresh()
    }

    // MARK: - Batch Eval Execution

    /// Build a plan using all available suites and all discovered models.
    /// Uses resolvedMetadata so imported/community models without registry
    /// entries are included in the batch plan and model count.
    private func buildBatchPlan() -> BatchEvalPlan {
        let modelEntries: [EvalModelEntry] = viewModel.discoveredModels
            .map { discovered in
                EvalModelEntry(
                    metadata: discovered.resolvedMetadata,
                    modelPath: discovered.url.path,
                    mmProjPath: discovered.mmProjPath
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
        guard plan.totalRuns > 0 else {
            Self.logger.warning("startBatchEvaluation() — totalRuns is 0, returning early")
            return
        }

        // Clear any previous error
        evalErrorMessage = nil

        Self.logger.info("▶️ Starting batch eval: \(plan.description, privacy: .public)")
        Self.logger.info("📦 Models: \(plan.models.map { $0.metadata.name }.description, privacy: .public)")
        Self.logger.info("📋 Suites: \(plan.suites.map { $0.name }.description, privacy: .public)")

        isBatchRunning = true

        let orchestrator = BatchEvalOrchestrator(
            store: evalStore
        )
        batchOrchestrator = orchestrator

        _ = await orchestrator.runAll(
            plan: plan,
            flags: viewModel.runtimeFlags,
            cacheDir: FileManager.default.urls(
                for: .cachesDirectory, in: .userDomainMask
            ).first?.path ?? NSTemporaryDirectory(),
            runsPerPrompt: runsPerPrompt
        )

        Self.logger.info("🏁 Batch eval finished: state=\(orchestrator.state.displayLabel, privacy: .public), completed=\(orchestrator.completedRuns, privacy: .public)/\(orchestrator.totalRuns, privacy: .public)")

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
