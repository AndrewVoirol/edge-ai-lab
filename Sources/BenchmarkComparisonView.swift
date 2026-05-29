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

// MARK: - Benchmark Comparison View
//
// Displays a scrollable list of model benchmark comparison cards.
// Each card summarises a model's benchmark runs — best decode speed,
// best TTFT, average tokens — and a relative performance bar.
// Data is loaded from the on-disk MetricsStore JSON history.

/// Aggregated benchmark summary for a single model, derived from all of its
/// ``MetricsStore.Entry`` records.
private struct ModelBenchmarkSummary: Identifiable {
    var id: String { modelName }

    /// Display name (matches ``MetricsStore.Entry.model``).
    let modelName: String

    /// Total number of benchmark runs recorded for this model.
    let runCount: Int

    /// Best (highest) decode speed in tokens/second across all runs.
    let bestDecodeSpeed: Double

    /// Best (lowest) time-to-first-token in seconds across all runs.
    let bestTTFT: Double

    /// Average total decode token count across all runs.
    let averageDecodeTokens: Double

    /// Average total prefill token count across all runs.
    let averagePrefillTokens: Double
}

// MARK: - BenchmarkComparisonView

/// Top-level comparison view that lists every model with benchmark data.
///
/// Usage:
/// ```swift
/// BenchmarkComparisonView()
/// ```
struct BenchmarkComparisonView: View {

    // MARK: State

    /// Loaded & grouped benchmark summaries, one per model.
    @State private var summaries: [ModelBenchmarkSummary] = []

    /// The highest decode speed across *all* models (used to normalise bar widths).
    @State private var overallBestSpeed: Double = 0

    /// Whether an error occurred while loading the store.
    @State private var loadError: String?

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                header
                content
            }
            .padding(AppSpacing.lg)
        }
        .appBackground()
        .onAppear(perform: loadBenchmarkData)
        .accessibilityIdentifier("benchmarkComparisonView")
    }

    // MARK: - Subviews

    /// Title + subtitle header.
    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Model Comparison")
                .font(AppTypography.sectionHeader)
                .foregroundStyle(AppColors.textPrimary)

            Text("Compare performance across models")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    /// Main content: either the card list, error, or empty state.
    @ViewBuilder
    private var content: some View {
        if let error = loadError {
            errorState(error)
        } else if summaries.isEmpty {
            emptyState
        } else {
            modelList
        }
    }

    /// Empty state shown when no benchmark data exists.
    private var emptyState: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "chart.bar.xaxis.ascending")
                .font(.system(size: 40))
                .foregroundStyle(AppColors.textTertiary)

            Text("No benchmark data yet.\nRun inference with different models to compare performance.")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xxl)
        .accessibilityIdentifier("benchmarkComparisonEmptyState")
    }

    /// Error state shown when the store fails to load.
    private func errorState(_ message: String) -> some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(AppColors.warning)

            Text(message)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xxl)
    }

    /// Scrollable list of ``ModelBenchmarkCard``s.
    private var modelList: some View {
        LazyVStack(spacing: AppSpacing.md) {
            ForEach(summaries) { summary in
                ModelBenchmarkCard(
                    summary: summary,
                    overallBestSpeed: overallBestSpeed
                )
            }
        }
        .accessibilityIdentifier("benchmarkComparisonModelList")
    }

    // MARK: - Data Loading

    /// Load entries from the ``MetricsStore`` and build per-model summaries.
    private func loadBenchmarkData() {
        let store = MetricsStore()
        do {
            let entries = try store.loadEntries()
            guard !entries.isEmpty else {
                summaries = []
                overallBestSpeed = 0
                return
            }

            // Group by model name.
            let grouped = Dictionary(grouping: entries, by: \.model)

            // Build summaries, sorted by best decode speed descending.
            let built: [ModelBenchmarkSummary] = grouped.map { modelName, modelEntries in
                let bestDecode = modelEntries.map(\.metrics.decodeTokensPerSecond).max() ?? 0
                let bestTTFT = modelEntries.map(\.metrics.ttftSeconds).min() ?? 0
                let avgDecodeTokens = modelEntries.map { Double($0.metrics.lastDecodeTokenCount) }
                    .reduce(0, +) / Double(modelEntries.count)
                let avgPrefillTokens = modelEntries.map { Double($0.metrics.lastPrefillTokenCount) }
                    .reduce(0, +) / Double(modelEntries.count)

                return ModelBenchmarkSummary(
                    modelName: modelName,
                    runCount: modelEntries.count,
                    bestDecodeSpeed: bestDecode,
                    bestTTFT: bestTTFT,
                    averageDecodeTokens: avgDecodeTokens,
                    averagePrefillTokens: avgPrefillTokens
                )
            }
            .sorted { $0.bestDecodeSpeed > $1.bestDecodeSpeed }

            summaries = built
            overallBestSpeed = built.first?.bestDecodeSpeed ?? 0

        } catch {
            loadError = "Failed to load benchmark data: \(error.localizedDescription)"
        }
    }
}

// MARK: - ModelBenchmarkCard

/// A glass card displaying aggregated benchmark metrics for one model,
/// plus a horizontal bar showing relative decode speed.
private struct ModelBenchmarkCard: View {

    let summary: ModelBenchmarkSummary
    let overallBestSpeed: Double

    /// Animated bar fill ratio (0 → 1).
    @State private var barFillRatio: CGFloat = 0

    /// The ``PerformanceTier`` for this model's best decode speed.
    private var tier: PerformanceTier {
        PerformanceTier(decodeSpeed: summary.bestDecodeSpeed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Model name + run count
            HStack(alignment: .firstTextBaseline) {
                Text(summary.modelName)
                    .font(AppTypography.body.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                Spacer()

                Text("\(summary.runCount) run\(summary.runCount == 1 ? "" : "s")")
                    .font(AppTypography.badge)
                    .foregroundStyle(AppColors.textSecondary)
            }

            // Key metrics row
            HStack(spacing: AppSpacing.lg) {
                metricCell(
                    label: "Decode",
                    value: formatSpeed(summary.bestDecodeSpeed),
                    unit: "tok/s",
                    valueColor: tier.color
                )

                metricCell(
                    label: "TTFT",
                    value: formatTTFT(summary.bestTTFT),
                    unit: "s",
                    valueColor: AppColors.textPrimary
                )

                metricCell(
                    label: "Avg Tokens",
                    value: formatTokens(summary.averageDecodeTokens),
                    unit: "",
                    valueColor: AppColors.textPrimary
                )
            }

            // Relative performance bar
            performanceBar
        }
        .padding(AppSpacing.lg)
        .glassCard()
        .accessibilityIdentifier("benchmarkCard_\(summary.modelName)")
        .onAppear {
            withAnimation(AppAnimation.gentleSpring) {
                barFillRatio = overallBestSpeed > 0
                    ? CGFloat(summary.bestDecodeSpeed / overallBestSpeed)
                    : 0
            }
        }
    }

    // MARK: - Metric Cell

    /// A single labelled metric (label above, large value, optional unit).
    private func metricCell(
        label: String,
        value: String,
        unit: String,
        valueColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(AppTypography.metricLarge)
                    .foregroundStyle(valueColor)

                if !unit.isEmpty {
                    Text(unit)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
    }

    // MARK: - Performance Bar

    /// Horizontal bar that visualises this model's speed relative to the fastest.
    private var performanceBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: AppRadius.sm)
                    .fill(AppColors.backgroundTertiary)
                    .frame(height: 6)

                // Fill
                RoundedRectangle(cornerRadius: AppRadius.sm)
                    .fill(tier.color)
                    .frame(width: proxy.size.width * barFillRatio, height: 6)
            }
        }
        .frame(height: 6)
        .accessibilityIdentifier("benchmarkBar_\(summary.modelName)")
    }

    // MARK: - Formatting Helpers

    /// Format decode speed to one decimal place (e.g. "43.1").
    private func formatSpeed(_ speed: Double) -> String {
        String(format: "%.1f", speed)
    }

    /// Format TTFT in seconds to two decimal places (e.g. "0.87").
    private func formatTTFT(_ ttft: Double) -> String {
        String(format: "%.2f", ttft)
    }

    /// Format token count as a rounded integer string (e.g. "256").
    private func formatTokens(_ count: Double) -> String {
        String(format: "%.0f", count)
    }
}

// MARK: - Previews

#Preview("With Data") {
    BenchmarkComparisonView()
        .frame(minWidth: 400, minHeight: 600)
}

#Preview("Empty State") {
    // Shows the empty state because no history.json exists in the preview sandbox.
    BenchmarkComparisonView()
        .frame(minWidth: 400, minHeight: 400)
}
