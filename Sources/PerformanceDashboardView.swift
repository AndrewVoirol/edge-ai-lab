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
    @State private var isLoading = true

    private let store = MetricsStore()

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                // Header
                dashboardHeader

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
        .background(
            LinearGradient(
                colors: [AppColors.backgroundPrimary, AppColors.backgroundSecondary, Color(red: 0.1, green: 0.15, blue: 0.25)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .overlay(.ultraThinMaterial)
        )
        .onAppear { loadData() }
        .navigationTitle("Performance")
    }

    // MARK: - Header

    private var dashboardHeader: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2)
                    .foregroundStyle(AppColors.accentTeal)
                Text("Performance Dashboard")
                    .font(.system(.title3, design: .default, weight: .semibold))
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
                                .font(.caption2)
                        }
                        .foregroundStyle(AppColors.accentGold)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .background(AppColors.accentGold.opacity(0.1))
                        .clipShape(Capsule())
                    }
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
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textTertiary)

            Text("No benchmark data yet")
                .font(.headline)
                .foregroundStyle(AppColors.textSecondary)

            Text("Run some inferences with benchmarking enabled to see performance trends here.")
                .font(.subheadline)
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
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    LineMark(
                        x: .value("Run", index),
                        y: .value("tok/s", entry.metrics.decodeTokensPerSecond)
                    )
                    .foregroundStyle(by: .value("Model", entry.model))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))

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
            .frame(height: 200)
            .padding(AppSpacing.md)
            .glassCard()
        }
    }

    // MARK: - Summary Stats

    private var summaryStatsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: AppSpacing.md) {
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
                color: AppColors.accentTeal
            )
            statCard(
                label: "Peak Decode",
                value: String(format: "%.1f", peakDecodeSpeed),
                unit: "tok/s",
                color: AppColors.accentCyan
            )
            statCard(
                label: "Total Runs",
                value: "\(entries.count)",
                unit: "",
                color: AppColors.accentGold
            )
        }
    }

    private func statCard(label: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: AppSpacing.xs) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
            Text(value)
                .font(AppTypography.metricLarge)
                .foregroundStyle(color)
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
                        ForEach(Array(memoryEntries.enumerated()), id: \.offset) { index, entry in
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

            ForEach(Array(entries.suffix(10).reversed().enumerated()), id: \.offset) { _, entry in
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

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.model)
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Text("\(entry.platform) · \(entry.device)")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
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
            entries = []
        }
        isLoading = false
    }
}
