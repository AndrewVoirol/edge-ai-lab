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
import Charts

// MARK: - Performance Dashboard View

/// Historical performance analytics view using Swift Charts.
/// Visualizes decode speed trends, memory usage, and model comparisons
/// from the persistent MetricsStore.
///
/// This is a differentiator — no other edge AI app has real-time
/// performance analytics with historical trend analysis.
struct PerformanceDashboardView: View {
    @State private var entries: [MetricsStore.Entry] = []
    @State private var selectedModel: String?
    @State private var availableModels: [String] = []
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var isLoading = true
    @State private var loadError: String?

    private let store = MetricsStore()

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                // Header
                dashboardHeader

                // Error banner
                if let error = loadError {
                    HStack(spacing: AppSpacing.md) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppColors.destructive)
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text("Failed to load metrics")
                                .font(AppTypography.subtitle)
                                .foregroundStyle(AppColors.textPrimary)
                            Text(error)
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button("Retry") {
                            loadError = nil
                            loadData()
                        }
                        .font(AppTypography.badge)
                        .foregroundStyle(AppColors.accentSecondary)
                    }
                    .padding(AppSpacing.md)
                    .glassCard(cornerRadius: AppRadius.md)
                    .accessibilityLabel("Error loading metrics: \(error). Tap Retry to try again.")
                    .accessibilityIdentifier("dashboard_errorBanner")
                }

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if entries.isEmpty {
                    emptyState
                } else {
                    // Decode speed trend chart
                    decodeSpeedChart
                        .accessibilityIdentifier("chart_decodeSpeed")

                    // Summary stats grid
                    summaryStatsGrid

                    // Memory usage chart
                    memoryChart
                        .accessibilityIdentifier("chart_memory")

                    // Recent runs table
                    recentRunsSection
                }
            }
            .padding(AppSpacing.lg)
        }
        .background {
            AppGradients.showcaseBackground
            .ignoresSafeArea()
            .overlay {
                if !reduceTransparency {
                    Rectangle().fill(.ultraThinMaterial)
                }
            }
        }
        .onAppear { loadData() }
        .navigationTitle("Performance")
    }

    // MARK: - Header

    private var dashboardHeader: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(AppIconSize.xl)
                    .foregroundStyle(AppColors.accentPrimary)
                Text("Performance Dashboard")
                    .font(AppTypography.sectionTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()

                // Model filter
                if !availableModels.isEmpty {
                    Menu {
                        Button("All Models") { selectedModel = nil; loadData() }
                        ForEach(availableModels, id: \.self) { model in
                            Button(model) { selectedModel = model; loadData() }
                        }
                    } label: {
                        HStack(spacing: AppSpacing.xs) {
                            Text(selectedModel ?? "All Models")
                                .font(AppTypography.badge)
                            Image(systemName: "chevron.down")
                                .font(AppIconSize.xxs)
                        }
                        .foregroundStyle(AppColors.accentSecondary)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .background(AppColors.accentSecondary.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityIdentifier("menu_modelFilter")
                }
            }

            Text("\(entries.count) benchmark runs recorded")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "chart.bar.xaxis")
                .font(AppIconSize.hero)
                .foregroundStyle(AppColors.textTertiary)

            Text("No benchmark data yet")
                .font(AppTypography.cardTitle)
                .foregroundStyle(AppColors.textSecondary)

            Text("Run some inferences with benchmarking enabled to see performance trends here.")
                .font(AppTypography.subtitle)
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(AppSpacing.xl)
    }

    // MARK: - Decode Speed Chart

    private var decodeSpeedChart: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Decode Speed Trend")
                .font(AppTypography.sectionHeader)
                .foregroundStyle(AppColors.textSecondary)

            Chart {
                ForEach(entries, id: \.timestamp) { entry in
                    let index = entries.firstIndex(where: { $0.timestamp == entry.timestamp }) ?? 0
                    LineMark(
                        x: .value("Run", index),
                        y: .value("tok/s", entry.metrics.decodeTokensPerSecond)
                    )
                    .foregroundStyle(by: .value("Model", entry.model))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: AppLineWidth.thick))

                    PointMark(
                        x: .value("Run", index),
                        y: .value("tok/s", entry.metrics.decodeTokensPerSecond)
                    )
                    .foregroundStyle(by: .value("Model", entry.model))
                    .symbolSize(20)
                }
            }
            .chartYAxisLabel("Tokens/sec")
            .chartXAxisLabel("Run #")
            .accessibilityLabel("Decode speed trend chart showing \(entries.count) runs. Average speed: \(String(format: "%.1f", averageDecodeSpeed)) tokens per second.")
            .frame(height: 200)
            .padding(AppSpacing.md)
            .glassCard()
        }
    }

    // MARK: - Summary Stats

    private var summaryStatsGrid: some View {
        LazyVGrid(columns: statsGridColumns, spacing: AppSpacing.md) {
            statCard(
                label: "Avg Decode",
                value: String(format: "%.1f", averageDecodeSpeed),
                unit: "tok/s",
                color: PerformanceTier(decodeSpeed: averageDecodeSpeed).color
            )
            statCard(
                label: "Best TTFT",
                value: String(format: "%.3f", bestTTFT),
                unit: "sec",
                color: AppColors.accentPrimary
            )
            statCard(
                label: "Peak Decode",
                value: String(format: "%.1f", peakDecodeSpeed),
                unit: "tok/s",
                color: AppColors.accentPrimary
            )
            statCard(
                label: "Total Runs",
                value: "\(entries.count)",
                unit: "",
                color: AppColors.accentSecondary
            )
        }
    }

    /// Adaptive grid columns: 2 on compact iPhone, 4 on iPad/macOS.
    private var statsGridColumns: [GridItem] {
        #if os(iOS)
        let columnCount = horizontalSizeClass == .compact ? 2 : 4
        #else
        let columnCount = 4
        #endif
        return Array(repeating: GridItem(.flexible()), count: columnCount)
    }

    private func statCard(label: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: AppSpacing.xs) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
            Text(value)
                .font(AppTypography.metricLarge)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            if !unit.isEmpty {
                Text(unit)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.md)
        .glassCard()
    }

    // MARK: - Memory Chart

    private var memoryChart: some View {
        let memoryEntries = entries.filter { $0.metrics.availableMemoryAtStartMB != nil }

        return Group {
            if !memoryEntries.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Memory Usage")
                        .font(AppTypography.sectionHeader)
                        .foregroundStyle(AppColors.textSecondary)

                    Chart {
                        ForEach(memoryEntries, id: \.timestamp) { entry in
                            let index = memoryEntries.firstIndex(where: { $0.timestamp == entry.timestamp }) ?? 0
                            if let start = entry.metrics.availableMemoryAtStartMB,
                               let end = entry.metrics.availableMemoryAtEndMB {
                                BarMark(
                                    x: .value("Run", index),
                                    yStart: .value("Start", end),
                                    yEnd: .value("End", start)
                                )
                                .foregroundStyle(AppColors.warning.opacity(0.6))
                            }
                        }
                    }
                    .chartYAxisLabel("Available MB")
                    .accessibilityLabel("Memory usage chart showing available memory across \(memoryEntries.count) runs.")
                    .frame(height: 150)
                    .padding(AppSpacing.md)
                    .glassCard()
                }
            }
        }
    }

    // MARK: - Recent Runs

    private var recentRunsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Recent Runs")
                .font(AppTypography.sectionHeader)
                .foregroundStyle(AppColors.textSecondary)

            ForEach(entries.suffix(10).reversed(), id: \.timestamp) { entry in
                recentRunRow(entry)
            }
        }
    }

    private func recentRunRow(_ entry: MetricsStore.Entry) -> some View {
        let tier = PerformanceTier(decodeSpeed: entry.metrics.decodeTokensPerSecond)

        return HStack(spacing: AppSpacing.md) {
            // Tier indicator
            Circle()
                .fill(tier.color)
                .frame(width: 8, height: 8)
                .glow(tier.color, radius: 4, opacity: 0.6)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(entry.model)
                    .font(AppTypography.subtitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Text("\(entry.platform) · \(entry.device)")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                Text(String(format: "%.1f tok/s", entry.metrics.decodeTokensPerSecond))
                    .font(AppTypography.metric)
                    .foregroundStyle(tier.color)
                Text(String(format: "TTFT: %.3fs", entry.metrics.ttftSeconds))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
        .padding(AppSpacing.md)
        .glassCard(cornerRadius: AppRadius.md)
    }

    // MARK: - Computed Properties

    private var averageDecodeSpeed: Double {
        guard !entries.isEmpty else { return 0 }
        return entries.reduce(0.0) { $0 + $1.metrics.decodeTokensPerSecond } / Double(entries.count)
    }

    private var peakDecodeSpeed: Double {
        entries.map(\.metrics.decodeTokensPerSecond).max() ?? 0
    }

    private var bestTTFT: Double {
        entries.map(\.metrics.ttftSeconds).min() ?? 0
    }

    // MARK: - Data Loading

    private func loadData() {
        isLoading = true
        do {
            if let model = selectedModel {
                entries = try store.entries(forModel: model)
            } else {
                entries = try store.loadEntries()
            }
            availableModels = try store.uniqueModels()
        } catch {
            loadError = error.localizedDescription
            entries = []
        }
        isLoading = false
    }
}
