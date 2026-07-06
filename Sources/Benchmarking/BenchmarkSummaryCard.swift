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

// MARK: - Benchmark Summary Card

/// Full-featured benchmark metrics card showing the last inference run's performance.
///
/// Extracted from `DetailColumnView.swift` for reuse across macOS model detail,
/// iOS model detail, and one-tap benchmark results.
///
/// Displays two tiers of information:
/// 1. **Hero metrics** (always visible): Decode speed, TTFT, Prefill speed
/// 2. **Full detail metrics** (always visible — plenty of room in detail panels):
///    Token counts, Init time, Memory delta, MTP speculation stats,
///    Timing breakdowns, Latency percentiles, Thermal state
///
/// All fields are rendered conditionally (`if let`) — gracefully handles nil
/// for LiteRT-only or MLX-only metrics.
struct BenchmarkSummaryCard: View {
    let metrics: EnginePerformanceMetrics
    @Environment(ConversationViewModel.self) private var viewModel

    private var decodeTier: PerformanceTier {
        PerformanceTier(decodeSpeed: metrics.tokensPerSecond)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Section header
            HStack {
                Text("Last Inference")
                    .font(AppTypography.sectionHeader)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Text(decodeTier.label)
                    .badge(decodeTier.color)
            }
            .accessibilityIdentifier("benchmarkSummary_header")

            // MARK: Hero Metrics Row
            heroMetricsRow
                .accessibilityIdentifier("benchmarkSummary_heroRow")

            // MARK: Full Detail Metrics
            detailMetricsSection
                .accessibilityIdentifier("benchmarkSummary_detailSection")
        }
        .accessibilityIdentifier("benchmarkSummary_card")
    }

    // MARK: - Hero Metrics Row

    /// Top-level metrics: Decode Speed, TTFT, Prefill Speed
    private var heroMetricsRow: some View {
        HStack(spacing: AppSpacing.md) {
            // Decode Speed — hero metric
            VStack(spacing: AppSpacing.xs) {
                Text(String(format: "%.1f", metrics.tokensPerSecond))
                    .font(AppTypography.metricLarge)
                    .foregroundStyle(decodeTier.color)
                    .contentTransition(.numericText())
                Text("tok/s")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .frame(maxWidth: .infinity)

            metricDivider

            // TTFT
            VStack(spacing: AppSpacing.xs) {
                Text(String(format: "%.3f", metrics.timeToFirstToken ?? 0))
                    .font(AppTypography.metric)
                    .foregroundStyle(AppColors.accentTeal)
                Text("TTFT (s)")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .frame(maxWidth: .infinity)

            metricDivider

            // Prefill Speed
            VStack(spacing: AppSpacing.xs) {
                Text(String(format: "%.1f", metrics.promptTokensPerSecond ?? 0))
                    .font(AppTypography.metric)
                    .foregroundStyle(AppColors.accentCyan)
                Text("Prefill tok/s")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(AppSpacing.md)
        .glassCard(cornerRadius: AppRadius.md)
    }

    // MARK: - Detail Metrics

    private var detailMetricsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Token Counts & Timing
            tokenCountsSection

            // Memory
            memorySection

            // Latency Statistics
            latencySection

            // MTP Speculation Stats
            mtpSection

            // Timing Breakdown
            timingBreakdownSection
        }
    }

    // MARK: - Token Counts

    @ViewBuilder
    private var tokenCountsSection: some View {
        let hasTokenData = metrics.tokenCount != nil || metrics.promptTokenCount != nil || metrics.initTimeSeconds != nil

        if hasTokenData {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                sectionLabel("Token Counts")

                LazyVGrid(columns: detailColumns, alignment: .leading, spacing: AppSpacing.xs) {
                    if let decodeCount = metrics.tokenCount {
                        detailCell(label: "Decode", value: "\(decodeCount) tok", color: AppColors.accentGold)
                    }
                    if let prefillCount = metrics.promptTokenCount {
                        detailCell(label: "Prefill", value: "\(prefillCount) tok", color: AppColors.accentGold)
                    }
                    if let initTime = metrics.initTimeSeconds {
                        detailCell(label: "Init Time", value: String(format: "%.2fs", initTime), color: AppColors.accentGold)
                    }
                }
            }
            .padding(AppSpacing.sm)
            .background(AppColors.backgroundTertiary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
        }
    }

    // MARK: - Memory

    @ViewBuilder
    private var memorySection: some View {
        if let inferenceMetrics = viewModel.inferenceMetrics {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                sectionLabel("Memory")

                LazyVGrid(columns: detailColumns, alignment: .leading, spacing: AppSpacing.xs) {
                    detailCell(
                        label: "Start",
                        value: String(format: "%.0f MB", inferenceMetrics.startSnapshot.availableMemoryMB),
                        color: AppColors.accentTeal
                    )
                    detailCell(
                        label: "End",
                        value: String(format: "%.0f MB", inferenceMetrics.endSnapshot.availableMemoryMB),
                        color: AppColors.accentTeal
                    )
                    detailCell(
                        label: "Δ Memory",
                        value: String(format: "%+.0f MB", inferenceMetrics.memoryDeltaMB),
                        color: inferenceMetrics.memoryDeltaMB < -500 ? AppColors.warning : AppColors.accentTeal
                    )
                }

                // Thermal transition warning
                if inferenceMetrics.thermalStateChanged {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppColors.warning)
                            .font(.caption)
                        Text("Thermal: \(inferenceMetrics.startSnapshot.thermalLevel.label) → \(inferenceMetrics.endSnapshot.thermalLevel.label)")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .accessibilityIdentifier("benchmarkSummary_thermalWarning")
                }
            }
            .padding(AppSpacing.sm)
            .background(AppColors.backgroundTertiary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
        }
    }

    // MARK: - Latency Statistics

    @ViewBuilder
    private var latencySection: some View {
        if let inferenceMetrics = viewModel.inferenceMetrics,
           !inferenceMetrics.decodeLatenciesMs.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                sectionLabel("Latency Statistics")

                LazyVGrid(columns: detailColumns, alignment: .leading, spacing: AppSpacing.xs) {
                    detailCell(label: "Median", value: String(format: "%.1f ms", inferenceMetrics.medianTokenLatencyMs), color: AppColors.accentCyan)
                    detailCell(label: "P95", value: String(format: "%.1f ms", inferenceMetrics.p95TokenLatencyMs), color: AppColors.accentCyan)
                    detailCell(label: "Min", value: String(format: "%.1f ms", inferenceMetrics.minTokenLatencyMs), color: AppColors.accentCyan)
                    detailCell(label: "Max", value: String(format: "%.1f ms", inferenceMetrics.maxTokenLatencyMs), color: AppColors.accentCyan)
                }
            }
            .padding(AppSpacing.sm)
            .background(AppColors.backgroundTertiary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
        }
    }

    // MARK: - MTP Speculation

    @ViewBuilder
    private var mtpSection: some View {
        if let acceptance = metrics.draftAcceptanceRate {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                sectionLabel("MTP Speculation")

                LazyVGrid(columns: detailColumns, alignment: .leading, spacing: AppSpacing.xs) {
                    detailCell(label: "Acceptance", value: String(format: "%.1f%%", acceptance * 100), color: AppColors.warning)
                    detailCell(label: "Draft", value: "\(metrics.proposedDraftTokens ?? 0) tok", color: AppColors.warning)
                    detailCell(label: "Accepted", value: "\(metrics.acceptedDraftTokens ?? 0) tok", color: AppColors.warning)
                }

                if let reason = metrics.passthroughReason {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(AppColors.textTertiary)
                            .font(.caption)
                        Text("Passthrough: \(reason)")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .accessibilityIdentifier("benchmarkSummary_mtpPassthrough")
                }
            }
            .padding(AppSpacing.sm)
            .background(AppColors.backgroundTertiary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
        }
    }

    // MARK: - Timing Breakdown

    @ViewBuilder
    private var timingBreakdownSection: some View {
        if let promptTime = metrics.promptTimeSeconds, let genTime = metrics.generateTimeSeconds {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                sectionLabel("Timing Breakdown")

                LazyVGrid(columns: detailColumns, alignment: .leading, spacing: AppSpacing.xs) {
                    detailCell(label: "Prefill Time", value: String(format: "%.3fs", promptTime), color: AppColors.textSecondary)
                    detailCell(label: "Generate Time", value: String(format: "%.3fs", genTime), color: AppColors.textSecondary)
                }
            }
            .padding(AppSpacing.sm)
            .background(AppColors.backgroundTertiary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
        }
    }

    // MARK: - Shared Helpers

    /// 3-column grid for detail metrics (2 on compact iOS).
    private var detailColumns: [GridItem] {
        #if os(iOS)
        [GridItem(.flexible()), GridItem(.flexible())]
        #else
        [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        #endif
    }

    /// Thin vertical divider between hero metric columns.
    private var metricDivider: some View {
        Rectangle()
            .fill(AppColors.border)
            .frame(width: 0.5, height: 40)
    }

    /// Section label for detail metric groups.
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textTertiary)
            .textCase(.uppercase)
            .tracking(1)
    }

    /// Individual metric cell in the detail grid.
    private func detailCell(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
            Text(value)
                .font(AppTypography.metric)
                .foregroundStyle(color)
        }
    }
}
