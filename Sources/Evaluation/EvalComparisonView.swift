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

// MARK: - Eval Comparison View

/// Side-by-side comparison dashboard for a completed eval run.
///
/// Displays per-model result breakdowns with pass/fail indicators,
/// latency metrics, and an exportable summary.
///
/// Shown as a sheet from `EvalRunnerView` when a past run is tapped.
struct EvalComparisonView: View {
    let evalRun: EvalRun
    let evalStore: EvalStore

    @Environment(\.dismiss) private var dismiss
    @State private var selectedModelIndex: Int = 0
    @State private var showShareSheet = false
    @State private var filterStatus: EvalComparisonLogic.ResultFilter = .all
    @State private var exportError: String?
    @State private var deleteError: String?

    // MARK: - Type Aliases

    private typealias ResultFilter = EvalComparisonLogic.ResultFilter

    // MARK: - Computed

    /// All model results from this run.
    private var modelResults: [ModelEvalResult] {
        evalRun.modelResults
    }

    /// The currently selected model's results.
    private var activeModelResult: ModelEvalResult? {
        EvalComparisonLogic.activeModelResult(at: selectedModelIndex, from: modelResults)
    }

    /// Filtered prompt results for the active model.
    private var filteredPromptResults: [PromptEvalResult] {
        EvalComparisonLogic.filteredPromptResults(from: activeModelResult, filter: filterStatus)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            titleBar

            Divider().overlay(AppColors.border)

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    // Summary cards row
                    summaryCards

                    // Model tabs
                    if modelResults.count > 1 {
                        modelTabs
                    }

                    // Filter bar
                    filterBar

                    // Prompt results table
                    promptResultsTable

                    // Bottom actions
                    bottomActions
                }
                .padding(AppSpacing.xl)
            }
        }
        #if os(macOS)
        .frame(minWidth: 700, idealWidth: 900, minHeight: 600, idealHeight: 750)
        #endif
        .background(AppColors.backgroundPrimary)
        .sheet(isPresented: $showShareSheet) {
            EvalBenchmarkCardShareSheet(evalRun: evalRun)
        }
        .alert("Export Error", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .alert("Delete Error", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
        .accessibilityIdentifier("evalComparisonView_root")
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(evalRun.suiteName)
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.textPrimary)

                HStack(spacing: AppSpacing.sm) {
                    Text(
                        evalRun.startedAt,
                        format: .dateTime.month(.abbreviated).day().hour().minute()
                    )
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)

                    Text("·")
                        .foregroundStyle(AppColors.textTertiary)

                    Text(EvalComparisonLogic.modelCountLabel(modelResults.count))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }

            Spacer()

            HStack(spacing: AppSpacing.md) {
                Button {
                    showShareSheet = true
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                            .font(AppTypography.sectionHeader)
                    }
                    .foregroundStyle(AppColors.accentCyan)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("evalComparison_shareButton")

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.accentTeal)
                .accessibilityIdentifier("evalComparison_doneButton")
            }
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.lg)
    }

    // MARK: - Summary Cards

    /// Total prompts across all models (summed from model results).
    private var totalPromptCount: Int {
        EvalComparisonLogic.totalPromptCount(from: modelResults)
    }

    private var summaryCards: some View {
        HStack(spacing: AppSpacing.md) {
            // Overall pass rate
            summaryCard(
                title: "Pass Rate",
                value: EvalComparisonLogic.passRateLabel(evalRun.overallPassRate),
                icon: "checkmark.circle.fill",
                color: PassRateTier.color(for: evalRun.overallPassRate),
                identifier: "evalComparison_passRate"
            )

            // Total prompts
            summaryCard(
                title: "Prompts",
                value: "\(totalPromptCount)",
                icon: "text.bubble.fill",
                color: AppColors.accentCyan,
                identifier: "evalComparison_totalPrompts"
            )

            // Avg decode speed — numeric value only, unit folded into title
            if let avgSpeed = averageDecodeSpeed {
                summaryCard(
                    title: "Avg tok/s",
                    value: EvalComparisonLogic.speedValue(avgSpeed),
                    icon: "speedometer",
                    color: AppColors.accentTeal,
                    identifier: "evalComparison_avgSpeed"
                )
            }

            // Duration
            summaryCard(
                title: "Duration",
                value: EvalComparisonLogic.formatDuration(evalRun.duration ?? 0),
                icon: "clock.fill",
                color: AppColors.accentGold,
                identifier: "evalComparison_duration"
            )
        }
    }

    private func summaryCard(
        title: String,
        value: String,
        icon: String,
        color: Color,
        identifier: String
    ) -> some View {
        VStack(spacing: AppSpacing.xs) {
            Image(systemName: icon)
                .font(AppIconSize.lg)
                .foregroundStyle(color)

            Text(value)
                .font(AppTypography.metricLarge)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.md)
        .glassCard(cornerRadius: AppRadius.lg)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Model Tabs

    private var modelTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(Array(modelResults.enumerated()), id: \.offset) { idx, result in
                    let isActive = selectedModelIndex == idx

                    Button {
                        withAnimation(AppAnimation.standard) {
                            selectedModelIndex = idx
                        }
                    } label: {
                        HStack(spacing: AppSpacing.xs) {
                            Circle()
                                .fill(PassRateTier.color(for: result.passRate))
                                .frame(width: 8, height: 8)

                            Text(result.modelName)
                                .font(AppTypography.sectionHeader)
                                .foregroundStyle(
                                    isActive ? AppColors.textPrimary : AppColors.textSecondary
                                )

                            Text(String(format: "%.0f%%", result.passRate * 100))
                                .font(AppTypography.badge)
                                .foregroundStyle(PassRateTier.color(for: result.passRate))
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.md)
                                .fill(isActive ? AppColors.accentCyan.opacity(0.1) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.md)
                                .stroke(
                                    isActive ? AppColors.accentCyan.opacity(0.4) : AppColors.border.opacity(0.3),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("evalComparison_modelTab_\(idx)")
                }
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(ResultFilter.allCases) { filter in
                let isActive = filterStatus == filter
                let count = countForFilter(filter)

                Button {
                    withAnimation(AppAnimation.quick) {
                        filterStatus = filter
                    }
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Text(filter.rawValue)
                            .font(AppTypography.badge)

                        Text("\(count)")
                            .font(AppTypography.badge)
                    }
                    .foregroundStyle(isActive ? AppColors.textPrimary : AppColors.textTertiary)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.xs)
                    .background(
                        Capsule()
                            .fill(isActive ? AppColors.accentCyan.opacity(0.15) : Color.clear)
                    )
                    .overlay(
                        Capsule()
                            .stroke(
                                isActive ? AppColors.accentCyan.opacity(0.3) : AppColors.border.opacity(0.2),
                                lineWidth: 0.5
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("evalComparison_filter_\(filter.rawValue)")
            }

            Spacer()
        }
    }

    // MARK: - Prompt Results Table

    private var promptResultsTable: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            // Column headers — only useful on macOS wide table layout
            #if os(macOS)
            HStack(spacing: 0) {
                Text("Status")
                    .frame(width: 60, alignment: .leading)
                Text("Prompt")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Speed")
                    .frame(width: 80, alignment: .trailing)
                Text("Score")
                    .frame(width: 60, alignment: .trailing)
            }
            .font(AppTypography.badge)
            .foregroundStyle(AppColors.textTertiary)
            .padding(.horizontal, AppSpacing.md)
            .padding(.bottom, AppSpacing.xs)
            #endif

            Divider().overlay(AppColors.border.opacity(0.3))

            // Result rows
            ForEach(filteredPromptResults) { result in
                promptResultRow(result)
            }

            if filteredPromptResults.isEmpty {
                Text("No results match the current filter.")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.vertical, AppSpacing.lg)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .accessibilityIdentifier("evalComparison_resultsTable")
    }

    private func promptResultRow(_ result: PromptEvalResult) -> some View {
        #if os(iOS)
        // iOS: Card-based row with top-aligned icon and text
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: result.score.symbolName)
                .font(.body)
                .foregroundStyle(result.passed ? AppColors.success : AppColors.danger)
                .frame(width: 24, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(result.promptText)
                    .font(AppTypography.listSubtitle)
                    .foregroundStyle(AppColors.textPrimary)

                if let reason = result.score.reason {
                    Text(reason)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.danger.opacity(0.8))
                        .lineLimit(3)
                }

                HStack {
                    if let speed = result.decodeSpeed {
                        Text(String(format: "%.1f tok/s", speed))
                            .font(AppTypography.mono)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    Spacer()
                    Text(result.score.displayLabel)
                        .font(AppTypography.badge)
                        .foregroundStyle(result.passed ? AppColors.success : AppColors.danger)
                }
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.sm)
                .fill(result.passed ? Color.clear : AppColors.danger.opacity(0.03))
        )
        .accessibilityIdentifier("evalComparison_promptRow_\(result.id.uuidString.prefix(8))")
        #else
        // macOS: Wide table row with fixed-width columns
        HStack(spacing: 0) {
            Image(systemName: result.score.symbolName)
                .font(.caption)
                .foregroundStyle(result.passed ? AppColors.success : AppColors.danger)
                .frame(width: 60, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.promptText)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)

                if let reason = result.score.reason {
                    Text(reason)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.danger.opacity(0.8))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let speed = result.decodeSpeed {
                Text(String(format: "%.1f", speed))
                    .font(AppTypography.mono)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 80, alignment: .trailing)
            } else {
                Text("—")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                    .frame(width: 80, alignment: .trailing)
            }

            Text(result.score.displayLabel)
                .font(AppTypography.badge)
                .foregroundStyle(result.passed ? AppColors.success : AppColors.danger)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.sm)
                .fill(result.passed ? Color.clear : AppColors.danger.opacity(0.03))
        )
        .accessibilityIdentifier("evalComparison_promptRow_\(result.id.uuidString.prefix(8))")
        #endif
    }

    // MARK: - Bottom Actions

    private var bottomActions: some View {
        HStack(spacing: AppSpacing.md) {
            Spacer()

            Button {
                exportRunJSON()
            } label: {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export JSON")
                        .font(AppTypography.sectionHeader)
                }
                .foregroundStyle(AppColors.accentCyan)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background(AppColors.accentCyan.opacity(0.1))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("evalComparison_exportButton")

            Button {
                deleteRun()
            } label: {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "trash")
                    Text("Delete Run")
                        .font(AppTypography.sectionHeader)
                }
                .foregroundStyle(AppColors.danger)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background(AppColors.danger.opacity(0.1))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("evalComparison_deleteButton")
        }
    }

    // MARK: - Helpers

    private var averageDecodeSpeed: Double? {
        EvalComparisonLogic.averageDecodeSpeed(from: modelResults)
    }

    private func countForFilter(_ filter: ResultFilter) -> Int {
        EvalComparisonLogic.countForFilter(filter, in: activeModelResult)
    }

    private func exportRunJSON() {
        #if os(macOS)
        do {
            let data = try evalStore.exportJSON(id: evalRun.id)
            let panel = NSSavePanel()
            panel.title = "Export Eval Run"
            panel.nameFieldStringValue = "eval_\(evalRun.suiteName.replacingOccurrences(of: " ", with: "_"))_\(evalRun.id.uuidString.prefix(8)).json"
            panel.allowedContentTypes = [.json]
            panel.begin { response in
                if response == .OK, let url = panel.url {
                    try? data.write(to: url)
                }
            }
        } catch {
            exportError = "Export failed: \(error.localizedDescription)"
        }
        #endif
    }

    private func deleteRun() {
        do {
            try evalStore.delete(id: evalRun.id)
            dismiss()
        } catch {
            deleteError = "Delete failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Eval Comparison") {
    EvalComparisonView(
        evalRun: EvalRun(
            suiteId: UUID(),
            suiteName: "Math Accuracy"
        ),
        evalStore: EvalStore()
    )
    .preferredColorScheme(.dark)
}
#endif
